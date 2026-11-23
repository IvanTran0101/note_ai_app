/**
 * DeepSeek Chat Completions adapter for one Summary Cloud generation.
 *
 * Owns everything provider-specific: the fixed endpoint and model, the frozen
 * request flags, the per-stage output budget, the 20-second deadline, the
 * response byte cap, response validation, and the mapping from provider
 * failures to safe `SummaryFailure` codes. It never returns, logs, or throws
 * raw provider text, HTTP bodies, headers, or the API key.
 *
 * Response handling follows the frozen fixture mapping rather than a guess at
 * DeepSeek's full JSON: `choices[0].finish_reason` must be `stop`,
 * `choices[0].message.content` must be a non-empty string after trimming, and
 * `usage.prompt_tokens` / `usage.completion_tokens` must be non-negative whole
 * numbers. Official extra fields (for example `total_tokens`,
 * `prompt_cache_hit_tokens`, `prompt_tokens_details`) are ignored, not
 * rejected, because the provider adds fields over time; a *missing* usage
 * object is still a failure, since token numbers are never invented.
 *
 * The returned usage is what the handler reports as actual tokens. The input
 * estimate in `summary_contract.ts` is a conservative byte-based estimate used for
 * routing; it does not prove that a request the provider already accepted and
 * billed stayed under the cap.
 *
 * @see docs/summary_api_contract.md (sections 3-5)
 * @see https://api-docs.deepseek.com/api/create-chat-completion/
 */

import {
  MAX_INPUT_TOKENS_PER_CALL,
  SummaryFailure,
  buildSummaryMessages,
  estimateSummaryInputTokens,
  maxOutputTokensForStage,
  type SummaryRequest,
  type SummaryResult,
} from './summary_contract';

/** Frozen by contract section 5; not client-configurable. */
const CHAT_COMPLETIONS_URL = 'https://api.deepseek.com/chat/completions';
const SUMMARY_MODEL = 'deepseek-flash';

export const DEFAULT_PROVIDER_TIMEOUT_MS = 20000;
export const DEFAULT_MAX_RESPONSE_BYTES = 65536;

/** Upper bound for a provider `Retry-After`; longer waits are clamped. */
const MAX_RETRY_AFTER_SECONDS = 3600;

export type DeepSeekProviderOptions = Readonly<{
  /** Read from the Amplify secret at runtime; never hard-coded or logged. */
  apiKey: string;
  /** Injected in tests; production uses the runtime's global `fetch`. */
  fetchImpl?: typeof fetch;
  /** Deadline for the whole call, including body reading. @default 20000 */
  timeoutMs?: number;
  /** Hard cap on provider response bytes, enforced while reading. @default 65536 */
  maxResponseBytes?: number;
}>;

/** One generation call: a validated request in, mapped usage and text out. */
export type DeepSeekProvider = (request: SummaryRequest) => Promise<SummaryResult>;

const invalidOutput = (message: string): SummaryFailure =>
  new SummaryFailure('invalidOutput', message);

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const isPositiveWholeNumber = (value: unknown): value is number =>
  typeof value === 'number' && Number.isSafeInteger(value) && value > 0;

/**
 * Reads a Retry-After header as whole seconds. HTTP-date values, zero,
 * negatives, fractions, and junk are ignored; absurd waits are clamped so a
 * provider cannot park a client for an unbounded time.
 */
const retryAfterSecondsOf = (headers: Headers | undefined): number | undefined => {
  const raw = headers?.get?.('retry-after');
  if (typeof raw !== 'string') {
    return undefined;
  }
  const trimmed = raw.trim();
  if (!/^\d+$/.test(trimmed)) {
    return undefined;
  }
  const seconds = Number(trimmed);
  if (!Number.isSafeInteger(seconds) || seconds < 1) {
    return undefined;
  }
  return Math.min(seconds, MAX_RETRY_AFTER_SECONDS);
};

/**
 * A promise timeout that also aborts the request. `hasFired` makes the mapping
 * deterministic when an abort and a rejection race, and the internal catch
 * keeps a losing deadline from surfacing as an unhandled rejection.
 */
