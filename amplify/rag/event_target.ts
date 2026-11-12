/**
 * Bounded contrastive event-target shortcut: a lexical/date heuristic only.
 *
 * The caller owns the "strong primary" choice and all final authority. This helper answers one
 * narrow question: may `candidate` be the same requested target as `primary` under the current
 * query-evidence profile? It never calls a provider/model/NER, never edits the raw question and
 * never logs text.
 *
 * Two cheap conditions:
 * 1. Explicit full query dates are hard conditions. A candidate that has explicit full dates,
 *    none matching a requested date, is off-target unless it is explicitly marked as a
 *    correction/reschedule; that marked case stays visible to JEV instead of being hidden to
 *    clean the score. Undated candidates stay unknown/conservative, and bare numbers such as
 *    prices are never compared.
 * 2. The rarest meaningful non-numeric query terms matched by the primary form a contrastive
 *    target signature, which the candidate must share. If the candidate instead supplies a
 *    different meaningful requested term absent from the primary (a second conjunct/entity), it
 *    is allowed as an independent requested entity. With no defensible signature this stays
 *    date-only/conservative.
 *
 * This is not entity recognition and makes no semantic-truth claim.
 */
import { assertChunk, isWellFormed } from './chunking';
import { analyze } from './keyword';
import { matchedTerms, type QueryEvidence } from './query_evidence';
import { RagFailure, type Chunk } from './types';

/** Query labels/fillers that describe what to report, not which target is requested. */
const FACET_TERMS: ReadonlySet<string> = new Set([
  // Vietnamese time/place/cost/request labels.
  'ngày', 'lúc', 'giờ', 'lịch', 'đổi', 'chuyển', 'dời', 'thay', 'hoãn', 'thời', 'gian', 'buổi', 'sáng', 'chiều', 'tối', 'tuần', 'tháng', 'năm',
  'địa', 'điểm', 'nơi', 'chỗ', 'phòng', 'tại', 'ở', 'đâu',
  'lệ', 'phí', 'giá', 'học', 'tiền', 'miễn', 'đ', 'vnđ', 'vnd', 'usd', 'đồng', 'nghìn', 'ngàn',
  'triệu', 'trăm',
  'bao', 'nhiêu', 'lâu', 'khi', 'nào', 'diễn', 'ra', 'tổ', 'chức', 'có',
  'thông', 'tin', 'cho', 'biết', 'vui', 'lòng', 'xin', 'hỏi', 'cần', 'muốn', 'chi', 'tiết',
  'cụ', 'thể',
  // English equivalents.
  'date', 'time', 'day', 'change', 'changed', 'reschedule', 'rescheduled', 'place', 'location', 'venue', 'address', 'room', 'rooms', 'fee', 'cost', 'costs', 'price', 'prices',
  'when', 'where', 'how', 'much', 'many', 'schedule', 'registration', 'register', 'contact',
  'details', 'detail', 'information', 'info', 'tell', 'know', 'please', 'cover',
]);

/** Negation is never a target/entity condition and is never required in a source. */
const NEGATION_TERMS: ReadonlySet<string> = new Set([
  'không', 'chưa', 'chẳng', 'đừng', 'chớ', 'not', 'no', 'never', 'without', 'none', 'neither', 'nor',
]);

const CORRECTION_TOKENS: ReadonlySet<string> = new Set([
  'correction', 'corrections', 'corrected', 'reschedule', 'rescheduled', 'postponed', 'postpone',
  'hoãn',
]);
const CORRECTION_PAIRS: ReadonlySet<string> = new Set([
  'đính chính', 'chỉnh sửa', 'sửa lại', 'dời lịch', 'đổi lịch', 'đổi ngày', 'lùi lịch',
  'date changed', 'schedule changed',
]);
const CORRECTION_TRIPLES: ReadonlySet<string> = new Set(['thay đổi lịch', 'thay đổi ngày']);

type CalendarDate = Readonly<{ year: number; month: number; day: number }>;
type DatePattern = Readonly<{ pattern: RegExp; parts: 'ymd' | 'dmy' }>;

const DATE_PATTERNS: readonly DatePattern[] = [
  { pattern: /(?<!\d)(\d{4})-(\d{1,2})-(\d{1,2})(?!\d)/gu, parts: 'ymd' },
  { pattern: /(?<!\d)(\d{1,2})\/(\d{1,2})\/(\d{4})(?!\d)/gu, parts: 'dmy' },
  { pattern: /(?<!\d)(\d{1,2})-(\d{1,2})-(\d{4})(?!\d)/gu, parts: 'dmy' },
  { pattern: /(?<!\d)ngày\s+(\d{1,2})\s+tháng\s+(\d{1,2})\s+năm\s+(\d{4})(?!\d)/giu, parts: 'dmy' },
];

const daysInMonth = (year: number, month: number): number => {
  if (month === 2) return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0) ? 29 : 28;
  return [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1] ?? 0;
};

