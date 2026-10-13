/**
 * Phase 5 pilot policy tests: the exact frozen shape, the five-sub cap, the pinned Phase 4
 * model/threshold pair, the disabled/non-pilot refusal and the consent-revoke seam that must
 * not depend on admission. Every exported guard is also called DIRECTLY with a frozen but
 * malformed policy, because a guard that validates only the fields it happens to read can be
 * handed a policy missing a threshold, over the owner cap or carrying an extra key.
 * Pure values; no AWS, network or provider call.
 *
 * Runner: node --import tsx --test amplify/rag/phase5/pilot_policy.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  MAX_PILOT_OWNERS, PILOT_MODEL, PILOT_THRESHOLDS,
  allowsIndexOwner, assertPilotActor, isCognitoSub, isPilotOwner, readPilotPolicy,
} from './pilot_policy';
import { RagFailure } from '../types';

const sub = (n: number): string => `0000000${n}-0000-4000-8000-00000000000${n}`;
const OWNERS = Object.freeze([sub(1), sub(2)]);
const THRESHOLDS = Object.freeze({ answerabilityMin: 0.85, conflictMax: 0.1 });

const policy = (patch: Record<string, unknown> = {}): Readonly<Record<string, unknown>> =>
  Object.freeze({ enabled: true, owners: OWNERS, model: PILOT_MODEL, thresholds: THRESHOLDS, ...patch });

const refused = (value: unknown): boolean => {
  try {
    readPilotPolicy(value);
    return false;
  } catch (error) {
    return error instanceof RagFailure && error.code === 'LIVE_POLICY_NOT_CONFIGURED';
  }
};

const refusedActor = (value: unknown, actor: unknown): boolean => {
  try {
    assertPilotActor(value as never, actor);
    return false;
  } catch (error) {
    return error instanceof RagFailure && error.code === 'LIVE_POLICY_NOT_CONFIGURED';
  }
};

/**
 * Frozen candidates that a partial guard could mistake for a valid policy: the model matches and
 * the owner list contains `sub(1)`, but the rest of the exact shape is missing or wrong.
 */
const SIX = Object.freeze([sub(1), sub(2), sub(3), sub(4), sub(5), sub(6)]);
const MALFORMED: ReadonlyArray<readonly [string, unknown]> = [
  ['missing thresholds', Object.freeze({ enabled: true, owners: OWNERS, model: PILOT_MODEL })],
  ['missing model', Object.freeze({ enabled: true, owners: OWNERS, thresholds: THRESHOLDS })],
  ['unknown key', Object.freeze({ enabled: true, owners: OWNERS, model: PILOT_MODEL, thresholds: THRESHOLDS, extra: true })],
  ['model retuned', Object.freeze({ enabled: true, owners: OWNERS, model: 'jev-1.12.0', thresholds: THRESHOLDS })],
  ['threshold retuned', Object.freeze({
    enabled: true, owners: OWNERS, model: PILOT_MODEL,
    thresholds: Object.freeze({ answerabilityMin: 0.9, conflictMax: 0.1 }),
  })],
  ['threshold missing a key', Object.freeze({
    enabled: true, owners: OWNERS, model: PILOT_MODEL, thresholds: Object.freeze({ answerabilityMin: 0.85 }),
  })],
  ['thresholds not frozen', Object.freeze({
    enabled: true, owners: OWNERS, model: PILOT_MODEL,
    thresholds: { answerabilityMin: 0.85, conflictMax: 0.1 },
  })],
  ['six owners', Object.freeze({ enabled: true, owners: SIX, model: PILOT_MODEL, thresholds: THRESHOLDS })],
  ['duplicate owner', Object.freeze({ enabled: true, owners: Object.freeze([sub(1), sub(1)]), model: PILOT_MODEL, thresholds: THRESHOLDS })],
  ['aliased owner', Object.freeze({ enabled: true, owners: Object.freeze([sub(1), 'actor-a']), model: PILOT_MODEL, thresholds: THRESHOLDS })],
  ['owners not frozen', Object.freeze({ enabled: true, owners: [sub(1)], model: PILOT_MODEL, thresholds: THRESHOLDS })],
  ['mutable policy', { enabled: true, owners: OWNERS, model: PILOT_MODEL, thresholds: THRESHOLDS }],
];

