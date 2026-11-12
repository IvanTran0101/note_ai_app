import { createHash } from 'node:crypto';
import { buildJevRequestBody, JEV_MODEL } from '../providers/jev';
import { LIVE_QUESTION_SET, LIVE_RECORDING_PROVENANCE } from '../question_set';
import { validateNoul } from '../contract';
import { fail } from './errors';
import { loadRecordingFile } from './recordings';
import type { Fixture, RecordingFile } from './types';

const inputHash = (fixture: Fixture): string => createHash('sha256').update(buildJevRequestBody({
  model: JEV_MODEL, questionSetVersion: LIVE_QUESTION_SET.questionSetVersion,
  questions: LIVE_QUESTION_SET.questions, state: { question: fixture.question, evidence: fixture.evidence.text },
})).digest('hex');

/** A gold/ID correction may reuse probabilities only for the byte-identical provider input. */
export function reuseUnchangedInputs(recording: RecordingFile, before: readonly Fixture[], after: readonly Fixture[], renames: Readonly<Record<string, string>>) {
  const source = loadRecordingFile(recording);
  if (source.provenance !== LIVE_RECORDING_PROVENANCE) fail('RECORDING_REUSE_DENIED', 'model/question-set provenance changed');
  const old = new Map(before.map(f => [f.id, f]));
  const next = new Map(after.map(f => [f.id, f]));
  if (old.size !== before.length || next.size !== after.length || old.size !== next.size) {
    fail('RECORDING_REUSE_DENIED', 'fixture identities/counts differ beyond a relabel');
  }
  const targets = new Set<string>();
  const proofs = before.map(f => {
    const id = renames[f.id] ?? f.id;
    const corrected = next.get(id);
    if (!corrected || targets.has(id) || f.split !== corrected.split) fail('RECORDING_REUSE_DENIED', 'rename is missing, duplicated or crosses a split');
    targets.add(id);
    const beforeHash = inputHash(f);
    const afterHash = inputHash(corrected);
    if (beforeHash !== afterHash) fail('RECORDING_REUSE_DENIED', 'question/evidence/provider payload changed');
    return { originalFixtureId: f.id, fixtureId: id, beforeHash, afterHash };
  });
  const results = source.results.map(row => {
    if (!old.has(row.fixtureId)) fail('RECORDING_REUSE_DENIED', 'recording is outside the approved split');
    if (row.status === 'recorded') validateNoul(row.envelope, JEV_MODEL);
    return { ...row, fixtureId: renames[row.fixtureId] ?? row.fixtureId };
  });
  return { recording: loadRecordingFile({ ...source, results }), proofs };
}
