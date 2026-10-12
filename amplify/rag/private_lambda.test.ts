import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readPublishedApproval } from './private_lambda';
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
