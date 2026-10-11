/**
 * Chunking slice tests — contract C02/C03 (paragraph-first, sentence/token fallback, title in
 * budget, UTF-16 offsets, no dropped tail) against the supplied fixtures.
 * Runner: node_modules/.bin/tsx --test amplify/rag/chunking.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import notesFixture from '../../test/fixtures/rag/notes.json';
import contextFixture from '../../test/fixtures/rag/context_cases.json';
import {
  MAX_EMBEDDING_CHARACTERS,
  MAX_EMBEDDING_TOKENS,
  OVERLAP_TOKENS,
  SECTION_BODY,
  TARGET_TOKENS,
  chunkNote,
  countUnicodeCharacters,
  embeddingText,
} from './chunking';
import { RagFailure, type CanonicalNote, type Chunk, type Counter, type ErrorCode } from './types';

const noteFromFixture = (key: string): CanonicalNote => {
  const raw = notesFixture.notes.find((entry) => entry.key === key);
  assert.ok(raw, `fixture note ${key} must exist`);
  return {
    ownerId: raw.ownerId,
    noteId: raw.noteId,
    revision: raw.revision,
    title: raw.title,
    content: raw.content,
    synced: raw.synced,
    protected: raw.protected,
    deleted: raw.deleted,
    available: raw.available,
  };
};

const syntheticNote = (content: string, title = 'Synthetic', overrides: Partial<CanonicalNote> = {}): CanonicalNote => ({
  ownerId: 'actor-a',
  noteId: 'n-synthetic',
  revision: 1,
  title,
  content,
  synced: true,
  protected: false,
  deleted: false,
  available: true,
  ...overrides,
});

/** Injected mock counter (never a real tokenizer): words scaled by a factor. */
const scaledWords = (factor: number): Counter => (text) => {
  const words = text.split(/\s+/).filter((part) => part.length > 0).length;
  return words * factor;
};
const words: Counter = scaledWords(1);
const zero: Counter = () => 0;
const tokensFromCharacters: Counter = (text) => Math.ceil(text.length / 4);

/** Number.isSafeInteger is not a TS type guard; this one narrows for the fixture rows. */
const isCount = (value: unknown): value is number =>
  typeof value === 'number' && Number.isSafeInteger(value);

const failsWith = (code: ErrorCode) => (error: unknown): boolean =>
  error instanceof RagFailure && error.code === code;

const splitsSurrogatePair = (content: string, offset: number): boolean =>
  offset > 0 &&
  offset < content.length &&
  /[\uDC00-\uDFFF]/.test(content[offset]) &&
  /[\uD800-\uDBFF]/.test(content[offset - 1]);

/** Every chunk is an exact slice, ascending, non-overlapping, and inside the hard budget. */
const assertChunkInvariants = (chunks: readonly Chunk[], content: string, counter: Counter): void => {
  let cursor = 0;
  for (const chunk of chunks) {
    assert.equal(chunk.text, content.slice(chunk.startOffset, chunk.endOffset));
    assert.equal(chunk.text.length, chunk.endOffset - chunk.startOffset);
    assert.ok(chunk.startOffset >= cursor, 'chunks must be ascending and non-overlapping');
    assert.ok(!splitsSurrogatePair(content, chunk.startOffset), 'start must not bisect a surrogate pair');
    assert.ok(!splitsSurrogatePair(content, chunk.endOffset), 'end must not bisect a surrogate pair');
    assert.ok(counter(embeddingText(chunk)) <= MAX_EMBEDDING_TOKENS, 'token budget');
    assert.ok(countUnicodeCharacters(embeddingText(chunk)) <= MAX_EMBEDDING_CHARACTERS, 'character budget');
    cursor = chunk.endOffset;
  }
  for (let index = 0; index < content.length; index += 1) {
    if (!/\s/.test(content[index])) {
      assert.ok(
        chunks.some((chunk) => index >= chunk.startOffset && index < chunk.endOffset),
        `non-whitespace code unit ${index} must not be dropped`,
      );
    }
  }
};

test('fixture note a-watch is one paragraph chunk with the exact UTF-16 span', () => {
  const note = noteFromFixture('a-watch');
  const chunks = chunkNote(note, words);
  assert.equal(chunks.length, 1);
  const chunk = chunks[0];
  assert.equal(note.content.length, 125); // wire fixture q01 sourceMap endOffset
  assert.equal(chunk.startOffset, 0);
  assert.equal(chunk.endOffset, 125);
  assert.equal(chunk.text, note.content);
  assert.equal(chunk.title, 'SLGH031');
  assert.equal(chunk.sectionId, SECTION_BODY);
  assert.equal(chunk.chunkId, 'body-0');
  assert.equal(chunk.ordinal, 0);
  assert.equal(chunk.ownerId, 'actor-a');
  assert.equal(chunk.noteId, 'n-watch');
  assert.equal(chunk.revision, 1);
  assert.equal(embeddingText(chunk), `SLGH031\n${note.content}`);
  assert.equal(OVERLAP_TOKENS, 0);
});

