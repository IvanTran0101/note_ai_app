/**
 * Pure calibration evaluator.
 *
 * `selectThresholds` searches a fixed high/low grid on the DEVELOPMENT split only and freezes the
 * choice; `evaluateConfirmation` replays that frozen policy on the confirmation split and NEVER
 * searches. Both consume already-recorded Noul envelopes and reuse the shipped `decideNoul` branch
 * order, so the numbers describe exactly the branch semantics the runtime would execute.
 *
 * Honesty rules enforced here:
 *  - a missing / provider-error / invalid recording stays a named error: it is never turned into a
 *    probability, never into INSUFFICIENT_EVIDENCE and never into "context missing";
 *  - a recorded envelope whose model differs from the frozen model is a hard MODEL_MIX refusal;
 *  - split, group and hash drift (a retune) are refused, not averaged away.
 */
import { OUTPUT_MAX_TOKENS, decideNoul } from '../contract';
import { policy as shippedPolicy } from '../types';
import type { RuntimeConfig, Verdict } from '../types';
import { CalibrationFailure, fail } from './errors';
import { contentHash } from './hash';
import { fixturesForSplit, hashFixtures, validateFixtureSet } from './fixtures';
import { hashRecording, loadRecordingFile, recordedById } from './recordings';
import {
  CALIBRATION_VERSION,
  CATEGORIES,
  LANGUAGES,
  type CalibrationGates,
  type CalibrationPolicy,
  type CalibrationReport,
  type CalibrationThresholds,
  type Category,
  type Fixture,
  type FixtureOutcome,
  type FixtureSet,
  type Language,
  type RecordingFile,
  type SplitMetrics,
} from './types';

export const REPORT_VERSION = 'rag-phase4-calibration-report.v1';
export const POLICY_VERSION = 'rag-phase4-calibration-policy.v1';
/** The frozen grid: strict live-valid thresholds, 0.05 apart, boundaries excluded. */
export const HIGH_GRID: readonly number[] = [0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9, 0.95, 1];
export const LOW_GRID: readonly number[] = [0, 0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45];
export const ANSWERABLE_ALLOW_TARGET = 0.75;

const LIMITATIONS = [
  'synthetic, hand-authored fixtures with author-claimed labels; NOT human-reviewed and NOT user data',
  'thresholds were selected on the development split; the confirmation split is only replayed and never used for tuning',
  'verdicts are replayed from recorded Noul envelopes through decideNoul; the evaluator itself performs no provider call',
  'evidence presence is not answer correctness: expectedFacts and semanticChecks are documented intent, not machine-verified truth',
  'demo calibration for a smoke actor only; this is not production confidence or a probability claim',
] as const;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);
const isHash = (value: unknown): value is string => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/.test(value);

const runtimeConfigFor = (model: string, thresholds: CalibrationThresholds): RuntimeConfig => Object.freeze({
  mode: 'live' as const,
  model,
  thresholds,
  jevMaxTokens: OUTPUT_MAX_TOKENS,
  requestTimeoutMs: shippedPolicy.technicalDefaults.wire.requestTimeoutMs,
});

/** A frozen policy is the only thing that may drive a confirmation run. */
function assertFrozenPolicy(value: unknown): CalibrationPolicy {
  if (!isRecord(value) || !Object.isFrozen(value)) fail('POLICY_NOT_FROZEN', 'calibration policy must be a frozen object');
  if (value['policyVersion'] !== POLICY_VERSION) fail('POLICY_MISMATCH', `policyVersion must be "${POLICY_VERSION}"`);
  if (value['calibrationVersion'] !== CALIBRATION_VERSION) fail('POLICY_MISMATCH', `calibrationVersion must be "${CALIBRATION_VERSION}"`);
  if (typeof value['model'] !== 'string' || value['model'].trim().length === 0) fail('POLICY_MISMATCH', 'policy.model must be a non-blank string');
  if (value['derivedFromSplit'] !== 'development') fail('POLICY_MISMATCH', 'calibration policy must be derived from the development split');
  const thresholds = value['thresholds'];
  if (!isRecord(thresholds) || !Object.isFrozen(thresholds)) fail('POLICY_NOT_FROZEN', 'policy.thresholds must be a frozen object');
  const high = thresholds['answerabilityMin'];
  const low = thresholds['conflictMax'];
  if (typeof high !== 'number' || !Number.isFinite(high) || !(high > 0.5 && high <= 1)) fail('POLICY_MISMATCH', 'answerabilityMin must be in (0.5, 1]');
  if (typeof low !== 'number' || !Number.isFinite(low) || !(low >= 0 && low < 0.5)) fail('POLICY_MISMATCH', 'conflictMax must be in [0, 0.5)');
  for (const key of ['developmentFixtureHash', 'confirmationFixtureHash', 'developmentResultsHash', 'policyHash'] as const) {
    if (!isHash(value[key])) fail('POLICY_MISMATCH', `policy.${key} must be a sha256 hash`);
  }
  if (typeof value['developmentRecordingProvenance'] !== 'string' || value['developmentRecordingProvenance'].trim().length === 0) {
    fail('POLICY_MISMATCH', 'policy.developmentRecordingProvenance must name where the development envelopes came from');
  }
  const body: Record<string, unknown> = { ...value };
  delete body['policyHash'];
  if (contentHash(body) !== value['policyHash']) fail('POLICY_MISMATCH', 'policyHash does not match the policy content: the freeze was edited');
  return value as unknown as CalibrationPolicy;
}

