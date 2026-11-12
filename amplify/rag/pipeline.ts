import { LIVE_QUESTION_SET } from './question_set';
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
import { readRuntimeConfig, type RuntimeValues } from './live_policy';
import {
  deepFreeze,
  emitDiagnostic,
  emptyQueryTrace,
  traceBranchCandidates,
  traceEvidenceSources,
  traceFusedCandidates,
  traceIdentity,
  traceRelevance,
  traceSelectedChunkRefs,
  type QueryTrace,
  type RagQueryDiagnostic,
} from './query_diagnostics';
import { mmr, rrf, validateVector } from './retrieval';
import { RELEVANCE_POLICY_VERSION, selectRelevantCandidates } from './relevance';

/** Existing public import path remains stable; the contract lives in `query_diagnostics`. */
export type { RagQueryDiagnostic } from './query_diagnostics';
/** Root-mapping callers use the same one-way domains instead of re-deriving the hash contract. */
export { chunkRef, indexRef, noteRef, ownerRef } from './query_diagnostics';

export type PipelineDeps = Readonly<{
  /** Optional enclosing handler deadline; cancellation must stop downstream paid stages. */
  signal?: AbortSignal;
  authority: AuthorityStore;
  retrieval: RetrievalDeps;
  providers: Providers;
  counters: Counters;
  config: RuntimeConfig;
  /** Mandatory quota port: runs after authorization and before any provider call. */
  consumeQuota: (actor: string, signal: AbortSignal) => Promise<boolean>;
  /** Optional best-effort query diagnostics; a missing or throwing sink never changes a result. */
  onDiagnostic?: (diagnostic: RagQueryDiagnostic) => void;
  /**
   * Optional private live approval. Absent (the default) live mode stays refused; when present it
   * must be one immutable calibrated approval for a `rag-smoke-` actor whose model and thresholds
   * exactly restate the runtime config. No public flag opens live mode.
   */
  liveApproval?: unknown;
  /**
   * Optional Phase 5 pilot policy. When supplied, live admission is the enabled+listed Cognito
   * `sub` gate instead of the private `rag-smoke-` prefix; an invalid explicit policy refuses and
   * never falls back to the smoke seam. Absent keeps the exact Phase 4 behavior.
   */
  pilotPolicy?: unknown;
}>;

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

type StageRunner = <T>(fallback: ErrorCode, operation: () => Promise<T>) => Promise<T>;

/** Runs one port under both the phase budget and the shared deadline; the budget can only shorten. */
const stageBounded = async <T>(
  deadline: RequestDeadline,
  budgetMs: number,
  fallback: ErrorCode,
  operation: () => Promise<T>,
): Promise<T> => {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const expired = new Promise<never>((_resolve, reject) => {
    timer = setTimeout(() => reject(new RagFailure('TIMEOUT')), budgetMs);
  });
  try {
    return await stage(deadline, fallback, () => Promise.race([operation(), expired]));
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
};

/**
 * The retrieval-phase runner. In mock mode it is exactly the P2 stage. In approved live mode every
 * retrieval call gets at most the remaining part of the pinned 6s phase, always inside the shared
 * 26s deadline; the provider ports carry their own 4s/13s root bounds.
 */
const retrievalRunner = (
  runtime: RuntimeValues,
  deadline: RequestDeadline,
  now: () => number = Date.now,
): StageRunner => {
  if (runtime.retrievalStageMs === null) {
    return (fallback, operation) => stage(deadline, fallback, operation);
  }
  const budgetMs = runtime.retrievalStageMs;
  const end = now() + budgetMs;
  return async (fallback, operation) => {
    const remaining = end - now();
    if (remaining <= 0) throw new RagFailure('TIMEOUT');
    return stageBounded(deadline, remaining, fallback, operation);
  };
};

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
  run: StageRunner,
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
  const vector = await run('PROVIDER_UNAVAILABLE', () =>
    deps.retrieval.embedQuery(question, context.signal, () => revalidate(deadline, context)),
  );
  validateVector(vector);
  return vector;
};

