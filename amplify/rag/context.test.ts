/**
 * Context slice tests — contracts C10–C15 (expansion +/-1 non-recursive, same note/revision/
 * section, canonical re-validation, span dedupe/merge, conflicting text preserved, 6000-token
 * evidence budget with expansion-first removal, immutable bundle) and the supplied
 * context_cases.json / query_cases.json fixtures.
 * Runner: node_modules/.bin/tsx --test amplify/rag/context.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import contextFixture from '../../test/fixtures/rag/context_cases.json';
import queryFixture from '../../test/fixtures/rag/query_cases.json';
import notesFixture from '../../test/fixtures/rag/notes.json';
import { chunkNote } from './chunking';
import { EVIDENCE_MAX_TOKENS, buildEvidence } from './context';
import {
  RagFailure,
  type CanonicalNote,
  type Chunk,
  type Counter,
  type ErrorCode,
  type Source,
} from './types';

const words: Counter = (text) => text.split(/\s+/).filter((part) => part.length > 0).length;
/** Mock evidence counter: a fixed cost per serialized source label. */
const tokensPerSource = (perSource: number): Counter => (text) => {
  const labels = text.match(/\[S\d+\]/g);
  return labels === null ? 0 : labels.length * perSource;
};

/** Fixture row -> CanonicalNote (keeps the test honest about which fields matter). */
const toNote = (raw: (typeof notesFixture.notes)[number]): CanonicalNote => ({
  ownerId: raw.ownerId,
  noteId: raw.noteId,
  revision: raw.revision,
  title: raw.title,
  content: raw.content,
  synced: raw.synced,
  protected: raw.protected,
  deleted: raw.deleted,
  available: raw.available,
});
const allFixtureNotes = (): CanonicalNote[] => notesFixture.notes.map(toNote);

const noteFromFixture = (key: string): CanonicalNote => {
  const raw = notesFixture.notes.find((entry) => entry.key === key);
  assert.ok(raw, `fixture note ${key} must exist`);
  return toNote(raw);
};

const chunkOf = (key: string): Chunk => {
  const chunks = chunkNote(noteFromFixture(key), words);
  assert.equal(chunks.length, 1);
  return chunks[0];
};

type SpanInput = Readonly<{ noteId: string; revision: number; startOffset: number; endOffset: number }>;

const spanKey = (span: SpanInput): string =>
  `${span.noteId}@r${span.revision}:${span.startOffset}-${span.endOffset}`;

/** Canonical notes for the span fixtures: n-watch (rev 1 and rev 2) plus n-conflict. */
const spanFixtureNotes = (): CanonicalNote[] => [
  { ownerId: 'actor-a', noteId: 'n-watch', revision: 1, title: 'Watch', content: 'x'.repeat(60), synced: true, protected: false, deleted: false, available: true },
  { ownerId: 'actor-a', noteId: 'n-watch', revision: 2, title: 'Watch', content: 'y'.repeat(60), synced: true, protected: false, deleted: false, available: true },
  { ownerId: 'actor-a', noteId: 'n-conflict', revision: 1, title: 'Conflict', content: 'z'.repeat(60), synced: true, protected: false, deleted: false, available: true },
];

const spanFixtureChunk = (span: SpanInput, ordinal: number): Chunk => {
  const note = spanFixtureNotes().find(
    (entry) => entry.noteId === span.noteId && entry.revision === span.revision,
  );
  assert.ok(note, `span fixture note ${span.noteId}@${span.revision}`);
  return {
    ownerId: 'actor-a',
    noteId: note.noteId,
    revision: note.revision,
    sectionId: 'body', // the canonical note model in this slice is text-only; sectionId is body
    chunkId: `body-${ordinal}`,
    ordinal,
    title: note.title,
    startOffset: span.startOffset,
    endOffset: span.endOffset,
    text: note.content.slice(span.startOffset, span.endOffset),
  };
};

const manualNote = (noteId: string, content: string, overrides: Partial<CanonicalNote> = {}): CanonicalNote => ({
  ownerId: 'actor-a',
  noteId,
  revision: 1,
  title: `Title ${noteId}`,
  content,
  synced: true,
  protected: false,
  deleted: false,
  available: true,
  ...overrides,
});

