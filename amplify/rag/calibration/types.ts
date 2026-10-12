/**
 * Phase 4 calibration types: fixtures, recorded Noul results, frozen policy and report.
 *
 * Everything here is offline analysis of already-recorded Jev Noul envelopes. The evaluator
 * never calls a provider, never invents a probability and never presents a synthetic label as
 * human-reviewed. A missing or failed recording stays a reported error and is never rewritten
 * into a verdict (in particular never into INSUFFICIENT_EVIDENCE / "context missing").
 */
export const LANGUAGES = ['vi', 'en'] as const;
export type Language = (typeof LANGUAGES)[number];

export const SPLITS = ['development', 'confirmation'] as const;
export type Split = (typeof SPLITS)[number];

export const CATEGORIES = ['answerable', 'insufficient', 'conflict', 'ambiguous'] as const;
export type Category = (typeof CATEGORIES)[number];

/** Closed trait vocabulary the fixture contract requires both splits/languages to exercise. */
export const TRAITS = [
  'negation',
  'right_entity',
  'wrong_entity',
  'multi_part',
  'unresolved_conflict',
  'resolved_conflict',
  'prompt_like_instruction',
  'missing_field',
] as const;
export type Trait = (typeof TRAITS)[number];

export const FIXTURE_VERSION = 'rag-phase4-fixtures.v2-gold1-fresh1';
export const CALIBRATION_VERSION = 'rag-phase4-calibration.v2-gold1-fresh1';
export const RECORDING_VERSION = 'rag-phase4-noul-recordings.v1';
/** The only accepted label provenance: author-claimed synthetic labels, never human review. */
export const LABEL_PROVENANCE = 'synthetic-handauthored-unverified-not-human-reviewed';

export type FixtureNote = Readonly<{ noteId: string; revision: number; title: string; content: string }>;
export type FixtureSource = Readonly<{
  sourceId: string;
  noteId: string;
  revision: number;
  title: string;
  startOffset: number;
  endOffset: number;
  quote: string;
}>;
export type FixtureEvidence = Readonly<{ sources: readonly FixtureSource[]; text: string }>;
export type FixtureGold = Readonly<{
  answerable: boolean | null;
  conflict: boolean | null;
  expectedFacts: readonly string[];
  citationLabels: readonly string[];
  semanticChecks: readonly string[];
}>;
export type Fixture = Readonly<{
  id: string;
  groupId: string;
  language: Language;
  split: Split;
  category: Category;
  question: string;
  notes: readonly FixtureNote[];
  evidence: FixtureEvidence;
  gold: FixtureGold;
  traits: readonly Trait[];
  provenance: typeof LABEL_PROVENANCE;
}>;

/** A validated fixture file: metadata plus the stable content hash of the fixture array. */
export type FixtureSet = Readonly<{
  fixtureVersion: string;
  labelProvenance: string;
  humanReviewed: false;
  confirmationPurpose: 'heldout' | 'regression-only';
  disclaimer: string;
  fixtures: readonly Fixture[];
  fixtureHash: string;
  developmentHash: string;
  confirmationHash: string;
}>;

export type RecordingErrorStatus = 'missing' | 'provider_error';
export type RecordedNoul = Readonly<
  | { fixtureId: string; status: 'recorded'; envelope: unknown }
  | { fixtureId: string; status: RecordingErrorStatus; detail: string }
>;
export type RecordingFile = Readonly<{
  recordingVersion: string;
  provenance: string;
  results: readonly RecordedNoul[];
}>;

/** A fixture outcome is either a real verdict or a named error. There is no "context missing". */
export type OutcomeError = RecordingErrorStatus | 'invalid_envelope';
export type FixtureOutcome = Readonly<{
  fixtureId: string;
  language: Language;
  category: Category;
  groupId: string;
  expected: Category;
  outcome: 'verdict' | 'error';
  verdict: 'ALLOW' | 'INSUFFICIENT_EVIDENCE' | 'UNRESOLVED_CONFLICT' | 'UNCERTAIN' | null;
  error: OutcomeError | null;
  errorDetail: string | null;
  /** True only for gold answerable=true AND conflict=false AND verdict ALLOW. */
  answerableAllowed: boolean;
  /** True only when the verdict is ALLOW while the fixture was not safe to answer. */
  unsafeAllow: boolean;
}>;

export type CalibrationThresholds = Readonly<{ answerabilityMin: number; conflictMax: number }>;

export type SelectionSummary = Readonly<{
  gridSize: number;
  eligibleUnsafeAllowZero: number;
  unsafeAllow: number;
  answerableAllowed: number;
  answerableTotal: number;
  answerableAllowRate: number;
  errors: 0;
  tieBreak: 'max-answerabilityMin-then-min-conflictMax';
}>;

/** Frozen, development-derived threshold policy; carries the provenance needed to detect a retune. */
export type CalibrationPolicy = Readonly<{
  policyVersion: string;
  model: string;
  fixtureVersion: string;
  calibrationVersion: string;
  thresholds: CalibrationThresholds;
  derivedFromSplit: 'development';
  developmentFixtureHash: string;
  confirmationFixtureHash: string;
  developmentResultsHash: string;
  developmentRecordingProvenance: string;
  selection: SelectionSummary;
  policyHash: string;
}>;

export type SplitMetrics = Readonly<{
  fixtures: number;
  verdicts: number;
  errors: number;
  unsafeAllow: number;
  answerableAllowed: number;
  answerableTotal: number;
  answerableAllowRate: number | null;
  refusedNonAnswerable: number;
  nonAnswerableVerdicts: number;
}>;

export type CalibrationGates = Readonly<{
  freshConfirmation: boolean;
  unsafeAllowZero: boolean;
  answerableAllowAtLeast75: boolean;
  recordingsComplete: boolean;
  perLanguageAnswerableCovered: boolean;
  passed: boolean;
}>;

export type CalibrationReport = Readonly<{
  reportVersion: string;
  split: 'confirmation' | 'regression';
  model: string;
  fixtureVersion: string;
  calibrationVersion: string;
  fixtureHash: string;
  developmentFixtureHash: string;
  confirmationFixtureHash: string;
  developmentResultsHash: string;
  confirmationResultsHash: string;
  confirmationRecordingProvenance: string;
  policyHash: string;
  thresholds: CalibrationThresholds;
  totals: SplitMetrics;
  byLanguage: Readonly<Record<Language, SplitMetrics>>;
  byCategory: Readonly<Record<Category, SplitMetrics>>;
  outcomes: readonly FixtureOutcome[];
  gates: CalibrationGates;
  limitations: readonly string[];
}>;
