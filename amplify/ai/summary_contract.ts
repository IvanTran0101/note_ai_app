import summaryPolicy from '../../assets/summary_policy.json';

/**
 * Shared Summary Cloud request/response contract (Phase 2 backend, worker-1 port).
 *
 * This module is the one owner of the frozen v0.3 vocabulary
 * (`docs/summary_api_contract.md`, sections 2-5): the stages, the per-stage
 * input cardinality, the request body schema (including the per-request consent
 * declaration), and the server-owned prompts. It is pure: no AWS SDK, no I/O,
 * no transport types, no provider knowledge.
 *
 * Validation is fail-closed and evidence-mapped:
 *
 * - body schema, stage, cardinality, unknown request fields -> `invalidInput`;
 * - missing/false/mistyped consent or a wrong consent version -> `consentRequired`;
 * - a missing consent object at all -> `consentRequired`; an extra field inside
 *   the consent object -> `invalidInput` (matches `wire_cases.json`
 *   `req.consent.extra_field`);
 * - transport and token-budget overruns -> `inputTooLong`.
 *
 * Client-supplied content is never echoed into a failure message, so a rejected
 * request cannot be reflected back through logs or the error envelope.
 *
 * Token counting is an ESTIMATE, declared as one: the sum of the UTF-8 bytes of
 * the fully rendered messages JSON plus a fixed framing headroom. It is a
 * conservative estimate useful for routing, not a proven token upper bound or
 * DeepSeek tokenizer, and it
 * cannot prevent a call the provider has already billed.
 *
 * @see docs/summary_api_contract.md
 */

/** Stages frozen by the contract: one generation call per request. */
export type SummaryStage = 'direct' | 'section' | 'merge';

/** A validated request for exactly one provider generation. */
export type SummaryRequest = Readonly<{
  stage: SummaryStage;
  /** Trimmed non-empty inputs; `direct`/`section` have 1, `merge` has 2-4. */
  inputs: string[];
}>;

/** What the provider adapter returns after a successful generation. */
export type SummaryResult = Readonly<{
  summary: string;
  usage: Readonly<{ inputTokens: number; outputTokens: number; }>;
}>;

/** Per-account minute quota decision produced by `quota.ts`. */
export type QuotaDecision =
  | Readonly<{ allowed: true; }>
  | Readonly<{ allowed: false; retryAfterSeconds: number; }>;

/** Error codes in the contract's failure envelope. */
export type SummaryErrorCode =
  | 'invalidInput'
  | 'inputTooLong'
  | 'unauthorized'
  | 'consentRequired'
  | 'rateLimited'
  | 'providerUnavailable'
  | 'invalidOutput'
  | 'timeout'
  | 'unexpected';

/**
 * Every refusal this feature reports travels as a `SummaryFailure`, so the HTTP
 * layer maps codes to statuses in one place and no raw provider exception,
 * token, input, or summary text can reach a response. `message` stays generic:
 * a caller may log it, never show it to the user.
 */
export class SummaryFailure extends Error {
  readonly code: SummaryErrorCode;
  /** Only set for `rateLimited`; bounded positive whole seconds. */
  readonly retryAfterSeconds: number | undefined;

  constructor(code: SummaryErrorCode, message: string, retryAfterSeconds?: number) {
    super(message);
    this.name = 'SummaryFailure';
    this.code = code;
    this.retryAfterSeconds = retryAfterSeconds;
  }
}

/** Operational input cap for one generation, prompt and framing included. */
export const MAX_INPUT_TOKENS_PER_CALL = summaryPolicy.maxInputEstimate;
export const MAX_BODY_BYTES_UTF8 = summaryPolicy.maxBodyBytesUtf8;
export const CONSENT_VERSION = summaryPolicy.consentVersion;
export const ESTIMATE_FRAMING_HEADROOM_TOKENS = summaryPolicy.framingHeadroom;
export const DIRECT_MAX_OUTPUT_TOKENS = summaryPolicy.stages.direct.maxOutputTokens;
export const SECTION_MAX_OUTPUT_TOKENS = summaryPolicy.stages.section.maxOutputTokens;
export const MERGE_MAX_OUTPUT_TOKENS = summaryPolicy.stages.merge.maxOutputTokens;
export const MIN_MERGE_INPUTS = 2;
export const MAX_MERGE_INPUTS = summaryPolicy.maxChunks;