const manualChunk = (note: CanonicalNote, startOffset: number, endOffset: number, ordinal: number): Chunk => ({
  ownerId: note.ownerId,
  noteId: note.noteId,
  revision: note.revision,
  sectionId: 'body',
  chunkId: `body-${ordinal}`,
  ordinal,
  title: note.title,
  startOffset,
  endOffset,
  text: note.content.slice(startOffset, endOffset),
});

/** Number.isSafeInteger is not a TS type guard; this one narrows for the fixture rows. */
const isCount = (value: unknown): value is number =>
  typeof value === 'number' && Number.isSafeInteger(value);

const failsWith = (code: ErrorCode) => (error: unknown): boolean =>
  error instanceof RagFailure && error.code === code;

const sentence = (label: string, index: number): string => `Cau ${label} so ${index} duoc viet o day.`;
const paragraph = (label: string, count: number): string =>
  Array.from({ length: count }, (_value, index) => sentence(label, index)).join(' ');
/** Two paragraphs per note so each note has a chunk 0 and a chunk 1 that are +/-1 neighbors. */
const twoChunkNote = (noteId: string): CanonicalNote => {
  const first = paragraph(noteId, 3);
  return manualNote(noteId, `${first}\n\n${paragraph(noteId, 3)}`);
};
const twoChunksOf = (note: CanonicalNote): [Chunk, Chunk] => {
  const separator = note.content.indexOf('\n\n') + 2;
  return [manualChunk(note, 0, separator, 0), manualChunk(note, separator, note.content.length, 1)];
};
/** Same two chunks but with a whitespace gap, so they stay two separate passages. */
const gappedChunksOf = (note: CanonicalNote): [Chunk, Chunk] => {
  const separator = note.content.indexOf('\n\n');
  return [
    manualChunk(note, 0, separator - 1, 0),
    manualChunk(note, separator + 2, note.content.length, 1),
  ];
};

test('supplied span fixtures merge exactly as the oracle expects (C10–C12)', () => {
  for (const spanCase of contextFixture.cases) {
    const anchors = spanCase.spans.map((span, index) => spanFixtureChunk(span, index));
    const evidence = buildEvidence(anchors, [], spanFixtureNotes(), words);
    // The oracle fixes the merged span set; label order follows MMR anchor priority (q05 keeps
    // S1 on the highest-priority anchor), so compare the transformed spans as a set.
    assert.deepEqual(
      evidence.sources.map((source) => spanKey(source)).sort(),
      spanCase.expected.map((span) => spanKey(span)).sort(),
      `fixture ${spanCase.id}`,
    );
    for (const source of evidence.sources) {
      const note = spanFixtureNotes().find(
        (entry) => entry.noteId === source.noteId && entry.revision === source.revision,
      );
      assert.ok(note);
      assert.equal(source.quote, note.content.slice(source.startOffset, source.endOffset));
    }
  }
});

test('overlapping, duplicate and contiguous same-source spans merge once', () => {
  const note = manualNote('n-merge', 'C1C2C3C4');
  const chunks = [0, 1, 2, 3].map((ordinal) => manualChunk(note, ordinal * 2, ordinal * 2 + 2, ordinal));
  // Anchors C2 and C3; the caller also fetched C1..C4 (anchors included, so they dedupe by identity).
  const anchors = [chunks[1], chunks[2]];
  const neighbors = [chunks[0], chunks[1], chunks[2], chunks[3]];
  const evidence = buildEvidence(anchors, neighbors, [note], words);
  assert.equal(evidence.sources.length, 1, 'C1..C4 become one contiguous source once');
  assert.equal(evidence.sources[0].sourceId, 'S1');
  assert.equal(evidence.sources[0].startOffset, 0);
  assert.equal(evidence.sources[0].endOffset, 8);
  assert.equal(evidence.sources[0].quote, 'C1C2C3C4');
  assert.equal(evidence.text, `[S1] Title n-merge\nC1C2C3C4`);
});

