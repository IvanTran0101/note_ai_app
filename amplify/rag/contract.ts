/**
 * RAG v1 wire contract: request parsing, the two-Noul Jev envelope/verdict, and the generated
 * answer citation check.
 *
 * Contract: docs/contracts/rag_api_v1.md §2/§3/§6. Policy: docs/rag/policy_v1.json
 * `technicalDefaults.wire`, `safety`, `jev` and `mockOnly`.
 *
 * Boundaries:
 *  - the body supplies only `wireVersion`/`question`/`scope`; actor, owner, model, consent,
 *    thresholds and evidence never come from the client;
 *  - a small stdlib scanner refuses duplicate JSON keys (escaped or raw) and nesting beyond
 *    MAX_JSON_DEPTH before `JSON.parse` runs, so a duplicate can never silently win;
 *  - booleans, fractions, non-finite and unsafe numbers are refused, never coerced;
 *  - the Noul envelope is exactly `{model, answers, usage}` (the version is fixed request
 *    config, not a response field) and the decision follows the Phase 1 oracle branch order;
 *  - a generated answer must carry the exact approved evidence; that proves lineage, never
 *    semantic truth.
 */
import { policy, RagFailure } from './types';
import type { Counter, Evidence, RagRequest, RuntimeConfig, Scope, Source, Verdict } from './types';
import { countTokens, countUnicodeCharacters, isSafeInteger, isWellFormed } from './chunking';

export const WIRE_VERSION = 1;
export const MAX_IDENTIFIER_CODE_POINTS = 128;
export const REQUEST_MAX_BYTES: number = policy.technicalDefaults.wire.bodyMaxUtf8Bytes;
export const QUESTION_MAX_CODE_POINTS: number = policy.technicalDefaults.wire.questionMaxCodePoints;
export const QUESTION_MAX_BYTES: number = policy.technicalDefaults.wire.questionMaxUtf8Bytes;
export const RESPONSE_MAX_BYTES: number = policy.technicalDefaults.wire.responseMaxUtf8Bytes;
export const OUTPUT_MAX_TOKENS: number = policy.technicalDefaults.wire.outputMaxTokens;
export const CONSENT_VERSION: string = policy.safety.consentVersion;
/** Deepest JSON nesting the duplicate-key scanner walks before refusing (the wire needs two). */
export const MAX_JSON_DEPTH = 32;
/** Upper bound mirrored from the Phase 1 oracle for one generated answer. */
export const MAX_GENERATED_SOURCES = 24;
export const ABSTENTION_REASONS = ['INSUFFICIENT_EVIDENCE', 'UNRESOLVED_CONFLICT', 'UNCERTAIN'] as const;
export const NOUL_QUESTION_IDS = ['answerable_from_evidence', 'has_unresolved_conflict'] as const;

export type NoulQuestionId = (typeof NOUL_QUESTION_IDS)[number];
export type NoulAnswer = Readonly<{ type: 'noul'; noul: number }>;
export type NoulEnvelope = Readonly<{
  model: string;
  answers: Readonly<Record<NoulQuestionId, NoulAnswer>>;
  usage: Readonly<{ input_tokens: number; output_tokens: number }>;
}>;
export type GeneratedAnswer = Readonly<{ answer: string; sources: readonly Source[] }>;

const encoder = new TextEncoder();
const ASCII_CONTROL = /[\u0000-\u001f\u007f]/;
const SOURCE_KEYS = ['sourceId', 'noteId', 'revision', 'title', 'startOffset', 'endOffset', 'quote'] as const;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

/** Exact key-set equality: every required key present and no additional key. */
const hasExactKeys = (value: Record<string, unknown>, required: readonly string[]): boolean =>
  Object.keys(value).length === required.length &&
  required.every((key) => Object.prototype.hasOwnProperty.call(value, key));

/** A lone surrogate cannot survive UTF-8 egress; it must be refused, not replaced. */
export const isValidUnicode = (text: string): boolean => isWellFormed(text);

/** Contract identifier: string, trimmed, nonblank, well-formed, <=128 code points, no controls. */
export const isValidIdentifier = (value: unknown): value is string =>
  typeof value === 'string' &&
  value.length > 0 &&
  value === value.trim() &&
  !ASCII_CONTROL.test(value) &&
  isValidUnicode(value) &&
  countUnicodeCharacters(value) <= MAX_IDENTIFIER_CODE_POINTS;

