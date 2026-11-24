/**
 * EmbeddingGemma-2 self-hosted HTTP port.
 *
 * Fixed endpoint only: `https://embedding-noteflow.trananhminh.uk/v1/embeddings`, protected by
 * Cloudflare Access Service Auth headers supplied by the server-side runtime secret store. One
 * input per call (pilot batch=1), no redirects, no retries, no fallback provider.
 *
 * The envelope is llama-server's OpenAI-compatible response: exactly one `data[0]` entry with
 * `index: 0` and a 768-component finite embedding. Every vector is normalized to unit length
 * before it can be stored or scored; a zero, non-finite or wrong-sized vector is rejected as
 * INVALID_PROVIDER_OUTPUT. Response bytes are bounded while streaming (64 KiB).
 *
 * Deadlines are the smaller of the caller's AbortSignal and 3 s for a query / 10 s for indexing.
 * `beforeDispatch` runs after the deadline is armed and immediately before the fetch; a refusal
 * thrown by it is preserved, never remapped to a provider error. No header, body, noted text or
 * raw provider error is ever copied into an IndexFailure message.
 */
import {
  MAX_EMBEDDING_CHARACTERS,
  MAX_EMBEDDING_TOKENS,
  countTokens,
  countUnicodeCharacters,
  isWellFormed,
} from '../chunking';
import { RagFailure, type Counter } from '../types';
import {
  DEFAULT_MAX_RESPONSE_BYTES,
  cancelBody,
  decodeUtf8,
  isRecord,
  parseJsonObject,
  readBoundedBody,
  startDeadline,
  withinDeadline,
} from '../providers/http_body';
import { IndexFailure, type Embedding } from './types';

/** Contract constant; callers cannot supply or override the endpoint. */
export const SELF_HOSTED_EMBEDDING_ENDPOINT =
  'https://embedding-noteflow.trananhminh.uk/v1/embeddings';
/** EmbeddingGemma-2 text-only profile: 768 dimensions, cosine. */
export const SELF_HOSTED_EMBEDDING_DIMENSIONS = 768;
/** Fixed server-side model alias; the request cannot select a different model. */
export const SELF_HOSTED_EMBEDDING_MODEL = 'embeddinggemma2';
/** The envelope must carry raw float vectors, never base64. */
export const SELF_HOSTED_EMBEDDING_ENCODING_FORMAT = 'float';
/** Bounded query deadline; always composed with the caller's remaining deadline. */
export const SELF_HOSTED_QUERY_TIMEOUT_MS = 3000;
/** Bounded indexing deadline; always composed with the caller's remaining deadline. */
export const SELF_HOSTED_INDEX_TIMEOUT_MS = 10000;
/** Pilot dispatch size: one input per HTTP call. */
export const SELF_HOSTED_EMBED_BATCH_LIMIT = 1;

export type SelfHostedEmbeddingConfig = Readonly<{
  /** Cloudflare Access Service Auth client id; a runtime secret, never logged. */
  clientId: string;
  /** Cloudflare Access Service Auth client secret; a runtime secret, never logged. */
  clientSecret: string;
}>;

const invalidInput: () => never = () => {
  throw new IndexFailure('INVALID_INPUT', false);
};
const invalidState: () => never = () => {
  throw new IndexFailure('INVALID_STATE', false);
};
const invalidOutput: () => never = () => {
  throw new IndexFailure('INVALID_PROVIDER_OUTPUT', false);
};
const inputTooLong: () => never = () => {
  throw new IndexFailure('INPUT_TOO_LONG', false);
};

/** Wraps a `beforeDispatch` refusal so the transport's own mapping cannot replace its code. */
class DispatchRefusal extends Error {
  constructor(readonly cause: unknown) {
    super('DISPATCH_REFUSED');
    this.name = 'DispatchRefusal';
  }
}

/** HTTP status mapping: only a timeout, 429 and 5xx are eligible for a caller replay. */
function failureForStatus(status: number): IndexFailure {
  if (status === 408) return new IndexFailure('TIMEOUT', true);
  if (status === 429) return new IndexFailure('RATE_LIMITED', true);
  if (status >= 500) return new IndexFailure('PROVIDER_UNAVAILABLE', true);
  if (status === 401 || status === 403) return new IndexFailure('UNAUTHORIZED', false);
  return new IndexFailure('PROVIDER_UNAVAILABLE', false);
}

const readConfig = (config: unknown): SelfHostedEmbeddingConfig => {
  if (!isRecord(config)) invalidState();
  const clientId = config['clientId'];
  const clientSecret = config['clientSecret'];
  if (
    typeof clientId !== 'string' || clientId.length === 0 ||
    typeof clientSecret !== 'string' || clientSecret.length === 0
  ) {
    invalidState();
  }
  return Object.freeze({ clientId, clientSecret });
};

/** Strict schema + finite/non-zero/normalize guard; the returned vector is frozen. */
function readVector(value: unknown): readonly number[] {
  if (!Array.isArray(value) || value.length !== SELF_HOSTED_EMBEDDING_DIMENSIONS) invalidOutput();
  const vector: number[] = [];
  for (const component of value) {
    if (typeof component !== 'number' || !Number.isFinite(component)) invalidOutput();
    vector.push(component);
  }
  const norm = Math.hypot(...vector);
  if (!Number.isFinite(norm) || norm <= 0) invalidOutput();
  const unit = vector.map((component) => component / norm);
  for (const component of unit) {
    if (!Number.isFinite(component)) invalidOutput();
  }
  return Object.freeze(unit);
}

