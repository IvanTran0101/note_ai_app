import { STATUS_BY_CODE, defaultRequestId, toResponse, logOutcome, type Outcome } from './summary_response';
import type { SummaryNoteAuthority, SummaryStageAuthority } from './summary_note_authority';
import { unlockGrantOf } from '../protection/handler';
/**
 * Summary Cloud HTTP handler: `POST /ai/summary`.
 *
 * Transport and policy only: verified JWT claims, a bounded and UTF-8 checked
 * body, `parseSummaryBody` for schema/consent, the prompt-budget estimate, the
 * per-account quota, and exactly one injected provider call. Prompt rendering
 * lives in `summary_contract.ts`, provider behavior in `deepseek_client.ts`.
 *
 * Order is deliberate - authenticate, parse, estimate, quota, generation - so
 * an unauthorized, malformed, over-budget, or unconsented request consumes no
 * quota and never reaches the provider, and a quota refusal or failure returns
 * before generation.
 *
 * Logs carry metadata only: server-generated request id, stage, latency, usage,
 * and error code. JWT claims, the provider key, inputs, provider payloads, and
 * summary text are never logged or echoed, and no raw error message crosses the
 * response envelope. `requestId` is generated per HTTP request; it is not an
 * identity or an idempotency key, and the contract forbids both uses.
 *
 * @see docs/summary_api_contract.md (sections 3, 5)
 */

import type {
  APIGatewayProxyEventV2WithJWTAuthorizer,
  APIGatewayProxyStructuredResultV2,
} from 'aws-lambda';
import {
  MAX_BODY_BYTES_UTF8,
  MAX_INPUT_TOKENS_PER_CALL,
  SummaryFailure,
  estimateSummaryInputTokens,
  maxOutputTokensForStage,
  parseSummaryBody,
  type QuotaDecision,
  type SummaryErrorCode,
  type SummaryRequest,
  type SummaryResult,
  type SummaryStage,
} from './summary_contract';

/** The contract's only route; the API Gateway resource serves no other. */
const SUMMARY_PATH = '/ai/summary';

/** Default bound for the quota check; keeps the call well inside Lambda's 28s. */
export const DEFAULT_QUOTA_TIMEOUT_MS = 5000;

/** Mirrors the provider's Retry-After clamp, so the header is always bounded. */
const MAX_RETRY_AFTER_SECONDS = 3600;

/** Base64 expands three bytes to four characters; used for the cheap pre-check. */
const BASE64_CHARS_PER_GROUP = 4;
const BASE64_BYTES_PER_GROUP = 3;

export type SummaryHandlerDeps = Readonly<{
  /** One generation call; `deepseek_client.ts` in production. */
  generate: (request: SummaryRequest) => Promise<SummaryResult>;
  /** Atomic per-account minute quota; `quota.ts` in production. */
  consumeQuota: (accountId: string, nowMs: number) => Promise<QuotaDecision>;
  security?: SummaryNoteAuthority;
  /** Injectable clock for tests. @default Date.now */
  now?: () => number;
  /** Injectable server request-id factory for tests. @default crypto.randomUUID */
  requestId?: () => string;
  /** Bound for `consumeQuota`; on expiry the request fails closed. @default 5000 */
  quotaTimeoutMs?: number;
}>;

/** What one request produced; `code` is set exactly when the request failed. */
type BodyRead =
  | Readonly<{ ok: true; text: string; }>
  | Readonly<{ ok: false; code: SummaryErrorCode; }>;

/** A request that passed route, auth, body, schema, consent, and budget checks. */
type PreparedRequest =
  | Readonly<{ ok: true; request: SummaryRequest; accountId: string; }>
  | Readonly<{ ok: false; code: SummaryErrorCode; status?: number; }>;

const textEncoder = new TextEncoder();

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const isNonBlankString = (value: unknown): value is string =>
  typeof value === 'string' && value.trim().length > 0;

const isPositiveWholeNumber = (value: unknown): value is number =>
  typeof value === 'number' && Number.isSafeInteger(value) && value > 0;

/** A retry hint is served only when it is a bounded positive whole number. */
const boundedRetryAfter = (value: unknown): number | undefined =>
  isPositiveWholeNumber(value) ? Math.min(value, MAX_RETRY_AFTER_SECONDS) : undefined;

const outcomeForError = (error: unknown, stage?: SummaryStage): Outcome =>
  error instanceof SummaryFailure
    ? {
      statusCode: STATUS_BY_CODE[error.code],
      code: error.code,
      stage,
      retryAfterSeconds: boundedRetryAfter(error.retryAfterSeconds),
    }
    : { statusCode: STATUS_BY_CODE.unexpected, code: 'unexpected', stage };