const utf8Bytes = (text: string): number => encoder.encode(text).byteLength;

type JsonFrame = { kind: 'object' | 'array'; state: number; keys: Set<string> | null };

/**
 * Refuses duplicate object keys after JSON escape decoding and nesting beyond MAX_JSON_DEPTH.
 * Anything the scanner cannot follow is left to `JSON.parse`, so malformed JSON still fails as
 * INVALID_INPUT without a second, competing syntax opinion.
 */
const assertNoDuplicateKeys = (text: string): void => {
  const stack: JsonFrame[] = [];
  let index = 0;

  const skipWhitespace = (): void => {
    while (index < text.length && ' \t\n\r'.includes(text[index] as string)) index += 1;
  };

  const readString = (): string | null => {
    const start = index;
    index += 1;
    while (index < text.length) {
      const unit = text.charCodeAt(index);
      if (unit === 0x22) {
        index += 1;
        try {
          return JSON.parse(text.slice(start, index)) as string;
        } catch {
          return null;
        }
      }
      index += unit === 0x5c ? 2 : 1;
    }
    return null;
  };

  const readValue = (): boolean => {
    skipWhitespace();
    const char = text[index];
    if (char === '{' || char === '[') {
      if (stack.length >= MAX_JSON_DEPTH) throw new RagFailure('INVALID_INPUT');
      stack.push({ kind: char === '{' ? 'object' : 'array', state: 0, keys: char === '{' ? new Set() : null });
      index += 1;
      return true;
    }
    if (char === '"') return readString() !== null;
    const start = index;
    while (index < text.length && !',}] \t\n\r'.includes(text[index] as string)) index += 1;
    return index > start;
  };

  while (index < text.length) {
    skipWhitespace();
    if (index >= text.length) return;
    const frame = stack[stack.length - 1];
    if (frame === undefined) {
      if (!readValue()) return;
      if (stack.length === 0) return; // scalar root: nothing left to scan
      continue;
    }
    const char = text[index];
    if (frame.kind === 'object') {
      if (frame.state === 0) {
        if (char === '}') {
          index += 1;
          stack.pop();
          continue;
        }
        const key = readString();
        if (key === null || frame.keys === null) return;
        if (frame.keys.has(key)) throw new RagFailure('INVALID_INPUT');
        frame.keys.add(key);
        frame.state = 1;
        continue;
      }
      if (frame.state === 1) {
        if (char !== ':') return;
        index += 1;
        frame.state = 2;
        continue;
      }
      if (frame.state === 2) {
        if (!readValue()) return;
        frame.state = 3;
        continue;
      }
      if (char === ',') {
        index += 1;
        frame.state = 0;
        continue;
      }
      if (char === '}') {
        index += 1;
        stack.pop();
        continue;
      }
      return;
    }
    if (frame.state === 0) {
      if (char === ']') {
        index += 1;
        stack.pop();
        continue;
      }
      if (!readValue()) return;
      frame.state = 1;
      continue;
    }
    if (char === ',') {
      index += 1;
      frame.state = 0;
      continue;
    }
    if (char === ']') {
      index += 1;
      stack.pop();
      continue;
    }
    return;
  }
};

const parseScope = (value: unknown): Scope => {
  if (!isRecord(value)) throw new RagFailure('INVALID_INPUT');
  if (value['type'] === 'account') {
    if (!hasExactKeys(value, ['type'])) throw new RagFailure('INVALID_INPUT');
    return Object.freeze({ type: 'account' });
  }
  if (value['type'] === 'note') {
    if (!hasExactKeys(value, ['type', 'noteId']) || !isValidIdentifier(value['noteId'])) {
      throw new RagFailure('INVALID_INPUT');
    }
    return Object.freeze({ type: 'note', noteId: value['noteId'] });
  }
  throw new RagFailure('INVALID_INPUT');
};

