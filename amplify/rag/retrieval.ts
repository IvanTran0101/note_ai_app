// Fuse original ranks, then diversify using validated vectors already stored in the index.
import { policy, RagFailure, sourceKey, type Candidate, type Chunk, type Ranked } from './types';
import { assertChunk, isSafeInteger } from './chunking';
import { compareSourceKey } from './keyword';
import {
  buildQueryEvidence,
  coveredTerms,
  isMeaningfulMissing,
  matchedTerms,
  missingTermCoverage,
  missingTerms,
  targetTermOverlap,
  weightedCoverage,
} from './query_evidence';
import {
  RELEVANCE_COVERAGE_FLOOR,
  RELEVANCE_POSITIVE_DISTANCE,
  isConjunctiveQuestion,
} from './relevance';

export const RRF_CONSTANT: number = policy.retrieval.rrf.constant;
export const RRF_VECTOR_WEIGHT: number = policy.retrieval.rrf.vectorWeight;
export const RRF_BM25_WEIGHT: number = policy.retrieval.rrf.bm25Weight;
export const RRF_MAX_CANDIDATES: number = policy.retrieval.maxUnionCandidates;
export const MMR_LAMBDA: number = policy.retrieval.mmr.lambda;
export const MMR_MAX_ANCHORS: number = policy.retrieval.mmr.maxAnchors;
export const EMBEDDING_DIMENSIONS: number = policy.embedding.dimensions;

/**
 * A vector artifact from the index must be 768-dimensional (EmbeddingGemma-2 Q8), finite and
 * non-zero. Rejection is INDEX_NOT_READY: the index artifacts are not usable for the configured
 * embedding policy (policy.embedding.dimensions / truncate NONE), so no candidate can be scored.
 * A 1024-dimensional Cohere vector is refused here, never padded or truncated.
 */
export function validateVector(vector: readonly number[]): void {
  if (!Array.isArray(vector) || vector.length !== EMBEDDING_DIMENSIONS) {
    throw new RagFailure('INDEX_NOT_READY');
  }
  for (const value of vector) {
    if (typeof value !== 'number' || !Number.isFinite(value)) throw new RagFailure('INDEX_NOT_READY');
  }
  const norm = Math.hypot(...vector);
  if (!Number.isFinite(norm) || norm <= 0) throw new RagFailure('INDEX_NOT_READY');
}

/** Same exact source identity (sourceKey) must also carry the same span/text/title. */
export const sameChunk = (left: Chunk, right: Chunk): boolean =>
  left.ownerId === right.ownerId &&
  left.noteId === right.noteId &&
  left.revision === right.revision &&
  left.sectionId === right.sectionId &&
  left.chunkId === right.chunkId &&
  left.ordinal === right.ordinal &&
  left.title === right.title &&
  left.startOffset === right.startOffset &&
  left.endOffset === right.endOffset &&
  left.text === right.text;

type BranchEntry = Readonly<{
  chunk: Chunk; rank: number; vectorDistance?: number; bm25Score?: number;
}>;

/**
 * Optional raw signals are allowed to be absent (legacy branch entries) but, when present, must
 * be the exact numeric domain the producer documents: cosine distance in [0,2], BM25 score > 0.
 * Rejecting malformed values here keeps a bad metric from ever reaching trace output.
 */
const validateVectorDistance = (value: unknown): number | undefined => {
  if (value === undefined) return undefined;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 2) {
    throw new RagFailure('INVALID_INPUT');
  }
  return value;
};

const validateBm25Score = (value: unknown): number | undefined => {
  if (value === undefined) return undefined;
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) {
    throw new RagFailure('INVALID_INPUT');
  }
  return value;
};

/** Normalizes one branch: validated ranks, one contribution per source, best rank retained. */
const collectBranch = (entries: readonly Ranked[]): ReadonlyMap<string, BranchEntry> => {
  if (!Array.isArray(entries)) throw new RagFailure('INVALID_INPUT');
  const byKey = new Map<string, BranchEntry>();
  const ranks = new Set<number>();
  for (const entry of entries) {
    if (entry === null || typeof entry !== 'object') throw new RagFailure('INVALID_INPUT');
    const rank = (entry as { rank?: unknown }).rank;
    if (!isSafeInteger(rank) || rank < 1 || rank > policy.retrieval.vectorTopK) throw new RagFailure('INVALID_INPUT');
    assertChunk(entry.chunk);
    const vectorDistance = validateVectorDistance((entry as { vectorDistance?: unknown }).vectorDistance);
    const bm25Score = validateBm25Score((entry as { bm25Score?: unknown }).bm25Score);
    const normalized: BranchEntry = {
      chunk: entry.chunk,
      rank,
      ...(vectorDistance === undefined ? {} : { vectorDistance }),
      ...(bm25Score === undefined ? {} : { bm25Score }),
    };
    const key = sourceKey(entry.chunk);
    const existing = byKey.get(key);
    if (existing !== undefined) {
      // Duplicate of the same source: keep the best rank, reject contradictory span data.
      if (!sameChunk(existing.chunk, entry.chunk)) throw new RagFailure('SOURCE_CHANGED');
      if (rank < existing.rank) byKey.set(key, normalized);
      continue;
    }
    // Two different sources cannot claim the same rank inside one branch (ambiguous order).
    if (ranks.has(rank)) throw new RagFailure('INVALID_INPUT');
    ranks.add(rank);
    byKey.set(key, normalized);
  }
  return byKey;
};

