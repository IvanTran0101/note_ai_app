import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readPublishedApproval, reserveCohere } from './private_lambda';
import type { Embedding } from './indexing/types';
import { readFixtureFile, selectThresholds, RECORDING_VERSION, type RecordingFile } from './calibration';
import { LIVE_QUESTION_SET, LIVE_RECORDING_PROVENANCE } from './question_set';
import { contentHash } from './calibration/hash';
import { RagFailure } from './types';

// Fake envelopes only exercise the approval boundary; they are not live receipts.
const fixtures = readFixtureFile('test/fixtures/rag/phase4/fixtures.json');
const recording = (split: 'development' | 'confirmation'): RecordingFile => ({
  recordingVersion: RECORDING_VERSION, provenance: LIVE_RECORDING_PROVENANCE,
  results: fixtures.fixtures.filter(f => f.split === split).map(f => ({
    fixtureId: f.id, status: 'recorded' as const, envelope: {
      model: 'jev-1.13.0', answers: {
        answerable_from_evidence: { type: 'noul', noul: f.category === 'answerable' ? .99 : .1 },
        has_unresolved_conflict: { type: 'noul', noul: f.category === 'conflict' ? .99 : .01 },
      }, usage: { input_tokens: 900, output_tokens: 20 },
    },
  })),
});
const item = { questionSetHash: contentHash(LIVE_QUESTION_SET),
  policy: selectThresholds({ fixtureSet: fixtures, recording: recording('development'), model: 'jev-1.13.0' }),
  recording: recording('confirmation') };
const isCode = (code: string) => (error: unknown) => error instanceof RagFailure && error.code === code;

test('published approval recomputes confirmation and rejects a changed question binding', async () => {
  const signal = new AbortController().signal;
  const approval = await readPublishedApproval({ send: async () => ({ Item: item }) }, 'state', signal);
  assert.equal(approval.fixtureVersion, fixtures.fixtureVersion);
  assert.equal(Object.isFrozen(approval.thresholds), true);
  await assert.rejects(readPublishedApproval({ send: async () => ({ Item: { ...item, questionSetHash: 'changed' } }) }, 'state', signal), isCode('LIVE_POLICY_NOT_CONFIGURED'));
});

test('storage failure remains unavailable rather than an unconfigured policy, without a retry', async () => {
  let reads = 0;
  const store = { send: async () => { reads++; throw new Error('synthetic transport failure'); } };
  await assert.rejects(readPublishedApproval(store, 'state', new AbortController().signal), isCode('PROVIDER_UNAVAILABLE'));
  assert.equal(reads, 1);
  const cancelled = new AbortController(); cancelled.abort();
  await assert.rejects(readPublishedApproval(store, 'state', cancelled.signal), isCode('TIMEOUT'));
});

test('missing or malformed approval cannot permit generation', async () => {
  for (const Item of [undefined, { ...item, recording: {} }]) {
    await assert.rejects(readPublishedApproval({ send: async () => ({ Item }) }, 'state', new AbortController().signal), isCode('LIVE_POLICY_NOT_CONFIGURED'));
  }
});

const unitVector = (): readonly number[] => {
  const vector = new Array<number>(1024).fill(0);
  vector[0] = 1;
  return vector;
};

test('the private Cohere wrapper reserves once, revalidates after the reservation, then forwards', async () => {
  let reserved = 0;
  let raw = 0;
  const refused: Embedding = reserveCohere(
    { count: (text) => text.length, embed: async (texts) => { raw += 1; return texts.map(() => unitVector()); } },
    async () => { reserved += 1; },
  );
  const withdrawal = async (): Promise<void> => { throw new RagFailure('SOURCE_CHANGED'); };
  await assert.rejects(
    () => refused.embed(['q'], 'search_query', new AbortController().signal, withdrawal),
    isCode('SOURCE_CHANGED'),
  );
  assert.equal(reserved, 1, 'the Cohere reservation ran exactly once');
  assert.equal(raw, 0, 'no raw embed when the post-reservation revalidation refuses');

  let forwarded: unknown;
  let accepted = 0;
  const stable = async (): Promise<void> => {};
  const embedding: Embedding = reserveCohere(
    {
      count: (text) => text.length,
      embed: async (texts, _purpose, _signal, beforeDispatch) => {
        forwarded = beforeDispatch;
        accepted += 1;
        return texts.map(() => unitVector());
      },
    },
    async () => {},
  );
  const produced = await embedding.embed(['q'], 'search_query', new AbortController().signal, stable);
  assert.equal(accepted, 1);
  assert.equal(forwarded, stable, 'the callback is forwarded into the signed transport');
  assert.equal(produced.length, 1);
  assert.equal(embedding.count('abc'), 3);
});