/** Parses the raw request body into the only request shape the backend accepts. */
export function parseRequest(body: string): RagRequest {
  if (typeof body !== 'string' || body.length === 0) throw new RagFailure('INVALID_INPUT');
  if (utf8Bytes(body) > REQUEST_MAX_BYTES) throw new RagFailure('INPUT_TOO_LONG');
  if (!isValidUnicode(body)) throw new RagFailure('INVALID_INPUT');
  assertNoDuplicateKeys(body);

  let value: unknown;
  try {
    value = JSON.parse(body);
  } catch {
    throw new RagFailure('INVALID_INPUT');
  }
  if (!isRecord(value) || !hasExactKeys(value, ['wireVersion', 'question', 'scope'])) {
    throw new RagFailure('INVALID_INPUT');
  }
  if (!isSafeInteger(value['wireVersion']) || value['wireVersion'] !== WIRE_VERSION) {
    throw new RagFailure('INVALID_INPUT');
  }
  const question = value['question'];
  if (typeof question !== 'string' || !isValidUnicode(question) || question.trim().length === 0) {
    throw new RagFailure('INVALID_INPUT');
  }
  if (countUnicodeCharacters(question) > QUESTION_MAX_CODE_POINTS || utf8Bytes(question) > QUESTION_MAX_BYTES) {
    throw new RagFailure('INPUT_TOO_LONG');
  }
  return Object.freeze({ wireVersion: WIRE_VERSION, question, scope: parseScope(value['scope']) });
}

function noulUnavailable(): never {
  throw new RagFailure('EVIDENCE_VALIDATION_UNAVAILABLE');
}

/**
 * Validates one Jev response: exactly `{model, answers, usage}`, the two named Noul answers,
 * finite probabilities in [0, 1] and safe-integer usage. There is no questionSetVersion field
 * and no confidence/free-text field; the model must be the configured one.
 */
export function validateNoul(value: unknown, expectedModel: string): NoulEnvelope {
  if (!isRecord(value) || !isValidIdentifier(expectedModel)) noulUnavailable();
  if (!hasExactKeys(value, ['model', 'answers', 'usage'])) noulUnavailable();
  if (value['model'] !== expectedModel) noulUnavailable();

  const answersValue = value['answers'];
  if (!isRecord(answersValue) || !hasExactKeys(answersValue, NOUL_QUESTION_IDS)) noulUnavailable();
  const answers = {} as Record<NoulQuestionId, NoulAnswer>;
  for (const questionId of NOUL_QUESTION_IDS) {
    const answer = answersValue[questionId];
    if (!isRecord(answer) || !hasExactKeys(answer, ['type', 'noul'])) noulUnavailable();
    const probability = answer['noul'];
    if (answer['type'] !== 'noul') noulUnavailable();
    if (typeof probability !== 'number' || !Number.isFinite(probability) || probability < 0 || probability > 1) {
      noulUnavailable();
    }
    answers[questionId] = Object.freeze({ type: 'noul', noul: probability });
  }

  const usageValue = value['usage'];
  if (!isRecord(usageValue) || !hasExactKeys(usageValue, ['input_tokens', 'output_tokens'])) noulUnavailable();
  const inputTokens = usageValue['input_tokens'];
  const outputTokens = usageValue['output_tokens'];
  if (!isSafeInteger(inputTokens) || inputTokens < 0) noulUnavailable();
  if (!isSafeInteger(outputTokens) || outputTokens < 0) noulUnavailable();

  return Object.freeze({
    model: expectedModel,
    answers: Object.freeze(answers),
    usage: Object.freeze({ input_tokens: inputTokens, output_tokens: outputTokens }),
  });
}

