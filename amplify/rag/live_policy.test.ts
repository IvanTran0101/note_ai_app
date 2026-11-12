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
  isSmokeActor, isValidLiveThresholds, matchesRuntime, readLiveApproval, readRuntimeConfig,
} from './live_policy';
import { PILOT_DEMO_THRESHOLDS, PILOT_THRESHOLDS } from './phase5/pilot_policy';
import { RagFailure } from './types';
import type { RuntimeConfig } from './types';

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
  // The user-approved uncalibrated pilot pair is exactly at the inclusive floor.
  assert.ok(isValidLiveThresholds({ answerabilityMin: 0.5, conflictMax: 0.1 }));
  assert.ok(!isValidLiveThresholds({ answerabilityMin: 0.499, conflictMax: 0.1 }));
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

const ACTOR = '00000001-0000-4000-8000-000000000001';
const OTHER = '00000002-0000-4000-8000-000000000002';

/** The genuine historical calibration readPublishedApproval reconstructs. */
const baselineApproval = () => readLiveApproval(Object.freeze({
  model: 'jev-1.13.0',
  thresholds: Object.freeze({ answerabilityMin: 0.85, conflictMax: 0.1 }),
  fixtureVersion: 'rag-phase4-fixtures.v1',
  calibrationVersion: 'rag-phase4-confirmation-2026-10-12.v1',
}));

const runtime = (
  thresholds: Readonly<{ answerabilityMin: number; conflictMax: number }>,
): RuntimeConfig => Object.freeze({
  mode: 'live',
  model: 'jev-1.13.0',
  thresholds,
  jevMaxTokens: 32_000,
  requestTimeoutMs: LIVE_TOTAL_DEADLINE_MS,
});

const pilot = (
  thresholds: Readonly<{ answerabilityMin: number; conflictMax: number }> = PILOT_THRESHOLDS,
  owners: readonly string[] = [ACTOR],
  enabled = true,
) => Object.freeze({
  enabled,
  owners: Object.freeze([...owners]),
  model: 'jev-1.13.0',
  thresholds,
});

const refusedRuntime = (...args: Parameters<typeof readRuntimeConfig>): boolean => {
  try {
    readRuntimeConfig(...args);
    return false;
  } catch (error) {
    return error instanceof RagFailure && error.code === 'LIVE_POLICY_NOT_CONFIGURED';
  }
};

test('the exact 0.5 pilot pair runs only with the genuine historical 0.85 approval', () => {
  const values = readRuntimeConfig(
    runtime(PILOT_DEMO_THRESHOLDS), ACTOR, baselineApproval(), pilot(PILOT_DEMO_THRESHOLDS),
  );
  assert.equal(values.model, 'jev-1.13.0');
  assert.deepEqual(values.thresholds, { answerabilityMin: 0.5, conflictMax: 0.1 });
  assert.equal(values.retrievalStageMs, LIVE_RETRIEVAL_STAGE_MS);
});

test('the legacy .85 pilot pair and its approval stay unchanged', () => {
  const values = readRuntimeConfig(runtime(PILOT_THRESHOLDS), ACTOR, baselineApproval(), pilot());
  assert.deepEqual(values.thresholds, { answerabilityMin: 0.85, conflictMax: 0.1 });
});

test('the 0.5 pilot pair refuses a missing, forged, malformed or unlisted approval', () => {
  assert.ok(refusedRuntime(runtime(PILOT_DEMO_THRESHOLDS), ACTOR, undefined, pilot(PILOT_DEMO_THRESHOLDS)));
  // A mutable approval can never be treated as the historical calibration.
  assert.ok(refusedRuntime(runtime(PILOT_DEMO_THRESHOLDS), ACTOR, {
    model: 'jev-1.13.0',
    thresholds: { answerabilityMin: 0.85, conflictMax: 0.1 },
    fixtureVersion: 'fix-1',
    calibrationVersion: 'cal-1',
  }, pilot(PILOT_DEMO_THRESHOLDS)));
  // A frozen 0.5 approval is syntactically valid now, but it is not the genuine 0.85 record.
  assert.ok(refusedRuntime(runtime(PILOT_DEMO_THRESHOLDS), ACTOR, readLiveApproval(Object.freeze({
    model: 'jev-1.13.0',
    thresholds: Object.freeze({ answerabilityMin: 0.5, conflictMax: 0.1 }),
    fixtureVersion: 'fix-1',
    calibrationVersion: 'cal-1',
  })), pilot(PILOT_DEMO_THRESHOLDS)));
  // An approval that does not name the runtime model is refused too.
  assert.ok(refusedRuntime(runtime(PILOT_DEMO_THRESHOLDS), ACTOR, baselineApproval(), pilot(PILOT_DEMO_THRESHOLDS, [OTHER])));
  // The runtime pair may not drift away from the validated pilot pair.
  assert.ok(refusedRuntime(runtime(PILOT_DEMO_THRESHOLDS), ACTOR, baselineApproval(), pilot(PILOT_THRESHOLDS)));
});

test('the smoke/default seam keeps exact equality and cannot borrow the .5 pilot exception', () => {
  // A historical .85 approval cannot open a .5 runtime without the explicit pilot pair.
  assert.ok(refusedRuntime(runtime(PILOT_DEMO_THRESHOLDS), 'rag-smoke-a', baselineApproval()));
  // Even a matching hand-built .5 approval cannot open the pilot pair through the smoke seam.
  const demoApproval = readLiveApproval(Object.freeze({
    model: 'jev-1.13.0',
    thresholds: Object.freeze({ answerabilityMin: 0.5, conflictMax: 0.1 }),
    fixtureVersion: 'fix-1',
    calibrationVersion: 'cal-1',
  }));
  assert.ok(refusedRuntime(runtime(PILOT_DEMO_THRESHOLDS), 'rag-smoke-a', demoApproval));
  // Nor can a smoke actor present the explicit .5 pilot: the actor gate still refuses.
  assert.ok(refusedRuntime(
    runtime(PILOT_DEMO_THRESHOLDS), 'rag-smoke-a', baselineApproval(), pilot(PILOT_DEMO_THRESHOLDS),
  ));
  // The legacy smoke path with exact approval/runtime equality is unchanged.
  const values = readRuntimeConfig(runtime(PILOT_THRESHOLDS), 'rag-smoke-a', baselineApproval());
  assert.deepEqual(values.thresholds, { answerabilityMin: 0.85, conflictMax: 0.1 });
});
