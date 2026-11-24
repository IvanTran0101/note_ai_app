/**
 * Privacy-safe query diagnostics: the one frozen allowlisted event emitted by the canonical
 * pipeline, deterministic SHA-256 references for source trace, and best-effort emission.
 *
 * References are domain-separated hashes over UTF-8 inputs. Every reference is one-way: the raw
 * actor, note id, chunk id and manifest version never enter the event. The same helpers are the
 * single source of truth for routing and tests, so the hash contract is never duplicated.
 */
import { createHash } from 'node:crypto';
import { sourceKey } from './types';
import type { Candidate, Chunk, ErrorCode, Ranked, Source, Verdict } from './types';
import type { RelevanceDecision, RelevanceMode, RelevanceRejectionReason } from './relevance';

/** Scalars accepted by the bounded diagnostic log sinks. */
export type DiagnosticScalar = string | number | null;
/** A bounded value: scalars, arrays and nested records; never raw source/provider objects. */
export type DiagnosticValue =
  | DiagnosticScalar
  | readonly DiagnosticValue[]
  | Readonly<{ [key: string]: DiagnosticValue }>;
/** The widened safe-sink payload: typed arrays/objects, never a pre-serialized string. */
export type DiagnosticMetadata = Readonly<Record<string, DiagnosticValue>>;

export type TraceBranchCandidate = Readonly<{
  chunkRef: string;
  rank: number;
  vectorDistance: number | null;
  bm25Score: number | null;
}>;
export type TraceFusedCandidate = Readonly<{
  chunkRef: string;
  score: number;
  vectorRank: number | null;
  bm25Rank: number | null;
  vectorDistance: number | null;
  bm25Score: number | null;
}>;
export type TraceEvidenceSource = Readonly<{
  sourceId: string;
  noteRef: string;
  revision: number;
  startOffset: number;
  endOffset: number;
}>;

/**
 * Frozen, allowlisted metadata for one admitted query. It carries counts, the two Noul scores,
 * fixed codes and domain-separated source references only; never actor, question, note text,
 * evidence, titles, ids, vectors or raw errors.
 */
export type RagQueryDiagnostic = Readonly<{
  stage: 'rag-query-diagnostic';
  requestId: string;
  scopeType: 'account' | 'note';
  ownerRef: string;
  indexRef: string;
  vectorCandidateCount: number;
  keywordCandidateCount: number;
  fusedCandidateCount: number;
  selectedChunkCount: number;
  evidenceSourceCount: number;
  vectorCandidates: readonly TraceBranchCandidate[];
  keywordCandidates: readonly TraceBranchCandidate[];
  fusedCandidates: readonly TraceFusedCandidate[];
  /** Ordered relevance gate metadata: version, retained count, hashed rejects and safe reasons. */
  relevancePolicyVersion: string;
  relevantCandidateCount: number;
  rejectedChunkRefs: readonly string[];
  rejectedChunkReasons: readonly RelevanceRejectionReason[];
  relevanceMode: RelevanceMode | null;
  selectedChunkRefs: readonly string[];
  evidenceSources: readonly TraceEvidenceSource[];
  answerabilityNoul: number | null;
  conflictNoul: number | null;
  outcome: 'ANSWERED' | 'NOT_ENOUGH_CONTEXT' | 'ERROR';
  reason: Verdict | ErrorCode | null;
  abstentionStage: 'scope' | 'retrieval' | 'relevance' | 'evidence' | 'jev' | null;
}>;

/** Per-invocation trace state; empty defaults are safe until a validated stage supplies data. */
export type QueryTrace = Readonly<{
  ownerRef: string;
  indexRef: string;
  vectorCandidates: readonly TraceBranchCandidate[];
  keywordCandidates: readonly TraceBranchCandidate[];
  fusedCandidates: readonly TraceFusedCandidate[];
  relevancePolicyVersion: string;
  relevantCandidateCount: number;
  rejectedChunkRefs: readonly string[];
  rejectedChunkReasons: readonly RelevanceRejectionReason[];
  relevanceMode: RelevanceMode | null;
  selectedChunkRefs: readonly string[];
  evidenceSources: readonly TraceEvidenceSource[];
}>;

