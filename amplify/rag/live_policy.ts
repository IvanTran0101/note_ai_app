/**
 * Private Phase 4 live-approval seam.
 *
 * Live mode is deliberately not a public flag. `createQuery` keeps refusing live mode unless the
 * caller injects exactly one immutable, calibrated approval into `PipelineDeps.liveApproval`,
 * the request actor is a private `rag-smoke-` synthetic account, and the request's model and
 * threshold pair match that approval exactly. The approval must be frozen, name a valid Jev
 * model and carry non-blank fixture and calibration identities, so an uncalibrated placeholder
 * can never open provider egress. Nothing here is read from the wire, a header, an environment
 * variable or the shipped policy file (which stays closed).
 *
 * The retrieval-stage bound is pinned here as well: the approval may only shorten the 6s
 * retrieval phase and can never exceed the 26s request deadline. The 4s Jev / 13s generate
 * bounds belong to the root adapter that wraps the provider ports.
 */
import { isValidIdentifier } from './contract';
import { policy, RagFailure, type RuntimeConfig } from './types';

/** The private synthetic-account namespace; mirrors index_job_policy_v1.smoke.ownerPrefix. */
export const SMOKE_ACTOR_PREFIX = 'rag-smoke-';
/** policy.technicalDefaults.wire.requestTimeoutMs: the one total deadline. */
export const LIVE_TOTAL_DEADLINE_MS = 26_000;
/** Proposed retrieval-phase bound; the root adapter owns the 4s Jev / 13s generate bounds. */
export const LIVE_RETRIEVAL_STAGE_MS = 6_000;

export type LiveThresholds = Readonly<{ answerabilityMin: number; conflictMax: number }>;

export type LiveApproval = Readonly<{
  model: string;
  thresholds: LiveThresholds;
  fixtureVersion: string;
  calibrationVersion: string;
  retrievalStageMs: number;
}>;

const APPROVAL_REQUIRED = ['model', 'thresholds', 'fixtureVersion', 'calibrationVersion'] as const;
const APPROVAL_OPTIONAL = ['retrievalStageMs'] as const;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

/** Exact-shape guard: every required key, no unknown key, at most the one optional key. */
const hasApprovalShape = (value: Record<string, unknown>): boolean => {
  const keys = Object.keys(value);
  if (keys.length < APPROVAL_REQUIRED.length || keys.length > APPROVAL_REQUIRED.length + APPROVAL_OPTIONAL.length) {
    return false;
  }
  return APPROVAL_REQUIRED.every((key) => Object.hasOwn(value, key)) &&
    keys.every((key) =>
      (APPROVAL_REQUIRED as readonly string[]).includes(key) ||
      (APPROVAL_OPTIONAL as readonly string[]).includes(key));
};

/** Same threshold policy as the mock gates: support strictly above 0.5, conflict strictly below. */
export const isValidLiveThresholds = (value: unknown): value is LiveThresholds => {
  if (!isRecord(value)) return false;
  const answerabilityMin = value['answerabilityMin'];
  const conflictMax = value['conflictMax'];
  return (
    typeof answerabilityMin === 'number' &&
    Number.isFinite(answerabilityMin) &&
    answerabilityMin > 0.5 &&
    answerabilityMin <= 1 &&
    typeof conflictMax === 'number' &&
    Number.isFinite(conflictMax) &&
    conflictMax >= 0 &&
    conflictMax < 0.5
  );
};

/** Only a private synthetic account may ever enter live mode. */
export const isSmokeActor = (actor: unknown): actor is string =>
  isValidIdentifier(actor) && actor.startsWith(SMOKE_ACTOR_PREFIX);

/**
 * Validates and normalizes one caller-supplied approval. Any missing, mutable, malformed or
 * uncalibrated value is `LIVE_POLICY_NOT_CONFIGURED`; the returned copy is deep-frozen, so a
 * later mutation of the caller's object cannot retune a running runtime.
 */