const methodOf = (event: APIGatewayProxyEventV2WithJWTAuthorizer): string =>
  event.requestContext?.http?.method?.toUpperCase() ?? '';

/**
 * The account behind the request: a non-blank verified `sub` on a Cognito
 * *access* token. ID tokens and tokens without a subject are refused; no OAuth
 * scope is required or invented, and no body or header value can supply an
 * identity.
 */
const accessTokenSubjectOf = (event: APIGatewayProxyEventV2WithJWTAuthorizer): string | undefined => {
  const claims = event.requestContext?.authorizer?.jwt?.claims;
  if (!isRecord(claims)) {
    return undefined;
  }
  const sub = claims['sub'];
  if (!isNonBlankString(sub) || claims['token_use'] !== 'access') {
    return undefined;
  }
  return sub.trim();
};

/**
 * Reads the Lambda body into a UTF-8 string with the 256 KiB transport cap
 * enforced on real bytes: the decoded bytes for a base64 body, the encoded
 * length for a raw one. Invalid base64, invalid UTF-8, and over-cap bodies are
 * refused before JSON parsing, so a malformed or oversized body is never
 * interpreted.
 */
const readBody = (event: APIGatewayProxyEventV2WithJWTAuthorizer): BodyRead => {
  const raw = event.body;
  if (typeof raw !== 'string' || raw.length === 0) {
    return { ok: false, code: 'invalidInput' };
  }

  if (event.isBase64Encoded === true) {
    const groups = Math.ceil(MAX_BODY_BYTES_UTF8 / BASE64_BYTES_PER_GROUP);
    const maxBase64Chars = groups * BASE64_CHARS_PER_GROUP + BASE64_CHARS_PER_GROUP;
    if (raw.length > maxBase64Chars) {
      return { ok: false, code: 'inputTooLong' };
    }
    let binary: string;
    try {
      binary = atob(raw);
    } catch {
      return { ok: false, code: 'invalidInput' };
    }
    if (binary.length > MAX_BODY_BYTES_UTF8) {
      return { ok: false, code: 'inputTooLong' };
    }
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    try {
      return { ok: true, text: new TextDecoder('utf-8', { fatal: true }).decode(bytes) };
    } catch {
      return { ok: false, code: 'invalidInput' };
    }
  }

  if (textEncoder.encode(raw).byteLength > MAX_BODY_BYTES_UTF8) {
    return { ok: false, code: 'inputTooLong' };
  }
  return { ok: true, text: raw };
};

/** Route, auth, body, schema/consent, and budget - everything before quota. */
const prepareRequest = (event: APIGatewayProxyEventV2WithJWTAuthorizer): PreparedRequest => {
  // The API serves one method and one path; anything else is not this API.
  if (methodOf(event) !== 'POST' || event.rawPath !== SUMMARY_PATH) {
    return { ok: false, code: 'unexpected', status: 404 };
  }
  const accountId = accessTokenSubjectOf(event);
  if (accountId === undefined) {
    return { ok: false, code: 'unauthorized' };
  }
  const body = readBody(event);
  if (!body.ok) {
    return { ok: false, code: body.code };
  }
  try {
    const request = parseSummaryBody(body.text);
    if (estimateSummaryInputTokens(request) > MAX_INPUT_TOKENS_PER_CALL) {
      return { ok: false, code: 'inputTooLong' };
    }
    return { ok: true, request, accountId };
  } catch (error) {
    return { ok: false, code: error instanceof SummaryFailure ? error.code : 'unexpected' };
  }
};

/**
 * Races the quota call against its bound. A quota backend that never answers
 * must not hold the Lambda open, and it must not be treated as allowed: the
 * deadline rejection is `unexpected`, so the request fails closed.
 */
const consumeQuotaWithinDeadline = async (
  consumeQuota: SummaryHandlerDeps['consumeQuota'],
  accountId: string,
  nowMs: number,
  timeoutMs: number,
): Promise<QuotaDecision> => {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<never>((_resolve, reject) => {
    timer = setTimeout(() => reject(new SummaryFailure('unexpected', 'quota check timed out')), timeoutMs);
  });
  void deadline.catch(() => undefined);
  const attempt = consumeQuota(accountId, nowMs);
  void attempt.catch(() => undefined);
  try {
    return await Promise.race([attempt, deadline]);
  } finally {
    if (timer !== undefined) {
      clearTimeout(timer);
    }
  }
};