const calendarDate = (year: number, month: number, day: number): CalendarDate | null => {
  if (!Number.isSafeInteger(year) || !Number.isSafeInteger(month) || !Number.isSafeInteger(day)) {
    return null;
  }
  if (year < 1 || year > 9999 || month < 1 || month > 12) return null;
  if (day < 1 || day > daysInMonth(year, month)) return null;
  return Object.freeze({ year, month, day });
};

/** All explicit full dates in raw text, normalized and deduplicated. Bare numbers are ignored. */
const fullDates = (text: string): readonly CalendarDate[] => {
  const found: CalendarDate[] = [];
  const seen = new Set<string>();
  for (const { pattern, parts } of DATE_PATTERNS) {
    for (const match of text.normalize('NFKC').matchAll(pattern)) {
      const year = Number.parseInt(parts === 'ymd' ? match[1] : match[3], 10);
      const month = Number.parseInt(match[2], 10);
      const day = Number.parseInt(parts === 'ymd' ? match[3] : match[1], 10);
      const date = calendarDate(year, month, day);
      if (date === null) continue;
      const key = `${date.year}-${date.month}-${date.day}`;
      if (seen.has(key)) continue;
      seen.add(key);
      found.push(date);
    }
  }
  return found;
};

const sameDate = (left: CalendarDate, right: CalendarDate): boolean =>
  left.year === right.year && left.month === right.month && left.day === right.day;

const documentText = (chunk: Chunk): string => `${chunk.title}\n${chunk.text}`;

const isCorrection = (text: string): boolean => {
  const tokens = analyze(text);
  for (const token of tokens) if (CORRECTION_TOKENS.has(token)) return true;
  for (let index = 0; index < tokens.length - 1; index += 1) {
    const pair = `${tokens[index]} ${tokens[index + 1]}`;
    if (CORRECTION_PAIRS.has(pair)) return true;
    if (index + 2 < tokens.length) {
      const triple = `${pair} ${tokens[index + 2]}`;
      if (CORRECTION_TRIPLES.has(triple)) return true;
    }
  }
  return false;
};

const hasConflictingFullDate = (question: string, candidate: Chunk): boolean => {
  const requested = fullDates(question);
  if (requested.length === 0) return false;
  const actual = fullDates(documentText(candidate));
  if (actual.length === 0) return false; // Unknown source date stays conservative.
  return !actual.some((date) => requested.some((requestedDate) => sameDate(date, requestedDate)));
};

// Bare numbers/unit-like values are not identities; letter-led/interleaved IDs such as SLGH031 are.
const isMeaningful = (term: string): boolean =>
  !/^\p{N}+\p{L}*$/u.test(term) && !FACET_TERMS.has(term) && !NEGATION_TERMS.has(term);

/**
 * Rarest meaningful query terms that the strong primary actually matches. Equal top weights are
 * kept together so a tie cannot silently select a generic shared term instead of a target term.
 */
const targetSignature = (
  evidence: QueryEvidence,
  primaryMatched: ReadonlySet<string>,
): readonly string[] => {
  let maximum = 0;
  const matched: string[] = [];
  for (const term of evidence.terms) {
    if (!primaryMatched.has(term) || !isMeaningful(term)) continue;
    matched.push(term);
    maximum = Math.max(maximum, evidence.weights.get(term) ?? 0);
  }
  if (!(maximum > 0)) return [];
  return matched.filter((term) => {
    const weight = evidence.weights.get(term) ?? 0;
    return Math.abs(weight - maximum) <= 1e-12;
  });
};

/**
 * True when the candidate may represent the requested target. The canonical pipeline remains the
 * only authority; this pure predicate is a bounded lexical/date shortcut, not entity recognition.
 */
export function matchesQueryTarget(
  question: string,
  primary: Chunk,
  candidate: Chunk,
  evidence: QueryEvidence,
): boolean {
  if (typeof question !== 'string' || !isWellFormed(question)) throw new RagFailure('INVALID_INPUT');
  assertChunk(primary);
  assertChunk(candidate);
  if (evidence === null || typeof evidence !== 'object') throw new RagFailure('INVALID_INPUT');

  const primaryMatched = matchedTerms(evidence, primary);
  const signature = targetSignature(evidence, primaryMatched);
  const candidateMatched = matchedTerms(evidence, candidate);
  const sameTarget = signature.every((term) => candidateMatched.has(term));
  const independentTarget = evidence.terms.some(
    (term) => isMeaningful(term) && candidateMatched.has(term) && !primaryMatched.has(term),
  );
  // A date attached to the primary event is not a condition on another explicitly requested topic.
  if (signature.length > 0 && !sameTarget && independentTarget) return true;
  if (hasConflictingFullDate(question, candidate) && !isCorrection(question) && !isCorrection(documentText(candidate))) {
    return false;
  }
  return signature.length === 0 || sameTarget || independentTarget;
}
