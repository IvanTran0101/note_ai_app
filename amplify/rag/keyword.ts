// Mock analyzer v1: NFKC/lowercase + Unicode words; BM25 parameters are fixture defaults.
import { policy, RagFailure, sourceKey, type Chunk, type Ranked } from './types';
import { assertChunk } from './chunking';

/** Documented analyzer identity — bump only with a migration. */
export const ANALYZER_VERSION = 'rag-analyzer.v1';
export const ANALYZER_PATTERN = /[\p{L}\p{N}]+/gu;
export const BM25_K1 = 1.2;
export const BM25_B = 0.75;
export const BM25_TOP_K: number = policy.retrieval.bm25TopK;
/**
 * BM25 indexes the lexical title-newline-content document, never the provider-framed embedding
 * input. Embedding prefixes (`title:`, `task: search result | query:`) must not change match
 * terms or document length.
 */
export const BM25_DOCUMENT = 'title-newline-content-span' as const;

/**
 * Query-scoring policy version. This describes how a *question* is reduced to BM25 terms; it is
 * deliberately separate from `ANALYZER_VERSION`/`BM25_K1`/`BM25_B`, which are part of the index
 * policy identity. Changing query term selection must never force a re-embed or invalidate an
 * existing index generation.
 */
export const QUERY_POLICY_VERSION = 'rag-query-policy.v1' as const;

/**
 * Explicit, conservative VI/EN function-word and question fillers removed from QUERY SCORING
 * ONLY. The raw question is never edited (JEV and embeddings still receive it verbatim).
 *
 * Deliberately absent: negations (không, chưa, not, no, never, without), numbers, dates and
 * distinctive name/content tokens. Tokens are matched exactly after `analyze`, so any token with
 * a digit or a diacritic different from the listed form is always preserved.
 */
const QUERY_FILLERS: ReadonlySet<string> = new Set([
  // Vietnamese question/function words.
  'khi', 'ra', 'nào', 'diễn', 'cuộc', 'và', 'là', 'của', 'cho', 'với', 'trong', 'trên',
  'tại', 'từ', 'về', 'để', 'thì', 'như', 'nhưng', 'hoặc', 'đã', 'đang', 'sẽ',
  'ai', 'gì', 'sao', 'đâu', 'thế', 'này', 'đó', 'các', 'những', 'việc', 'bị', 'mà',
  'rồi', 'hãy', 'vậy', 'nên',
  // English question/function words.
  'when', 'what', 'who', 'whom', 'whose', 'where', 'why', 'which', 'how', 'does', 'did',
  'do', 'is', 'are', 'was', 'were', 'be', 'been', 'being', 'the', 'a', 'an', 'of', 'to',
  'and', 'or', 'but', 'in', 'on', 'at', 'for', 'with', 'from', 'by', 'as', 'that', 'this',
  'these', 'those', 'it', 'its', 'there', 'here',
]);

/**
 * Pure query-term selection for BM25 only: analyzer v1 over the raw question, minus the explicit
 * filler list, deduplicated in first-occurrence order. A question made only of fillers yields
 * `[]`; the caller must then leave the keyword branch empty and let the semantic branch decide.
 * Document terms, analyzer identity, tokenization and chunking are untouched.
 */
export function queryTerms(question: string): readonly string[] {
  if (typeof question !== 'string') throw new RagFailure('INVALID_INPUT');
  const terms: string[] = [];
  const seen = new Set<string>();
  for (const token of analyze(question)) {
    if (QUERY_FILLERS.has(token) || seen.has(token)) continue;
    seen.add(token);
    terms.push(token);
  }
  return Object.freeze(terms);
}

/**
 * Analyzer v1: NFKC -> lowercase -> Unicode letter/number tokens, in text order.
 * Returns [] for text without word/number tokens.
 */
export function analyze(text: string): string[] {
  if (typeof text !== 'string') throw new RagFailure('INVALID_INPUT');
  const normalized = text.normalize('NFKC').toLowerCase();
  const matches = normalized.match(ANALYZER_PATTERN);
  return matches === null ? [] : matches;
}

/** Raw lexical document: title, newline, exact content span. No embedding framing is added. */
const documentTerms = (chunk: Chunk): string[] => analyze(`${chunk.title}\n${chunk.text}`);

/**
 * BM25 over the caller-supplied eligible corpus. Query terms come from `queryTerms` (explicit
 * question fillers removed); document terms still come from `analyze`. Returns positive matches
 * only, ranked 1..n (rank starts at 1), capped at `retrieval.bm25TopK` (20), ties broken by
 * ascending source key so the order is deterministic. Every entry carries its positive finite
 * `bm25Score`; the score never participates in RRF/MMR decisions here.
 */
export function bm25(question: string, chunks: readonly Chunk[]): readonly Ranked[] {
  if (typeof question !== 'string') throw new RagFailure('INVALID_INPUT');
  if (!Array.isArray(chunks)) throw new RagFailure('INVALID_INPUT');
  const k1 = BM25_K1;
  const b = BM25_B;

  const terms = queryTerms(question);
  if (terms.length === 0 || chunks.length === 0) return [];

  const keys = new Set<string>();
  const documents: string[][] = [];
  for (const chunk of chunks) {
    assertChunk(chunk);
    const key = sourceKey(chunk);
    // The eligible corpus is a set of distinct source identities; duplicates are upstream corruption.
    if (keys.has(key)) throw new RagFailure('INVALID_INPUT');
    keys.add(key);
    documents.push(documentTerms(chunk));
  }

  const totalLength = documents.reduce((sum, document) => sum + document.length, 0);
  const averageLength = totalLength / documents.length;

  const documentFrequency = new Map<string, number>();
  for (const term of terms) {
    let frequency = 0;
    for (const document of documents) {
      if (document.includes(term)) frequency += 1;
    }
    documentFrequency.set(term, frequency);
  }

  const scored: { chunk: Chunk; score: number }[] = [];
  for (let index = 0; index < chunks.length; index += 1) {
    const document = documents[index];
    const frequencies = new Map<string, number>();
    for (const token of document) frequencies.set(token, (frequencies.get(token) ?? 0) + 1);
    let score = 0;
    for (const term of terms) {
      const termFrequency = frequencies.get(term);
      if (termFrequency === undefined) continue;
      const frequency = documentFrequency.get(term) ?? 0;
      const idf = Math.log(1 + (documents.length - frequency + 0.5) / (frequency + 0.5));
      const lengthRatio = averageLength > 0 ? document.length / averageLength : 1;
      score += (idf * (termFrequency * (k1 + 1))) / (termFrequency + k1 * (1 - b + b * lengthRatio));
    }
    if (!Number.isFinite(score)) throw new RagFailure('INVALID_INPUT');
    if (score > 0) scored.push({ chunk: chunks[index], score });
  }

  scored.sort(
    (left, right) => right.score - left.score || compareSourceKey(left.chunk, right.chunk),
  );

  return scored.slice(0, BM25_TOP_K).map((entry, index) => ({
    chunk: entry.chunk,
    rank: index + 1,
    bm25Score: entry.score,
  }));
}

/** Ascending source key (policy.technicalDefaults.tieBreak), compared as code units. */
export const compareSourceKey = (left: Chunk, right: Chunk): number => {
  const a = sourceKey(left);
  const b = sourceKey(right);
  return a < b ? -1 : a > b ? 1 : 0;
};
