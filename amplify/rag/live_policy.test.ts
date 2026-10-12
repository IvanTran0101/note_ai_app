/**
 * Private live-approval seam tests: the default refusal, the immutable calibrated approval shape,
 * the private `rag-smoke-` actor restriction, the pinned model/threshold match and the retrieval
 * phase bound. Pure values; no provider, cloud or network call.
 *
 * Runner: node --import tsx --test amplify/rag/live_policy.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  LIVE_RETRIEVAL_STAGE_MS, LIVE_TOTAL_DEADLINE_MS, SMOKE_ACTOR_PREFIX,
  isSmokeActor, isValidLiveThresholds, matchesRuntime, readLiveApproval,
} from './live_policy';
import { RagFailure } from './types';

const thresholds = Object.freeze({ answerabilityMin: 0.9, conflictMax: 0.1 });

const approval = (patch: Record<string, unknown> = {}): Readonly<Record<string, unknown>> =>
  Object.freeze({
    model: 'jev-1.13.0',
    thresholds,
    fixtureVersion: 'rag-phase4-fixtures.v1',
    calibrationVersion: 'rag-phase4-confirmation-2026-10-12.v1',
    ...patch,
  });

const refusal = (value: unknown): boolean => {
  try {
    readLiveApproval(value);
    return false;
  } catch (error) {
    return error instanceof RagFailure && error.code === 'LIVE_POLICY_NOT_CONFIGURED';
  }
};

test('a valid frozen calibrated approval normalizes and defaults to the 6s retrieval bound', () => {
  const parsed = readLiveApproval(approval());
  assert.equal(parsed.model, 'jev-1.13.0');
  assert.deepEqual(parsed.thresholds, { answerabilityMin: 0.9, conflictMax: 0.1 });
  assert.equal(parsed.fixtureVersion, 'rag-phase4-fixtures.v1');
  assert.equal(parsed.calibrationVersion, 'rag-phase4-confirmation-2026-10-12.v1');
  assert.equal(parsed.retrievalStageMs, LIVE_RETRIEVAL_STAGE_MS);
  assert.ok(LIVE_RETRIEVAL_STAGE_MS < LIVE_TOTAL_DEADLINE_MS);
  assert.ok(Object.isFrozen(parsed) && Object.isFrozen(parsed.thresholds));
  assert.equal(readLiveApproval(approval({ retrievalStageMs: 25 })).retrievalStageMs, 25);
});

test('a mutable or malformed approval can never open live mode', () => {
  // Mutable approval objects and mutable thresholds are refused: a live switch must not be tunable.
  assert.ok(refusal({ ...approval() }));
  assert.ok(refusal(approval({ thresholds: { answerabilityMin: 0.9, conflictMax: 0.1 } })));
  assert.ok(refusal({ ...approval(), extra: true }));
  assert.ok(refusal({ model: 'jev-1.13.0', thresholds }));
  assert.ok(refusal(null));
  assert.ok(refusal([]));
  assert.ok(refusal('approved'));
});

test('the fixture and calibration identities must be non-blank, and the model a valid identifier', () => {
  assert.ok(refusal(approval({ fixtureVersion: '' })));
  assert.ok(refusal(approval({ fixtureVersion: '   ' })));
  assert.ok(refusal(approval({ calibrationVersion: '' })));
  assert.ok(refusal(approval({ calibrationVersion: ' ' })));
  assert.ok(refusal(approval({ fixtureVersion: 7 })));
  assert.ok(refusal(approval({ model: '' })));
  assert.ok(refusal(approval({ model: ' jev-1.13.0' })));
});

test('thresholds keep the mock policy ranges and the retrieval bound respects the total deadline', () => {
  assert.ok(isValidLiveThresholds(thresholds));
  assert.ok(isValidLiveThresholds({ answerabilityMin: 1, conflictMax: 0 }));
  assert.ok(!isValidLiveThresholds({ answerabilityMin: 0.5, conflictMax: 0.1 }));
  assert.ok(!isValidLiveThresholds({ answerabilityMin: 0.9, conflictMax: 0.5 }));
  assert.ok(!isValidLiveThresholds({ answerabilityMin: Number.NaN, conflictMax: 0.1 }));
  assert.ok(!isValidLiveThresholds({ answerabilityMin: 0.9 }));

  assert.ok(refusal(approval({ retrievalStageMs: 0 })));
  assert.ok(refusal(approval({ retrievalStageMs: -1 })));
  assert.ok(refusal(approval({ retrievalStageMs: 6_001 })));
  assert.ok(refusal(approval({ retrievalStageMs: 6.5 })));
});

test('only the private rag-smoke- actor namespace is eligible for live mode', () => {
  assert.equal(SMOKE_ACTOR_PREFIX, 'rag-smoke-');
  assert.ok(isSmokeActor('rag-smoke-a'));
  assert.ok(isSmokeActor('rag-smoke-1234567890'));
  assert.ok(!isSmokeActor('actor-a'));
  assert.ok(!isSmokeActor(' rag-smoke-a'));
  // Mirrors the Phase 3 smokeOwner predicate: any non-blank identifier under the prefix.
  assert.ok(isSmokeActor('rag-smoke-'));
  assert.ok(!isSmokeActor(''));
});

test('the runtime config must restate the approved model and threshold pair exactly', () => {
  const parsed = readLiveApproval(approval());
  assert.ok(matchesRuntime(parsed, 'jev-1.13.0', { answerabilityMin: 0.9, conflictMax: 0.1 }));
  assert.ok(!matchesRuntime(parsed, 'jev-1.13.1', { answerabilityMin: 0.9, conflictMax: 0.1 }));
  assert.ok(!matchesRuntime(parsed, 'jev-1.13.0', { answerabilityMin: 0.95, conflictMax: 0.1 }));
  assert.ok(!matchesRuntime(parsed, 'jev-1.13.0', { answerabilityMin: 0.9, conflictMax: 0.05 }));
});