/**
 * Reciprocal rank fusion of the independent vector and BM25 branches. Returns candidates sorted
 * by fused score descending, then source key ascending (deterministic ties).
 */
export function rrf(vector: readonly Ranked[], keyword: readonly Ranked[]): readonly Candidate[] {
  const vectorBranch = collectBranch(vector);
  const keywordBranch = collectBranch(keyword);
  const keys = new Set<string>([...vectorBranch.keys(), ...keywordBranch.keys()]);
  if (keys.size > RRF_MAX_CANDIDATES) throw new RagFailure('INVALID_INPUT');

  const candidates: Candidate[] = [];
  for (const key of keys) {
    const fromVector = vectorBranch.get(key);
    const fromKeyword = keywordBranch.get(key);
    if (fromVector !== undefined && fromKeyword !== undefined && !sameChunk(fromVector.chunk, fromKeyword.chunk)) {
      throw new RagFailure('SOURCE_CHANGED');
    }
    const chunk = (fromVector ?? fromKeyword)?.chunk;
    if (chunk === undefined) throw new RagFailure('INVALID_INPUT');
    let score = 0;
    if (fromVector !== undefined) score += RRF_VECTOR_WEIGHT / (RRF_CONSTANT + fromVector.rank);
    if (fromKeyword !== undefined) score += RRF_BM25_WEIGHT / (RRF_CONSTANT + fromKeyword.rank);
    const candidate: {
      chunk: Chunk; score: number; vectorRank?: number; bm25Rank?: number;
      vectorDistance?: number; bm25Score?: number;
    } = { chunk, score };
    if (fromVector !== undefined) candidate.vectorRank = fromVector.rank;
    if (fromKeyword !== undefined) candidate.bm25Rank = fromKeyword.rank;
    // Raw signals are provenance only; the fused score above never reads them. A supplied
    // metric survives from whichever branch carried it (branch-native value wins on overlap).
    const vectorDistance = fromVector?.vectorDistance ?? fromKeyword?.vectorDistance;
    const bm25Score = fromKeyword?.bm25Score ?? fromVector?.bm25Score;
    if (vectorDistance !== undefined) candidate.vectorDistance = vectorDistance;
    if (bm25Score !== undefined) candidate.bm25Score = bm25Score;
    candidates.push(candidate);
  }

  candidates.sort((left, right) => right.score - left.score || compareSourceKey(left.chunk, right.chunk));
  return candidates;
}

type Prepared = Readonly<{
  chunk: Chunk;
  score: number;
  vector: readonly number[];
  norm: number;
  lexical: boolean;
  vectorDistance?: number;
  bm25Score?: number;
}>;

const cosine = (left: Prepared, right: Prepared): number => {
  let dot = 0;
  // Normalize first to avoid underflow/overflow in dot and norm products.
  for (let index = 0; index < EMBEDDING_DIMENSIONS; index += 1) {
    dot += (left.vector[index] / left.norm) * (right.vector[index] / right.norm);
  }
  return Math.max(-1, Math.min(1, dot));
};

/**
 * Optional caller hints.
 *
 * `question` is the raw question for evidence-aware additions. When present and at least one
 * candidate carries a raw signal, every addition after the seed must cover
 * a meaningful uncovered query part or share the selected target enough to preserve a possible
 * correction/conflict. `retainOnNonPositiveUtility` is the legacy blanket hint for direct callers
 * that do not pass a question; it is intentionally ignored when `question` is supplied so an
 * explicit conjunction can never fill the ceiling by itself.
 *
 * Existing two-argument callers keep the old behavior exactly: rank-only pools still fill to the
 * ceiling, and scored pools still keep qualified lexical candidates while the adaptive semantic
 * stop applies.
 */
