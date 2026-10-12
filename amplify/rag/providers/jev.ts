/**
 * Jev (TypeSafe System One) HTTP adapter for the Phase 4 single RAG evidence gate.
 *
 * Owns everything vendor-specific for the gate: the fixed approved endpoint, the fixed approved
 * model `jev-1.13.0`, the exact two-Noul question set from `docs/rag/policy_v1.json`, the single
 * non-streaming request, the 4-second deadline, the 64 KiB response cap, and the normalization of
 * a vendor response into the strict P2 `{model, answers, usage}` envelope.
 *
 * Trust boundaries:
 *  - the endpoint, the model, and both question instructions/criteria are contract constants; a
 *    caller-supplied model that differs, or altered criteria, is refused before any egress, so a
 *    caller can never retune or redirect the gate;
 *  - `questionSetVersion` is local receipt config, not wire data: it is deliberately absent from
 *    the request body;
 *  - vendor extra fields are ignored, core fields are required: `model` must equal the approved
 *    model, both named answers must be finite probabilities in [0, 1], and `usage` must carry
 *    finite non-negative safe integers. Usage numbers are never invented or estimated;
 *  - the normalized envelope is handed to the Phase 2 `validateNoul` validator, which stays the
 *    single authority on the strict envelope shape.
 *
 * One call per invocation, no retry, no redirect, no raw body or key logging.
 */
import { RagFailure } from '../types';
import { LIVE_QUESTION_SET } from '../question_set';
import type { JevInput, Providers } from '../types';
import { isValidUnicode, validateNoul } from '../contract';
import type { NoulEnvelope } from '../contract';
import {
  DEFAULT_MAX_RESPONSE_BYTES,
  cancelBody,
  decodeUtf8,
  isRecord,
  parseJsonObject,
  readBoundedBody,
  startDeadline,
  withinDeadline,
} from './http_body';

/** Frozen by the approved Phase 4 contract; not client-configurable. */
export const JEV_ENDPOINT = 'https://api.typesafe.ai/v1/systemone';
export const JEV_MODEL = 'jev-1.13.0';
export const JEV_TIMEOUT_MS = 4000;

/** Synchronous metadata callback for the root receipt; never a billing claim. */
export type ProviderUsage = Readonly<{ model: string; inputTokens: number; outputTokens: number }>;

export type JevProviderOptions = Readonly<{
  /** Read from the runtime secret; never hard-coded, logged or echoed. */
  apiKey: string;
  /** Injected in tests; production uses the runtime's global `fetch`. */
  fetchImpl?: typeof fetch;
  /** Optional receipt hook; synchronous and side-effect-only. */
  onUsage?: (usage: ProviderUsage) => void;
  /** Test seam, clamped to the approved 4000 ms bound. @default 4000 */
  timeoutMs?: number;
  /** Test seam, clamped to the approved 65536-byte response cap. @default 65536 */
  maxResponseBytes?: number;
}>;

type ApprovedQuestion = Readonly<{
  type: 'noul';
  instructions: string;
  criteria: Readonly<{ true: string; false: string }>;
}>;

const APPROVED_QUESTIONS = LIVE_QUESTION_SET.questions as unknown as Readonly<Record<string, ApprovedQuestion>>;
const NOUL_IDS = Object.freeze(Object.keys(APPROVED_QUESTIONS).sort());

/** Always throws; also usable as the transport helper's `fail` factory. */
function gateUnavailable(_message: string): never {
  throw new RagFailure('EVIDENCE_VALIDATION_UNAVAILABLE');
}

function noEgress(): never {
  throw new RagFailure('EVIDENCE_VALIDATION_UNAVAILABLE');
}

/** Exact approved question set: two named Noul questions with unaltered instructions/criteria. */
const assertApprovedQuestions = (value: unknown): void => {
  if (!isRecord(value)) noEgress();
  const sent = Object.keys(value).sort();
  if (sent.length !== NOUL_IDS.length || !NOUL_IDS.every((id) => sent.includes(id))) noEgress();
  for (const id of NOUL_IDS) {
    const question = value[id];
    const approved = APPROVED_QUESTIONS[id];
    if (approved === undefined) noEgress();
    if (!isRecord(question)) noEgress();
    if (Object.keys(question).sort().join(',') !== 'criteria,instructions,type') noEgress();
    if (question['type'] !== 'noul') noEgress();
    if (question['instructions'] !== approved.instructions) noEgress();
    const criteria = question['criteria'];
    if (!isRecord(criteria)) noEgress();
    if (Object.keys(criteria).sort().join(',') !== 'false,true') noEgress();
    if (criteria['true'] !== approved.criteria.true || criteria['false'] !== approved.criteria.false) noEgress();
  }
};

const readState = (value: unknown): Readonly<{ question: string; evidence: string }> => {
  if (!isRecord(value)) noEgress();
  if (Object.keys(value).sort().join(',') !== 'evidence,question') noEgress();
  const question = value['question'];
  const evidence = value['evidence'];
  if (typeof question !== 'string' || !isValidUnicode(question) || question.trim().length === 0) noEgress();
  if (typeof evidence !== 'string' || !isValidUnicode(evidence) || evidence.trim().length === 0) noEgress();
  return { question, evidence };
};

/**
 * Validates the caller input against the fixed approved contract and builds the single wire body
 * from the approved constants (never from caller-supplied criteria), dropping the local
 * `questionSetVersion`.
 */