test('a frozen policy with the exact fields normalizes and stays immutable', () => {
  const parsed = readPilotPolicy(policy());
  assert.equal(parsed.enabled, true);
  assert.deepEqual(parsed.owners, [sub(1), sub(2)]);
  assert.equal(parsed.model, PILOT_MODEL);
  assert.deepEqual(parsed.thresholds, { answerabilityMin: 0.85, conflictMax: 0.1 });
  assert.equal(MAX_PILOT_OWNERS, 5);
  assert.ok(Object.isFrozen(parsed) && Object.isFrozen(parsed.owners) && Object.isFrozen(parsed.thresholds));
  // The returned owner list is frozen, so a running policy cannot be widened afterwards.
  assert.throws(() => (parsed.owners as string[]).push(sub(4)), TypeError);
  assert.ok(!parsed.owners.includes(sub(4)));
  // A disabled policy still parses; only admission refuses.
  assert.equal(readPilotPolicy(policy({ enabled: false })).enabled, false);
  assert.equal(readPilotPolicy(policy({ owners: Object.freeze([]) })).owners.length, 0);
  const five = [sub(1), sub(2), sub(3), sub(4), sub(5)];
  assert.equal(readPilotPolicy(policy({ owners: Object.freeze(five) })).owners.length, 5);
});

test('a mutable, extra-keyed, missing-keyed or badly typed policy can never open the pilot', () => {
  assert.ok(refused({ ...policy() }));
  assert.ok(refused(policy({ owners: [sub(1)] })));
  assert.ok(refused(policy({ thresholds: { answerabilityMin: 0.85, conflictMax: 0.1 } })));
  assert.ok(refused(policy({ extra: true })));
  assert.ok(refused({ owners: OWNERS, model: PILOT_MODEL, thresholds: THRESHOLDS }));
  assert.ok(refused(policy({ enabled: 'true' })));
  assert.ok(refused(policy({ enabled: undefined })));
  assert.ok(refused(null));
  assert.ok(refused([]));
  assert.ok(refused('enabled'));
  assert.ok(refused(undefined));
});

test('owners are at most five unique lowercase Cognito sub UUIDs', () => {
  const letters = 'abcdef01-2345-4678-89ab-cdef01234567';
  assert.ok(isCognitoSub(sub(9)));
  assert.ok(isCognitoSub(letters));
  assert.ok(!isCognitoSub(letters.toUpperCase()));
  assert.ok(!isCognitoSub('actor-a'));
  assert.ok(!isCognitoSub('rag-smoke-actor'));
  assert.ok(!isCognitoSub(` ${sub(9)}`));
  assert.ok(!isCognitoSub(7));
  assert.ok(!isCognitoSub(`${sub(9)}#x`));
  assert.ok(refused(policy({ owners: Object.freeze([sub(1), sub(1)]) })));
  assert.ok(refused(policy({ owners: Object.freeze([sub(1), 'actor-a']) })));
  assert.ok(refused(policy({ owners: Object.freeze([sub(1), sub(2), sub(3), sub(4), sub(5), sub(6)]) })));
  assert.ok(refused(policy({ owners: 'owner' })));
});

test('the model and threshold pair are pinned to the frozen Phase 4 binding', () => {
  assert.equal(PILOT_MODEL, 'jev-1.13.0');
  assert.deepEqual(PILOT_THRESHOLDS, { answerabilityMin: 0.85, conflictMax: 0.1 });
  assert.ok(refused(policy({ model: 'jev-1.12.0' })));
  assert.ok(refused(policy({ model: 'deepseek-flash' })));
  assert.ok(refused(policy({ model: null })));
  assert.ok(refused(policy({ thresholds: Object.freeze({ answerabilityMin: 0.9, conflictMax: 0.1 }) })));
  assert.ok(refused(policy({ thresholds: Object.freeze({ answerabilityMin: 0.85, conflictMax: 0.15 }) })));
  assert.ok(refused(policy({ thresholds: Object.freeze({ answerabilityMin: Number.NaN, conflictMax: 0.1 }) })));
  assert.ok(refused(policy({ thresholds: Object.freeze({ answerabilityMin: 0.85 }) })));
  assert.ok(refused(policy({ thresholds: Object.freeze({ answerabilityMin: 0.85, conflictMax: 0.1, extra: 1 }) })));
});

