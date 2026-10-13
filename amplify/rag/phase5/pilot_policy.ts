/**
 * Phase 5 pilot policy (plan 5.1D): the one server-side permission input for the bounded
 * pilot. It is a frozen value, never a flag: the caller supplies an already frozen, exactly
 * shaped config, `enabled` must literally be true, and the owner list is capped at five
 * lowercase Cognito `sub` UUIDs. Nothing here is read from the wire, a header, a query
 * parameter or the app, so a UI can never widen the pilot.
 *
 * `enabled` means "the server has been authorized to admit pilot traffic"; it is not a UI
 * state. `assertPilotActor` is the query/index admission gate (disabled or non-pilot both
 * refuse with LIVE_POLICY_NOT_CONFIGURED). `isPilotOwner` deliberately ignores `enabled` so
 * the consent endpoint can still let a listed owner revoke a grant when admission is off.
 *
 * Every exported guard and predicate re-runs the full `readPilotPolicy` validation on the value
 * it is handed, so a caller that freezes only the fields it knows about cannot pass a policy
 * that is missing a threshold, over the owner cap or carries an extra key.
 */
import { isValidIdentifier } from '../contract';
import { RagFailure } from '../types';

/** Fixed Phase 4 binding: the calibrated model and threshold pair may not be retuned here. */
export const PILOT_MODEL = 'jev-1.13.0';
export const PILOT_THRESHOLDS: Readonly<{ answerabilityMin: number; conflictMax: number }> =
  Object.freeze({ answerabilityMin: 0.85, conflictMax: 0.1 });
export const MAX_PILOT_OWNERS = 5;

export type PilotPolicy = Readonly<{
  enabled: boolean;
  owners: readonly string[];
  model: string;
  thresholds: Readonly<{ answerabilityMin: number; conflictMax: number }>;
}>;

const POLICY_KEYS = ['enabled', 'owners', 'model', 'thresholds'] as const;
const THRESHOLD_KEYS = ['answerabilityMin', 'conflictMax'] as const;
/** Cognito `sub` is a lowercase UUID; that shape is what makes every owner key unambiguous. */
const COGNITO_SUB = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const hasExactKeys = (value: Record<string, unknown>, required: readonly string[]): boolean =>
  Object.keys(value).length === required.length &&
  required.every((key) => Object.prototype.hasOwnProperty.call(value, key));

/** Every rejection is the same code: a malformed pilot policy is simply not configured. */
const refuse: () => never = () => {
  throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
};

export const isCognitoSub = (value: unknown): value is string =>
  isValidIdentifier(value) && COGNITO_SUB.test(value);

/**
 * Validates one caller-supplied policy. The input and its `owners`/`thresholds` members must
 * already be frozen (a mutable policy is a tunable pilot switch), every key set is exact, the
 * model and threshold pair must equal the frozen Phase 4 binding, and owners must be unique
 * Cognito subs. The returned copy is deeply frozen so a later mutation of the caller's value
 * cannot widen a running runtime.
 */
export function readPilotPolicy(value: unknown): PilotPolicy {
  if (!isRecord(value) || !Object.isFrozen(value) || !hasExactKeys(value, POLICY_KEYS)) refuse();
  const enabled = value['enabled'];
  if (typeof enabled !== 'boolean') refuse();
  const rawOwners = value['owners'];
  if (!Array.isArray(rawOwners) || !Object.isFrozen(rawOwners) || rawOwners.length > MAX_PILOT_OWNERS) refuse();
  const owners: string[] = [];
  for (const owner of rawOwners) {
    if (!isCognitoSub(owner) || owners.includes(owner)) refuse();
    owners.push(owner);
  }
  if (value['model'] !== PILOT_MODEL) refuse();
  const thresholds = value['thresholds'];
  if (!isRecord(thresholds) || !Object.isFrozen(thresholds) || !hasExactKeys(thresholds, THRESHOLD_KEYS)) refuse();
  if (
    thresholds['answerabilityMin'] !== PILOT_THRESHOLDS.answerabilityMin ||
    thresholds['conflictMax'] !== PILOT_THRESHOLDS.conflictMax
  ) {
    refuse();
  }
  return Object.freeze({
    enabled,
    owners: Object.freeze(owners),
    model: PILOT_MODEL,
    thresholds: PILOT_THRESHOLDS,
  });
}

/**
 * The one validated view every guard uses. A policy that did not come out of `readPilotPolicy`
 * in full — mutable, malformed, missing a threshold, over five owners, retuned model or an extra
 * key — is `null`, so membership predicates answer false and the admission gate refuses instead
 * of trusting the two or three fields a caller happened to freeze.
 */
const validated = (policy: unknown): PilotPolicy | null => {
  try {
    return readPilotPolicy(policy);
  } catch {
    return null;
  }
};

const ownersOf = (policy: unknown): readonly string[] => validated(policy)?.owners ?? [];

const enabledOf = (policy: unknown): boolean => validated(policy)?.enabled === true;

/** Listed-owner membership only; admission is a separate question (see `assertPilotActor`). */
export const isPilotOwner = (policy: PilotPolicy, actor: unknown): boolean =>
  isCognitoSub(actor) && ownersOf(policy).includes(actor);

/**
 * The explicit disabled/non-pilot gate for query, consent-permission and worker admission.
 * The whole policy is re-validated first: a policy missing a threshold, over five owners or
 * carrying an extra key refuses here exactly like a disabled one. There is no smoke-prefix or
 * wildcard fallback: anything but an enabled policy naming this exact actor is
 * LIVE_POLICY_NOT_CONFIGURED.
 */
export function assertPilotActor(policy: PilotPolicy, actor: unknown): void {
  const parsed = validated(policy);
  if (parsed === null || !parsed.enabled || !isCognitoSub(actor) || !parsed.owners.includes(actor)) refuse();
}

/** Owner filter for the indexing worker: a disabled or malformed policy allows no owner. */
export const allowsIndexOwner = (policy: PilotPolicy, owner: unknown): boolean =>
  enabledOf(policy) && isPilotOwner(policy, owner);
