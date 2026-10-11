// Canonical authority → retrieval → immutable evidence → Jev gate → authorized answer release.
import { policy, RagFailure, sourceKey } from './types';
import type {
  AuthorityStore,
  Candidate,
  Chunk,
  Counters,
  ErrorCode,
  Evidence,
  GenerateInput,
  JevInput,
  Providers,
  RagRequest,
  RagResponse,
  Ranked,
  RequestContext,
  RetrievalDeps,
  RuntimeConfig,
  Verdict,
} from './types';
import { assertChunkAuthority, beginContext } from './authority';
import { buildEvidence } from './context';
import {
  MAX_EMBEDDING_CHARACTERS,
  MAX_EMBEDDING_TOKENS,
  countTokens,
  countUnicodeCharacters,
} from './chunking';
import { OUTPUT_MAX_TOKENS, WIRE_VERSION, decideNoul, isValidIdentifier, validateGenerated, validateNoul } from './contract';
import { RequestDeadline } from './deadline';
import { mmr, rrf, validateVector } from './retrieval';

export type PipelineDeps = Readonly<{
  authority: AuthorityStore;
  retrieval: RetrievalDeps;
  providers: Providers;
  counters: Counters;
  config: RuntimeConfig;
  /** Mandatory quota port: runs after authorization and before any provider call. */
  consumeQuota: (actor: string, signal: AbortSignal) => Promise<boolean>;
}>;

type RuntimeValues = Readonly<{
  model: string;
  thresholds: Readonly<{ answerabilityMin: number; conflictMax: number }>;
  jevMaxTokens: number;
  requestTimeoutMs: number;
}>;

const POLICY_RUNTIME_ENABLED: boolean = policy.runtimeEnabled;
const POLICY_LIVE_MODEL: string | null = policy.jev.liveModel;
const POLICY_LIVE_THRESHOLDS: unknown = policy.jev.liveThresholds;

const deepFreeze = <T>(value: T): T => {
  if (value !== null && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const key of Object.keys(value)) deepFreeze((value as Record<string, unknown>)[key]);
  }
  return value;
};

const failureCode = (error: unknown): ErrorCode =>
  error instanceof RagFailure ? error.code : 'PROVIDER_UNAVAILABLE';

const errorResponse = (requestId: string, code: ErrorCode): RagResponse => {
  const response: RagResponse = { wireVersion: WIRE_VERSION, requestId, status: 'ERROR', code };
  return Object.freeze(response);
};

const abstention = (requestId: string, reason: Exclude<Verdict, 'ALLOW'>): RagResponse => {
  const response: RagResponse = {
    wireVersion: WIRE_VERSION,
    requestId,
    status: 'NOT_ENOUGH_CONTEXT',
    reason,
    answer: null,
    sources: [],
  };
  return Object.freeze(response);
};

/** Clone once so a later mutation of the caller's object cannot retune a running runtime. */
const cloneConfig = (config: RuntimeConfig): RuntimeConfig | null => {
  if (config === null || typeof config !== 'object') return null;
  try {
    const thresholds = config.thresholds;
    return deepFreeze({
      mode: config.mode,
      model: config.model,
      thresholds:
        thresholds === null || typeof thresholds !== 'object'
          ? null
          : { answerabilityMin: thresholds.answerabilityMin, conflictMax: thresholds.conflictMax },
      jevMaxTokens: config.jevMaxTokens,
      requestTimeoutMs: config.requestTimeoutMs,
    });
  } catch {
    return null;
  }
};

/**
 * Validates the fixed model, threshold pair and both budgets before any egress. Live mode is
 * refused unconditionally; policy gates (runtimeEnabled false, liveModel/liveThresholds null)
 * mean no server-supplied config can open a live path in this slice.
 */