test('a non-contiguous window of the same source stays two distinct sources', () => {
  const note = manualNote('n-gap', 'C1C2C3C4');
  const chunks = [0, 1, 2, 3].map((ordinal) => manualChunk(note, ordinal * 2, ordinal * 2 + 2, ordinal));
  const evidence = buildEvidence([chunks[0], chunks[3]], [], [note], words);
  assert.equal(evidence.sources.length, 2);
  assert.deepEqual(
    evidence.sources.map((source) => spanKey(source)),
    ['n-gap@r1:0-2', 'n-gap@r1:6-8'],
  );
  assert.equal(evidence.text, `[S1] Title n-gap\nC1\n\n[S2] Title n-gap\nC4`);
});

test('conflicting numbers from different sources are both preserved (C13)', () => {
  const watch = chunkOf('a-watch');
  const conflict = chunkOf('a-watch-conflict');
  const notes = [noteFromFixture('a-watch'), noteFromFixture('a-watch-conflict')];
  const evidence = buildEvidence([watch, conflict], [], notes, words);
  assert.equal(evidence.sources.length, 2);
  assert.deepEqual(
    evidence.sources.map((source) => source.sourceId),
    ['S1', 'S2'],
  );
  assert.ok(evidence.sources[0].quote.includes('80 giờ'));
  assert.ok(evidence.sources[1].quote.includes('100 giờ'));
  assert.ok(evidence.text.includes('80 giờ') && evidence.text.includes('100 giờ'));
  assert.equal(evidence.sources[0].quote, noteFromFixture('a-watch').content);
  assert.equal(evidence.sources[1].quote, noteFromFixture('a-watch-conflict').content);
});

test('the q01 wire fixture source map matches the assembled evidence', () => {
  const sourceMap = queryFixture.cases.find((entry) => entry.id === 'q01')?.sourceMap?.S1;
  assert.ok(sourceMap, 'q01 S1 source map');
  const evidence = buildEvidence([chunkOf('a-watch')], [], [noteFromFixture('a-watch')], words);
  assert.equal(evidence.sources.length, 1);
  const source = evidence.sources[0];
  assert.equal(source.sourceId, 'S1');
  assert.equal(source.noteId, sourceMap.noteId);
  assert.equal(source.revision, sourceMap.revision);
  assert.equal(source.startOffset, sourceMap.startOffset);
  assert.equal(source.endOffset, sourceMap.endOffset);
  assert.equal(source.quote, sourceMap.quote);
  assert.equal(evidence.text, `[S1] SLGH031\n${sourceMap.quote}`);
});

test('a wrong revision fails with SOURCE_CHANGED, never with stale text', () => {
  const note = noteFromFixture('a-watch');
  const stale: Chunk = { ...chunkOf('a-watch'), revision: 2, chunkId: 'body-0' };
  assert.throws(() => buildEvidence([stale], [], [note], words), failsWith('SOURCE_CHANGED'));
  // The same check applies to an expansion neighbor.
  assert.throws(
    () => buildEvidence([chunkOf('a-watch')], [{ ...stale, ordinal: 1 }], [note], words),
    failsWith('SOURCE_CHANGED'),
  );
});

test('a foreign chunk fails with SCOPE_DENIED (existence stays hidden)', () => {
  const own = chunkOf('a-watch');
  const foreign = chunkOf('b-watch');
  // Even when the caller's note list contains the foreign note, the owner of the anchor set rules.
  assert.throws(
    () => buildEvidence([own], [{ ...foreign, ordinal: 1 }], allFixtureNotes(), words),
    failsWith('SCOPE_DENIED'),
  );
  // With an actor-scoped canonical note set a foreign anchor cannot even be resolved.
  assert.throws(
    () => buildEvidence([foreign], [], [noteFromFixture('a-watch')], words),
    failsWith('SCOPE_DENIED'),
  );
  // Mixed-owner anchors are rejected before any note is admitted.
  assert.throws(
    () => buildEvidence([own, foreign], [], allFixtureNotes(), words),
    failsWith('SCOPE_DENIED'),
  );
});

test('protected, deleted, unsynced and unavailable notes fail with SOURCE_CHANGED', () => {
  const anchor = chunkOf('a-watch');
  const notes = allFixtureNotes();
  for (const key of ['a-protected', 'a-deleted', 'a-local']) {
    const neighbor = chunkOf(key);
    assert.throws(
      () => buildEvidence([anchor], [{ ...neighbor, ordinal: 1 }], notes, words),
      failsWith('SOURCE_CHANGED'),
      `neighbor ${key}`,
    );
    assert.throws(
      () => buildEvidence([neighbor], [], notes, words),
      failsWith('SOURCE_CHANGED'),
      `anchor ${key}`,
    );
  }
  const unavailable = noteFromFixture('a-watch');
  assert.throws(
    () => buildEvidence([anchor], [], [{ ...unavailable, available: false }], words),
    failsWith('SOURCE_CHANGED'),
  );
});

