/**
 * Behaviour tests for the pure calibration evaluator.
 *
 * All envelopes below are hand-built synthetic Noul payloads: they exist to exercise branch
 * semantics and provenance refusal, and are never presented as live provider output. The fixture
 * labels are synthetic and author-claimed, so no assertion here may claim human review.
 */
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { CalibrationFailure } from './errors';
import { readFixtureFile } from './fixtures';
import { evaluateConfirmation, evaluateRegression, selectThresholds } from './evaluate';
import { SYNTHETIC_RECORDING_PROVENANCE, hashRecording, loadRecordingFile } from './recordings';
import { RECORDING_VERSION, type Fixture, type RecordingFile } from './types';

const FIXTURE_PATH = fileURLToPath(new URL('../../../test/fixtures/rag/phase4/fixtures.json', import.meta.url));
const actualSet = readFixtureFile(FIXTURE_PATH);
// Fake envelopes below test held-out mechanics, not the current seen-data status.
const set = Object.freeze({ ...actualSet, confirmationPurpose: 'heldout' as const });
const MODEL = 'jev-1.13.0';
const development = set.fixtures.filter((fixture) => fixture.split === 'development');
const confirmation = set.fixtures.filter((fixture) => fixture.split === 'confirmation');

const envelope = (model: string, support: number, conflict: number): unknown => ({
  model,
  answers: {
    answerable_from_evidence: { type: 'noul', noul: support },
    has_unresolved_conflict: { type: 'noul', noul: conflict },
  },
  usage: { input_tokens: 900, output_tokens: 20 },
});

/** Gold-aligned synthetic envelope: safe fixtures score high, conflict/insufficient/ambiguous do not. */
const goldEnvelope = (fixture: Fixture, model = MODEL): unknown => {
  if (fixture.category === 'answerable') return envelope(model, 0.96, 0.02);
  if (fixture.category === 'conflict') return envelope(model, 0.9, 0.9);
  if (fixture.category === 'insufficient') return envelope(model, 0.2, 0.02);
  return envelope(model, 0.5, 0.02);
};

const recordingFor = (fixtures: readonly Fixture[], pick: (fixture: Fixture) => unknown = goldEnvelope): RecordingFile =>
  loadRecordingFile({
    recordingVersion: RECORDING_VERSION,
    provenance: SYNTHETIC_RECORDING_PROVENANCE,
    results: fixtures.map((fixture) => ({ fixtureId: fixture.id, status: 'recorded', envelope: pick(fixture) })),
  });

const codeOf = (run: () => unknown): string => {
  try {
    run();
  } catch (error) {
    return error instanceof CalibrationFailure ? error.code : `unexpected:${String(error)}`;
  }
  return 'no-throw';
};

const developmentRecording = recordingFor(development);
const policy = selectThresholds({ fixtureSet: set, recording: developmentRecording, model: MODEL });

test('selectThresholds freezes a development-only policy with unsafe allow 0 and best acceptance', () => {
  assert.equal(Object.isFrozen(policy), true);
  assert.equal(Object.isFrozen(policy.thresholds), true);
  assert.equal(policy.derivedFromSplit, 'development');
  assert.equal(policy.model, MODEL);
  assert.equal(policy.developmentFixtureHash, set.developmentHash);
  assert.equal(policy.confirmationFixtureHash, set.confirmationHash);
  assert.equal(policy.developmentResultsHash, hashRecording(developmentRecording));
  assert.equal(policy.developmentRecordingProvenance, SYNTHETIC_RECORDING_PROVENANCE);
  assert.deepEqual(policy.selection, {
    gridSize: 100, eligibleUnsafeAllowZero: 100, unsafeAllow: 0,
    answerableAllowed: 9, answerableTotal: 9, answerableAllowRate: 1,
    errors: 0, tieBreak: 'max-answerabilityMin-then-min-conflictMax',
  });
  assert.deepEqual(policy.thresholds, { answerabilityMin: 0.95, conflictMax: 0.05 });
  assert.match(policy.policyHash, /^sha256:[0-9a-f]{64}$/);
});

test('selection refuses partial development data, model mixing and an unsafe recording', () => {
  const partial = loadRecordingFile({
    recordingVersion: RECORDING_VERSION, provenance: SYNTHETIC_RECORDING_PROVENANCE,
    results: development.slice(1).map((fixture) => ({ fixtureId: fixture.id, status: 'recorded', envelope: goldEnvelope(fixture) })),
  });
  assert.equal(codeOf(() => selectThresholds({ fixtureSet: set, recording: partial, model: MODEL })), 'RECORDING_INCOMPLETE');
  const mixed = recordingFor(development, (fixture) => goldEnvelope(fixture, fixture.id.endsWith('01') ? 'other-model' : MODEL));
  assert.equal(codeOf(() => selectThresholds({ fixtureSet: set, recording: mixed, model: MODEL })), 'MODEL_MIX');
  const unsafe = recordingFor(development, (fixture) => (fixture.category === 'insufficient' ? envelope(MODEL, 1, 0) : goldEnvelope(fixture)));
  assert.equal(codeOf(() => selectThresholds({ fixtureSet: set, recording: unsafe, model: MODEL })), 'UNSATISFIABLE');
});