const readRuntimePolicy = (config: RuntimeConfig): Readonly<{ model: string; high: number; low: number }> => {
  if (config === null || typeof config !== 'object') throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  const model = config.model;
  if (typeof model !== 'string' || !isValidIdentifier(model)) throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  const thresholds = config.thresholds;
  if (thresholds === null || thresholds === undefined || typeof thresholds !== 'object') {
    throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
  const high = thresholds.answerabilityMin;
  const low = thresholds.conflictMax;
  if (typeof high !== 'number' || !Number.isFinite(high) || !(high > 0.5 && high <= 1)) {
    throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
  if (typeof low !== 'number' || !Number.isFinite(low) || !(low >= 0 && low < 0.5)) {
    throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
  return { model, high, low };
};

/**
 * The Phase 1 oracle branch order: a high conflict wins, then insufficient support, then
 * uncertainty, otherwise ALLOW. The two Noul values are never averaged.
 */
export function decideNoul(value: unknown, config: RuntimeConfig): Verdict {
  const { model, high, low } = readRuntimePolicy(config);
  let envelope: NoulEnvelope;
  try {
    envelope = validateNoul(value, model);
  } catch {
    throw new RagFailure('EVIDENCE_VALIDATION_UNAVAILABLE');
  }
  const support = envelope.answers.answerable_from_evidence.noul;
  const conflict = envelope.answers.has_unresolved_conflict.noul;
  if (conflict >= high) return 'UNRESOLVED_CONFLICT';
  if (support <= low) return 'INSUFFICIENT_EVIDENCE';
  if (support < high || conflict > low) return 'UNCERTAIN';
  return 'ALLOW';
}

export const isValidSource = (value: unknown): value is Source => {
  if (!isRecord(value) || !hasExactKeys(value, SOURCE_KEYS)) return false;
  if (!isValidIdentifier(value['sourceId']) || !isValidIdentifier(value['noteId'])) return false;
  if (!isSafeInteger(value['revision']) || value['revision'] < 1) return false;
  const start = value['startOffset'];
  const end = value['endOffset'];
  if (!isSafeInteger(start) || !isSafeInteger(end) || start < 0 || end <= start) return false;
  const title = value['title'];
  const quote = value['quote'];
  if (typeof title !== 'string' || !isValidUnicode(title)) return false;
  if (typeof quote !== 'string' || !isValidUnicode(quote)) return false;
  // The quote is the exact span slice: a bisected surrogate pair would leave a lone surrogate.
  return quote.length === end - start;
};

const approvedSourceMap = (evidence: Evidence): ReadonlyMap<string, Source> => {
  if (!isRecord(evidence) || !Array.isArray(evidence.sources)) {
    throw new RagFailure('EVIDENCE_VALIDATION_UNAVAILABLE');
  }
  const approved = new Map<string, Source>();
  for (const source of evidence.sources) {
    if (!isValidSource(source) || approved.has(source.sourceId)) {
      throw new RagFailure('EVIDENCE_VALIDATION_UNAVAILABLE');
    }
    approved.set(source.sourceId, source);
  }
  return approved;
};

const readCitedSource = (candidate: unknown, approved: ReadonlyMap<string, Source>): Source => {
  if (!isRecord(candidate) || !hasExactKeys(candidate, SOURCE_KEYS)) {
    throw new RagFailure('INVALID_PROVIDER_OUTPUT');
  }
  const sourceId = candidate['sourceId'];
  const expected = typeof sourceId === 'string' ? approved.get(sourceId) : undefined;
  if (expected === undefined || !SOURCE_KEYS.every((key) => candidate[key] === expected[key])) {
    throw new RagFailure('INVALID_PROVIDER_OUTPUT');
  }
  return expected;
};

/**
 * Validates one generated `{answer, sources}` payload against the approved evidence: named
 * citation labels only, no invented/renamed/copied-outside source, at least one citation and
 * one reference per used source, and the 1024-token output cap from a guarded counter.
 */
export function validateGenerated(value: unknown, evidence: Evidence, counter: Counter): GeneratedAnswer {
  const approved = approvedSourceMap(evidence);
  if (!isRecord(value) || !hasExactKeys(value, ['answer', 'sources'])) {
    throw new RagFailure('INVALID_PROVIDER_OUTPUT');
  }
  const answer = value['answer'];
  if (typeof answer !== 'string' || !isValidUnicode(answer) || answer.trim().length === 0) {
    throw new RagFailure('INVALID_PROVIDER_OUTPUT');
  }
  if (countTokens(counter, answer) > OUTPUT_MAX_TOKENS) throw new RagFailure('INVALID_PROVIDER_OUTPUT');

  const candidates = value['sources'];
  if (!Array.isArray(candidates) || candidates.length === 0 || candidates.length > MAX_GENERATED_SOURCES) {
    throw new RagFailure('INVALID_PROVIDER_OUTPUT');
  }
  const sources: Source[] = [];
  const used = new Set<string>();
  for (const candidate of candidates) {
    const source = readCitedSource(candidate, approved);
    if (used.has(source.sourceId)) throw new RagFailure('INVALID_PROVIDER_OUTPUT');
    used.add(source.sourceId);
    sources.push(source);
  }

  const referenced = new Set<string>();
  for (const match of answer.matchAll(/\[(S[0-9]+)\]/g)) referenced.add(match[1] as string);
  if (referenced.size === 0 || referenced.size !== used.size) throw new RagFailure('INVALID_PROVIDER_OUTPUT');
  for (const label of referenced) {
    if (!used.has(label)) throw new RagFailure('INVALID_PROVIDER_OUTPUT');
  }
  return Object.freeze({ answer, sources: Object.freeze(sources) });
}
