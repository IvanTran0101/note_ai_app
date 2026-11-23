import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildQueryEvidence } from './query_evidence';
import { mmr } from './retrieval';
import { selectRelevantCandidates } from './relevance';
import { policy, sourceKey, type Candidate, type Chunk } from './types';

const chunk = (noteId: string, text: string): Chunk => ({
  ownerId: 'synthetic-evidence', noteId, revision: 1, sectionId: 'body', chunkId: 'body-0',
  ordinal: 0, title: noteId, startOffset: 0, endOffset: text.length, text,
});
const vector = (...values: number[]): readonly number[] =>
  Array.from({ length: policy.embedding.dimensions }, (_, i) => values[i] ?? 0);
const candidate = (chunk: Chunk, rank: number, distance: number, score: number): Candidate => ({
  chunk, score: 2 / (60 + rank), vectorRank: rank, bm25Rank: rank,
  vectorDistance: distance, bm25Score: score,
});

test('a single-token second entity is evidence even with unsupported question wording', () => {
  const first = chunk('Orion', 'Orion costs 10 dollars.');
  const second = chunk('Vega', 'Vega costs 20 dollars.');
  const question = 'What are the prices for Orion and Vega?';
  const pool = [candidate(first, 1, 0.2, 4), candidate(second, 2, 0.8, 0.4)];
  const vectors = new Map([
    [sourceKey(first), vector(0.8, 0.6)],
    [sourceKey(second), vector(0.2, Math.sqrt(0.96))],
  ]);
  const kept = selectRelevantCandidates(question, pool).kept;
  assert.deepEqual(new Set(mmr(kept, vectors, { question }).map(c => c.noteId)), new Set(['Orion', 'Vega']));
});

test('positive MMR utility alone does not justify off-target evidence after the seed', () => {
  const fee = chunk('fee', 'Workshop vẽ màu nước ngày 25/10/2026 có lệ phí 150.000 đồng.');
  const schedule = chunk('schedule', 'Workshop vẽ màu nước ngày 25/10/2026 diễn ra lúc 09:00 tại phòng A2.');
  const other = chunk('other', 'Workshop Trúc Bạc ngày 29/11/2026 có lệ phí 100.000 đồng.');
  const vectors = new Map([
    [sourceKey(fee), vector(0.8, 0.6)],
    [sourceKey(schedule), vector(0.7, 0, Math.sqrt(0.51))],
    [sourceKey(other), vector(0.4, 0, 0, Math.sqrt(0.84))],
  ]);
  const pool = [candidate(fee, 1, 0.2, 4), candidate(schedule, 2, 0.3, 3), candidate(other, 3, 0.6, 1)];
  const question = 'Workshop vẽ màu nước ngày 25/10/2026 diễn ra khi nào, ở đâu và lệ phí bao nhiêu?';
  assert.deepEqual(new Set(mmr(pool, vectors, { question }).map(c => c.noteId)), new Set(['fee', 'schedule']));
});

test('quantity phrases are not target evidence, while a separate noun bao remains', () => {
  const sample = chunk('packaging', 'Bao giấy màu xanh.');
  const pool = [candidate(sample, 1, 0.2, 1)];
  assert.deepEqual(buildQueryEvidence('Có bao nhiêu bao giấy?', pool).terms, ['có', 'bao', 'giấy']);
  assert.deepEqual(buildQueryEvidence('Lệ phí bao nhiêu?', pool).terms, ['lệ', 'phí']);
  assert.deepEqual(buildQueryEvidence('How many boxes?', pool).terms, ['boxes']);
});
