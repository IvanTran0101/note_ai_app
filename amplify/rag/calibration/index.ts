/**
 * Phase 4 calibration public surface.
 *
 * Root integration is expected to be exactly:
 *   1. `readFixtureFile(path)` once for the frozen 64-fixture set;
 *   2. `selectThresholds({fixtureSet, recording: developmentRecording, model})` and store the
 *      returned frozen policy next to the live approval it will justify;
 *   3. `evaluateConfirmation({fixtureSet, recording: confirmationRecording, policy})` after the
 *      confirmation calls are recorded — never before, and never to re-pick a threshold.
 * Missing and failed recordings are reported, never fabricated.
 */
export {
  CalibrationFailure,
  type CalibrationErrorCode,
} from './errors';
export {
  EMBEDDED_INSTRUCTION,
  INSTRUCTION_CHECK,
  SYNTHETIC_MARKER,
  TOTAL_FIXTURES,
  assertNoGroupLeak,
  evidenceTextFor,
  fixturesForSplit,
  hashFixtures,
  loadFixtureFile,
  readFixtureFile,
  validateDistribution,
  validateFixture,
  validateFixtureSet,
  type DistributionCounts,
} from './fixtures';
export {
  SYNTHETIC_RECORDING_PROVENANCE,
  hashRecording,
  loadRecordingFile,
  recordedById,
} from './recordings';
export {
  ANSWERABLE_ALLOW_TARGET,
  HIGH_GRID,
  LOW_GRID,
  POLICY_VERSION,
  REPORT_VERSION,
  evaluateConfirmation,
  evaluateRegression,
  metricsFor,
  selectThresholds,
  type ConfirmationInput,
  type SelectionInput,
} from './evaluate';
export {
  CALIBRATION_VERSION,
  CATEGORIES,
  FIXTURE_VERSION,
  LABEL_PROVENANCE,
  LANGUAGES,
  RECORDING_VERSION,
  SPLITS,
  TRAITS,
  type CalibrationGates,
  type CalibrationPolicy,
  type CalibrationReport,
  type CalibrationThresholds,
  type Category,
  type Fixture,
  type FixtureGold,
  type FixtureNote,
  type FixtureOutcome,
  type FixtureSet,
  type FixtureSource,
  type Language,
  type OutcomeError,
  type RecordedNoul,
  type RecordingFile,
  type SelectionSummary,
  type Split,
  type SplitMetrics,
  type Trait,
} from './types';
