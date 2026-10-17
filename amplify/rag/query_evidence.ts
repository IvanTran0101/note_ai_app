/**
 * Deterministic query-evidence profile shared by the ordered relevance gate and the
 * evidence-aware MMR additions.
 *
 * The profile is deliberately lexical only: it never calls a provider, never invents a metric and
 * never claims that a lexical match is semantic truth. It reduces the raw question to the existing
 * `queryTerms` stream and weights each term by how rare it is across THIS query's candidate pool
 * (document frequency over candidate title+span). Terms such as a shared year or "workshop" that
 * occur in many candidates therefore contribute little, while a named event/topic or a specific
 * date/number contributes more. This is a bounded query-relative heuristic, not NER, not a
 * calibrated probability and not a universal cosine/idf threshold.
 *
 * Candidate documents reuse the exact analyzer and title-newline-span document the existing
 * coverage helper used. Query fillers are already removed by `queryTerms`; the raw question is
 * never edited for embedding/JEV.
 */
import { analyze, queryTerms } from './keyword';
import { RagFailure, sourceKey, type Candidate, type Chunk } from './types';

export type QueryEvidence = Readonly<{
  /** Meaningful, deduplicated query terms in first-occurrence order (may be empty). */
  terms: readonly string[];
  /** Query-relative rarity weight for each term; a term absent everywhere still has a weight. */
  weights: ReadonlyMap<string, number>;
  totalWeight: number;
  /** Matched query terms per source key, computed once for this candidate pool. */
  matches: ReadonlyMap<string, ReadonlySet<string>>;
}>;

const EMPTY_MATCHES: ReadonlySet<string> = Object.freeze(new Set<string>());
const EMPTY_TERMS: readonly string[] = Object.freeze([]);

/** Raw comparison/conjunction markers that structure a question but are not target evidence. */
const CONJUNCTIVE_TOKENS: ReadonlySet<string> = new Set(['and', 'và', 'vs', 'versus']);
const COMPARISON_TOKENS: ReadonlySet<string> = new Set(['so', 'sánh']);
/**
 * Evidence-only question markers not yet in the existing BM25 `QUERY_FILLERS` list. These are
 * deliberately tiny and generic ("ở", the tail of "bao nhiêu"); removing them here cannot change
 * BM25 scoring, the analyzer, the embedding input or JEV. They must never be treated as a missing
 * target part.
 */
const QUESTION_STRUCTURE_TOKENS: ReadonlySet<string> = new Set(['ở', 'nhiêu']);

/**
 * `and`/`và`/`vs`/`versus` or the two-token phrase `so sánh` in the RAW analyzer stream marks a
 * multi-part question. This is lexical structure only: no model confidence, no quantization.
 */
export const isConjunctiveQuestion = (question: string): boolean => {
  const tokens = analyze(question);
  for (let index = 0; index < tokens.length; index += 1) {
    if (CONJUNCTIVE_TOKENS.has(tokens[index])) return true;
    if (tokens[index] === 'so' && tokens[index + 1] === 'sánh') return true;
  }
  return false;
};

/** Structural markers are not missing target evidence, even if queryTerms keeps them. */
const isQueryStructure = (term: string): boolean =>
  CONJUNCTIVE_TOKENS.has(term) ||
  COMPARISON_TOKENS.has(term) ||
  QUESTION_STRUCTURE_TOKENS.has(term);

const documentTerms = (chunk: Chunk): ReadonlySet<string> =>
  new Set(analyze(`${chunk.title}\n${chunk.text}`));

/**
 * Rarity-weighted profile over one candidate pool. Weight is `ln(1 + N/(df+1))`, so a term in
 * every candidate has a lower weight (approaching ln(2)), while a rare matched term weighs more. `df` counts candidates
 * whose title+span contains the term, not occurrences, so repeated boilerplate cannot dominate.
 * Conjunction/comparison markers are excluded from the evidence terms; they select structure, not
 * target content, and must never become a "missing evidence" gap.
 */
