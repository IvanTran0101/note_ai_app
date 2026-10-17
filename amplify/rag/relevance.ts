/**
 * Ordered relevance gate: a deterministic, query-relative shortlist heuristic over fully
 * validated RRF candidates, applied before MMR. It is deliberately NOT a calibrated
 * answerability model and never calls a provider; the JEV gate still decides answerability.
 *
 * The gate only removes candidates from the fused list. Keeping a candidate preserves its
 * original vector/BM25 ranks and fused score, so the result is equivalent to filtering the
 * original branches before ranking while retaining original ranks. Authority and full branch
 * validation happen upstream (assertRanked + RRF); a malformed or foreign result errors before
 * this module can drop it.
 *
 * Documented defaults (policy v2):
 * - reliability is a query-relative rarity-weighted evidence coverage, not "any overlap":
 *   a lexical candidate must cover at least half of the best candidate's meaningful query weight.
 *   A shared generic term (a year, "workshop") cannot by itself anchor an off-target note.
 * - explicit multi-part protection is bounded: a weak lexical candidate is retained only when
 *   the strong shortlist leaves a meaningful (two terms or a number/date) uncovered part and the
 *   candidate covers at least half of that part. "and/và" alone never trusts every source.
 * - a vector-only candidate must be no farther than the closest reliable lexical anchor
 *   (query-relative distance boundary; no universal cosine floor). When the strong lexical
 *   evidence leaves a meaningful independent part uncovered, a known positive semantic candidate
 *   may represent that part; this is a bounded recall shortcut, not semantic truth.
 * - with no lexical anchor, only a known positive cosine (distance < 1) is retained; an
 *   absent legacy distance stays conservative rank-only, never a fabricated value.
 */
import { assertChunk } from './chunking';
import { matchesQueryTarget } from './event_target';
import { chunkRef } from './query_diagnostics';
import {
  buildQueryEvidence,
  coveredTerms,
  isConjunctiveQuestion,
  isMeaningfulMissing,
  matchedTerms,
  missingTermCoverage,
  missingTerms,
  weightedCoverage,
} from './query_evidence';
import { RagFailure, sourceKey, type Candidate } from './types';

export const RELEVANCE_POLICY_VERSION = 'rag-relevance-policy.v2' as const;
/**
 * Legacy v1 relative BM25 floor. v2 deliberately does not use a relative BM25 bypass: a high BM25
 * score earned by generic query words must not anchor an off-target source. The constant remains
 * exported so replay code that reports the old policy still has a named value.
 */
export const RELEVANCE_BM25_FLOOR = 0.5;
/** Query-relative evidence floors: reliability, missing-part coverage and same-target overlap. */
export const RELEVANCE_COVERAGE_FLOOR = 0.5;
/** A known semantic hit is a cosine distance strictly below this (negative cosine excluded). */
export const RELEVANCE_POSITIVE_DISTANCE = 1;

export type RelevanceMode = 'legacy-rank-only' | 'scored' | 'mixed';

/** Safe, finite reason allowlist for the observer/root replay. Never raw text or errors. */
export type RelevanceRejectionReason =
  | 'target_mismatch'
  | 'no_query_overlap'
  | 'weak_lexical'
  | 'outside_vector_boundary'
  | 'non_positive_semantic';

export type RelevanceRejection = Readonly<{
  chunkRef: string;
  reason: RelevanceRejectionReason;
}>;

export type RelevanceDecision = Readonly<{
  policyVersion: typeof RELEVANCE_POLICY_VERSION;
  kept: readonly Candidate[];
  rejected: readonly RelevanceRejection[];
  mode: RelevanceMode;
}>;

/** Raw question markers that explicitly ask for independent facts/entities. */
export { isConjunctiveQuestion } from './query_evidence';

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

const validateRank = (value: unknown): number | undefined => {
  if (value === undefined) return undefined;
  if (!Number.isSafeInteger(value) || (value as number) < 1) throw new RagFailure('INVALID_INPUT');
  return value as number;
};

/**
 * Re-validates the optional raw signals the gate reads. RRF already validated them for the
 * canonical path; doing it again keeps the pure export safe for replay callers and guarantees a
 * bad/mixed metric can never be interpreted as a fabricated zero.
 */
const assertCandidate = (candidate: Candidate, seen: Set<string>): void => {
  if (candidate === null || typeof candidate !== 'object') throw new RagFailure('INVALID_INPUT');
  assertChunk(candidate.chunk);
  if (typeof candidate.score !== 'number' || !Number.isFinite(candidate.score) || candidate.score < 0) {
    throw new RagFailure('INVALID_INPUT');
  }
  validateVectorDistance(candidate.vectorDistance);
  validateBm25Score(candidate.bm25Score);
  validateRank(candidate.vectorRank);
  validateRank(candidate.bm25Rank);
  const key = sourceKey(candidate.chunk);
  if (seen.has(key)) throw new RagFailure('INVALID_INPUT');
  seen.add(key);
};