const startDeadline = (
  timeoutMs: number,
): Readonly<{
  signal: AbortSignal;
  promise: Promise<never>;
  hasFired: () => boolean;
  settle: () => void;
}> => {
  const controller = new AbortController();
  let fired = false;
  let timer: ReturnType<typeof setTimeout> | undefined;
  const promise = new Promise<never>((_resolve, reject) => {
    timer = setTimeout(() => {
      fired = true;
      controller.abort();
      reject(new SummaryFailure('timeout', 'provider deadline exceeded'));
    }, timeoutMs);
  });
  void promise.catch(() => undefined);
  return {
    signal: controller.signal,
    promise,
    hasFired: () => fired,
    settle: () => {
      if (timer !== undefined) {
        clearTimeout(timer);
      }
    },
  };
};

const concatBytes = (chunks: readonly Uint8Array[], total: number): Uint8Array => {
  const joined = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    joined.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return joined;
};

const cancelBody = (response: Response): void => {
  const body: ReadableStream<Uint8Array> | null | undefined = response.body;
  if (body === null || body === undefined) {
    return;
  }
  try {
    void body.cancel().catch(() => undefined);
  } catch {
    // A body that cannot be cancelled is already unusable; nothing to report.
  }
};

const contentLengthOf = (headers: Headers | undefined): number | undefined => {
  const raw = headers?.get?.('content-length');
  if (typeof raw !== 'string' || !/^\d+$/.test(raw.trim())) {
    return undefined;
  }
  const length = Number(raw.trim());
  return Number.isSafeInteger(length) && length >= 0 ? length : undefined;
};

/**
 * Reads the response body with a hard byte bound. The bound is on the bytes
 * actually read, not on the declared `Content-Length`; the declared length is
 * only a cheap early refusal. `registerCancel` lets the deadline cancel a read
 * that a stalled body would otherwise leave pending.
 */
const readBoundedBody = async (
  response: Response,
  maxBytes: number,
  registerCancel: (cancel: () => void) => void,
): Promise<Uint8Array> => {
  const declared = contentLengthOf(response.headers);
  if (declared !== undefined && declared > maxBytes) {
    cancelBody(response);
    throw invalidOutput('provider response is too large');
  }

  const body = response.body;
  if (body !== null && typeof body?.getReader === 'function') {
    const reader = body.getReader();
    registerCancel(() => {
      void reader.cancel().catch(() => undefined);
    });
    const chunks: Uint8Array[] = [];
    let total = 0;
    for (; ;) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }
      if (value === undefined || value === null) {
        continue;
      }
      total += value.byteLength;
      if (total > maxBytes) {
        void reader.cancel().catch(() => undefined);
        throw invalidOutput('provider response is too large');
      }
      chunks.push(value);
    }
    return concatBytes(chunks, total);
  }

  throw invalidOutput('provider response has no readable body');
};

/** Strict whole-number token count; booleans, strings, floats, NaN, and negatives fail. */
const tokenCount = (value: unknown): number | undefined =>
  typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 ? value : undefined;

const readUsage = (value: unknown): Readonly<{ inputTokens: number; outputTokens: number; }> => {
  if (!isRecord(value)) {
    throw invalidOutput('provider usage is missing');
  }
  const inputTokens = tokenCount(value.prompt_tokens);
  const outputTokens = tokenCount(value.completion_tokens);
  if (inputTokens === undefined || outputTokens === undefined) {
    throw invalidOutput('provider usage is malformed');
  }
  return { inputTokens, outputTokens };
};

/**
 * Validates the decoded provider payload and maps it to the contract's result.
 * Only the selected fields are read; the payload itself is discarded.
 */
const readProviderPayload = (bytes: Uint8Array, stage: SummaryRequest['stage']): SummaryResult => {
  let text: string;
  try {
    text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    throw invalidOutput('provider response is not valid UTF-8');
  }

  let decoded: unknown;
  try {
    decoded = JSON.parse(text);
  } catch {
    throw invalidOutput('provider response is not valid JSON');
  }
  if (!isRecord(decoded)) {
    throw invalidOutput('provider response must be a JSON object');
  }

  const choices = decoded.choices;
  if (!Array.isArray(choices) || choices.length !== 1 || !isRecord(choices[0])) {
    throw invalidOutput('provider response has no single choice');
  }
  const choice = choices[0];
  if (choice.finish_reason !== 'stop') {
    throw invalidOutput('provider did not stop normally');
  }
  const message = choice.message;
  if (!isRecord(message) || typeof message.content !== 'string') {
    throw invalidOutput('provider content is missing');
  }
  const summary = message.content.trim();
  if (summary.length === 0) {
    throw invalidOutput('provider content is empty');
  }

  const usage = readUsage(decoded.usage);
  if (usage.inputTokens > MAX_INPUT_TOKENS_PER_CALL) {
    throw invalidOutput('provider exceeded the input budget');
  }
  if (usage.outputTokens > maxOutputTokensForStage(stage)) {
    throw invalidOutput('provider exceeded the stage output budget');
  }
  return { summary, usage };
};