test('emoji and Vietnamese content keeps original UTF-16 offsets (no normalization)', () => {
  const note = noteFromFixture('a-unicode');
  const chunks = chunkNote(note, words);
  assert.equal(note.content.length, 68); // 67 code points: the astral emoji is a surrogate pair
  assert.equal(countUnicodeCharacters(note.content), 67);
  assert.equal(chunks.length, 1);
  assert.equal(chunks[0].text, note.content);
  assert.equal(chunks[0].endOffset, 68);
  assert.ok(!splitsSurrogatePair(note.content, chunks[0].endOffset));
});

test('paragraph boundaries are blank-line runs and chunks stay contiguous', () => {
  const content = 'Alpha beta gamma.\n\nDelta epsilon zeta.\n\nEta theta iota.';
  const note = syntheticNote(content);
  const chunks = chunkNote(note, scaledWords(100)); // each paragraph alone reaches the 400 target
  assert.equal(chunks.length, 3);
  assert.deepEqual(
    chunks.map((chunk) => chunk.text),
    ['Alpha beta gamma.\n\n', 'Delta epsilon zeta.\n\n', 'Eta theta iota.'],
  );
  assert.deepEqual(
    chunks.map((chunk) => [chunk.startOffset, chunk.endOffset]),
    [
      [0, 19],
      [19, 40],
      [40, content.length],
    ],
  );
  assert.equal(chunks.map((chunk) => chunk.text).join(''), content); // whitespace preserved inside spans
  assert.deepEqual(chunks.map((chunk) => chunk.ordinal), [0, 1, 2]);
  assert.deepEqual(chunks.map((chunk) => chunk.chunkId), ['body-0', 'body-1', 'body-2']);
  assertChunkInvariants(chunks, content, scaledWords(100));
});

test('adjacent paragraphs are packed up to the target without crossing the maximum', () => {
  const content = 'Alpha beta.\n\nGamma delta.\n\nEpsilon zeta.';
  const note = syntheticNote(content);
  const counter = scaledWords(50);
  const chunks = chunkNote(note, counter);
  assert.equal(chunks.length, 1);
  assert.equal(chunks[0].text, content);
  const tokens = counter(embeddingText(chunks[0]));
  assert.ok(tokens <= TARGET_TOKENS, `packed chunk ${tokens} must stay at the 400 target`);
  assert.ok(tokens <= MAX_EMBEDDING_TOKENS);
});

test('a paragraph over target but within max is kept whole (graceful)', () => {
  // 420 short words stay inside both budgets while exceeding the 400 target.
  const wordsInParagraph = Array.from({ length: 420 }, () => 'aa').join(' ');
  const content = `${wordsInParagraph}.`;
  const note = syntheticNote(content, 'Long');
  const chunks = chunkNote(note, words);
  assert.equal(chunks.length, 1);
  assert.equal(chunks[0].text, content);
  const tokens = words(embeddingText(chunks[0]));
  assert.ok(tokens > TARGET_TOKENS && tokens <= MAX_EMBEDDING_TOKENS, `tokens=${tokens}`);
  assert.ok(countUnicodeCharacters(embeddingText(chunks[0])) <= MAX_EMBEDDING_CHARACTERS);
});

test('oversized paragraph falls back to Intl.Segmenter sentences', () => {
  const sentence = 'Alpha beta gamma delta epsilon. ';
  const content = sentence.repeat(12);
  const note = syntheticNote(content, 'Sentences');
  const counter = scaledWords(20);
  const chunks = chunkNote(note, counter);
  assert.ok(chunks.length > 1, 'oversized paragraph must be split');
  assert.equal(chunks.map((chunk) => chunk.text).join(''), content);
  for (const chunk of chunks) {
    assert.match(chunk.text, /\.\s*$/, 'a chunk must end on a sentence boundary');
    assert.match(chunk.text.trimStart(), /^Alpha/, 'a chunk must start on a sentence boundary');
    assert.equal(chunk.text.trim().split(/\s+/).length % 5, 0, 'whole sentences only');
  }
  assertChunkInvariants(chunks, content, counter);
});

test('an oversized single sentence falls back to code points without cutting words', () => {
  const wordsInSentence = [
    'Alpha',
    ...Array.from({ length: 299 }, (_value, index) => `w${index}`),
  ].join(' ');
  const content = `${wordsInSentence}.`;
  const note = syntheticNote(content, 'OneSentence');
  const counter = scaledWords(20);
  const chunks = chunkNote(note, counter);
  assert.ok(chunks.length > 1, 'oversized sentence must be split');
  assert.equal(chunks.map((chunk) => chunk.text).join(''), content);
  for (const chunk of chunks) {
    assert.match(chunk.text.trim(), /^[A-Za-z0-9]+( [A-Za-z0-9]+)*\.?$/, 'no partial word may survive');
    assert.ok(counter(embeddingText(chunk)) <= MAX_EMBEDDING_TOKENS);
  }
  assertChunkInvariants(chunks, content, counter);
});