export type MmrOptions = Readonly<{
  retainOnNonPositiveUtility?: boolean;
  question?: string;
}>;

/**
 * Maximal marginal relevance anchor selection. `vectors` is the injected getVectors batch keyed
 * by sourceKey(chunk) — vectors are reused, never re-embedded here.
 *
 * When at least one candidate carries a raw signal, relevance quality is
 * `max(positive cosine similarity (1 - distance), bm25Score / maxBm25Score)`. A candidate that
 * carries no raw signal of its own falls back to the normal RRF score. With a supplied question,
 * the adaptive stop is replaced by evidence-aware additions: a non-positive candidate survives
 * only for a meaningful uncovered query part or a genuine same-target correction/conflict, always
 * within the same eight-anchor ceiling. Without a question, the legacy conservative stop (and the
 * optional explicit hint) is preserved. When every candidate is rank-only (legacy branch seam),
 * the original fill-to-ceiling selection is kept unchanged.
 */
export function mmr(
  candidates: readonly Candidate[],
  vectors: ReadonlyMap<string, readonly number[]>,
  options: MmrOptions = {},
): readonly Chunk[] {
  const retainOnNonPositiveUtility = options.retainOnNonPositiveUtility === true;
  const question = options.question;
  if (question !== undefined && typeof question !== 'string') throw new RagFailure('INVALID_INPUT');
  if (!Array.isArray(candidates)) throw new RagFailure('INVALID_INPUT');
  if (candidates.length === 0) return [];
  if (vectors === null || typeof vectors !== 'object' || typeof vectors.get !== 'function') {
    throw new RagFailure('INVALID_INPUT');
  }

  const prepared: Prepared[] = [];
  const seen = new Set<string>();
  let poolMaximum = 0;
  let rawSignalCount = 0;
  for (const candidate of candidates) {
    if (candidate === null || typeof candidate !== 'object') throw new RagFailure('INVALID_INPUT');
    assertChunk(candidate.chunk);
    if (
      typeof candidate.score !== 'number' ||
      !Number.isFinite(candidate.score) ||
      candidate.score < 0
    ) {
      throw new RagFailure('INVALID_INPUT');
    }
    const key = sourceKey(candidate.chunk);
    if (seen.has(key)) throw new RagFailure('INVALID_INPUT');
    seen.add(key);
    const vector = vectors.get(key);
    if (vector === undefined) throw new RagFailure('INDEX_NOT_READY');
    validateVector(vector);
    // Re-validate the optional raw domains here: MMR is a public export and must not read a
    // malformed/mixed metric that bypassed RRF.
    const vectorDistance = validateVectorDistance(candidate.vectorDistance);
    const bm25Score = validateBm25Score(candidate.bm25Score);
    if (vectorDistance !== undefined || bm25Score !== undefined) rawSignalCount += 1;
    if (candidate.score > poolMaximum) poolMaximum = candidate.score;
    prepared.push({
      chunk: candidate.chunk,
      score: candidate.score,
      vector,
      norm: Math.hypot(...vector),
      lexical: candidate.bm25Rank !== undefined && bm25Score !== undefined,
      ...(vectorDistance === undefined ? {} : { vectorDistance }),
      ...(bm25Score === undefined ? {} : { bm25Score }),
    });
  }
  if (!(poolMaximum > 0)) throw new RagFailure('INVALID_INPUT');

  // Stable source-key order makes every tie deterministic before selection starts.
  prepared.sort((left, right) => compareSourceKey(left.chunk, right.chunk));

  let bestBm25Score = 0;
  for (const candidate of prepared) {
    if (candidate.bm25Score !== undefined && candidate.bm25Score > bestBm25Score) {
      bestBm25Score = candidate.bm25Score;
    }
  }

  // Evidence-aware additions only exist when a question is supplied and this is not the legacy
  // rank-only seam. `hasLexicalEvidence` distinguishes a genuinely cross-language/no-overlap
  // pool (safe positive-semantic fallback) from a lexical pool with a bounded uncovered part.
  const evidence = question === undefined ? null : buildQueryEvidence(question, candidates);
  const conjunctive = question !== undefined && isConjunctiveQuestion(question);
  const hasLexicalEvidence =
    evidence !== null &&
    prepared.some((candidate) => matchedTerms(evidence, candidate.chunk).size > 0);
  const bestCoverage =
    evidence === null
      ? 0
      : prepared.reduce(
          (best, candidate) => Math.max(best, weightedCoverage(evidence, candidate.chunk)),
          0,
        );
  const positiveSemantic = (candidate: Prepared): boolean =>
    candidate.vectorDistance === undefined ||
    candidate.vectorDistance < RELEVANCE_POSITIVE_DISTANCE;

  /**
   * A non-positive candidate is an addition only when it answers an uncovered meaningful query
   * part, shares enough of the already-selected target to be a correction/conflict about the same
   * thing, or (with no lexical evidence at all) is a positive-semantic recall candidate. This is a
   * bounded deterministic shortcut; it does not prove that the candidate semantically answers the
   * missing part, and JEV still decides sufficiency and conflict.
   */
  const evidenceAddition = (
    candidate: Prepared,
    missing: readonly string[],
    meaningfulMissing: boolean,
    coveredBySelected: ReadonlySet<string>,
  ): boolean => {
    if (evidence === null) return false;
    if (!hasLexicalEvidence) return positiveSemantic(candidate);
    if (meaningfulMissing) {
      if (missingTermCoverage(evidence, candidate.chunk, missing) >= RELEVANCE_COVERAGE_FLOOR) {
        return true;
      }
      // The deterministic text cannot map a cross-language answer to the missing part; keep a
      // positive semantic candidate within the same ceiling as a bounded completion attempt.
      if (conjunctive && !candidate.lexical && positiveSemantic(candidate)) return true;
    }
    // A correction/conflict must still be a target-level match for this question, not merely a
    // note sharing one generic selected term.
    return (
      weightedCoverage(evidence, candidate.chunk) >= RELEVANCE_COVERAGE_FLOOR * bestCoverage &&
      targetTermOverlap(evidence, candidate.chunk, coveredBySelected) >= RELEVANCE_COVERAGE_FLOOR
    );
  };

  /** Per-candidate relevance in [0,1]; rank-only entries use the normal RRF fallback. */
  const relevanceOf = (candidate: Prepared): number => {
    if (rawSignalCount === 0) return candidate.score / poolMaximum;
    const semantic =
      candidate.vectorDistance === undefined
        ? undefined
        : Math.max(0, Math.min(1, 1 - candidate.vectorDistance));
    const lexical =
      candidate.bm25Score === undefined || bestBm25Score <= 0
        ? undefined
        : candidate.bm25Score / bestBm25Score;
    // A candidate that supplies neither signal uses the RRF fallback, never a fabricated 0.
    if (semantic === undefined && lexical === undefined) return candidate.score / poolMaximum;
    return Math.max(semantic ?? 0, lexical ?? 0);
  };

  const remaining = [...prepared];
  const selected: Prepared[] = [];
  while (selected.length < MMR_MAX_ANCHORS && remaining.length > 0) {
    const coveredBySelected =
      evidence === null ? null : coveredTerms(evidence, selected.map((entry) => entry.chunk));
    const missing =
      evidence === null || coveredBySelected === null
        ? null
        : missingTerms(evidence, coveredBySelected);
    const meaningfulMissing =
      evidence !== null && missing !== null && isMeaningfulMissing(evidence, missing);
    let bestIndex = -1;
    let bestValue = Number.NEGATIVE_INFINITY;
    for (let index = 0; index < remaining.length; index += 1) {
      const candidate = remaining[index];
      const relevance = relevanceOf(candidate);
      let redundancy = 0;
      for (const chosen of selected) {
        const similarity = cosine(candidate, chosen);
        if (similarity > redundancy) redundancy = similarity;
      }
      if (redundancy < 0) redundancy = 0;
      const value = MMR_LAMBDA * relevance - (1 - MMR_LAMBDA) * redundancy;
      if (rawSignalCount > 0) {
        if (evidence !== null && missing !== null && coveredBySelected !== null) {
          // Positive utility alone is not new evidence: after the seed, every addition must
          // complete a requested part or retain a same-target correction/conflict.
          if ((selected.length > 0 || value <= 0) &&
              !evidenceAddition(candidate, missing, meaningfulMissing, coveredBySelected)) continue;
        } else if (value <= 0 && !retainOnNonPositiveUtility && !candidate.lexical) {
          // Direct legacy callers without a question retain their existing stop semantics.
          continue;
        }
      }
      // Strict comparison keeps the earliest source key on exact ties.
      if (value > bestValue) {
        bestValue = value;
        bestIndex = index;
      }
    }
    // Stop when no eligible candidate remains; the eight-anchor ceiling is unchanged.
    if (bestIndex < 0) break;
    const chosen = remaining.splice(bestIndex, 1)[0];
    if (chosen === undefined) break;
    selected.push(chosen);
  }

  return selected.map((entry) => entry.chunk);
}