test('the confirmation replay passes its gates and reports per-language and per-category outcomes', () => {
  const report = evaluateConfirmation({ fixtureSet: set, recording: recordingFor(confirmation), policy });
  assert.equal(report.split, 'confirmation');
  assert.equal(report.model, MODEL);
  assert.deepEqual(report.thresholds, policy.thresholds);
  assert.equal(report.totals.fixtures, 32);
  assert.equal(report.totals.errors, 0);
  assert.equal(report.totals.unsafeAllow, 0);
  assert.equal(report.totals.answerableAllowRate, 1);
  assert.deepEqual(Object.keys(report.byLanguage).sort(), ['en', 'vi']);
  for (const language of ['vi', 'en'] as const) {
    assert.equal(report.byLanguage[language].answerableTotal, 4);
    assert.equal(report.byLanguage[language].answerableAllowRate, 1);
    assert.equal(report.byLanguage[language].unsafeAllow, 0);
  }
  assert.equal(report.byCategory.conflict.fixtures, 8);
  assert.equal(report.byCategory.insufficient.unsafeAllow, 0);
  assert.deepEqual(report.gates, {
    freshConfirmation: true, unsafeAllowZero: true, answerableAllowAtLeast75: true, recordingsComplete: true,
    perLanguageAnswerableCovered: true, passed: true,
  });
  assert.equal(report.confirmationResultsHash, hashRecording(recordingFor(confirmation)));
  assert.equal(report.confirmationRecordingProvenance, SYNTHETIC_RECORDING_PROVENANCE);
  assert.equal(report.policyHash, policy.policyHash);
  assert.ok(report.limitations.some((line) => line.includes('NOT human-reviewed')));
  assert.equal(JSON.stringify(report).includes('human-reviewed":true'), false);
});

test('a missing or failed recording stays a named error and never becomes a verdict', () => {
  const omitted = confirmation.find((candidate) => candidate.category === 'answerable')!.id;
  const failedId = 'fx-conf-en-ins-01';
  const entries = confirmation.filter((fixture) => fixture.id !== omitted && fixture.id !== failedId);
  const partial = loadRecordingFile({
    recordingVersion: RECORDING_VERSION, provenance: SYNTHETIC_RECORDING_PROVENANCE,
    results: [
      ...entries.map((fixture) => ({ fixtureId: fixture.id, status: 'recorded' as const, envelope: goldEnvelope(fixture) })),
      { fixtureId: failedId, status: 'provider_error' as const, detail: 'HTTP 503 from the provider' },
    ],
  });
  const report = evaluateConfirmation({ fixtureSet: set, recording: partial, policy });
  const missing = report.outcomes.filter((outcome) => outcome.error === 'missing');
  const failed = report.outcomes.filter((outcome) => outcome.error === 'provider_error');
  assert.equal(missing.length, 1);
  assert.equal(failed.length, 1);
  for (const outcome of [...missing, ...failed]) {
    assert.equal(outcome.outcome, 'error');
    assert.equal(outcome.verdict, null);
    assert.equal(outcome.answerableAllowed, false);
    assert.equal(outcome.unsafeAllow, false);
    assert.notEqual(outcome.verdict, 'INSUFFICIENT_EVIDENCE');
    assert.ok((outcome.errorDetail ?? '').length > 0);
  }
  assert.equal(report.totals.errors, 2);
  assert.equal(report.gates.recordingsComplete, false);
  assert.equal(report.gates.passed, false);
  assert.equal(report.outcomes.some((outcome) => outcome.error === null && outcome.verdict === 'ALLOW' && outcome.fixtureId === missing[0]!.fixtureId), false);
});

test('an invalid envelope is reported as invalid_envelope, not scored', () => {
  const bad = recordingFor(confirmation, (fixture) => (fixture.id === confirmation[0]!.id ? envelope(MODEL, 1.5, 0.02) : goldEnvelope(fixture)));
  const report = evaluateConfirmation({ fixtureSet: set, recording: bad, policy });
  const outcome = report.outcomes.find((candidate) => candidate.fixtureId === confirmation[0]!.id)!;
  assert.equal(outcome.error, 'invalid_envelope');
  assert.equal(outcome.verdict, null);
  assert.equal(report.gates.passed, false);
});

test('an ALLOW on evidence that was not safe to answer fails the unsafe-allow gate', () => {
  const unsafe = recordingFor(confirmation, (fixture) => (fixture.category === 'insufficient' ? envelope(MODEL, 1, 0) : goldEnvelope(fixture)));
  const report = evaluateConfirmation({ fixtureSet: set, recording: unsafe, policy });
  assert.ok(report.totals.unsafeAllow >= 1);
  assert.equal(report.gates.unsafeAllowZero, false);
  assert.equal(report.gates.passed, false);
});