const safeToAnswer = (fixture: Fixture): boolean => fixture.gold.answerable === true && fixture.gold.conflict === false;

function errorOutcome(fixture: Fixture, error: FixtureOutcome['error'], detail: string): FixtureOutcome {
  return Object.freeze({
    fixtureId: fixture.id, language: fixture.language, category: fixture.category, groupId: fixture.groupId,
    expected: fixture.category, outcome: 'error' as const, verdict: null, error, errorDetail: detail,
    answerableAllowed: false, unsafeAllow: false,
  });
}

function verdictOutcome(fixture: Fixture, verdict: Verdict): FixtureOutcome {
  return Object.freeze({
    fixtureId: fixture.id, language: fixture.language, category: fixture.category, groupId: fixture.groupId,
    expected: fixture.category, outcome: 'verdict' as const, verdict, error: null, errorDetail: null,
    answerableAllowed: verdict === 'ALLOW' && fixture.gold.answerable === true,
    unsafeAllow: verdict === 'ALLOW' && !safeToAnswer(fixture),
  });
}

/**
 * Replays every fixture's recording. Unknown fixture ids, split leakage and model mixing are
 * refused before any metric is computed; absence or failure of one recording is reported per
 * fixture as an error and never silently scored.
 */
function outcomesFor(fixtures: readonly Fixture[], recording: RecordingFile, model: string, thresholds: CalibrationThresholds): readonly FixtureOutcome[] {
  const byId = recordedById(recording);
  const known = new Set(fixtures.map((fixture) => fixture.id));
  for (const entry of recording.results) {
    if (!known.has(entry.fixtureId)) fail('SPLIT_DENIED', `recording references "${entry.fixtureId}" which is not part of the scored split`);
  }
  const config = runtimeConfigFor(model, thresholds);
  return fixtures.map((fixture): FixtureOutcome => {
    const entry = byId.get(fixture.id);
    if (entry === undefined) return errorOutcome(fixture, 'missing', 'no recording entry for this fixture');
    if (entry.status !== 'recorded') return errorOutcome(fixture, entry.status, entry.detail);
    const envelope = entry.envelope;
    if (isRecord(envelope) && typeof envelope.model === 'string' && envelope.model !== model) {
      fail('MODEL_MIX', `${fixture.id} was recorded with model "${envelope.model}" but the frozen model is "${model}"`);
    }
    try {
      return verdictOutcome(fixture, decideNoul(envelope, config));
    } catch (error) {
      const detail = error instanceof CalibrationFailure ? error.detail : error instanceof Error ? error.message : 'unknown validation failure';
      return errorOutcome(fixture, 'invalid_envelope', detail);
    }
  });
}

const round4 = (value: number): number => Math.round(value * 10_000) / 10_000;