export const buildJevRequestBody = (input: JevInput): string => {
  if (!isRecord(input)) noEgress();
  if (input['model'] !== JEV_MODEL) noEgress();
  if (input['questionSetVersion'] !== LIVE_QUESTION_SET.questionSetVersion) noEgress();
  assertApprovedQuestions(input['questions']);
  const state = readState(input['state']);
  return JSON.stringify({
    model: JEV_MODEL,
    questions: APPROVED_QUESTIONS,
    state: { question: state.question, evidence: state.evidence },
  });
};

/**
 * Normalizes a vendor response to the strict P2 envelope: only the three core fields are read,
 * official extra fields are ignored, and `validateNoul` makes the final strict decision.
 */
export const normalizeJevResponse = (value: unknown): NoulEnvelope => {
  if (!isRecord(value) || value['model'] !== JEV_MODEL) gateUnavailable('unexpected model');
  const answersValue = value['answers'];
  if (!isRecord(answersValue)) gateUnavailable('answers are missing');
  if (Object.keys(answersValue).sort().join(',') !== NOUL_IDS.join(',')) gateUnavailable('unexpected question IDs');
  const answers: Record<string, Readonly<{ type: 'noul'; noul: number }>> = {};
  for (const id of NOUL_IDS) {
    const answer = answersValue[id];
    if (!isRecord(answer) || answer['type'] !== 'noul') gateUnavailable('answer is malformed');
    const noul = answer['noul'];
    if (typeof noul !== 'number' || !Number.isFinite(noul) || noul < 0 || noul > 1) {
      gateUnavailable('answer is not a probability');
    }
    answers[id] = { type: 'noul', noul };
  }
  const usageValue = value['usage'];
  if (!isRecord(usageValue)) gateUnavailable('usage is missing');
  const inputTokens = usageValue['input_tokens'];
  const outputTokens = usageValue['output_tokens'];
  if (!Number.isSafeInteger(inputTokens) || (inputTokens as number) < 0) gateUnavailable('usage is malformed');
  if (!Number.isSafeInteger(outputTokens) || (outputTokens as number) < 0) gateUnavailable('usage is malformed');
  return validateNoul({ model: JEV_MODEL, answers, usage: { input_tokens: inputTokens, output_tokens: outputTokens } }, JEV_MODEL);
};

const clampBound = (value: number | undefined, approved: number): number =>
  value === undefined ? approved : Math.min(value, approved);

/**
 * Creates the production Jev adapter. A missing API key or an invalid bound is a composition
 * failure, not a request failure, and fails closed before any request is made.
 */
export const createJevProvider = ({
  apiKey,
  fetchImpl,
  onUsage,
  timeoutMs,
  maxResponseBytes,
}: JevProviderOptions): Providers['jev'] => {
  if (typeof apiKey !== 'string' || apiKey.trim().length === 0) {
    throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
  if (timeoutMs !== undefined && (!Number.isSafeInteger(timeoutMs) || timeoutMs <= 0)) {
    throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
  if (maxResponseBytes !== undefined && (!Number.isSafeInteger(maxResponseBytes) || maxResponseBytes <= 0)) {
    throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
  const callFetch: typeof fetch = fetchImpl ?? ((input, init) => fetch(input, init));
  const deadlineMs = clampBound(timeoutMs, JEV_TIMEOUT_MS);
  const byteCap = clampBound(maxResponseBytes, DEFAULT_MAX_RESPONSE_BYTES);

  return async (input, signal) => {
    const body = buildJevRequestBody(input);
    const deadline = startDeadline(deadlineMs, signal);
    let cancelPendingRead: (() => void) | undefined;

    const attempt = (async (): Promise<unknown> => {
      const response = await callFetch(JEV_ENDPOINT, {
        method: 'POST',
        headers: {
          authorization: `Bearer ${apiKey}`,
          'content-type': 'application/json',
          accept: 'application/json',
        },
        body,
        redirect: 'error',
        signal: deadline.signal,
      });

      if (response.status === 429) {
        cancelBody(response);
        throw new RagFailure('RATE_LIMITED');
      }
      if (response.status === 408) {
        cancelBody(response);
        throw new RagFailure('TIMEOUT');
      }
      if (response.status < 200 || response.status >= 300) {
        // 4xx/5xx/auth failures are one safe upstream class: status and body are never echoed,
        // and there is no automatic retry.
        cancelBody(response);
        throw new RagFailure('EVIDENCE_VALIDATION_UNAVAILABLE');
      }

      const bytes = await readBoundedBody(response, byteCap, (cancel) => {
        cancelPendingRead = cancel;
      }, gateUnavailable);
      const envelope = normalizeJevResponse(parseJsonObject(decodeUtf8(bytes, gateUnavailable), gateUnavailable));
      if (onUsage !== undefined) {
        try {
          onUsage({ model: envelope.model, inputTokens: envelope.usage.input_tokens, outputTokens: envelope.usage.output_tokens });
        } catch {
          // A receipt hook must never change the gate decision.
        }
      }
      return envelope;
    })();

    return withinDeadline(deadline, attempt, () => cancelPendingRead?.(), (error) =>
      error instanceof RagFailure ? error : new RagFailure('EVIDENCE_VALIDATION_UNAVAILABLE'),
    );
  };
};
