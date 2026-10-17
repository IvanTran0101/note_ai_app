// Counter-bounded paragraph/sentence/Unicode chunking; real tokenizers need a later live gate.
import { policy, RagFailure, type CanonicalNote, type Chunk, type Counter } from './types';

/** policy.chunking.strategy — kept as a documented constant, not a runtime switch. */
export const CHUNKING_STRATEGY: string = policy.chunking.strategy;
/** Text-only notes have no markup parser in this slice: the whole content is section `body`. */
export const SECTION_BODY = 'body';
export const TARGET_TOKENS: number = policy.chunking.targetTokens;
export const MAX_EMBEDDING_TOKENS: number = policy.chunking.maxEmbeddingTokens;
export const MAX_EMBEDDING_CHARACTERS: number = policy.chunking.maxEmbeddingCharacters;
export const OVERLAP_TOKENS: number = policy.chunking.overlapTokens;

/** Blank-line boundary: two or more newlines with only non-newline whitespace between them. */
const PARAGRAPH_BREAK = /\n[^\S\n]*\n+/g;

/** JavaScript safe-integer semantics (contract: integral 1.0 equals 1, booleans rejected). */
export const isSafeInteger = (value: unknown): value is number =>
  typeof value === 'number' && Number.isSafeInteger(value);

const isIdentifier = (value: unknown): value is string =>
  typeof value === 'string' && value.trim().length > 0 && value === value.trim() &&
  Array.from(value).length <= 128 && !/[\u0000-\u001f\u007f]/.test(value);

export function isWellFormed(text: string): boolean {
  for (const character of text) {
    const point = character.codePointAt(0)!;
    if (point >= 0xd800 && point <= 0xdfff) return false;
  }
  return true;
}

const isWhitespace = (value: string): boolean => /\s/.test(value);

/** Unicode characters = code points (an astral emoji counts once, not twice). */
export const countUnicodeCharacters = (text: string): number => Array.from(text).length;

/**
 * Injected counter port guard. Fails closed (EVIDENCE_VALIDATION_UNAVAILABLE) on a missing
 * counter, a throwing counter, or a non-finite / non-integer / negative count.
 */
export function countTokens(counter: Counter, text: string): number {
  if (typeof counter !== 'function') throw new RagFailure('EVIDENCE_VALIDATION_UNAVAILABLE');
  let value: unknown;
  try {
    value = counter(text);
  } catch {
    throw new RagFailure('EVIDENCE_VALIDATION_UNAVAILABLE');
  }
  if (!isSafeInteger(value) || value < 0) throw new RagFailure('EVIDENCE_VALIDATION_UNAVAILABLE');
  return value;
}

/** Structural + span-lineage guard for a chunk crossing a module/provider boundary. */
export function assertChunk(chunk: unknown): asserts chunk is Chunk {
  if (chunk === null || typeof chunk !== 'object') throw new RagFailure('INVALID_INPUT');
  const candidate = chunk as Record<string, unknown>;
  if (
    !isIdentifier(candidate.ownerId) ||
    !isIdentifier(candidate.noteId) ||
    !isIdentifier(candidate.sectionId) ||
    !isIdentifier(candidate.chunkId)
  ) {
    throw new RagFailure('INVALID_INPUT');
  }
  if (!isSafeInteger(candidate.revision) || candidate.revision < 1) throw new RagFailure('INVALID_INPUT');
  if (!isSafeInteger(candidate.ordinal) || candidate.ordinal < 0) throw new RagFailure('INVALID_INPUT');
  if (!isSafeInteger(candidate.startOffset) || !isSafeInteger(candidate.endOffset)) {
    throw new RagFailure('INVALID_INPUT');
  }
  if (candidate.startOffset < 0 || candidate.endOffset <= candidate.startOffset) {
    throw new RagFailure('INVALID_INPUT');
  }
  if (typeof candidate.title !== 'string' || typeof candidate.text !== 'string') {
    throw new RagFailure('INVALID_INPUT');
  }
  if (!isWellFormed(candidate.title) || !isWellFormed(candidate.text)) throw new RagFailure('INVALID_INPUT');
  // text must be the exact content slice for the span (no trimming/normalization drift).
  if (candidate.text.length !== candidate.endOffset - candidate.startOffset) {
    throw new RagFailure('INVALID_INPUT');
  }
}

/** EmbeddingGemma document framing: `title: {title or none} | text: {content span}`. */
const documentPrefix = (title: string): string =>
  `title: ${title.length === 0 ? 'none' : title} | text: `;

/** EmbeddingGemma query framing; applied exactly once, never to a document. */
export const QUERY_PREFIX = 'task: search result | query: ';