test('the 2048-character ceiling splits astral text without bisecting surrogate pairs', () => {
  const content = '😀'.repeat(3000);
  const note = syntheticNote(content, '');
  const chunks = chunkNote(note, zero);
  assert.equal(chunks.length, 2);
  assert.equal(chunks[0].endOffset, 4094); // 2047 code points per chunk + the title newline
  assert.equal(chunks.map((chunk) => chunk.text).join(''), content);
  assert.equal(countUnicodeCharacters(embeddingText(chunks[0])), 2048);
  assert.equal(countUnicodeCharacters(embeddingText(chunks[1])), 954);
  for (const chunk of chunks) {
    assert.ok(countUnicodeCharacters(embeddingText(chunk)) <= MAX_EMBEDDING_CHARACTERS);
    assert.ok(!splitsSurrogatePair(content, chunk.startOffset));
    assert.ok(!splitsSurrogatePair(content, chunk.endOffset));
  }
  assertChunkInvariants(chunks, content, zero);
});

test('whitespace-only gaps between chunks are not emitted and never hide content', () => {
  const first = Array.from({ length: 420 }, () => 'aa').join(' ');
  const second = Array.from({ length: 420 }, () => 'bb').join(' ');
  const content = `${first}.\n\n\n   \n\n${second}.`;
  const note = syntheticNote(content, 'Gap');
  const chunks = chunkNote(note, words);
  assert.equal(chunks.length, 2, 'each oversized paragraph becomes its own chunk');
  assert.ok(chunks[1].startOffset > chunks[0].endOffset, 'the whitespace-only run is skipped');
  assert.equal(chunks[0].text, content.slice(chunks[0].startOffset, chunks[0].endOffset));
  assert.equal(chunks[1].text, content.slice(chunks[1].startOffset, chunks[1].endOffset));
  assert.ok(chunks[0].text.startsWith('aa'));
  assert.ok(chunks[1].text.startsWith('bb'));
  assertChunkInvariants(chunks, content, words);
});

test('a title that leaves no room for content fails with INPUT_TOO_LONG', () => {
  const note = syntheticNote('Alpha beta.', 'x'.repeat(3000));
  assert.throws(() => chunkNote(note, zero), failsWith('INPUT_TOO_LONG'));
  // prefix = title + "\n": 2047 characters leaves exactly one code point of room.
  const boundary = chunkNote(syntheticNote('A', 'x'.repeat(2046)), zero);
  assert.equal(boundary.length, 1);
  assert.equal(boundary[0].text, 'A');
  assert.throws(() => chunkNote(syntheticNote('A', 'x'.repeat(2047)), zero), failsWith('INPUT_TOO_LONG'));
  // A title whose own tokens already consume the 512-token input budget is equally impossible.
  assert.throws(() => chunkNote(syntheticNote('A', 'x '.repeat(600)), words), failsWith('INPUT_TOO_LONG'));
});

test('empty or whitespace-only content yields no chunks', () => {
  assert.deepEqual(chunkNote(syntheticNote(''), words), []);
  assert.deepEqual(chunkNote(syntheticNote('   \n\n\t  '), words), []);
});

test('an invalid injected counter fails closed with EVIDENCE_VALIDATION_UNAVAILABLE', () => {
  const note = noteFromFixture('a-watch');
  const invalid: Counter[] = [
    () => Number.NaN,
    () => Number.POSITIVE_INFINITY,
    () => 1.5,
    () => -1,
    (() => true) as unknown as Counter,
    () => {
      throw new Error('counter exploded');
    },
  ];
  for (const counter of invalid) {
    assert.throws(() => chunkNote(note, counter), failsWith('EVIDENCE_VALIDATION_UNAVAILABLE'));
  }
  assert.throws(
    () => chunkNote(note, undefined as unknown as Counter),
    failsWith('EVIDENCE_VALIDATION_UNAVAILABLE'),
  );
});

test('embedding budget fixture: 512 tokens/2048 characters is the inclusive limit', () => {
  const maxCharacters = MAX_EMBEDDING_CHARACTERS;
  for (const budgetCase of contextFixture.budgetCases) {
    if (budgetCase.kind !== 'embedding') continue;
    const { tokens, characters } = budgetCase;
    const valid =
      isCount(tokens) &&
      tokens >= 0 &&
      tokens <= MAX_EMBEDDING_TOKENS &&
      isCount(characters) &&
      characters >= 0 &&
      characters <= maxCharacters;
    assert.equal(valid, budgetCase.valid, `budget fixture ${budgetCase.id}`);
  }

  // Exactly 2048 characters and 512 estimated tokens is accepted as a single chunk ...
  const atLimit = 'a'.repeat(2047); // + the title newline = 2048
  const chunks = chunkNote(syntheticNote(atLimit, ''), tokensFromCharacters);
  assert.equal(chunks.length, 1);
  assert.equal(countUnicodeCharacters(embeddingText(chunks[0])), 2048);
  assert.equal(tokensFromCharacters(embeddingText(chunks[0])), 512);

  // ... while one more character (or one more token) is split, never emitted over budget.
  for (const content of ['a'.repeat(2048), 'a'.repeat(2051)]) {
    const oversized = chunkNote(syntheticNote(content, ''), tokensFromCharacters);
    assert.ok(oversized.length > 1);
    assertChunkInvariants(oversized, content, tokensFromCharacters);
  }
});