const EMPTY_BRANCH: readonly TraceBranchCandidate[] = Object.freeze([]);
const EMPTY_FUSED: readonly TraceFusedCandidate[] = Object.freeze([]);
const EMPTY_REFS: readonly string[] = Object.freeze([]);
const EMPTY_REASONS: readonly RelevanceRejectionReason[] = Object.freeze([]);
const EMPTY_EVIDENCE: readonly TraceEvidenceSource[] = Object.freeze([]);

export const emptyQueryTrace = (): QueryTrace =>
  Object.freeze({
    ownerRef: '',
    indexRef: '',
    vectorCandidates: EMPTY_BRANCH,
    keywordCandidates: EMPTY_BRANCH,
    fusedCandidates: EMPTY_FUSED,
    relevancePolicyVersion: '',
    relevantCandidateCount: 0,
    rejectedChunkRefs: EMPTY_REFS,
    rejectedChunkReasons: EMPTY_REASONS,
    relevanceMode: null,
    selectedChunkRefs: EMPTY_REFS,
    evidenceSources: EMPTY_EVIDENCE,
  });

const sha256Utf8 = (value: string): string =>
  createHash('sha256').update(value, 'utf8').digest('hex');

/** `owner\0<actor>` -> lowercase SHA-256 hex. */
export const ownerRef = (actor: string): string => sha256Utf8(`owner\u0000${actor}`);

/** `index\0<actor>\0<manifestVersion>` -> lowercase SHA-256 hex. */
export const indexRef = (actor: string, manifestVersion: string): string =>
  sha256Utf8(`index\u0000${actor}\u0000${manifestVersion}`);

/** `chunk\0<sourceKey(chunk)>` -> lowercase SHA-256 hex. */
export const chunkRef = (
  chunk: Pick<Chunk, 'ownerId' | 'noteId' | 'revision' | 'sectionId' | 'chunkId'>,
): string => sha256Utf8(`chunk\u0000${sourceKey(chunk)}`);

/** `note\0<owner>\0<noteId>` -> lowercase SHA-256 hex. */
export const noteRef = (owner: string, noteId: string): string =>
  sha256Utf8(`note\u0000${owner}\u0000${noteId}`);

/** Both context references; a failure falls back to the empty defaults and never throws. */
export const traceIdentity = (
  actor: string,
  manifestVersion: string,
): Readonly<{ ownerRef: string; indexRef: string }> => {
  try {
    return Object.freeze({ ownerRef: ownerRef(actor), indexRef: indexRef(actor, manifestVersion) });
  } catch {
    return Object.freeze({ ownerRef: '', indexRef: '' });
  }
};

const safely = <T>(operation: () => T, fallback: T): T => {
  try {
    return operation();
  } catch {
    return fallback;
  }
};

/**
 * Raw signals are optional; absence becomes `null`, never a fabricated number. A present value
 * must be the exact documented numeric domain or the whole trace slice falls back to empty, so a
 * malformed metric string can never leak into the event.
 */
const traceVectorDistance = (value: unknown): number | null => {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 2) {
    throw new TypeError('Invalid trace vector distance');
  }
  return value;
};

const traceBm25Score = (value: unknown): number | null => {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) {
    throw new TypeError('Invalid trace bm25 score');
  }
  return value;
};