const toSummaryFailure = (error: unknown): SummaryFailure =>
  error instanceof SummaryFailure
    ? error
    : new SummaryFailure('providerUnavailable', 'provider request failed');

const callProvider = async (
  apiKey: string,
  fetchImpl: typeof fetch,
  body: string,
  stage: SummaryRequest['stage'],
  signal: AbortSignal,
  maxResponseBytes: number,
  registerCancel: (cancel: () => void) => void,
): Promise<SummaryResult> => {
  const response = await fetchImpl(CHAT_COMPLETIONS_URL, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${apiKey}`,
      'content-type': 'application/json',
      accept: 'application/json',
    },
    body,
    redirect: 'error',
    signal,
  });

  if (response.status === 429) {
    cancelBody(response);
    throw new SummaryFailure('rateLimited', 'provider rate limited', retryAfterSecondsOf(response.headers));
  }
  if (response.status === 408) {
    cancelBody(response);
    throw new SummaryFailure('timeout', 'provider timed out');
  }
  if (response.status < 200 || response.status >= 300) {
    // 5xx, 4xx refusals, and auth failures are one safe upstream class: the
    // status and body are never echoed, and there is no automatic retry.
    cancelBody(response);
    throw new SummaryFailure('providerUnavailable', 'provider is unavailable');
  }

  const bytes = await readBoundedBody(response, maxResponseBytes, registerCancel);
  return readProviderPayload(bytes, stage);
};

/**
 * Creates the production provider adapter.
 *
 * A missing API key or an invalid bound is a configuration failure, not a
 * request failure, and fails closed at composition time. Each call performs at
 * most one request to the fixed endpoint, sends `thinking: disabled` and
 * `stream: false`, and carries no retry.
 *
 * @throws {SummaryFailure} `unexpected` when the adapter itself is misconfigured.
 */
export const createDeepSeekProvider = ({
  apiKey,
  fetchImpl,
  timeoutMs = DEFAULT_PROVIDER_TIMEOUT_MS,
  maxResponseBytes = DEFAULT_MAX_RESPONSE_BYTES,
}: DeepSeekProviderOptions): DeepSeekProvider => {
  if (typeof apiKey !== 'string' || apiKey.trim().length === 0) {
    throw new SummaryFailure('unexpected', 'provider api key is not configured');
  }
  if (!isPositiveWholeNumber(timeoutMs) || !isPositiveWholeNumber(maxResponseBytes)) {
    throw new SummaryFailure('unexpected', 'provider bounds are invalid');
  }
  const callFetch: typeof fetch = fetchImpl ?? ((input, init) => fetch(input, init));

  return async (request) => {
    const messages = buildSummaryMessages(request);
    if (estimateSummaryInputTokens(request) > MAX_INPUT_TOKENS_PER_CALL) {
      throw new SummaryFailure('inputTooLong', 'estimated prompt exceeds the input cap');
    }

    const body = JSON.stringify({
      model: SUMMARY_MODEL,
      messages,
      thinking: { type: 'disabled' },
      stream: false,
      max_tokens: maxOutputTokensForStage(request.stage),
    });

    const deadline = startDeadline(timeoutMs);
    let cancelPendingRead: (() => void) | undefined;
    const attempt = callProvider(
      apiKey,
      callFetch,
      body,
      request.stage,
      deadline.signal,
      maxResponseBytes,
      (cancel) => {
        cancelPendingRead = cancel;
      },
    );
    // The attempt may settle after losing the race; handle it so a late
    // rejection or an ignored abort never becomes an unhandled rejection.
    void attempt.catch(() => undefined);

    try {
      return await Promise.race([attempt, deadline.promise]);
    } catch (error) {
      if (deadline.hasFired()) {
        throw new SummaryFailure('timeout', 'provider deadline exceeded');
      }
      throw toSummaryFailure(error);
    } finally {
      deadline.settle();
      // Only an abandoned read needs cancelling; a completed one is already
      // closed, and the over-size path cancels the reader itself.
      if (deadline.hasFired()) {
        cancelPendingRead?.();
      }
    }
  };
};