const hasAnyMetric = (candidate: Candidate): boolean =>
  candidate.vectorDistance !== undefined || candidate.bm25Score !== undefined;

const isLexical = (candidate: Candidate): boolean => candidate.bm25Rank !== undefined;

const frozenDecision = (
  kept: readonly Candidate[],
  rejected: readonly RelevanceRejection[],
  mode: RelevanceMode,
): RelevanceDecision =>
  Object.freeze({
    policyVersion: RELEVANCE_POLICY_VERSION,
    kept: Object.freeze([...kept]),
    rejected: Object.freeze([...rejected]),
    mode,
  });

/**
 * Pure ordered gate. Returns the original candidate objects for the retained shortlist plus
 * hashed references and safe enum reasons for every rejection, so the root can replay the
 * decision without seeing questions, titles, ids, text or vectors.
 */
export function selectRelevantCandidates(
  question: string,
  candidates: readonly Candidate[],
): RelevanceDecision {
  if (typeof question !== 'string' || !Array.isArray(candidates)) throw new RagFailure('INVALID_INPUT');
  if (candidates.length === 0) return frozenDecision([], [], 'legacy-rank-only');

  const seen = new Set<string>();
  for (const candidate of candidates) assertCandidate(candidate, seen);

  const metricCount = candidates.filter(hasAnyMetric).length;
  const mode: RelevanceMode =
    metricCount === 0 ? 'legacy-rank-only' : metricCount === candidates.length ? 'scored' : 'mixed';

  // Legacy seam: the branches carry ranks only. Keep every validated candidate, exactly as the
  // pre-raw-signal pipeline did, and never infer a metric from rank position.
  if (mode === 'legacy-rank-only') return frozenDecision(candidates, [], mode);

  const evidence = buildQueryEvidence(question, candidates);
  const conjunctive = isConjunctiveQuestion(question);

  // Choose a primary only from sources compatible with explicit query dates. All original
  // candidates were validated above; target filtering must not conceal invalid branch data.
  const dateEligible = new Set(candidates.filter((candidate) =>
    matchesQueryTarget(question, candidate.chunk, candidate.chunk, evidence)).map((candidate) => sourceKey(candidate.chunk)));
  const primary = candidates.filter((candidate) => isLexical(candidate) && dateEligible.has(sourceKey(candidate.chunk)))
    .reduce<Candidate | undefined>((best, candidate) => {
      if (best === undefined) return candidate;
      const gain = weightedCoverage(evidence, candidate.chunk) - weightedCoverage(evidence, best.chunk);
      if (gain !== 0) return gain > 0 ? candidate : best;
      if (candidate.score !== best.score) return candidate.score > best.score ? candidate : best;
      return sourceKey(candidate.chunk) < sourceKey(best.chunk) ? candidate : best;
    }, undefined);
  const targets = new Set(candidates.filter((candidate) =>
    primary !== undefined && isLexical(candidate)
      ? matchesQueryTarget(question, primary.chunk, candidate.chunk, evidence)
      : dateEligible.has(sourceKey(candidate.chunk)))
    .map((candidate) => sourceKey(candidate.chunk)));
  const lexical = candidates.filter((candidate) => isLexical(candidate) && targets.has(sourceKey(candidate.chunk)));
  const bestCoverage = lexical.reduce(
    (best, candidate) => Math.max(best, weightedCoverage(evidence, candidate.chunk)),
    0,
  );

  // Strong target/event match: anchored to the best candidate for THIS question and measured by
  // rarity-weighted query evidence. A shared year/"workshop" contributes too little to qualify an
  // off-target note; a named event or a specific date/number contributes more.
  const reliable = new Set<string>();
  for (const candidate of lexical) {
    const coverage = weightedCoverage(evidence, candidate.chunk);
    if (coverage <= 0 || bestCoverage <= 0) continue;
    if (coverage >= RELEVANCE_COVERAGE_FLOOR * bestCoverage) reliable.add(sourceKey(candidate.chunk));
  }

  // Bounded independent-part recall: only an explicitly multi-part question AND a meaningful
  // uncovered part (>=2 terms or a number/date) can add a weaker lexical source, and only when it
  // covers at least half of that part. This replaces the v1 "any overlap under a conjunction"
  // bypass; the conjunction is a signal, never sufficient on its own.
  const strongCovered = coveredTerms(
    evidence,
    lexical.filter((candidate) => reliable.has(sourceKey(candidate.chunk))).map((candidate) => candidate.chunk),
  );
  const missingFromStrong = missingTerms(evidence, strongCovered);
  if (conjunctive && isMeaningfulMissing(evidence, missingFromStrong)) {
    for (const candidate of lexical) {
      const key = sourceKey(candidate.chunk);
      if (reliable.has(key) || weightedCoverage(evidence, candidate.chunk) <= 0) continue;
      if (missingTermCoverage(evidence, candidate.chunk, missingFromStrong) >= RELEVANCE_COVERAGE_FLOOR) {
        reliable.add(key);
      }
    }
  }

  const anchors = candidates.filter(
    (candidate) => isLexical(candidate) && reliable.has(sourceKey(candidate.chunk)),
  );
  const anchorCovered = coveredTerms(evidence, anchors.map((candidate) => candidate.chunk));
  const meaningfulVectorGap =
    conjunctive && isMeaningfulMissing(evidence, missingTerms(evidence, anchorCovered));
  const anchorDistances = anchors
    .map((candidate) => candidate.vectorDistance)
    .filter((distance): distance is number => distance !== undefined);
  const anchorRanks = anchors
    .map((candidate) => candidate.vectorRank)
    .filter((rank): rank is number => rank !== undefined);
  const closestAnchorDistance = anchorDistances.length > 0 ? Math.min(...anchorDistances) : undefined;
  const bestLexicalVectorRank = anchorRanks.length > 0 ? Math.min(...anchorRanks) : undefined;
  const anyDistance = candidates.some((candidate) => candidate.vectorDistance !== undefined);

  /**
   * Vector-only decision. `null` means keep. Lexical candidates never reach this path: reliable
   * ones are always kept, weak ones are rejected as lexical below.
   */
  const vectorReason = (candidate: Candidate): RelevanceRejectionReason | null => {
    const distance = candidate.vectorDistance;
    const rank = candidate.vectorRank;

    if (anchors.length === 0) {
      // Explicit safe semantic fallback when there is no lexical evidence at all (for example a
      // cross-language query). An absent legacy distance remains a conservative rank-only keep,
      // never an invented score.
      if (distance === undefined) return null;
      return distance < RELEVANCE_POSITIVE_DISTANCE ? null : 'non_positive_semantic';
    }

    if (meaningfulVectorGap) {
      // A strong first part must not set the boundary for a different requested part that the
      // lexical shortlist cannot represent. Only a known positive cosine is admitted, and MMR
      // must still justify the addition against the missing evidence.
      if (distance === undefined) return null;
      return distance < RELEVANCE_POSITIVE_DISTANCE ? null : 'non_positive_semantic';
    }

    if (closestAnchorDistance !== undefined) {
      if (distance !== undefined) {
        return distance <= closestAnchorDistance ? null : 'outside_vector_boundary';
      }
      // Mixed metadata: the candidate has no distance while its anchors do. Fall back to the
      // original rank order only when a comparable lexical vector rank exists; otherwise the
      // comparison is genuinely unavailable and the conservative keep applies.
      if (bestLexicalVectorRank !== undefined && rank !== undefined) {
        return rank <= bestLexicalVectorRank ? null : 'outside_vector_boundary';
      }
      return null;
    }

    // Distances are uniformly absent: use the original vector rank order as a proxy, never a
    // fabricated distance.
    if (!anyDistance) {
      if (bestLexicalVectorRank !== undefined && rank !== undefined) {
        return rank <= bestLexicalVectorRank ? null : 'outside_vector_boundary';
      }
      // Lexical anchors are not in the vector branch: no comparable boundary.
      return null;
    }

    // Distances exist somewhere but not on any reliable lexical anchor: no comparable boundary.
    if (distance !== undefined) {
      return distance < RELEVANCE_POSITIVE_DISTANCE ? null : 'non_positive_semantic';
    }
    return null;
  };

  const kept: Candidate[] = [];
  const rejected: RelevanceRejection[] = [];
  for (const candidate of candidates) {
    const key = sourceKey(candidate.chunk);
    if (!targets.has(key)) {
      rejected.push(Object.freeze({ chunkRef: chunkRef(candidate.chunk),
        reason: isLexical(candidate) && matchedTerms(evidence, candidate.chunk).size === 0
          ? 'no_query_overlap' : 'target_mismatch' }));
      continue;
    }
    if (reliable.has(key)) {
      kept.push(candidate);
      continue;
    }
    if (isLexical(candidate)) {
      rejected.push(Object.freeze({
        chunkRef: chunkRef(candidate.chunk),
        reason: matchedTerms(evidence, candidate.chunk).size > 0 ? 'weak_lexical' : 'no_query_overlap',
      }));
      continue;
    }
    const reason = vectorReason(candidate);
    if (reason === null) {
      kept.push(candidate);
    } else {
      rejected.push(Object.freeze({ chunkRef: chunkRef(candidate.chunk), reason }));
    }
  }

  return frozenDecision(kept, rejected, mode);
}