/**
 * The operational identity is the fixed endpoint plus the 768-dimension/profile guard. The
 * OpenAI envelope's `model` field is deliberately not compared to the request alias here:
 * llama-server builds differ in whether they echo `request.model` or the loaded model name, and
 * no live response shape has been pinned for this deployment. Rejecting a valid envelope over a
 * display field would break embeddings without adding an identity guarantee.
 */
function readEmbedding(payload: Record<string, unknown>): readonly number[] {
  const data = payload['data'];
  if (!Array.isArray(data) || data.length !== 1) invalidOutput();
  const entry = data[0];
  if (!isRecord(entry) || entry['index'] !== 0) invalidOutput();
  return readVector(entry['embedding']);
}

/**
 * `count` is the injected EmbeddingGemma tokenizer counter (BOS/EOS included). `fetchImpl` is a
 * test seam; production uses the runtime's global fetch. Both Cloudflare secrets are required.
 */
export function createSelfHostedEmbedding(
  config: SelfHostedEmbeddingConfig,
  count: Counter,
  fetchImpl?: typeof fetch,
): Embedding {
  const { clientId, clientSecret } = readConfig(config);
  if (typeof count !== 'function') invalidState();
  if (fetchImpl !== undefined && typeof fetchImpl !== 'function') invalidState();
  const callFetch: typeof fetch = fetchImpl ?? ((input, init) => fetch(input, init));
  const accessHeaders: Readonly<Record<string, string>> = Object.freeze({
    'CF-Access-Client-Id': clientId,
    'CF-Access-Client-Secret': clientSecret,
  });

  const measure = (text: string): void => {
    if (text.length === 0 || !isWellFormed(text)) invalidInput();
    if (countUnicodeCharacters(text) > MAX_EMBEDDING_CHARACTERS) inputTooLong();
    // A broken counter throws EVIDENCE_VALIDATION_UNAVAILABLE from countTokens: fail closed.
    if (countTokens(count, text) > MAX_EMBEDDING_TOKENS) inputTooLong();
  };

  return Object.freeze({
    count,
    embed: async (texts, purpose, signal, beforeDispatch) => {
      if (purpose !== 'search_document' && purpose !== 'search_query') invalidInput();
      if (!Array.isArray(texts) || texts.length !== SELF_HOSTED_EMBED_BATCH_LIMIT) invalidInput();
      if (!(signal instanceof AbortSignal)) invalidInput();
      if (beforeDispatch !== undefined && typeof beforeDispatch !== 'function') invalidInput();
      const text = texts[0];
      if (typeof text !== 'string') invalidInput();
      measure(text);

      const timeoutMs = purpose === 'search_query'
        ? SELF_HOSTED_QUERY_TIMEOUT_MS
        : SELF_HOSTED_INDEX_TIMEOUT_MS;
      const deadline = startDeadline(timeoutMs, signal);
      let cancelPendingRead: (() => void) | undefined;

      const attempt = (async (): Promise<readonly (readonly number[])[]> => {
        // Revalidate after the deadline is armed; a refusal keeps its own typed code.
        if (beforeDispatch !== undefined) {
          try {
            await beforeDispatch();
          } catch (error) {
            throw new DispatchRefusal(error);
          }
        }
        if (deadline.expired()) throw new IndexFailure('TIMEOUT', true);

        let response: Response;
        try {
          response = await callFetch(SELF_HOSTED_EMBEDDING_ENDPOINT, {
            method: 'POST',
            headers: {
              'content-type': 'application/json',
              accept: 'application/json',
              ...accessHeaders,
            },
            body: JSON.stringify({
              model: SELF_HOSTED_EMBEDDING_MODEL,
              input: [text],
              encoding_format: SELF_HOSTED_EMBEDDING_ENCODING_FORMAT,
            }),
            redirect: 'error',
            signal: deadline.signal,
          });
        } catch {
          if (deadline.expired()) throw new IndexFailure('TIMEOUT', true);
          throw new IndexFailure('PROVIDER_UNAVAILABLE', false);
        }

        if (response.status < 200 || response.status >= 300) {
          cancelBody(response);
          throw failureForStatus(response.status);
        }

        const bytes = await readBoundedBody(
          response,
          DEFAULT_MAX_RESPONSE_BYTES,
          (cancel) => {
            cancelPendingRead = cancel;
          },
          invalidOutput,
        );
        const payload = parseJsonObject(decodeUtf8(bytes, invalidOutput), invalidOutput);
        return Object.freeze([readEmbedding(payload)]);
      })();

      try {
        return await withinDeadline(
          deadline,
          attempt,
          () => cancelPendingRead?.(),
          (error) => (error instanceof Error ? error : new IndexFailure('PROVIDER_UNAVAILABLE', false)),
        );
      } catch (error) {
        if (error instanceof DispatchRefusal) throw error.cause;
        if (error instanceof IndexFailure) throw error;
        if (error instanceof RagFailure) {
          throw error.code === 'TIMEOUT'
            ? new IndexFailure('TIMEOUT', true)
            : new IndexFailure(error.code, false);
        }
        throw new IndexFailure('PROVIDER_UNAVAILABLE', false);
      }
    },
  });
}