test('the answerable acceptance gate is 75%, inclusive, with 8 answerable confirmation fixtures', () => {
  const answerable = confirmation.filter((fixture) => fixture.category === 'answerable');
  const fail = (count: number): RecordingFile =>
    recordingFor(confirmation, (fixture) => (answerable.slice(0, count).includes(fixture) ? envelope(MODEL, 0.1, 0.02) : goldEnvelope(fixture)));
  const atBoundary = evaluateConfirmation({ fixtureSet: set, recording: fail(2), policy });
  assert.equal(atBoundary.totals.answerableAllowed, 6);
  assert.equal(atBoundary.totals.answerableAllowRate, 0.75);
  assert.equal(atBoundary.gates.answerableAllowAtLeast75, true);
  assert.equal(atBoundary.gates.passed, true);
  const belowBoundary = evaluateConfirmation({ fixtureSet: set, recording: fail(3), policy });
  assert.equal(belowBoundary.totals.answerableAllowRate, 0.625);
  assert.equal(belowBoundary.gates.answerableAllowAtLeast75, false);
  assert.equal(belowBoundary.gates.passed, false);
});

test('confirmation cannot retune: it replays frozen thresholds and refuses drifted provenance', () => {
  const other = evaluateConfirmation({
    fixtureSet: set,
    recording: recordingFor(confirmation, (fixture) => envelope(MODEL, 0.3, 0.3)),
    policy,
  });
  assert.deepEqual(other.thresholds, policy.thresholds);
  const loose = JSON.parse(JSON.stringify(policy)) as typeof policy;
  assert.equal(codeOf(() => evaluateConfirmation({ fixtureSet: set, recording: recordingFor(confirmation), policy: loose })), 'POLICY_NOT_FROZEN');
  const confirmationDerived = Object.freeze({ ...policy, derivedFromSplit: 'confirmation' }) as unknown as typeof policy;
  assert.equal(codeOf(() => evaluateConfirmation({ fixtureSet: set, recording: recordingFor(confirmation), policy: confirmationDerived })), 'POLICY_MISMATCH');
  const edited = Object.freeze({ ...policy, confirmationFixtureHash: `sha256:${'a'.repeat(64)}` });
  assert.equal(codeOf(() => evaluateConfirmation({ fixtureSet: set, recording: recordingFor(confirmation), policy: edited })), 'POLICY_MISMATCH');
  const splitLeak = recordingFor([...confirmation.slice(1), development[0]!]);
  assert.equal(codeOf(() => evaluateConfirmation({ fixtureSet: set, recording: splitLeak, policy })), 'SPLIT_DENIED');
});

test('the recording loader refuses malformed or duplicated claims', () => {
  const base = { recordingVersion: RECORDING_VERSION, provenance: SYNTHETIC_RECORDING_PROVENANCE };
  const build = (results: unknown[]): unknown => ({ ...base, results });
  assert.equal(codeOf(() => loadRecordingFile(build([{ fixtureId: 'fx-conf-vi-ans-01', status: 'recorded', envelope: envelope(MODEL, 0.9, 0.1) }]))), 'no-throw');
  assert.equal(codeOf(() => loadRecordingFile(build([{ fixtureId: 'a', status: 'unknown' }]))), 'INVALID_RECORDING');
  assert.equal(codeOf(() => loadRecordingFile(build([
    { fixtureId: 'a', status: 'missing', detail: 'x' }, { fixtureId: 'a', status: 'missing', detail: 'y' },
  ]))), 'INVALID_RECORDING');
  assert.equal(codeOf(() => loadRecordingFile(build([{ fixtureId: 'a', status: 'missing', detail: 'x', extra: 1 }]))), 'INVALID_RECORDING');
  assert.equal(codeOf(() => loadRecordingFile({ ...base, provenance: '  ', results: [] })), 'INVALID_RECORDING');
});

 test('seen confirmation never becomes a fresh approval even when regression metrics pass',()=>{
 const seenSet=Object.freeze({...actualSet,confirmationPurpose:'regression-only' as const});
 const frozen=selectThresholds({fixtureSet:seenSet,recording:developmentRecording,model:MODEL});
 const recorded=recordingFor(confirmation);
 assert.equal(codeOf(()=>evaluateConfirmation({fixtureSet:seenSet,recording:recorded,policy:frozen})),'SPLIT_DENIED');
 const regression=evaluateRegression({fixtureSet:seenSet,recording:recorded,policy:frozen});
 assert.equal(regression.split,'regression');assert.equal(regression.gates.freshConfirmation,false);
 assert.equal(regression.gates.passed,false);assert.equal(regression.totals.answerableAllowRate,1);
 });