export const maxOutputTokensForStage = (stage: SummaryStage): number =>
  summaryPolicy.stages[stage].maxOutputTokens;

// The bundled asset is trusted configuration, but malformed numeric values must
// never turn an estimate comparison into NaN or weaken startup validation.
const policyKeys = ['schemaVersion', 'consentVersion', 'maxInputEstimate', 'framingHeadroom',
  'maxBodyBytesUtf8', 'maxChunks', 'maxGenerationCalls', 'stages'];
if (Object.keys(summaryPolicy).length !== policyKeys.length ||
  policyKeys.some(key => !Object.hasOwn(summaryPolicy, key)) ||
  summaryPolicy.schemaVersion !== 1 || !summaryPolicy.consentVersion.trim()) {
  throw new Error('Invalid Summary policy schema');
}
for (const value of [summaryPolicy.maxInputEstimate, summaryPolicy.maxBodyBytesUtf8,
summaryPolicy.maxChunks, summaryPolicy.maxGenerationCalls]) {
  if (!Number.isSafeInteger(value) || value <= 0) throw new Error('Invalid Summary policy limit');
}
if (!Number.isSafeInteger(summaryPolicy.framingHeadroom) || summaryPolicy.framingHeadroom < 0 ||
  summaryPolicy.maxInputEstimate <= summaryPolicy.framingHeadroom || summaryPolicy.maxChunks < 2 ||
  summaryPolicy.maxGenerationCalls !== summaryPolicy.maxChunks + 1 ||
  Object.keys(summaryPolicy.stages).sort().join(',') !== 'direct,merge,section') {
  throw new Error('Invalid Summary policy budget');
}
for (const data of Object.values(summaryPolicy.stages)) {
  if (Object.keys(data).sort().join(',') !== 'maxOutputTokens,systemPrompt,userPrompt' ||
    !Number.isSafeInteger(data.maxOutputTokens) || data.maxOutputTokens <= 0 ||
    typeof data.systemPrompt !== 'string' || !data.systemPrompt.trim() ||
    typeof data.userPrompt !== 'string' || !data.userPrompt.trim()) {
    throw new Error('Invalid Summary stage policy');
  }
}

const STAGES: readonly SummaryStage[] = ['direct', 'section', 'merge'];

/** The contract allows exactly these top-level request fields. */
const REQUEST_FIELDS: readonly string[] = ['stage', 'inputs', 'consent'];

/** Extra fields inside `consent` are a schema defect, not a consent defect. */
const CONSENT_FIELDS: readonly string[] = ['accepted', 'version'];

const textEncoder = new TextEncoder();

const utf8ByteLength = (value: string): number => textEncoder.encode(value).byteLength;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const isStage = (value: unknown): value is SummaryStage =>
  typeof value === 'string' && (STAGES as readonly string[]).includes(value);

const fail = (code: SummaryErrorCode, message: string): never => {
  throw new SummaryFailure(code, message);
};

/** `direct`/`section`: exactly one input; `merge`: 2-4, order preserved. */
const cardinalityFor = (stage: SummaryStage): Readonly<{ min: number; max: number; }> =>
  stage === 'merge' ? { min: MIN_MERGE_INPUTS, max: MAX_MERGE_INPUTS } : { min: 1, max: 1 };

/**
 * Reads the `inputs` array: strings only, trimmed at the edges only, non-empty
 * after trimming, and right count for the stage. Interior whitespace, newlines,
 * and Unicode are preserved exactly as sent.
 */
const readInputs = (value: unknown, stage: SummaryStage): string[] => {
  if (!Array.isArray(value)) {
    return fail('invalidInput', 'inputs must be an array of strings');
  }
  const { min, max } = cardinalityFor(stage);
  if (value.length < min || value.length > max) {
    return fail('invalidInput', `stage ${stage} requires ${min === max ? min : `${min}-${max}`} inputs`);
  }
  return value.map((element) => {
    if (typeof element !== 'string') {
      return fail('invalidInput', 'every input must be a string');
    }
    const trimmed = element.trim();
    if (trimmed.length === 0) {
      return fail('invalidInput', 'an input is empty after trimming');
    }
    return trimmed;
  });
};