test('the admission gate refuses a disabled policy and every non-pilot actor', () => {
  const enabled = readPilotPolicy(policy());
  const disabled = readPilotPolicy(policy({ enabled: false }));
  assert.doesNotThrow(() => assertPilotActor(enabled, sub(1)));
  assert.ok(refusedActor(enabled, sub(9)));
  assert.ok(refusedActor(enabled, 'actor-a'));
  assert.ok(refusedActor(enabled, undefined));
  assert.ok(refusedActor(disabled, sub(1)));
  // A hand-built object that never passed readPilotPolicy fails closed.
  assert.ok(refusedActor({ enabled: true, owners: [sub(1)] }, sub(1)));
  assert.ok(refusedActor(Object.freeze({ enabled: true, owners: Object.freeze([sub(1)]) }), sub(1)));
});

test('the consent-revoke seam is listed-owner membership and ignores admission', () => {
  const enabled = readPilotPolicy(policy());
  const disabled = readPilotPolicy(policy({ enabled: false }));
  assert.ok(isPilotOwner(enabled, sub(1)));
  assert.ok(isPilotOwner(disabled, sub(1)));
  assert.ok(!isPilotOwner(disabled, sub(7)));
  assert.ok(!isPilotOwner(enabled, 'actor-a'));
  assert.ok(!isPilotOwner(Object.freeze({ enabled: true, owners: Object.freeze([sub(1)]) }) as never, sub(1)));
});

test('the index-owner filter allows only a listed owner of an enabled policy', () => {
  const enabled = readPilotPolicy(policy());
  const disabled = readPilotPolicy(policy({ enabled: false }));
  assert.ok(allowsIndexOwner(enabled, sub(1)));
  assert.ok(!allowsIndexOwner(enabled, sub(7)));
  assert.ok(!allowsIndexOwner(disabled, sub(1)));
  assert.ok(!allowsIndexOwner(enabled, 'rag-smoke-actor'));
  assert.ok(!allowsIndexOwner(Object.freeze({ enabled: true, owners: Object.freeze([sub(1)]) }) as never, sub(1)));
});

test('every exported guard re-validates the whole policy when called directly', () => {
  // A valid policy still passes every guard; the parsed copy re-validates as itself.
  const enabled = readPilotPolicy(policy());
  assert.ok(isPilotOwner(enabled, sub(1)));
  assert.ok(allowsIndexOwner(enabled, sub(1)));
  assert.doesNotThrow(() => assertPilotActor(enabled, sub(1)));

  for (const [label, candidate] of MALFORMED) {
    assert.equal(isPilotOwner(candidate as never, sub(1)), false, `${label} (isPilotOwner)`);
    assert.equal(allowsIndexOwner(candidate as never, sub(1)), false, `${label} (allowsIndexOwner)`);
    assert.ok(refusedActor(candidate, sub(1)), `${label} (assertPilotActor)`);
    // A malformed policy must refuse an unlisted actor too, never widen.
    assert.equal(isPilotOwner(candidate as never, sub(9)), false, `${label} (unlisted)`);
  }
});

test('a disabled policy keeps a listed owner in the consent seam but admits nobody', () => {
  const disabled = readPilotPolicy(policy({ enabled: false }));
  // Consent read/revoke stays available while admission is off; index admission does not.
  assert.ok(isPilotOwner(disabled, sub(1)));
  assert.ok(!isPilotOwner(disabled, sub(7)));
  assert.ok(!allowsIndexOwner(disabled, sub(1)));
  assert.ok(refusedActor(disabled, sub(1)));
  assert.ok(refusedActor(disabled, sub(9)));
});
