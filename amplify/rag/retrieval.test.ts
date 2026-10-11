/**
 * Retrieval slice tests — contracts C06/C07 (RRF constant 60, equal weights, rank from 1,
 * one contribution per branch, union <= 40), C08 (MMR lambda 0.7, <= 8 anchors), C09 (vectors
 * reused from getVectors, keyword-only candidates included) and the supplied ranking fixtures.
 * Runner: node_modules/.bin/tsx --test amplify/rag/retrieval.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import rankingFixture from '../../test/fixtures/rag/ranking_cases.json';
import notesFixture from '../../test/fixtures/rag/notes.json';
import { chunkNote } from './chunking';
import { bm25 } from './keyword';
import {
  EMBEDDING_DIMENSIONS,
  MMR_LAMBDA,
  MMR_MAX_ANCHORS,
  RRF_CONSTANT,
  RRF_MAX_CANDIDATES,
  mmr,
  rrf,
  validateVector,
} from './retrieval';
import {
  RagFailure,
  sourceKey,
  type Candidate,
  type CanonicalNote,
  type Chunk,
  type Counter,
  type ErrorCode,
  type Ranked,
} from './types';

const words: Counter = (text) => text.split(/\s+/).filter((part) => part.length > 0).length;

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

const chunkOf = (key: string): Chunk => {
  const chunks = chunkNote(noteFromFixture(key), words);
  assert.equal(chunks.length, 1);
  return chunks[0];
};

const LABELS = ['A', 'B', 'C', 'D'] as const;
const LABEL_CONTENT = 'ABCD';
const labelChunks = new Map<string, Chunk>(
  LABELS.map((label, index) => [
    label,
    {
      ownerId: 'actor-a',
      noteId: 'n-ranking',
      revision: 1,
      sectionId: 'body',
      chunkId: label,
      ordinal: index,
      title: 'Ranking',
      startOffset: index,
      endOffset: index + 1,
      text: LABEL_CONTENT.slice(index, index + 1),
    },
  ]),
);
const chunkByLabel = (label: string): Chunk => {
  const chunk = labelChunks.get(label);
  assert.ok(chunk, `ranking fixture label ${label}`);
  return chunk;
};
const rankedFrom = (labels: readonly string[]): Ranked[] =>
  labels.map((label, index) => ({ chunk: chunkByLabel(label), rank: index + 1 }));

const basisVector = (index: number): number[] =>
  Array.from({ length: EMBEDDING_DIMENSIONS }, (_value, position) => (position === index ? 1 : 0));
const mixingVector = (primary: number, secondary: number): number[] =>
  Array.from({ length: EMBEDDING_DIMENSIONS }, (_value, position) => {
    if (position === primary) return 0.8;
    if (position === secondary) return 0.6;
    return 0;
  });

const asCandidate = (chunk: Chunk, score: number): Candidate => ({ chunk, score });

const vectorsFor = (entries: readonly (readonly [Chunk, readonly number[]])[]): ReadonlyMap<string, readonly number[]> =>
  new Map(entries.map(([chunk, vector]) => [sourceKey(chunk), vector]));

const failsWith = (code: ErrorCode) => (error: unknown): boolean =>
  error instanceof RagFailure && error.code === code;

test('RRF reproduces every supplied ranking fixture', () => {
  for (const rankingCase of rankingFixture.cases) {
    const [vectorRanking, keywordRanking] = rankingCase.rankings;
    const fused = rrf(rankedFrom(vectorRanking), rankedFrom(keywordRanking));
    assert.deepEqual(
      fused.map((candidate) => candidate.chunk.chunkId),
      rankingCase.expected,
      `fixture ${rankingCase.id}`,
    );
  }
});

test('RRF fixture rank-01 is the B-A-D-C order with the constant-60 arithmetic', () => {
  const fixture = rankingFixture.cases.find((entry) => entry.id === 'rank-01');
  assert.ok(fixture);
  const fused = rrf(
    rankedFrom(fixture.rankings[0]),
    rankedFrom(fixture.rankings[1]),
  );
  assert.deepEqual(fused.map((candidate) => candidate.chunk.chunkId), ['B', 'A', 'D', 'C']);
  const byLabel = new Map(fused.map((candidate) => [candidate.chunk.chunkId, candidate]));
  assert.equal(byLabel.get('A')?.score, 1 / (RRF_CONSTANT + 1) + 1 / (RRF_CONSTANT + 3));
  assert.equal(byLabel.get('B')?.score, 1 / (RRF_CONSTANT + 2) + 1 / (RRF_CONSTANT + 1));
  assert.equal(byLabel.get('D')?.score, 1 / (RRF_CONSTANT + 2));
  // Provenance of both branches is retained on the fused candidate.
  assert.deepEqual([byLabel.get('B')?.vectorRank, byLabel.get('B')?.bm25Rank], [2, 1]);
  assert.deepEqual([byLabel.get('C')?.vectorRank, byLabel.get('C')?.bm25Rank], [3, undefined]);
});

test('RRF keeps one contribution per source per branch and the best original rank', () => {
  const duplicate = rankingFixture.cases.find((entry) => entry.id === 'rank-03');
  assert.ok(duplicate);
  const fused = rrf(rankedFrom(duplicate.rankings[0]), rankedFrom(duplicate.rankings[1]));
  assert.deepEqual(fused.map((candidate) => candidate.chunk.chunkId), duplicate.expected);
  const labelA = fused.find((candidate) => candidate.chunk.chunkId === 'A');
  assert.ok(labelA);
  assert.equal(labelA.vectorRank, 1, 'the duplicated rank-2 entry does not add a second contribution');
  assert.equal(labelA.bm25Rank, 2);
  assert.equal(labelA.score, 1 / (RRF_CONSTANT + 1) + 1 / (RRF_CONSTANT + 2));
});

test('RRF merges only the exact source identity: revision is part of it', () => {
  const base = chunkOf('a-watch');
  const otherRevision: Chunk = { ...base, revision: 2, chunkId: 'body-0' };
  const fused = rrf(
    [{ chunk: base, rank: 1 }],
    [{ chunk: otherRevision, rank: 1 }],
  );
  assert.equal(fused.length, 2, 'rev1 and rev2 are distinct sources, never merged');
  assert.deepEqual(
    fused.map((candidate) => candidate.chunk.revision).sort(),
    [1, 2],
  );
});

test('RRF rejects a union larger than the 40-candidate cap', () => {
  const make = (prefix: string, count: number): Ranked[] =>
    Array.from({ length: count }, (_value, index) => ({
      chunk: {
        ownerId: 'actor-a',
        noteId: `n-${prefix}-${index}`,
        revision: 1,
        sectionId: 'body',
        chunkId: 'body-0',
        ordinal: 0,
        title: 'T',
        startOffset: 0,
        endOffset: 1,
        text: 'x',
      },
      rank: index + 1,
    }));
  assert.equal(RRF_MAX_CANDIDATES, 40);
  assert.equal(rrf(make('v', 20), make('k', 20)).length, 40);
  assert.equal(rrf(make('v', 20), make('k', 19)).length, 39);
  assert.throws(() => rrf(make('v', 21), make('k', 20)), failsWith('INVALID_INPUT'));
});

test('RRF rejects malformed ranks and ambiguous duplicates', () => {
  const valid: Ranked = { chunk: chunkByLabel('A'), rank: 1 };
  const bad = [0, -1, 1.5, Number.NaN, Number.POSITIVE_INFINITY, '1', null, undefined];
  for (const rank of bad) {
    assert.throws(
      () => rrf([{ ...valid, rank: rank as number }], []),
      failsWith('INVALID_INPUT'),
      `rank ${String(rank)}`,
    );
  }
  assert.throws(
    () => rrf([], [null as unknown as Ranked]),
    failsWith('INVALID_INPUT'),
  );
  // Two different sources cannot share one rank inside a branch.
  assert.throws(
    () => rrf([{ chunk: chunkByLabel('A'), rank: 1 }, { chunk: chunkByLabel('B'), rank: 1 }], []),
    failsWith('INVALID_INPUT'),
  );
});

test('RRF rejects the same identity carrying inconsistent spans instead of corrupting silently', () => {
  const base = chunkByLabel('A');
  const inconsistent: Chunk = { ...base, text: 'Z' };
  assert.throws(() => rrf([{ chunk: base, rank: 1 }], [{ chunk: inconsistent, rank: 1 }]), failsWith('SOURCE_CHANGED'));
  assert.throws(
    () =>
      rrf(
        [
          { chunk: base, rank: 1 },
          { chunk: { ...base, endOffset: 2, text: 'AB' }, rank: 2 },
        ],
        [],
      ),
    failsWith('SOURCE_CHANGED'),
  );
});

test('validateVector accepts only finite non-zero 1024-dimensional vectors', () => {
  assert.equal(EMBEDDING_DIMENSIONS, 1024);
  assert.doesNotThrow(() => validateVector(basisVector(0)));
  assert.doesNotThrow(() => validateVector(Array.from({ length: 1024 }, () => -0.5)));
  for (const length of [0, 1, 1023, 1025]) {
    assert.throws(() => validateVector(Array.from({ length }, () => 1)), failsWith('INDEX_NOT_READY'), `length ${length}`);
  }
  const withNaN = basisVector(0);
  (withNaN as number[])[5] = Number.NaN;
  assert.throws(() => validateVector(withNaN), failsWith('INDEX_NOT_READY'));
  const withInfinity = basisVector(0);
  (withInfinity as number[])[5] = Number.POSITIVE_INFINITY;
  assert.throws(() => validateVector(withInfinity), failsWith('INDEX_NOT_READY'));
  const withString = basisVector(0);
  (withString as unknown as unknown[])[5] = '1';
  assert.throws(() => validateVector(withString as unknown as number[]), failsWith('INDEX_NOT_READY'));
  assert.throws(() => validateVector(Array.from({ length: 1024 }, () => 0)), failsWith('INDEX_NOT_READY'));
  assert.throws(() => validateVector(null as unknown as number[]), failsWith('INDEX_NOT_READY'));
});

test('MMR seeds by relevance and then prefers diversity (lambda 0.7)', () => {
  const duplicate = chunkByLabel('A');
  const diverse = chunkByLabel('B');
  const middle = chunkByLabel('C');
  const candidates = [asCandidate(duplicate, 1), asCandidate(middle, 0.9), asCandidate(diverse, 0.5)];
  const vectors = vectorsFor([
    [duplicate, basisVector(0)],
    [middle, basisVector(0)], // identical to the seed: fully redundant
    [diverse, basisVector(1)], // orthogonal: maximum diversity
  ]);
  const anchors = mmr(candidates, vectors);
  assert.deepEqual(anchors.map((chunk) => chunk.chunkId), ['A', 'B', 'C']);
  assert.equal(MMR_LAMBDA, 0.7);
});

test('MMR relevance is normalized by the pool maximum, so scaling scores changes nothing', () => {
  const chunks = ['A', 'B', 'C'].map((label) => chunkByLabel(label));
  const vectors = vectorsFor([
    [chunks[0], basisVector(0)],
    [chunks[1], basisVector(1)],
    [chunks[2], mixingVector(0, 1)],
  ]);
  const base = [asCandidate(chunks[0], 1), asCandidate(chunks[1], 0.6), asCandidate(chunks[2], 0.5)];
  const scaled = base.map((candidate) => asCandidate(candidate.chunk, candidate.score * 1000));
  assert.deepEqual(
    mmr(base, vectors).map((chunk) => chunk.chunkId),
    mmr(scaled, vectors).map((chunk) => chunk.chunkId),
  );
  assert.deepEqual(mmr(base, vectors).map((chunk) => chunk.chunkId), ['A', 'B', 'C']);
});

test('MMR is stable on ties, capped at 8 anchors and keeps keyword-only candidates eligible', () => {
  const many = Array.from({ length: 12 }, (_value, index) => ({
    ownerId: 'actor-a',
    noteId: `n-${String(index).padStart(2, '0')}`,
    revision: 1,
    sectionId: 'body',
    chunkId: 'body-0',
    ordinal: 0,
    title: 'T',
    startOffset: 0,
    endOffset: 1,
    text: 'x',
  }));
  const candidates = many.map((chunk) => asCandidate(chunk, 0.5));
  const vectors = vectorsFor(many.map((chunk, index) => [chunk, basisVector(index)] as const));
  const anchors = mmr(candidates, vectors);
  assert.equal(anchors.length, MMR_MAX_ANCHORS);
  assert.equal(MMR_MAX_ANCHORS, 8);
  assert.deepEqual(
    anchors.map((chunk) => chunk.noteId),
    many.slice(0, 8).map((chunk) => chunk.noteId),
    'equal relevance and equal novelty break by ascending source key',
  );
  assert.deepEqual(mmr([], new Map()), []);
});

test('MMR fails closed on missing vectors and malformed candidates', () => {
  const chunk = chunkByLabel('A');
  assert.throws(() => mmr([asCandidate(chunk, 1)], new Map()), failsWith('INDEX_NOT_READY'));
  assert.throws(
    () => mmr([asCandidate(chunk, 1)], vectorsFor([[chunk, Array.from({ length: 1024 }, () => 0)]])),
    failsWith('INDEX_NOT_READY'),
  );
  assert.throws(() => mmr([asCandidate(chunk, Number.NaN)], vectorsFor([[chunk, basisVector(0)]])), failsWith('INVALID_INPUT'));
  assert.throws(() => mmr([asCandidate(chunk, -1)], vectorsFor([[chunk, basisVector(0)]])), failsWith('INVALID_INPUT'));
  assert.throws(
    () => mmr([asCandidate(chunk, 1), asCandidate(chunk, 1)], vectorsFor([[chunk, basisVector(0)]])),
    failsWith('INVALID_INPUT'),
  );
  assert.throws(
    () => mmr([asCandidate(chunk, 0)], vectorsFor([[chunk, basisVector(0)]])),
    failsWith('INVALID_INPUT'),
    'an all-zero pool has no relevance signal',
  );
});

test('integration: keyword-only chunks survive fusion and reach MMR anchors', () => {
  const corpus = ['a-watch', 'a-meeting', 'a-condition', 'a-negation'].map((key) => chunkOf(key));
  const keywordRanking = bm25('SLGH031 chạy bao lâu khi lên cót đầy?', corpus);
  const watch = corpus[0];
  const meeting = corpus[1];
  assert.equal(keywordRanking[0].chunk.noteId, 'n-watch', 'BM25 found the watch chunk independently');
  // The vector branch does not contain the watch chunk at all: the BM25-only match must still win.
  const vectorRanking: Ranked[] = [{ chunk: meeting, rank: 5 }];
  const fused = rrf(vectorRanking, keywordRanking);
  assert.equal(fused[0].chunk.noteId, 'n-watch');
  const keywordOnly = fused.filter((candidate) => candidate.vectorRank === undefined);
  assert.ok(keywordOnly.length > 0, 'BM25-only candidates are part of the union');
  // getVectors supplies a vector for every union candidate, including BM25-only ones (C09).
  const vectors = vectorsFor(fused.map((candidate, index) => [candidate.chunk, basisVector(index)] as const));
  const anchors = mmr(fused, vectors);
  assert.equal(anchors[0].noteId, 'n-watch');
  assert.ok(anchors.length <= MMR_MAX_ANCHORS);
  assert.equal(vectors.has(sourceKey(watch)), true, 'the keyword-only candidate got a reused vector');
});