export function metricsFor(outcomes: readonly FixtureOutcome[]): SplitMetrics {
  const answerable = outcomes.filter((outcome) => outcome.expected === 'answerable');
  const nonAnswerableVerdicts = outcomes.filter((outcome) => outcome.outcome === 'verdict' && outcome.expected !== 'answerable');
  const allowed = answerable.filter((outcome) => outcome.answerableAllowed).length;
  return Object.freeze({
    fixtures: outcomes.length,
    verdicts: outcomes.filter((outcome) => outcome.outcome === 'verdict').length,
    errors: outcomes.filter((outcome) => outcome.outcome === 'error').length,
    unsafeAllow: outcomes.filter((outcome) => outcome.unsafeAllow).length,
    answerableAllowed: allowed,
    answerableTotal: answerable.length,
    answerableAllowRate: answerable.length === 0 ? null : round4(allowed / answerable.length),
    refusedNonAnswerable: nonAnswerableVerdicts.filter((outcome) => outcome.verdict !== 'ALLOW').length,
    nonAnswerableVerdicts: nonAnswerableVerdicts.length,
  });
}

const groupMetrics = <Key extends string>(
  keys: readonly Key[],
  outcomes: readonly FixtureOutcome[],
  keyOf: (outcome: FixtureOutcome) => Key,
): Readonly<Record<Key, SplitMetrics>> =>
  Object.freeze(Object.fromEntries(keys.map((key) => [key, metricsFor(outcomes.filter((outcome) => keyOf(outcome) === key))])) as Record<Key, SplitMetrics>);

export type SelectionInput = Readonly<{ fixtureSet: FixtureSet; recording: RecordingFile; model: string; calibrationVersion?: string }>;

/**
 * Grid search over the development split with `unsafe allow == 0` as a hard filter, then maximum
 * answerable acceptance. Ties are broken conservatively: the highest answerabilityMin (hardest
 * answer gate) and then the lowest conflictMax. No eligible point means no frozen policy at all.
 */
export function selectThresholds(input: SelectionInput): CalibrationPolicy {
  const set = validateFixtureSet(input.fixtureSet);
  const recording = loadRecordingFile(input.recording);
  if (typeof input.model !== 'string' || input.model.trim().length === 0) fail('MODEL_MIX', 'a non-blank frozen model name is required');
  const development = fixturesForSplit(set, 'development');
  const candidates = HIGH_GRID.flatMap((answerabilityMin) => LOW_GRID.map((conflictMax) => Object.freeze({ answerabilityMin, conflictMax })));
  let best: { thresholds: CalibrationThresholds; accepted: number; eligible: number; unsafe: number } | null = null;
  let eligible = 0;
  let lastErrors = 0;
  for (const thresholds of candidates) {
    const outcomes = outcomesFor(development, recording, input.model, thresholds);
    const metrics = metricsFor(outcomes);
    if (metrics.errors > 0) {
      lastErrors = metrics.errors;
      fail('RECORDING_INCOMPLETE', `${metrics.errors} development fixtures have no usable recording; refusing to select thresholds from partial data`);
    }
    if (metrics.unsafeAllow !== 0) continue;
    eligible += 1;
    if (best === null || metrics.answerableAllowed > best.accepted ||
      (metrics.answerableAllowed === best.accepted && (thresholds.answerabilityMin > best.thresholds.answerabilityMin ||
        (thresholds.answerabilityMin === best.thresholds.answerabilityMin && thresholds.conflictMax < best.thresholds.conflictMax)))) {
      best = { thresholds, accepted: metrics.answerableAllowed, eligible, unsafe: metrics.unsafeAllow };
    }
  }
  if (best === null) fail('UNSATISFIABLE', `no grid point keeps unsafe allow at 0 over ${development.length} development fixtures (${lastErrors} unusable recordings)`);
  const answerableTotal = development.filter((fixture) => fixture.category === 'answerable').length;
  const selection = Object.freeze({
    gridSize: candidates.length,
    eligibleUnsafeAllowZero: eligible,
    unsafeAllow: best.unsafe,
    answerableAllowed: best.accepted,
    answerableTotal,
    answerableAllowRate: round4(best.accepted / answerableTotal),
    errors: 0 as const,
    tieBreak: 'max-answerabilityMin-then-min-conflictMax' as const,
  });
  const body = {
    policyVersion: POLICY_VERSION,
    model: input.model,
    fixtureVersion: set.fixtureVersion,
    calibrationVersion: input.calibrationVersion ?? CALIBRATION_VERSION,
    thresholds: Object.freeze({ answerabilityMin: best.thresholds.answerabilityMin, conflictMax: best.thresholds.conflictMax }),
    derivedFromSplit: 'development' as const,
    developmentFixtureHash: set.developmentHash,
    confirmationFixtureHash: set.confirmationHash,
    developmentResultsHash: hashRecording(recording),
    developmentRecordingProvenance: recording.provenance,
    selection,
  };
  return Object.freeze({ ...body, policyHash: contentHash(body) });
}