/** Canonical embedding input for one document chunk, already framed and counted as-is. */
export function embeddingText(chunk: Chunk): string {
  if (
    chunk === null ||
    typeof chunk !== 'object' ||
    typeof chunk.title !== 'string' ||
    typeof chunk.text !== 'string'
  ) {
    throw new RagFailure('INVALID_INPUT');
  }
  return documentPrefix(chunk.title) + chunk.text;
}

/** Canonical embedding input for one question; the caller counts and embeds this exact string. */
export function queryEmbeddingText(question: string): string {
  if (typeof question !== 'string' || question.length === 0 || !isWellFormed(question)) {
    throw new RagFailure('INVALID_INPUT');
  }
  return QUERY_PREFIX + question;
}

type Span = Readonly<{ start: number; end: number }>;

type Measurement = Readonly<{ tokens: number; characters: number }>;

const hasNonWhitespace = (content: string, span: Span): boolean => {
  const text = content.slice(span.start, span.end);
  for (let index = 0; index < text.length; index += 1) {
    if (!isWhitespace(text[index])) return true;
  }
  return false;
};

let sentenceSegmenter: Intl.Segmenter | null | undefined;

const getSentenceSegmenter = (): Intl.Segmenter | null => {
  if (sentenceSegmenter === undefined) {
    try {
      sentenceSegmenter =
        typeof Intl !== 'undefined' && typeof (Intl as { Segmenter?: unknown }).Segmenter === 'function'
          ? new Intl.Segmenter(undefined, { granularity: 'sentence' })
          : null;
    } catch {
      sentenceSegmenter = null;
    }
  }
  return sentenceSegmenter;
};

/** Contiguous partition of `content` on blank-line runs; each break stays with the piece before it. */
const splitParagraphs = (content: string): Span[] => {
  const spans: Span[] = [];
  let cursor = 0;
  PARAGRAPH_BREAK.lastIndex = 0;
  let match = PARAGRAPH_BREAK.exec(content);
  while (match !== null) {
    const end = match.index + match[0].length;
    spans.push({ start: cursor, end });
    cursor = end;
    match = PARAGRAPH_BREAK.exec(content);
  }
  if (cursor < content.length) spans.push({ start: cursor, end: content.length });
  return spans;
};

/** Contiguous sentence partition of one piece via Intl.Segmenter (fallback: the piece itself). */
const splitSentences = (content: string, span: Span): Span[] => {
  const segmenter = getSentenceSegmenter();
  if (segmenter === null) return [span];
  const text = content.slice(span.start, span.end);
  const spans: Span[] = [];
  for (const segment of segmenter.segment(text)) {
    if (segment.segment.length === 0) continue;
    spans.push({ start: span.start + segment.index, end: span.start + segment.index + segment.segment.length });
  }
  return spans.length > 0 ? spans : [span];
};

/** Last whitespace code unit in [from, to), or -1. Cutting before it never splits a word. */
const lastWhitespaceIndex = (content: string, from: number, to: number): number => {
  for (let index = to - 1; index >= from; index -= 1) {
    if (isWhitespace(content[index])) return index;
  }
  return -1;
};

/**
 * Largest end offset for a piece such that `prefix + slice` still fits the hard embedding
 * maximum. Walks code-point boundaries only, so a surrogate pair is never bisected.
 * Returns -1 when even one code point cannot fit.
 */
