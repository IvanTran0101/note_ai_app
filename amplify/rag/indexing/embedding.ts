/**
 * Phase 3 embedding port: the policy-fixed Cohere v3 request over the signed JSON transport.
 *
 * Contract (docs/rag/policy_v1.json `embedding`): model `cohere.embed-multilingual-v3`,
 * `POST /model/cohere.embed-multilingual-v3/invoke`, body `{texts, input_type, truncate}` with
 * `truncate: NONE` — no silent truncation, an over-long input is refused locally instead.
 * `search_document` accepts 1..96 texts; `search_query` accepts exactly one.
 *
 * Every text is checked with the injected real counter before the call: non-empty, well-formed,
 * at most 2048 code points and at most 512 tokens. Provider output must be exactly one finite,
 * non-zero 1024-dimensional float vector per input; anything else is INVALID_PROVIDER_OUTPUT.
 * This module never reserves budget — the worker/probe reserve before calling `embed`.
 */
import { policy, type Counter } from '../types';
import {
  MAX_EMBEDDING_CHARACTERS, MAX_EMBEDDING_TOKENS, countTokens, countUnicodeCharacters,
  isWellFormed,
} from '../chunking';
import { EMBEDDING_DIMENSIONS } from '../retrieval';
import { IndexFailure, type Embedding } from './types';
import {
  BEDROCK_INVOKE_MODEL_PATH, createAwsJson, isAwsRegion, type AwsJson,
} from './aws_http';

/** The policy model; the invoke path whitelist in aws_http is derived from the same value. */
export const EMBEDDING_MODEL: string = policy.embedding.model;
/** Cohere embed accepts at most 96 texts per call (worker EMBED_BATCH_LIMIT mirrors this). */
export const EMBED_BATCH_LIMIT = 96;
export const EMBEDDING_TRUNCATE: string = policy.embedding.truncate;
export const EMBEDDING_PATH: string = BEDROCK_INVOKE_MODEL_PATH;

const INPUT_TYPES: Readonly<Record<'search_document' | 'search_query', string>> = Object.freeze({
  search_document: policy.embedding.documentInputType,
  search_query: policy.embedding.queryInputType,
});

const invalidInput: () => never = () => {
  throw new IndexFailure('INVALID_INPUT', false);
};
const inputTooLong: () => never = () => {
  throw new IndexFailure('INPUT_TOO_LONG', false);
};
const invalidOutput: () => never = () => {
  throw new IndexFailure('INVALID_PROVIDER_OUTPUT', false);
};

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

/** Provider failure codes are already typed; only a malformed success payload is remapped. */
const requireEmbeddings = (payload: unknown, expected: number): readonly (readonly number[])[] => {
  if (!isRecord(payload)) invalidOutput();
  const embeddings = payload['embeddings'];
  if (!Array.isArray(embeddings) || embeddings.length !== expected) invalidOutput();
  const vectors: (readonly number[])[] = [];
  for (const entry of embeddings) {
    if (!Array.isArray(entry) || entry.length !== EMBEDDING_DIMENSIONS) invalidOutput();
    const vector: number[] = [];
    for (const value of entry) {
      if (typeof value !== 'number' || !Number.isFinite(value)) invalidOutput();
      vector.push(value);
    }
    const norm = Math.hypot(...vector);
    if (!Number.isFinite(norm) || norm <= 0) invalidOutput();
    vectors.push(Object.freeze(vector));
  }
  return Object.freeze(vectors);
};

/**
 * `count` is the injected real tokenizer counter (the worker measures with the same one).
 * `request` is the signed aws_http port; tests inject a fake, production uses the region.
 */
export function createEmbedding(region: string, count: Counter, request?: AwsJson): Embedding {
  if (!isAwsRegion(region)) throw new IndexFailure('INVALID_STATE', false);
  if (typeof count !== 'function') throw new IndexFailure('INVALID_STATE', false);
  if (request !== undefined && typeof request !== 'function') {
    throw new IndexFailure('INVALID_STATE', false);
  }
  const call: AwsJson = request ?? createAwsJson(region);

  const measure = (text: string): void => {
    if (text.length === 0 || !isWellFormed(text)) invalidInput();
    if (countUnicodeCharacters(text) > MAX_EMBEDDING_CHARACTERS) inputTooLong();
    // A broken counter throws EVIDENCE_VALIDATION_UNAVAILABLE from countTokens: fail closed.
    if (countTokens(count, text) > MAX_EMBEDDING_TOKENS) inputTooLong();
  };

  return Object.freeze({
    count,
    embed: async (texts, purpose, signal) => {
      if (purpose !== 'search_document' && purpose !== 'search_query') invalidInput();
      if (!Array.isArray(texts) || texts.length === 0 || texts.length > EMBED_BATCH_LIMIT) {
        invalidInput();
      }
      if (purpose === 'search_query' && texts.length !== 1) invalidInput();
      if (!(signal instanceof AbortSignal)) invalidInput();
      const inputs: string[] = [];
      for (const text of texts) {
        if (typeof text !== 'string') invalidInput();
        measure(text);
        inputs.push(text);
      }
      const payload = await call('bedrock', EMBEDDING_PATH, {
        texts: inputs,
        input_type: INPUT_TYPES[purpose],
        truncate: EMBEDDING_TRUNCATE,
      }, signal);
      return requireEmbeddings(payload, inputs.length);
    },
  });
}