export function readLiveApproval(value: unknown): LiveApproval {
  if (!isRecord(value) || !hasApprovalShape(value)) throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  // The approval itself must be immutable: a mutable object is a tunable live switch.
  if (!Object.isFrozen(value)) throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  const model = value['model'];
  if (model !== 'jev-1.13.0') throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  const thresholds = value['thresholds'];
  if (!Object.isFrozen(thresholds) || !isValidLiveThresholds(thresholds)) {
    throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
  const fixtureVersion = value['fixtureVersion'];
  const calibrationVersion = value['calibrationVersion'];
  if (!isValidIdentifier(fixtureVersion) || !isValidIdentifier(calibrationVersion)) {
    throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
  const rawBudget = value['retrievalStageMs'];
  if (
    rawBudget !== undefined &&
    (!Number.isSafeInteger(rawBudget) || (rawBudget as number) <= 0 || (rawBudget as number) > LIVE_RETRIEVAL_STAGE_MS)
  ) {
    throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
  const retrievalStageMs = rawBudget === undefined ? LIVE_RETRIEVAL_STAGE_MS : (rawBudget as number);
  if (retrievalStageMs >= LIVE_TOTAL_DEADLINE_MS) throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  return Object.freeze({
    model,
    thresholds: Object.freeze({ answerabilityMin: thresholds.answerabilityMin, conflictMax: thresholds.conflictMax }),
    fixtureVersion,
    calibrationVersion,
    retrievalStageMs,
  });
}

/** The runtime config may only restate the approved model and threshold pair, nothing else. */
export const matchesRuntime = (
  approval: LiveApproval,
  model: string,
  thresholds: LiveThresholds,
): boolean =>
  approval.model === model &&
  approval.thresholds.answerabilityMin === thresholds.answerabilityMin &&
  approval.thresholds.conflictMax === thresholds.conflictMax;

export type RuntimeValues = Readonly<{
  model: string;
  thresholds: Readonly<{ answerabilityMin: number; conflictMax: number }>;
  jevMaxTokens: number;
  requestTimeoutMs: number;
  /** Live-only retrieval-phase bound in ms; null in mock mode keeps the P2 timing untouched. */
  retrievalStageMs: number | null;
}>;

const POLICY_RUNTIME_ENABLED: boolean = policy.runtimeEnabled;
const POLICY_LIVE_MODEL: string | null = policy.jev.liveModel;
const POLICY_LIVE_THRESHOLDS: unknown = policy.jev.liveThresholds;

/**
 * Validates the fixed model, threshold pair and both budgets before any egress. Mock mode needs
 * no approval. Live mode is private: the shipped policy gates must still be closed, the actor
 * must be a `rag-smoke-` synthetic account, and exactly one immutable calibrated approval must
 * restate the model and threshold pair. Anything else is refused before the first port call.
 */
export const readRuntimeConfig = (config: RuntimeConfig, actor: string, approval: unknown): RuntimeValues => {
  if (config === null || typeof config !== 'object') throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  if (config.mode !== 'mock' && config.mode !== 'live') throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  if (POLICY_RUNTIME_ENABLED !== false || POLICY_LIVE_MODEL !== null || POLICY_LIVE_THRESHOLDS !== null) {
    throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
  const model = config.model;
  if (typeof model !== 'string' || !isValidIdentifier(model)) throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  const thresholds = config.thresholds;
  if (!isValidLiveThresholds(thresholds)) throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  const answerabilityMin = thresholds.answerabilityMin;
  const conflictMax = thresholds.conflictMax;
  if (!Number.isSafeInteger(config.jevMaxTokens) || config.jevMaxTokens <= 0) {
    throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
  if (
    !Number.isSafeInteger(config.requestTimeoutMs) ||
    config.requestTimeoutMs <= 0 ||
    config.requestTimeoutMs > LIVE_TOTAL_DEADLINE_MS
  ) {
    throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
  const bound = Object.freeze({ answerabilityMin, conflictMax });
  if (config.mode === 'mock') {
    return Object.freeze({
      model,
      thresholds: bound,
      jevMaxTokens: config.jevMaxTokens,
      requestTimeoutMs: config.requestTimeoutMs,
      retrievalStageMs: null,
    });
  }
  if (!isSmokeActor(actor)) throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  const live = readLiveApproval(approval);
  if (!matchesRuntime(live, model, bound)) throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  if (live.retrievalStageMs >= config.requestTimeoutMs) throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  return Object.freeze({
    model,
    thresholds: bound,
    jevMaxTokens: config.jevMaxTokens,
    requestTimeoutMs: config.requestTimeoutMs,
    retrievalStageMs: live.retrievalStageMs,
  });
};

