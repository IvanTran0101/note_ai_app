// Fuse original ranks, then diversify using validated vectors already stored in the index.
import { policy, RagFailure, sourceKey, type Candidate, type Chunk, type Ranked } from './types';
import { assertChunk, isSafeInteger } from './chunking';
import { compareSourceKey } from './keyword';

export const RRF_CONSTANT: number = policy.retrieval.rrf.constant;
export const RRF_VECTOR_WEIGHT: number = policy.retrieval.rrf.vectorWeight;
export const RRF_BM25_WEIGHT: number = policy.retrieval.rrf.bm25Weight;
export const RRF_MAX_CANDIDATES: number = policy.retrieval.maxUnionCandidates;
export const MMR_LAMBDA: number = policy.retrieval.mmr.lambda;
export const MMR_MAX_ANCHORS: number = policy.retrieval.mmr.maxAnchors;
export const EMBEDDING_DIMENSIONS: number = policy.embedding.dimensions;

/**
 * A vector artifact from the index must be 1024-dimensional, finite and non-zero. Rejection is
 * INDEX_NOT_READY: the index artifacts are not usable for the configured embedding policy
 * (policy.embedding.dimensions / truncate NONE), so no candidate can be scored.
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

type BranchEntry = Readonly<{ chunk: Chunk; rank: number }>;

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
    const key = sourceKey(entry.chunk);
    const existing = byKey.get(key);
    if (existing !== undefined) {
      // Duplicate of the same source: keep the best rank, reject contradictory span data.
      if (!sameChunk(existing.chunk, entry.chunk)) throw new RagFailure('SOURCE_CHANGED');
      if (rank < existing.rank) byKey.set(key, { chunk: entry.chunk, rank });
      continue;
    }
    // Two different sources cannot claim the same rank inside one branch (ambiguous order).
    if (ranks.has(rank)) throw new RagFailure('INVALID_INPUT');
    ranks.add(rank);
    byKey.set(key, { chunk: entry.chunk, rank });
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
    const candidate: { chunk: Chunk; score: number; vectorRank?: number; bm25Rank?: number } = { chunk, score };
    if (fromVector !== undefined) candidate.vectorRank = fromVector.rank;
    if (fromKeyword !== undefined) candidate.bm25Rank = fromKeyword.rank;
    candidates.push(candidate);
  }

  candidates.sort((left, right) => right.score - left.score || compareSourceKey(left.chunk, right.chunk));
  return candidates;
}

type Prepared = Readonly<{ chunk: Chunk; score: number; vector: readonly number[]; norm: number }>;

const cosine = (left: Prepared, right: Prepared): number => {
  let dot = 0;
  // Normalize first to avoid underflow/overflow in dot and norm products.
  for (let index = 0; index < EMBEDDING_DIMENSIONS; index += 1) {
    dot += (left.vector[index] / left.norm) * (right.vector[index] / right.norm);
  }
  return Math.max(-1, Math.min(1, dot));
};

/**
 * Maximal marginal relevance anchor selection. `vectors` is the injected getVectors batch keyed
 * by sourceKey(chunk) — vectors are reused, never re-embedded here.
 */
export function mmr(
  candidates: readonly Candidate[],
  vectors: ReadonlyMap<string, readonly number[]>,
): readonly Chunk[] {
  if (!Array.isArray(candidates)) throw new RagFailure('INVALID_INPUT');
  if (candidates.length === 0) return [];
  if (vectors === null || typeof vectors !== 'object' || typeof vectors.get !== 'function') {
    throw new RagFailure('INVALID_INPUT');
  }

  const prepared: Prepared[] = [];
  const seen = new Set<string>();
  let poolMaximum = 0;
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
    if (candidate.score > poolMaximum) poolMaximum = candidate.score;
    prepared.push({ chunk: candidate.chunk, score: candidate.score, vector, norm: Math.hypot(...vector) });
  }
  if (!(poolMaximum > 0)) throw new RagFailure('INVALID_INPUT');

  // Stable source-key order makes every tie deterministic before selection starts.
  prepared.sort((left, right) => compareSourceKey(left.chunk, right.chunk));

  const remaining = [...prepared];
  const selected: Prepared[] = [];
  while (selected.length < MMR_MAX_ANCHORS && remaining.length > 0) {
    let bestIndex = -1;
    let bestValue = Number.NEGATIVE_INFINITY;
    for (let index = 0; index < remaining.length; index += 1) {
      const candidate = remaining[index];
      const relevance = candidate.score / poolMaximum;
      let redundancy = 0;
      for (const chosen of selected) {
        const similarity = cosine(candidate, chosen);
        if (similarity > redundancy) redundancy = similarity;
      }
      if (redundancy < 0) redundancy = 0;
      const value = MMR_LAMBDA * relevance - (1 - MMR_LAMBDA) * redundancy;
      // Strict comparison keeps the earliest source key on exact ties.
      if (value > bestValue) {
        bestValue = value;
        bestIndex = index;
      }
    }
    const chosen = remaining.splice(bestIndex, 1)[0];
    if (chosen === undefined) break;
    selected.push(chosen);
  }

  return selected.map((entry) => entry.chunk);
}