const largestFittingEnd = (content: string, span: Span, prefix: string, counter: Counter): number => {
  const prefixCharacters = countUnicodeCharacters(prefix);
  const characterRoom = MAX_EMBEDDING_CHARACTERS - prefixCharacters;
  const text = content.slice(span.start, span.end);
  const offsets: number[] = [span.start];
  for (const character of text) {
    if (offsets.length > characterRoom) break;
    offsets.push(offsets[offsets.length - 1] + character.length);
  }
  const fits = (end: number): boolean => {
    const candidate = prefix + content.slice(span.start, end);
    return (
      countTokens(counter, candidate) <= MAX_EMBEDDING_TOKENS &&
      countUnicodeCharacters(candidate) <= MAX_EMBEDDING_CHARACTERS
    );
  };
  let low = 1;
  let high = offsets.length - 1;
  let best = 0;
  while (low <= high) {
    const middle = (low + high) >> 1;
    if (fits(offsets[middle])) {
      best = middle;
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  if (best === 0) return -1;
  const fitted = offsets[best];
  const whitespace = lastWhitespaceIndex(content, span.start, fitted);
  if (whitespace > span.start && (whitespace - span.start) * 2 >= fitted - span.start) return whitespace;
  return fitted;
};

/**
 * Chunk one canonical note. Pure: no eligibility decision (the caller/index job filters
 * own/synced/available/protected/deleted scope before indexing) and no I/O.
 */
export function chunkNote(note: CanonicalNote, counter: Counter): readonly Chunk[] {
  if (note === null || typeof note !== 'object') throw new RagFailure('INVALID_INPUT');
  const { title, content } = note;
  if (typeof title !== 'string' || typeof content !== 'string') throw new RagFailure('INVALID_INPUT');
  if (!isWellFormed(title) || !isWellFormed(content)) throw new RagFailure('INVALID_INPUT');
  if (!isIdentifier(note.ownerId) || !isIdentifier(note.noteId)) throw new RagFailure('INVALID_INPUT');
  if (!isSafeInteger(note.revision) || note.revision < 1) throw new RagFailure('INVALID_INPUT');

  const prefix = documentPrefix(title);
  // The framed title shares the input budget; if it leaves no room for content the note is
  // unindexable. The counter includes the tokenizer's BOS/EOS runtime special tokens.
  if (
    countTokens(counter, prefix) >= MAX_EMBEDDING_TOKENS ||
    countUnicodeCharacters(prefix) >= MAX_EMBEDDING_CHARACTERS
  ) {
    throw new RagFailure('INPUT_TOO_LONG');
  }

  const chunks: Chunk[] = [];

  const measure = (span: Span): Measurement => {
    const candidate = prefix + content.slice(span.start, span.end);
    return { tokens: countTokens(counter, candidate), characters: countUnicodeCharacters(candidate) };
  };
  const withinMax = (measurement: Measurement): boolean =>
    measurement.tokens <= MAX_EMBEDDING_TOKENS && measurement.characters <= MAX_EMBEDDING_CHARACTERS;

  const emit = (span: Span): void => {
    const text = content.slice(span.start, span.end);
    if (!hasNonWhitespace(content, span)) return; // whitespace-only run: nothing text-bearing
    const measurement = measure(span);
    if (!withinMax(measurement)) throw new RagFailure('INPUT_TOO_LONG');
    const ordinal = chunks.length;
    chunks.push({
      ownerId: note.ownerId,
      noteId: note.noteId,
      revision: note.revision,
      sectionId: SECTION_BODY,
      chunkId: `${SECTION_BODY}-${ordinal}`,
      ordinal,
      title,
      startOffset: span.start,
      endOffset: span.end,
      text,
    });
  };

  let current: Span | null = null;
  let currentTokens = 0;

  const flush = (): void => {
    if (current === null) return;
    const span = current;
    current = null;
    currentTokens = 0;
    emit(span);
  };

  const appendPiece = (piece: Span): void => {
    const pieceMeasurement = measure(piece);
    if (current === null) {
      current = piece;
      currentTokens = pieceMeasurement.tokens;
    } else {
      const merged: Span = { start: current.start, end: piece.end };
      const mergedMeasurement = measure(merged);
      if (withinMax(mergedMeasurement)) {
        current = merged;
        currentTokens = mergedMeasurement.tokens;
      } else {
        flush();
        current = piece;
        currentTokens = pieceMeasurement.tokens;
      }
    }
    if (currentTokens >= TARGET_TOKENS) flush();
  };

  const emitPiece = (piece: Span, level: 'paragraph' | 'sentence' | 'codepoint'): void => {
    if (!hasNonWhitespace(content, piece)) return;
    if (withinMax(measure(piece))) {
      appendPiece(piece);
      return;
    }
    if (level === 'paragraph') {
      flush();
      for (const sentence of splitSentences(content, piece)) emitPiece(sentence, 'sentence');
      return;
    }
    if (level === 'sentence') {
      flush();
      let cursor = piece.start;
      while (cursor < piece.end) {
        const cut = largestFittingEnd(content, { start: cursor, end: piece.end }, prefix, counter);
        if (cut <= cursor) throw new RagFailure('INPUT_TOO_LONG');
        emitPiece({ start: cursor, end: cut }, 'codepoint');
        cursor = cut;
      }
      return;
    }
    // A single code point that still does not fit means no chunk can ever fit.
    throw new RagFailure('INPUT_TOO_LONG');
  };

  for (const paragraph of splitParagraphs(content)) emitPiece(paragraph, 'paragraph');
  flush();

  // Defensive lineage check: ascending, non-overlapping, and no non-whitespace code unit dropped.
  let cursor = 0;
  for (const chunk of chunks) {
    if (chunk.startOffset < cursor) throw new RagFailure('INPUT_TOO_LONG');
    for (let index = cursor; index < chunk.startOffset; index += 1) {
      if (!isWhitespace(content[index])) throw new RagFailure('INPUT_TOO_LONG');
    }
    cursor = chunk.endOffset;
  }
  for (let index = cursor; index < content.length; index += 1) {
    if (!isWhitespace(content[index])) throw new RagFailure('INPUT_TOO_LONG');
  }

  return chunks;
}