/** Explicit `{chunkRef,rank,vectorDistance,bm25Score}` allowlist for one validated branch. */
export const traceBranchCandidates = (
  entries: readonly Ranked[],
): readonly TraceBranchCandidate[] =>
  safely(
    () => Object.freeze(entries.map((entry) => {
      const rank = entry.rank;
      // A malformed rank can fail RRF later; never log an unvalidated scalar as trace data.
      if (!Number.isSafeInteger(rank) || rank < 1) throw new TypeError('Invalid trace rank');
      return Object.freeze({
        chunkRef: chunkRef(entry.chunk),
        rank,
        vectorDistance: traceVectorDistance(entry.vectorDistance),
        bm25Score: traceBm25Score(entry.bm25Score),
      });
    })),
    EMPTY_BRANCH,
  );

/** Explicit `{chunkRef,score,vectorRank,bm25Rank,vectorDistance,bm25Score}` allowlist for RRF. */
export const traceFusedCandidates = (
  entries: readonly Candidate[],
): readonly TraceFusedCandidate[] =>
  safely(
    () =>
      Object.freeze(entries.map((entry) =>
        Object.freeze({
          chunkRef: chunkRef(entry.chunk),
          score: entry.score,
          vectorRank: entry.vectorRank ?? null,
          bm25Rank: entry.bm25Rank ?? null,
          vectorDistance: traceVectorDistance(entry.vectorDistance),
          bm25Score: traceBm25Score(entry.bm25Score),
        }),
      )),
    EMPTY_FUSED,
  );

/** Ordered relevance gate result as version/count/hashed refs/safe reasons only. */
export const traceRelevance = (
  decision: RelevanceDecision,
): Pick<
  QueryTrace,
  | 'relevantCandidateCount'
  | 'rejectedChunkRefs'
  | 'rejectedChunkReasons'
  | 'relevanceMode'
> =>
  safely<Pick<
    QueryTrace,
    | 'relevantCandidateCount'
    | 'rejectedChunkRefs'
    | 'rejectedChunkReasons'
    | 'relevanceMode'
  >>(
    () =>
      Object.freeze({
        relevantCandidateCount: decision.kept.length,
        rejectedChunkRefs: Object.freeze(decision.rejected.map((entry) => entry.chunkRef)),
        rejectedChunkReasons: Object.freeze(decision.rejected.map((entry) => entry.reason)),
        relevanceMode: decision.mode,
      }),
    Object.freeze({
      relevantCandidateCount: 0,
      rejectedChunkRefs: EMPTY_REFS,
      rejectedChunkReasons: EMPTY_REASONS,
      relevanceMode: null,
    }),
  );

/** MMR anchors as references only. */
export const traceSelectedChunkRefs = (anchors: readonly Chunk[]): readonly string[] =>
  safely(() => anchors.map((anchor) => chunkRef(anchor)), EMPTY_REFS);

/** Final evidence sources after expansion/dedupe/budget, without note ids, titles or text. */
export const traceEvidenceSources = (
  owner: string,
  sources: readonly Source[],
): readonly TraceEvidenceSource[] =>
  safely(
    () =>
      sources.map((source) => ({
        sourceId: source.sourceId,
        noteRef: noteRef(owner, source.noteId),
        revision: source.revision,
        startOffset: source.startOffset,
        endOffset: source.endOffset,
      })),
    EMPTY_EVIDENCE,
  );

export const deepFreeze = <T>(value: T): T => {
  if (value !== null && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const key of Object.keys(value)) deepFreeze((value as Record<string, unknown>)[key]);
  }
  return value;
};

export type RagDiagnosticSink = (diagnostic: RagQueryDiagnostic) => void;

/**
 * Diagnostics are best effort: a missing, throwing or hostile sink cannot change the query.
 * The event and every nested array/object are frozen before the sink sees them.
 */
export const emitDiagnostic = (
  deps: Readonly<{ onDiagnostic?: RagDiagnosticSink }>,
  diagnostic: RagQueryDiagnostic,
): void => {
  try {
    const sink = deps.onDiagnostic;
    if (typeof sink !== 'function') return;
    sink(deepFreeze(diagnostic));
  } catch {
    // Logging must never change a request outcome.
  }
};
