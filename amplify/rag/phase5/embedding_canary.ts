/**
 * IAM-only embedding canary (plan 5.1B): the one fixed-synthetic-text embedding probe.
 *
 * This module owns the canary's complete runtime — the exact event shape, the fixed text, the
 * deadline-bounded runner and the bounded error mapping. It never reads a canonical note, store,
 * snapshot or consent row, never accepts caller text and returns metadata only (no vector, header
 * or raw error). HTTP routing and the production dependency composition stay in `http_lambda`;
 * an HTTP event can never reach this module.
 */
import { RequestDeadline } from '../deadline';
import {
  SELF_HOSTED_EMBEDDING_DIMENSIONS,
  SELF_HOSTED_EMBEDDING_MODEL,
} from '../indexing/self_hosted_embedding';
import { IndexFailure, type IndexDeps } from '../indexing/types';
import { policy, RagFailure } from '../types';
import type { Counter } from '../types';
import type { PilotBudget } from './pilot_budget';

/** The one trusted IAM canary event: exactly `{kind:'embedding-canary.v1'}`, no extra field. */
export const EMBEDDING_CANARY_KIND = 'embedding-canary.v1';
/** Fixed synthetic input; the caller cannot supply note text, a question or a model. */
const EMBEDDING_CANARY_TEXT = 'NoteFlow synthetic embedding canary. No user note content.';
const KNOWN_CANARY_CODES = new Set(Object.keys(policy.technicalDefaults.errorHttpStatus));

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

/**
 * The branch is selected before the private Phase 4 forward and only for an exact non-HTTP
 * payload. An HTTP event is routed first, so a body field can never select it; an IAM caller can
 * only ask for the fixed synthetic probe.
 */
export const isEmbeddingCanaryEvent = (event: unknown): boolean =>
  isRecord(event) &&
  Object.keys(event).length === 1 &&
  event['kind'] === EMBEDDING_CANARY_KIND;

/** Only a fixed code reaches the caller; an unknown error is never echoed or unwrapped. */
export const canaryFailure = (error: unknown): unknown => {
  const raw = error instanceof RagFailure
    ? error.code
    : error instanceof IndexFailure
      ? error.code
      : 'PROVIDER_UNAVAILABLE';
  return Object.freeze({
    status: 'ERROR',
    canary: EMBEDDING_CANARY_KIND,
    code: KNOWN_CANARY_CODES.has(raw) ? raw : 'PROVIDER_UNAVAILABLE',
  });
};

/** The inputs of one fixed-text probe; all are existing production ports. */
export type EmbeddingCanaryDeps = Readonly<{
  embedding: IndexDeps['embedding'];
  budget: PilotBudget;
  countOutput: Counter;
  now: () => number;
}>;

/**
 * Fixed-text canary: counts with both cold tokenizers, reserves the embedding allowance BEFORE
 * dispatch, then embeds once. It never reads a canonical note, store, snapshot or consent row,
 * never accepts caller text and returns only bounded metadata (no vector, header or raw error).
 */
export const runEmbeddingCanary = async (
  deps: EmbeddingCanaryDeps,
  signal: AbortSignal,
): Promise<unknown> => {
  const { embedding, budget, countOutput, now } = deps;
  const startedAt = now();
  const text = EMBEDDING_CANARY_TEXT;
  const embeddingTokens = embedding.count(text);
  const deepseekTokens = countOutput(text);
  if (!Number.isSafeInteger(embeddingTokens) || embeddingTokens < 0 ||
      !Number.isSafeInteger(deepseekTokens) || deepseekTokens < 0) {
    throw new IndexFailure('INVALID_STATE', false);
  }
  // The one paid reservation happens before the adapter can dispatch anything.
  await budget.acquireEmbedding(signal);
  const vectors = await embedding.embed([text], 'search_query', signal);
  if (vectors.length !== 1) throw new IndexFailure('INVALID_PROVIDER_OUTPUT', false);
  const vector = vectors[0];
  if (!Array.isArray(vector) || vector.length !== SELF_HOSTED_EMBEDDING_DIMENSIONS ||
      !vector.every((value) => typeof value === 'number' && Number.isFinite(value))) {
    throw new IndexFailure('INVALID_PROVIDER_OUTPUT', false);
  }
  const norm = Math.hypot(...vector);
  if (!Number.isFinite(norm) || norm <= 0) throw new IndexFailure('INVALID_PROVIDER_OUTPUT', false);
  return Object.freeze({
    status: 'OK',
    canary: EMBEDDING_CANARY_KIND,
    profile: Object.freeze({
      model: SELF_HOSTED_EMBEDDING_MODEL,
      dimensions: SELF_HOSTED_EMBEDDING_DIMENSIONS,
    }),
    dimensions: vector.length,
    norm,
    finite: true,
    timing: Object.freeze({ totalMs: Math.max(0, now() - startedAt) }),
    tokenizerCounts: Object.freeze({ embedding: embeddingTokens, deepseek: deepseekTokens }),
  });
};

/** Lazily supplies the two cold ports and the shared clock; the deadline starts before either. */
export type EmbeddingCanarySources = Readonly<{
  embedding: () => IndexDeps['embedding'];
  counters: () => Readonly<{ budget: PilotBudget; countOutput: Counter }>;
  now: () => number;
  timeoutMs: number;
}>;

/**
 * One request deadline started before the cold tokenizer/provider composition. A failing load,
 * reservation or adapter is mapped to the bounded safe error, never unwrapped to the caller.
 */
export const createEmbeddingCanary = (
  sources: EmbeddingCanarySources,
): (() => Promise<unknown>) => async (): Promise<unknown> => {
  const deadline = new RequestDeadline(sources.timeoutMs, sources.now);
  try {
    const embedding = sources.embedding();
    const built = sources.counters();
    return await deadline.within(() =>
      runEmbeddingCanary(
        { embedding, budget: built.budget, countOutput: built.countOutput, now: sources.now },
        deadline.signal,
      ));
  } catch (error) {
    return canaryFailure(error);
  } finally {
    deadline.close();
  }
};