test('a shared incoming copy is out of scope', () => {
  const shared: CanonicalNote = { ...noteFromFixture('a-watch'), incomingShared: true };
  assert.throws(() => buildEvidence([chunkOf('a-watch')], [], [shared], words), failsWith('SCOPE_DENIED'));
});

test('expansion enforces +/-1 ordinals, same note/revision/section and no recursion', () => {
  const note = twoChunkNote('n-chain');
  const [first, second] = twoChunksOf(note);
  // chunk1 anchor with chunk0 expansion: valid and merged into one passage.
  const ok = buildEvidence([second], [first], [note], words);
  assert.equal(ok.sources.length, 1);
  assert.equal(ok.sources[0].startOffset, 0);
  assert.equal(ok.sources[0].endOffset, note.content.length);

  const third = manualChunk(note, 0, 5, 2); // ordinal 2 is not +/-1 of anchor ordinal 0
  assert.throws(() => buildEvidence([first], [third], [note], words), failsWith('INVALID_INPUT'));

  const otherSection: Chunk = { ...second, sectionId: 'appendix' };
  assert.throws(() => buildEvidence([first], [otherSection], [note], words), failsWith('SOURCE_CHANGED'));

  const otherRevision: Chunk = { ...second, revision: 2 };
  assert.throws(
    () => buildEvidence([first], [otherRevision], [note, { ...note, revision: 2 }], words),
    failsWith('INVALID_INPUT'),
    'a neighbor from another revision is not an immediate neighbor',
  );
});

test('spans that no longer match the canonical content fail with SOURCE_CHANGED', () => {
  const note = noteFromFixture('a-watch');
  const chunk = chunkOf('a-watch');
  assert.throws(
    () => buildEvidence([{ ...chunk, text: 'rewritten text', endOffset: 14 }], [], [note], words),
    failsWith('SOURCE_CHANGED'),
  );
  assert.throws(
    () =>
      buildEvidence(
        [{ ...chunk, text: `${note.content}x`, endOffset: note.content.length + 1 }],
        [],
        [note],
        words,
      ),
    failsWith('SOURCE_CHANGED'),
    'a span past the canonical content is a changed source',
  );
  assert.throws(() => buildEvidence([{ ...chunk, title: 'Renamed' }], [], [note], words), failsWith('SOURCE_CHANGED'));
});

test('evidence removes expansions first, then the lowest anchor, rebuilding labels', () => {
  const noteA = twoChunkNote('n-a');
  const noteB = twoChunkNote('n-b');
  const [a0, a1] = gappedChunksOf(noteA);
  const [b0, b1] = gappedChunksOf(noteB);
  const counter = tokensPerSource(2000); // 3 sources fit 6000, 4 do not
  const evidence = buildEvidence([a1, b1], [a0, b0], [noteA, noteB], counter);
  assert.ok(counter(evidence.text) <= EVIDENCE_MAX_TOKENS);
  // Passages are ordered by best contained anchor, so an expansion follows its own anchor.
  assert.deepEqual(evidence.sources.map((source) => spanKey(source)), [
    spanKey(a1),
    spanKey(a0),
    spanKey(b1),
  ]);
  assert.deepEqual(
    evidence.sources.map((source) => source.sourceId),
    ['S1', 'S2', 'S3'],
    'anchors survive, the low-priority expansion is dropped first and labels are rebuilt',
  );

  // Four anchors: 8000 > 6000, so the lowest-priority anchor goes and labels are rebuilt.
  const noteC = twoChunkNote('n-c');
  const noteD = twoChunkNote('n-d');
  const c1 = twoChunksOf(noteC)[1];
  const d1 = twoChunksOf(noteD)[1];
  const anchorDropped = buildEvidence([a1, b1, c1, d1], [], [noteA, noteB, noteC, noteD], counter);
  assert.equal(counter(anchorDropped.text), EVIDENCE_MAX_TOKENS);
  assert.deepEqual(
    anchorDropped.sources.map((source) => source.noteId),
    ['n-a', 'n-b', 'n-c'],
  );
  assert.deepEqual(
    anchorDropped.sources.map((source) => source.sourceId),
    ['S1', 'S2', 'S3'],
  );

  // Over budget even alone: the evidence is allowed to become empty.
  const empty = buildEvidence([a1], [], [noteA], tokensPerSource(7000));
  assert.deepEqual(empty.sources, []);
  assert.equal(empty.text, '');
  assert.ok(Object.isFrozen(empty));

  // A counter that scores even an empty serialization over budget is not trustworthy.
  const untrustworthy: Counter = () => EVIDENCE_MAX_TOKENS + 1;
  assert.throws(
    () => buildEvidence([a1], [a0], [noteA], untrustworthy),
    failsWith('EVIDENCE_VALIDATION_UNAVAILABLE'),
  );
});