/** One batched getVectors call for the whole union; no candidate is ever re-embedded. */
const selectAnchors = async (
  run: StageRunner,
  deps: PipelineDeps,
  context: RequestContext,
  candidates: readonly Candidate[],
  question: string,
): Promise<readonly Chunk[]> => {
  const expected = new Set(candidates.map((candidate) => sourceKey(candidate.chunk)));
  const vectors = await run('PROVIDER_UNAVAILABLE', () =>
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
  const anchors = mmr(candidates, vectors, { question });
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
  run: StageRunner,
  deps: PipelineDeps,
  context: RequestContext,
  anchors: readonly Chunk[],
): Promise<Evidence> => {
  const neighbors = await run('PROVIDER_UNAVAILABLE', () => deps.retrieval.neighbors(anchors, context));
  if (!Array.isArray(neighbors)) throw new RagFailure('PROVIDER_UNAVAILABLE');
  for (const neighbor of neighbors) assertChunkAuthority(neighbor, context);
  return buildEvidence(anchors, neighbors, context.notes, deps.counters.evidence);
};

/** Minimal Jev state: model, fixed question set criteria and question/evidence text only. */
const buildJevInput = (model: string, question: string, evidence: Evidence, live: boolean): JevInput =>
  deepFreeze({
    model,
    questionSetVersion: live ? LIVE_QUESTION_SET.questionSetVersion : policy.jev.questionSetVersion,
    questions: structuredClone(live ? LIVE_QUESTION_SET.questions : policy.jev.questions),
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

    // Per-invocation diagnostic state. Nothing here is shared across concurrent queries; the single
    // frozen event is emitted from the finally below only after authorization admitted the request.
    let scopeType: RagQueryDiagnostic['scopeType'] | null = null;
    let vectorCandidateCount = 0;
    let keywordCandidateCount = 0;
    let fusedCandidateCount = 0;
    let selectedChunkCount = 0;
    let evidenceSourceCount = 0;
    let answerabilityNoul: number | null = null;
    let conflictNoul: number | null = null;
    let outcome: RagQueryDiagnostic['outcome'] = 'ERROR';
    let reason: RagQueryDiagnostic['reason'] = null;
    let abstentionStage: RagQueryDiagnostic['abstentionStage'] = null;
    // Empty trace defaults are safe before any validated retrieval stage; only the finally emits.
    let trace: QueryTrace = emptyQueryTrace();

    let runtime: RuntimeValues;
    let deadline: RequestDeadline;
    try {
      // Approval and config are validated before the first port call, so an invalid approval
      // never reaches the authority store, quota, retrieval or a provider.
      runtime = readRuntimeConfig(config, actor, deps.liveApproval, deps.pilotPolicy);
      deadline = new RequestDeadline(runtime.requestTimeoutMs, Date.now, deps.signal);
    } catch (error) {
      return errorResponse(requestId, failureCode(error));
    }
    const runRetrieval = retrievalRunner(runtime, deadline);

    try {
      const context = await stage(deadline, 'PROVIDER_UNAVAILABLE', () =>
        beginContext(actor, request, deps.authority, deadline.signal),
      );
      // beginContext validated the wire request; only its canonical scope enum reaches the event.
      scopeType = context.request.scope.type;
      // Domain-separated hashes only: the raw actor and manifest version never enter the event.
      trace = {
        ...trace,
        ...traceIdentity(context.actor, context.state.manifestVersion),
        relevancePolicyVersion: RELEVANCE_POLICY_VERSION,
      };
      // Quota after authorization, before any retrieval/provider egress.
      if ((await askQuota(deadline, deps, actor)) !== true) {
        reason = 'RATE_LIMITED';
        return errorResponse(requestId, 'RATE_LIMITED');
      }
      await revalidate(deadline, context);

      // An empty eligible scope can never yield evidence: abstain before any embedding egress.
      if (context.notes.length === 0) {
        await revalidate(deadline, context);
        outcome = 'NOT_ENOUGH_CONTEXT';
        reason = 'INSUFFICIENT_EVIDENCE';
        abstentionStage = 'scope';
        return abstention(requestId, 'INSUFFICIENT_EVIDENCE');
      }

      const embedding = await embedQuery(runRetrieval, deadline, deps, context);
      await revalidate(deadline, context);

      const vectorBranch = await runRetrieval('PROVIDER_UNAVAILABLE', () =>
        deps.retrieval.vectorSearch(embedding, context),
      );
      assertRanked(vectorBranch, context);
      vectorCandidateCount = vectorBranch.length;
      trace = { ...trace, vectorCandidates: traceBranchCandidates(vectorBranch) };
      await revalidate(deadline, context);
      const keywordBranch = await runRetrieval('PROVIDER_UNAVAILABLE', () =>
        deps.retrieval.keywordSearch(context.request.question, context),
      );
      assertRanked(keywordBranch, context);
      keywordCandidateCount = keywordBranch.length;
      trace = { ...trace, keywordCandidates: traceBranchCandidates(keywordBranch) };

      const candidates = rrf(vectorBranch, keywordBranch);
      fusedCandidateCount = candidates.length;
      // Raw branch/fused trace is preserved for comparability; the gate only adds its own
      // ordered shortlist metadata. It runs after both branches passed full validation/RRF, so a
      // foreign or malformed result errored above instead of being silently filtered here.
      trace = { ...trace, fusedCandidates: traceFusedCandidates(candidates) };
      if (candidates.length === 0) {
        await revalidate(deadline, context);
        outcome = 'NOT_ENOUGH_CONTEXT';
        reason = 'INSUFFICIENT_EVIDENCE';
        abstentionStage = 'retrieval';
        return abstention(requestId, 'INSUFFICIENT_EVIDENCE');
      }
      const relevance = selectRelevantCandidates(context.request.question, candidates);
      trace = { ...trace, ...traceRelevance(relevance) };
      await revalidate(deadline, context);
      // A non-empty union whose every candidate was rejected is not evidence. Abstain before
      // getVectors/JEV; the wire contract stays the existing INSUFFICIENT_EVIDENCE verdict.
      if (relevance.kept.length === 0) {
        outcome = 'NOT_ENOUGH_CONTEXT';
        reason = 'INSUFFICIENT_EVIDENCE';
        abstentionStage = 'relevance';
        return abstention(requestId, 'INSUFFICIENT_EVIDENCE');
      }

      // Only the kept shortlist reaches getVectors/MMR/expansion/dedupe/budget. The gate is
      // query-target/event-aware, and each MMR addition must contribute a meaningful
      // uncovered query part or a same-target correction/conflict; a conjunction never fills the
      // eight-anchor ceiling by itself.
      const anchors = await selectAnchors(
        runRetrieval,
        deps,
        context,
        relevance.kept,
        context.request.question,
      );
      selectedChunkCount = anchors.length;
      trace = { ...trace, selectedChunkRefs: traceSelectedChunkRefs(anchors) };
      await revalidate(deadline, context);

      const evidence = await collectEvidence(runRetrieval, deps, context, anchors);
      evidenceSourceCount = evidence.sources.length;
      trace = { ...trace, evidenceSources: traceEvidenceSources(context.actor, evidence.sources) };
      if (evidence.sources.length === 0) {
        await revalidate(deadline, context);
        outcome = 'NOT_ENOUGH_CONTEXT';
        reason = 'INSUFFICIENT_EVIDENCE';
        abstentionStage = 'evidence';
        return abstention(requestId, 'INSUFFICIENT_EVIDENCE');
      }

      // Separate Jev preflight: the counter measures the whole serialized payload, criteria and
      // question included; an over-budget payload fails before the single Jev call.
      const jevInput = buildJevInput(runtime.model, context.request.question, evidence, config.mode === 'live');
      if (countTokens(deps.counters.jev, JSON.stringify(jevInput)) > runtime.jevMaxTokens) {
        throw new RagFailure('EVIDENCE_VALIDATION_UNAVAILABLE');
      }

      await revalidate(deadline, context);
      deadline.check();
      const rawJev = await stage(deadline, 'EVIDENCE_VALIDATION_UNAVAILABLE', () =>
        deps.providers.jev(jevInput, deadline.signal, () => revalidate(deadline, context)),
      );
      const envelope = validateNoul(rawJev, runtime.model);
      // Null until this exact validation succeeds; pre-JEV refusals must never fabricate 0.
      answerabilityNoul = envelope.answers.answerable_from_evidence.noul;
      conflictNoul = envelope.answers.has_unresolved_conflict.noul;
      if (envelope.usage.input_tokens + envelope.usage.output_tokens > runtime.jevMaxTokens) {
        throw new RagFailure('EVIDENCE_VALIDATION_UNAVAILABLE');
      }
      const verdict = decideNoul(rawJev, config);
      if (verdict !== 'ALLOW') {
        await revalidate(deadline, context);
        outcome = 'NOT_ENOUGH_CONTEXT';
        reason = verdict;
        abstentionStage = 'jev';
        return abstention(requestId, verdict);
      }

      await revalidate(deadline, context);
      const generateInput = buildGenerateInput(context.request.question, evidence);
      const rawGenerated = await stage(deadline, 'PROVIDER_UNAVAILABLE', () =>
        deps.providers.generate(generateInput, deadline.signal, () => revalidate(deadline, context)),
      );
      const generated = validateGenerated(rawGenerated, evidence, deps.counters.output);
      // Release revalidation: a source changed after generation is reported, never released.
      await revalidate(deadline, context);
      outcome = 'ANSWERED';
      reason = null;
      abstentionStage = null;
      const response: RagResponse = {
        wireVersion: WIRE_VERSION,
        requestId,
        status: 'ANSWERED',
        answer: generated.answer,
        sources: generated.sources,
      };
      return Object.freeze(response);
    } catch (error) {
      const code = failureCode(error);
      // Any failure after JEV is still ERROR; an earlier partial verdict never wins.
      outcome = 'ERROR';
      reason = code;
      abstentionStage = null;
      return errorResponse(requestId, code);
    } finally {
      deadline.close();
      if (scopeType !== null) {
        emitDiagnostic(deps, {
          stage: 'rag-query-diagnostic',
          requestId,
          scopeType,
          ownerRef: trace.ownerRef,
          indexRef: trace.indexRef,
          vectorCandidateCount,
          keywordCandidateCount,
          fusedCandidateCount,
          selectedChunkCount,
          evidenceSourceCount,
          vectorCandidates: trace.vectorCandidates,
          keywordCandidates: trace.keywordCandidates,
          fusedCandidates: trace.fusedCandidates,
          relevancePolicyVersion: trace.relevancePolicyVersion,
          relevantCandidateCount: trace.relevantCandidateCount,
          rejectedChunkRefs: trace.rejectedChunkRefs,
          rejectedChunkReasons: trace.rejectedChunkReasons,
          relevanceMode: trace.relevanceMode,
          selectedChunkRefs: trace.selectedChunkRefs,
          evidenceSources: trace.evidenceSources,
          answerabilityNoul,
          conflictNoul,
          outcome,
          reason,
          abstentionStage,
        });
      }
    }
  };
}