const readRuntimeConfig = (config: RuntimeConfig): RuntimeValues => {
  if (config === null || typeof config !== 'object') throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  if (config.mode !== 'mock') throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  if (POLICY_RUNTIME_ENABLED !== false || POLICY_LIVE_MODEL !== null || POLICY_LIVE_THRESHOLDS !== null) {
    throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
  const model = config.model;
  if (typeof model !== 'string' || !isValidIdentifier(model)) throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  const thresholds = config.thresholds;
  if (thresholds === null || typeof thresholds !== 'object') throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  const answerabilityMin = thresholds.answerabilityMin;
  const conflictMax = thresholds.conflictMax;
  if (typeof answerabilityMin !== 'number' || !Number.isFinite(answerabilityMin) || !(answerabilityMin > 0.5 && answerabilityMin <= 1)) {
    throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
  if (typeof conflictMax !== 'number' || !Number.isFinite(conflictMax) || !(conflictMax >= 0 && conflictMax < 0.5)) {
    throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
  if (!Number.isSafeInteger(config.jevMaxTokens) || config.jevMaxTokens <= 0) {
    throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
  if (
    !Number.isSafeInteger(config.requestTimeoutMs) ||
    config.requestTimeoutMs <= 0 ||
    config.requestTimeoutMs > 26_000
  ) {
    throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
  return Object.freeze({
    model,
    thresholds: Object.freeze({ answerabilityMin, conflictMax }),
    jevMaxTokens: config.jevMaxTokens,
    requestTimeoutMs: config.requestTimeoutMs,
  });
};

/**
 * Runs one port inside the shared deadline. Typed RagFailures pass through; an unknown failure is
 * mapped to the stage's fallback code and anything observed after the signal aborted is TIMEOUT, so
 * a timeout can never be downgraded into an abstention or a success.
 */
const stage = async <T>(
  deadline: RequestDeadline,
  fallback: ErrorCode,
  operation: () => Promise<T>,
): Promise<T> => {
  try {
    return await deadline.within(async () => {
      try {
        return await operation();
      } catch (error) {
        throw error instanceof RagFailure ? error : new RagFailure(fallback);
      }
    });
  } catch (error) {
    if (error instanceof RagFailure) {
      if (error.code !== 'TIMEOUT' && deadline.signal.aborted) throw new RagFailure('TIMEOUT');
      throw error;
    }
    throw new RagFailure(deadline.signal.aborted ? 'TIMEOUT' : fallback);
  }
};

const revalidate = (deadline: RequestDeadline, context: RequestContext): Promise<void> =>
  stage(deadline, 'PROVIDER_UNAVAILABLE', () => context.revalidate());

/** Every returned entry must be an exact current own scoped span: a bad entry is an error,
 * while an empty branch is a legitimate empty result (never the same outcome). */
const assertRanked = (entries: readonly Ranked[], context: RequestContext): void => {
  if (!Array.isArray(entries)) throw new RagFailure('PROVIDER_UNAVAILABLE');
  for (const entry of entries) {
    if (entry === null || typeof entry !== 'object') throw new RagFailure('PROVIDER_UNAVAILABLE');
    assertChunkAuthority(entry.chunk, context);
  }
};

const askQuota = async (deadline: RequestDeadline, deps: PipelineDeps, actor: string): Promise<boolean> => {
  const consume = deps.consumeQuota;
  if (typeof consume !== 'function') throw new RagFailure('PROVIDER_UNAVAILABLE');
  return stage(deadline, 'PROVIDER_UNAVAILABLE', () => consume(actor, deadline.signal));
};

const embedQuery = async (
  deadline: RequestDeadline,
  deps: PipelineDeps,
  context: RequestContext,
): Promise<readonly number[]> => {
  const question = context.request.question;
  // Preflight the exact query input: the wire bound does not prove embedding fit (truncate NONE),
  // so an oversized question is refused instead of shortened or silently truncated by a provider.
  if (countTokens(deps.counters.embedding, question) > MAX_EMBEDDING_TOKENS) {
    throw new RagFailure('INPUT_TOO_LONG');
  }
  if (countUnicodeCharacters(question) > MAX_EMBEDDING_CHARACTERS) throw new RagFailure('INPUT_TOO_LONG');
  const vector = await stage(deadline, 'PROVIDER_UNAVAILABLE', () =>
    deps.retrieval.embedQuery(question, context.signal),
  );
  validateVector(vector);
  return vector;
};

/** One batched getVectors call for the whole union; no candidate is ever re-embedded. */
const selectAnchors = async (
  deadline: RequestDeadline,
  deps: PipelineDeps,
  context: RequestContext,
  candidates: readonly Candidate[],
): Promise<readonly Chunk[]> => {
  const expected = new Set(candidates.map((candidate) => sourceKey(candidate.chunk)));
  const vectors = await stage(deadline, 'PROVIDER_UNAVAILABLE', () =>
    deps.retrieval.getVectors(
      Object.freeze(candidates.map((candidate) => candidate.chunk)),
      context,
    ),
  );
  if (
    vectors === null ||
    typeof vectors !== 'object' ||
    typeof vectors.get !== 'function' ||
    typeof vectors.has !== 'function' ||
    typeof vectors.size !== 'number'
  ) {
    throw new RagFailure('INDEX_NOT_READY');
  }
  if (vectors.size !== expected.size) throw new RagFailure('INDEX_NOT_READY');
  for (const key of expected) {
    if (!vectors.has(key)) throw new RagFailure('INDEX_NOT_READY');
  }
  const anchors = mmr(candidates, vectors);
  const candidateKeys = new Set(candidates.map((candidate) => sourceKey(candidate.chunk)));
  for (const anchor of anchors) {
    // Every anchor must be one of the fused candidates at the same source identity/revision, and
    // must still be an exact current own scoped span.
    if (!candidateKeys.has(sourceKey(anchor))) throw new RagFailure('INDEX_NOT_READY');
    assertChunkAuthority(anchor, context);
  }
  return anchors;
};

const collectEvidence = async (
  deadline: RequestDeadline,
  deps: PipelineDeps,
  context: RequestContext,
  anchors: readonly Chunk[],
): Promise<Evidence> => {
  const neighbors = await stage(deadline, 'PROVIDER_UNAVAILABLE', () =>
    deps.retrieval.neighbors(anchors, context),
  );
  if (!Array.isArray(neighbors)) throw new RagFailure('PROVIDER_UNAVAILABLE');
  for (const neighbor of neighbors) assertChunkAuthority(neighbor, context);
  return buildEvidence(anchors, neighbors, context.notes, deps.counters.evidence);
};

/** Minimal Jev state: model, fixed question set criteria and question/evidence text only. */
const buildJevInput = (model: string, question: string, evidence: Evidence): JevInput =>
  deepFreeze({
    model,
    questionSetVersion: policy.jev.questionSetVersion,
    questions: structuredClone(policy.jev.questions),
    state: { question, evidence: evidence.text },
  });

/** Generation input: the question, the exact approved bundle and the 1024-token output cap. */
const buildGenerateInput = (question: string, evidence: Evidence): GenerateInput =>
  deepFreeze({ question, evidence, maxOutputTokens: OUTPUT_MAX_TOKENS });

export function createQuery(
  deps: PipelineDeps,
): (actor: string, request: RagRequest, requestId: string) => Promise<RagResponse> {
  const config = cloneConfig(deps.config);

  return async function query(actor: string, request: RagRequest, requestId: string): Promise<RagResponse> {
    // A malformed correlation id is a boundary error; it is never echoed into an envelope.
    if (!isValidIdentifier(requestId)) throw new RagFailure('INVALID_INPUT');
    if (config === null) return errorResponse(requestId, 'LIVE_POLICY_NOT_CONFIGURED');

    let runtime: RuntimeValues;
    let deadline: RequestDeadline;
    try {
      runtime = readRuntimeConfig(config);
      deadline = new RequestDeadline(runtime.requestTimeoutMs);
    } catch (error) {
      return errorResponse(requestId, failureCode(error));
    }

    try {
      const context = await stage(deadline, 'PROVIDER_UNAVAILABLE', () =>
        beginContext(actor, request, deps.authority, deadline.signal),
      );
      // Quota after authorization, before any retrieval/provider egress.
      if ((await askQuota(deadline, deps, actor)) !== true) return errorResponse(requestId, 'RATE_LIMITED');
      await revalidate(deadline, context);

      const embedding = await embedQuery(deadline, deps, context);
      await revalidate(deadline, context);

      const vectorBranch = await stage(deadline, 'PROVIDER_UNAVAILABLE', () =>
        deps.retrieval.vectorSearch(embedding, context),
      );
      assertRanked(vectorBranch, context);
      await revalidate(deadline, context);
      const keywordBranch = await stage(deadline, 'PROVIDER_UNAVAILABLE', () =>
        deps.retrieval.keywordSearch(context.request.question, context),
      );
      assertRanked(keywordBranch, context);

      const candidates = rrf(vectorBranch, keywordBranch);
      if (candidates.length === 0) {
        await revalidate(deadline, context);
        return abstention(requestId, 'INSUFFICIENT_EVIDENCE');
      }
      await revalidate(deadline, context);

      const anchors = await selectAnchors(deadline, deps, context, candidates);
      await revalidate(deadline, context);

      const evidence = await collectEvidence(deadline, deps, context, anchors);
      if (evidence.sources.length === 0) {
        await revalidate(deadline, context);
        return abstention(requestId, 'INSUFFICIENT_EVIDENCE');
      }

      // Separate Jev preflight: the counter measures the whole serialized payload, criteria and
      // question included; an over-budget payload fails before the single Jev call.
      const jevInput = buildJevInput(runtime.model, context.request.question, evidence);
      if (countTokens(deps.counters.jev, JSON.stringify(jevInput)) > runtime.jevMaxTokens) {
        throw new RagFailure('EVIDENCE_VALIDATION_UNAVAILABLE');
      }

      await revalidate(deadline, context);
      deadline.check();
      const rawJev = await stage(deadline, 'EVIDENCE_VALIDATION_UNAVAILABLE', () =>
        deps.providers.jev(jevInput, deadline.signal),
      );
      const envelope = validateNoul(rawJev, runtime.model);
      if (envelope.usage.input_tokens + envelope.usage.output_tokens > runtime.jevMaxTokens) {
        throw new RagFailure('EVIDENCE_VALIDATION_UNAVAILABLE');
      }
      const verdict = decideNoul(rawJev, config);
      if (verdict !== 'ALLOW') {
        await revalidate(deadline, context);
        return abstention(requestId, verdict);
      }

      await revalidate(deadline, context);
      const generateInput = buildGenerateInput(context.request.question, evidence);
      const rawGenerated = await stage(deadline, 'PROVIDER_UNAVAILABLE', () =>
        deps.providers.generate(generateInput, deadline.signal),
      );
      const generated = validateGenerated(rawGenerated, evidence, deps.counters.output);
      // Release revalidation: a source changed after generation is reported, never released.
      await revalidate(deadline, context);
      const response: RagResponse = {
        wireVersion: WIRE_VERSION,
        requestId,
        status: 'ANSWERED',
        answer: generated.answer,
        sources: generated.sources,
      };
      return Object.freeze(response);
    } catch (error) {
      return errorResponse(requestId, failureCode(error));
    } finally {
      deadline.close();
    }
  };
}