test('quotes are never cut mid-sentence and stay inside the token budget', () => {
  const note = twoChunkNote('n-cut');
  const [first, second] = twoChunksOf(note);
  const evidence = buildEvidence([second], [first], [note], tokensPerSource(2000));
  assert.equal(evidence.sources.length, 1);
  assert.equal(evidence.sources[0].quote, note.content);
  assert.match(evidence.sources[0].quote, /\.$/);
});

test('passage priority follows anchors, with expansions absorbed by their parent', () => {
  const noteA = twoChunkNote('n-p1');
  const noteB = twoChunkNote('n-p2');
  const [a0, a1] = twoChunksOf(noteA);
  const [b0, b1] = twoChunksOf(noteB);
  const evidence = buildEvidence([a1, b1], [b0, a0], [noteA, noteB], tokensPerSource(1));
  assert.deepEqual(
    evidence.sources.map((source) => source.noteId),
    ['n-p1', 'n-p2'],
    'anchors first in anchor order',
  );
  assert.deepEqual(
    evidence.sources.map((source) => source.startOffset),
    [0, 0],
  );
});

test('the evidence budget fixture and counter port fail closed', () => {
  for (const budgetCase of contextFixture.budgetCases) {
    if (budgetCase.kind !== 'evidence') continue;
    const { tokens } = budgetCase;
    const valid = isCount(tokens) && tokens >= 0 && tokens <= EVIDENCE_MAX_TOKENS;
    assert.equal(valid, budgetCase.valid, `budget fixture ${budgetCase.id}`);
  }
  assert.equal(EVIDENCE_MAX_TOKENS, 6000);
  const note = noteFromFixture('a-watch');
  const chunk = chunkOf('a-watch');
  const invalid: Counter[] = [
    () => 1.5,
    () => Number.NaN,
    () => Number.POSITIVE_INFINITY,
    () => -1,
    (() => true) as unknown as Counter,
  ];
  for (const counter of invalid) {
    assert.throws(() => buildEvidence([chunk], [], [note], counter), failsWith('EVIDENCE_VALIDATION_UNAVAILABLE'));
  }
});

test('an empty anchor set yields empty evidence and the bundle is frozen', () => {
  const empty = buildEvidence([], [chunkOf('a-watch')], [noteFromFixture('a-watch')], words);
  assert.deepEqual(empty.sources, []);
  assert.equal(empty.text, '');
  assert.ok(Object.isFrozen(empty));

  const evidence = buildEvidence([chunkOf('a-watch')], [], [noteFromFixture('a-watch')], words);
  assert.ok(Object.isFrozen(evidence));
  assert.ok(Object.isFrozen(evidence.sources));
  assert.ok(Object.isFrozen(evidence.sources[0]));
  const sourcesBefore = [...evidence.sources];
  try {
    (evidence as { text: string }).text = 'mutated';
    (evidence.sources as unknown as Source[]).push(sourcesBefore[0]);
  } catch {
    // strict mode throws instead of failing silently; either way the bundle must not change.
  }
  assert.equal(evidence.text, `[S1] SLGH031\n${noteFromFixture('a-watch').content}`);
  assert.deepEqual([...evidence.sources], sourcesBefore);
  assert.equal(evidence.sources.length, 1);
});