export function buildQueryEvidence(
  question: string,
  candidates: readonly Candidate[],
): QueryEvidence {
  if (!Array.isArray(candidates)) throw new RagFailure('INVALID_INPUT');
  const raw = analyze(question);
  const content: string[] = [];
  for (let index = 0; index < raw.length; index += 1) {
    const quantity = (raw[index] === 'bao' && ['nhiêu', 'lâu'].includes(raw[index + 1])) ||
      (raw[index] === 'how' && ['many', 'much', 'long'].includes(raw[index + 1]));
    if (quantity) { index += 1; continue; }
    content.push(raw[index]);
  }
  const terms = queryTerms(content.join(' ')).filter((term) => !isQueryStructure(term));
  if (terms.length === 0) {
    return Object.freeze({
      terms: EMPTY_TERMS,
      weights: Object.freeze(new Map<string, number>()),
      totalWeight: 0,
      matches: Object.freeze(new Map<string, ReadonlySet<string>>()),
    });
  }

  const documents = candidates.map((candidate) => ({
    key: sourceKey(candidate.chunk),
    terms: documentTerms(candidate.chunk),
  }));
  const documentFrequency = new Map<string, number>();
  for (const term of terms) {
    let frequency = 0;
    for (const document of documents) if (document.terms.has(term)) frequency += 1;
    documentFrequency.set(term, frequency);
  }

  const count = documents.length;
  const weights = new Map<string, number>();
  let totalWeight = 0;
  for (const term of terms) {
    const weight = count === 0 ? 0 : Math.log(1 + count / ((documentFrequency.get(term) ?? 0) + 1));
    weights.set(term, weight);
    totalWeight += weight;
  }

  const matches = new Map<string, ReadonlySet<string>>();
  for (const document of documents) {
    const matched = new Set<string>();
    for (const term of terms) if (document.terms.has(term)) matched.add(term);
    matches.set(document.key, matched);
  }

  return Object.freeze({
    terms,
    weights: Object.freeze(weights),
    totalWeight,
    matches: Object.freeze(matches),
  });
}

/** Matched query terms for a chunk; an unlisted chunk (foreign to the pool) matches nothing. */
export const matchedTerms = (
  evidence: QueryEvidence,
  chunk: Chunk,
): ReadonlySet<string> => evidence.matches.get(sourceKey(chunk)) ?? EMPTY_MATCHES;

/** Sum of rarity weights for the supplied terms that are actually query terms. */
export const weightedTermSum = (
  evidence: QueryEvidence,
  terms: Iterable<string>,
): number => {
  let total = 0;
  for (const term of terms) total += evidence.weights.get(term) ?? 0;
  return total;
};

/** Fraction of the query's rarity weight present in the candidate title+span, in [0,1]. */
export const weightedCoverage = (evidence: QueryEvidence, chunk: Chunk): number => {
  if (!(evidence.totalWeight > 0)) return 0;
  return weightedTermSum(evidence, matchedTerms(evidence, chunk)) / evidence.totalWeight;
};

/** Union of query terms already represented by at least one supplied chunk. */
export const coveredTerms = (
  evidence: QueryEvidence,
  chunks: readonly Chunk[],
): ReadonlySet<string> => {
  const covered = new Set<string>();
  for (const chunk of chunks) {
    for (const term of matchedTerms(evidence, chunk)) covered.add(term);
  }
  return covered;
};

/** Query terms not represented by the supplied coverage set. */
export const missingTerms = (
  evidence: QueryEvidence,
  covered: ReadonlySet<string>,
): readonly string[] => evidence.terms.filter((term) => !covered.has(term));

const isRepresented = (evidence: QueryEvidence, term: string): boolean =>
  [...evidence.matches.values()].some((terms) => terms.has(term));

/**
 * Conservative "this gap is worth completing" guard. A missing part must be a contiguous run in
 * the query's meaningful-term order: at least two adjacent terms, or any term containing a number.
 * A missing term actually represented by another candidate also counts, including a one-word name.
 * A single stray preposition/function word, or two unrelated single-term gaps, is not treated as an
 * event/target identity. This is a bounded shortcut, not a claim that the matched source answers
 * the missing part.
 */
export const isMeaningfulMissing = (
  evidence: QueryEvidence,
  missing: readonly string[],
): boolean => {
  // A single requested name/field can matter; do not drop it just because it is one token.
  if (missing.some((term) => isRepresented(evidence, term))) return true;
  const missingSet = new Set(missing);
  let run = 0;
  for (const term of evidence.terms) {
    if (!missingSet.has(term)) {
      run = 0;
      continue;
    }
    run += 1;
    if (run >= 2 || /\p{N}/u.test(term)) return true;
  }
  return false;
};

/** Fraction of available missing terms' rarity weight covered by one candidate, in [0,1]. */
export const missingTermCoverage = (
  evidence: QueryEvidence,
  chunk: Chunk,
  missing: readonly string[],
): number => {
  // Unsupported question wording must not dilute an actually available second fact.
  const represented = missing.filter((term) => isRepresented(evidence, term));
  const missingWeight = weightedTermSum(evidence, represented);
  if (!(missingWeight > 0)) return 0;
  const own = matchedTerms(evidence, chunk);
  return weightedTermSum(evidence, represented.filter((term) => own.has(term))) / missingWeight;
};

/** Fraction of an already-selected target-term set that one candidate shares, in [0,1]. */
export const targetTermOverlap = (
  evidence: QueryEvidence,
  chunk: Chunk,
  target: ReadonlySet<string>,
): number => {
  const targetWeight = weightedTermSum(evidence, target);
  if (!(targetWeight > 0)) return 0;
  const own = matchedTerms(evidence, chunk);
  return weightedTermSum(evidence, [...target].filter((term) => own.has(term))) / targetWeight;
};