export type ConfirmationInput = Readonly<{ fixtureSet: FixtureSet; recording: RecordingFile; policy: CalibrationPolicy }>;

/**
 * Replays the frozen policy on the confirmation split. It performs no grid search and cannot
 * change a threshold; it refuses fixture drift, split leakage and model mixing instead.
 */
function replayConfirmation(input: ConfirmationInput, purpose: 'confirmation' | 'regression'): CalibrationReport {
  const frozen = assertFrozenPolicy(input.policy);
  const set = validateFixtureSet(input.fixtureSet);
  if (purpose === 'confirmation' && set.confirmationPurpose !== 'heldout') fail('SPLIT_DENIED', 'seen confirmation is regression-only and cannot authorize promotion');
  const recording = loadRecordingFile(input.recording);
  if (set.fixtureVersion !== frozen.fixtureVersion) fail('POLICY_MISMATCH', 'fixture version differs from the frozen policy');
  if (set.developmentHash !== frozen.developmentFixtureHash) fail('POLICY_MISMATCH', 'development fixtures changed after the policy was frozen (possible retune)');
  if (set.confirmationHash !== frozen.confirmationFixtureHash) fail('POLICY_MISMATCH', 'confirmation fixtures changed after the policy was frozen');
  const confirmation = fixturesForSplit(set, 'confirmation');
  const developmentIds = new Set(fixturesForSplit(set, 'development').map((fixture) => fixture.id));
  if (recording.results.some((entry) => developmentIds.has(entry.fixtureId))) fail('SPLIT_DENIED', 'development fixtures must never appear in a confirmation recording');
  const outcomes = outcomesFor(confirmation, recording, frozen.model, frozen.thresholds);
  const totals = metricsFor(outcomes);
  const byLanguage = groupMetrics<Language>(LANGUAGES, outcomes, (outcome) => outcome.language);
  const byCategory = groupMetrics<Category>(CATEGORIES, outcomes, (outcome) => outcome.category);
  const gates: CalibrationGates = Object.freeze({
    freshConfirmation: purpose === 'confirmation' && set.confirmationPurpose === 'heldout',
    unsafeAllowZero: totals.unsafeAllow === 0,
    answerableAllowAtLeast75: totals.answerableAllowRate !== null && totals.answerableAllowRate >= ANSWERABLE_ALLOW_TARGET,
    recordingsComplete: totals.errors === 0,
    perLanguageAnswerableCovered: LANGUAGES.every((language) => byLanguage[language].answerableTotal > 0),
    passed: false,
  });
  const passed = gates.freshConfirmation && gates.unsafeAllowZero && gates.answerableAllowAtLeast75 && gates.recordingsComplete && gates.perLanguageAnswerableCovered;
  return Object.freeze({
    reportVersion: REPORT_VERSION, split: purpose, model: frozen.model,
    fixtureVersion: set.fixtureVersion, calibrationVersion: frozen.calibrationVersion,
    fixtureHash: set.fixtureHash, developmentFixtureHash: set.developmentHash, confirmationFixtureHash: set.confirmationHash,
    developmentResultsHash: frozen.developmentResultsHash, confirmationResultsHash: hashRecording(recording),
    confirmationRecordingProvenance: recording.provenance,
    policyHash: frozen.policyHash, thresholds: frozen.thresholds,
    totals, byLanguage, byCategory, outcomes: Object.freeze(outcomes),
    gates: Object.freeze({ ...gates, passed }),
    limitations: Object.freeze([...LIMITATIONS, `fixture hash ${set.confirmationHash}; development hash ${set.developmentHash}`]),
  });
}

export const evaluateConfirmation = (input: ConfirmationInput): CalibrationReport => replayConfirmation(input, 'confirmation');

/** Seen data is diagnostic only: even perfect metrics cannot become an approval. */
export const evaluateRegression = (input: ConfirmationInput): CalibrationReport => replayConfirmation(input, 'regression');

export type { FixtureOutcome };