/**
 * Validates the per-request consent declaration. A missing, false, mistyped, or
 * wrong-version declaration is `consentRequired`; an unknown field inside the
 * object is `invalidInput` because the request schema, not the consent, failed.
 */
const readConsent = (value: unknown): void => {
  if (!isRecord(value)) {
    return fail('consentRequired', 'consent declaration is missing');
  }
  for (const key of Object.keys(value)) {
    if (!CONSENT_FIELDS.includes(key)) {
      return fail('invalidInput', 'consent has an unexpected field');
    }
  }
  if (value.accepted !== true) {
    return fail('consentRequired', 'consent must be accepted');
  }
  if (value.version !== CONSENT_VERSION) {
    return fail('consentRequired', 'consent version is not accepted');
  }
};

/**
 * Parses and validates a raw `POST /ai/summary` JSON body.
 *
 * Applied in contract order: transport cap, JSON object, unknown fields, stage,
 * consent, inputs. The returned request is what the handler estimates and the
 * provider adapter renders; nothing else from the body is carried forward.
 *
 * @throws {SummaryFailure} `inputTooLong` above 256 KiB UTF-8, otherwise
 * `invalidInput` or `consentRequired`.
 */
export const parseSummaryBody = (body: string): SummaryRequest => {
  if (typeof body !== 'string' || body.length === 0) {
    return fail('invalidInput', 'request body is missing');
  }
  if (utf8ByteLength(body) > MAX_BODY_BYTES_UTF8) {
    return fail('inputTooLong', 'request body exceeds the transport cap');
  }

  let decoded: unknown;
  try {
    decoded = JSON.parse(body);
  } catch {
    return fail('invalidInput', 'request body is not valid JSON');
  }
  if (!isRecord(decoded)) {
    return fail('invalidInput', 'request body must be a JSON object');
  }

  for (const key of Object.keys(decoded)) {
    if (!REQUEST_FIELDS.includes(key)) {
      return fail('invalidInput', 'request has an unexpected field');
    }
  }
  if (!isStage(decoded.stage)) {
    return fail('invalidInput', 'stage is missing or unknown');
  }

  readConsent(decoded.consent);
  return { stage: decoded.stage, inputs: readInputs(decoded.inputs, decoded.stage) };
};

/**
 * Renders the server-owned chat messages for a validated request.
 *
 * The system message carries the stage policy; the user message carries the
 * inputs as a JSON string/array, which keeps client text in the data position
 * and preserves order. Also re-validates the request, so a caller that skipped
 * `parseSummaryBody` cannot send a malformed generation.
 *
 * @throws {SummaryFailure} `invalidInput` for an unknown stage, wrong
 * cardinality, or a non-string/blank input.
 */
export const buildSummaryMessages = (
  request: SummaryRequest,
): ReadonlyArray<Readonly<{ role: 'system' | 'user'; content: string; }>> => {
  if (!isRecord(request) || !isStage(request.stage)) {
    return fail('invalidInput', 'request stage is missing or unknown');
  }
  const inputs = readInputs(request.inputs, request.stage);
  const payload = request.stage === 'merge' ? JSON.stringify(inputs) : JSON.stringify(inputs[0]);
  return [
    { role: 'system', content: summaryPolicy.stages[request.stage].systemPrompt },
    { role: 'user', content: `${summaryPolicy.stages[request.stage].userPrompt}\n${payload}` },
  ];
};

/**
 * Conservative ESTIMATE of the prompt tokens one generation would send: the
 * UTF-8 byte length of the fully rendered messages JSON plus
 * `ESTIMATE_FRAMING_HEADROOM_TOKENS` for the rest of the request envelope.
 *
 * This is deliberately not a tokenizer and not a 2-chars-per-token ratio. It
 * over-counts most scripts, so it can refuse a call that would have fit; it is
 * used for routing/size guards only, and the provider's reported usage remains
 * the record of what was actually billed.
 *
 * @throws {SummaryFailure} `invalidInput` for a malformed request (via
 * `buildSummaryMessages`).
 */
export const estimateSummaryInputTokens = (request: SummaryRequest): number =>
  utf8ByteLength(JSON.stringify(buildSummaryMessages(request))) + ESTIMATE_FRAMING_HEADROOM_TOKENS;
