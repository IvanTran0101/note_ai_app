// shortcut: lexical hash vectors are synthetic; replace with Cohere after the live-fit gate.
import { policy, RagFailure } from './types';
import { analyze } from './keyword';
import { validateVector } from './retrieval';
const INDEX_DIMENSIONS = policy.embedding.dimensions;

const FNV_OFFSET = 0x811c9dc5;
const FNV_PRIME = 0x01000193;

/** Deterministic FNV-1a over UTF-16 code units: same text always maps to the same dimension. */
const hashToken = (token: string): number => {
  let hash = FNV_OFFSET;
  for (let index = 0; index < token.length; index += 1) {
    hash ^= token.charCodeAt(index);
    hash = Math.imul(hash, FNV_PRIME) >>> 0;
  }
  return hash >>> 0;
};

/** Analyzer-v1 tokens; a normalized fallback token keeps every embedding non-zero and finite. */
const vectorTokens = (text: string): readonly string[] => {
  const tokens = analyze(text);
  if (tokens.length > 0) return tokens;
  const fallback = text.normalize('NFKC').toLowerCase().trim();
  return [fallback.length > 0 ? fallback : '<empty>'];
};

const embed = (text: string): readonly number[] => {
  const vector = new Array<number>(INDEX_DIMENSIONS).fill(0);
  for (const token of vectorTokens(text)) vector[hashToken(token) % INDEX_DIMENSIONS] += 1;
  const norm = Math.hypot(...vector);
  return Object.freeze(vector.map((value) => value / norm));
};

/** policy.embedding.queryInputType = "search_query". */
export const embedSearchQuery = (question: string): readonly number[] => {
  if (typeof question !== 'string') throw new RagFailure('INVALID_INPUT');
  return embed(question);
};

/** policy.embedding.documentInputType = "search_document" over policy embeddingText. */
export const embedSearchDocument = (document: string): readonly number[] => {
  if (typeof document !== 'string') throw new RagFailure('INVALID_INPUT');
  return embed(document);
};

export const dot = (left: readonly number[], right: readonly number[]): number => {
  let sum = 0;
  for (let index = 0; index < INDEX_DIMENSIONS; index += 1) {
    sum += (left[index] as number) * (right[index] as number);
  }
  return Math.max(-1, Math.min(1, sum));
};

export const unitVector = (vector: readonly number[]): readonly number[] => {
  validateVector(vector);
  const norm = Math.hypot(...vector);
  return vector.map((value) => value / norm);
};