/** Re-checks the generated result so a bad injected provider cannot become a 200. */
const readGeneratedResult = (value: unknown, stage: SummaryStage): SummaryResult | undefined => {
  if (!isRecord(value) || !isNonBlankString(value.summary)) {
    return undefined;
  }
  const usage = value.usage;
  if (!isRecord(usage)) {
    return undefined;
  }
  const { inputTokens, outputTokens } = usage;
  const isTokenCount = (count: unknown): count is number =>
    typeof count === 'number' && Number.isSafeInteger(count) && count >= 0;
  if (!isTokenCount(inputTokens) || !isTokenCount(outputTokens) ||
    inputTokens > MAX_INPUT_TOKENS_PER_CALL || outputTokens > maxOutputTokensForStage(stage)) {
    return undefined;
  }
  return { summary: value.summary.trim(), usage: { inputTokens, outputTokens } };
};

/** Quota, generation, and result mapping for an already-validated request. */
const generateWithinPolicy = async (
  prepared: Readonly<{ request: SummaryRequest; accountId: string; }>,
  stageAuthority: SummaryStageAuthority,
  deps: Readonly<{
    generate: SummaryHandlerDeps['generate'];
    consumeQuota: SummaryHandlerDeps['consumeQuota'];
    now: () => number;
    quotaTimeoutMs: number;
  }>,
): Promise<Outcome> => {
  const { request, accountId } = prepared;
  const stage = request.stage;

  let decision: QuotaDecision;
  try {
    await stageAuthority.revalidate();
    decision = await consumeQuotaWithinDeadline(deps.consumeQuota, accountId, deps.now(), deps.quotaTimeoutMs);
  } catch (error) {
    // A quota failure or timeout is never a silent allow, and never reaches
    // the provider.
    return outcomeForError(error, stage);
  }
  if (!decision.allowed) {
    return {
      statusCode: STATUS_BY_CODE.rateLimited,
      code: 'rateLimited',
      stage,
      retryAfterSeconds: boundedRetryAfter(decision.retryAfterSeconds),
    };
  }

  let generated: unknown;
  try {
    await stageAuthority.revalidate();
    generated = await deps.generate(request);
  } catch (error) {
    return outcomeForError(error, stage);
  }
  const result = readGeneratedResult(generated, request.stage);
  if (result === undefined) {
    return { statusCode: STATUS_BY_CODE.invalidOutput, code: 'invalidOutput', stage };
  }
  try { await stageAuthority.complete(result.summary); }
  catch (error) { return outcomeForError(error, stage); }
  return { statusCode: 200, stage, summary: result.summary, usage: result.usage };
};

/**
 * Creates the Lambda handler for the frozen summary route.
 *
 * @throws {SummaryFailure} `unexpected` when a dependency bound is invalid
 * (a composition error, not a request error).
 */
export const createSummaryHandler = ({
  generate,
  consumeQuota,
  security,
  now = Date.now,
  requestId,
  quotaTimeoutMs = DEFAULT_QUOTA_TIMEOUT_MS,
}: SummaryHandlerDeps): ((event: APIGatewayProxyEventV2WithJWTAuthorizer) => Promise<APIGatewayProxyStructuredResultV2>) => {
  if (!isPositiveWholeNumber(quotaTimeoutMs)) {
    throw new SummaryFailure('unexpected', 'quota timeout is invalid');
  }
  const deps = { generate, consumeQuota, now, quotaTimeoutMs } as const;
  const nextRequestId = (): string => {
    const candidate = requestId?.();
    return isNonBlankString(candidate) ? candidate : defaultRequestId();
  };

  return async (event) => {
    const startedAt = now();
    let id = '';
    try {
      id = nextRequestId();
      const prepared = prepareRequest(event);
      let outcome: Outcome;
      if (!prepared.ok) {
        outcome = { statusCode: prepared.status ?? STATUS_BY_CODE[prepared.code], code: prepared.code };
      } else {
        try {
          if (!security) throw new SummaryFailure('unexpected', 'Note authority unavailable');
          const authority = await security.begin(prepared.request, prepared.accountId, unlockGrantOf(event));
          outcome = await generateWithinPolicy(prepared, authority, deps);
        } catch (error) { outcome = outcomeForError(error, prepared.request.stage); }
      }
      logOutcome(outcome, id, Math.max(0, now() - startedAt));
      return toResponse(outcome, id);
    } catch (error) {
      // Nothing that escapes the flow above may become a gateway error page:
      // log only the local failure code and answer with the safe envelope.
      const failureId = isNonBlankString(id) ? id : defaultRequestId();
      console.error('summary request failed', {
        requestId: failureId,
        code: 'unexpected',
      });
      return toResponse({ statusCode: STATUS_BY_CODE.unexpected, code: 'unexpected' }, failureId);
    }
  };
};
