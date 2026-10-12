import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createPrivateHandler } from './private_handler';
import { RagFailure } from './types';
import type { LiveApproval } from './live_policy';

const source = { sourceId: 'S1', noteId: 'synthetic', revision: 1, title: 'SYNTHETIC', startOffset: 0, endOffset: 8, quote: '80 hours' };
const fixture = { id: 'fx-1', question: 'How long?', evidence: { sources: [source], text: '[S1] SYNTHETIC\n80 hours' } };
const approval: LiveApproval = Object.freeze({ model: 'jev-1.13.0', thresholds: Object.freeze({ answerabilityMin: .9, conflictMax: .1 }),
  fixtureVersion: 'synthetic', calibrationVersion: 'synthetic', retrievalStageMs: 6000 });
const code = (value: unknown) => value && typeof value === 'object' && 'code' in value ? value.code : undefined;
function setup(support = .99, conflict = .01) {
  const calls: string[] = [];
  const jev = { model: 'jev-1.13.0', answers: { answerable_from_evidence: { type: 'noul', noul: support },
    has_unresolved_conflict: { type: 'noul', noul: conflict } }, usage: { input_tokens: 10, output_tokens: 2 } };
  const deps = { fixture: (id: string) => id === fixture.id ? fixture : undefined,
    providers: { jev: async () => { calls.push('jev'); return jev; }, generate: async () => { calls.push('generate'); return { answer: '80 hours [S1]', sources: [source] }; } },
    usage: [], budget: { reserve: async (provider: string) => { calls.push(`reserve:${provider}`); }, read: async () => ({}) },
    approval: async () => approval, countOutput: (text: string) => text.length,
    query: async () => ({ wireVersion: 1 as const, requestId: 'r', status: 'ERROR' as const, code: 'INDEX_NOT_READY' as const }) };
  return { deps, calls, run: createPrivateHandler(deps) };
}

test('calibration accepts bundled fixture IDs only; cannot send authored evidence or generate', async () => {
  const { run, calls } = setup();
  assert.equal((await run({ operation: 'jev-fixture', fixtureId: fixture.id })).status, 'EVALUATED');
  assert.deepEqual(calls, ['reserve:jev', 'jev']);
  assert.equal((await run({ operation: 'jev-fixture', fixtureId: fixture.id, evidence: 'foreign' })).status, 'ERROR');
  assert.equal((await run({ operation: 'jev-fixture', fixtureId: 'foreign' })).status, 'ERROR');
  assert.equal(calls.length, 2);
});

test('calibrated allowance reserves each provider before call and preserves evidence sources', async () => {
  const { run, calls } = setup();
  const result = await run({ operation: 'answer-fixture', fixtureId: fixture.id });
  assert.equal(result.status, 'ANSWERED');
  assert.deepEqual(calls, ['reserve:jev', 'jev', 'reserve:deepseek', 'generate']);
  assert.deepEqual('sources' in result ? result.sources : [], [source]);
});

test('all non-allow branches have zero generation reservations/calls; provider failure is separate', async () => {
  for (const [support, conflict] of [[.01, .01], [.99, .99], [.6, .01]]) {
    const { run, calls } = setup(support, conflict);
    assert.equal((await run({ operation: 'answer-fixture', fixtureId: fixture.id })).status, 'NOT_ENOUGH_CONTEXT');
    assert.deepEqual(calls, ['reserve:jev', 'jev']);
  }
  const { deps, calls } = setup();
  deps.providers.jev = async () => { throw new RagFailure('EVIDENCE_VALIDATION_UNAVAILABLE'); };
  assert.equal(code(await createPrivateHandler(deps)({ operation: 'answer-fixture', fixtureId: fixture.id })), 'EVIDENCE_VALIDATION_UNAVAILABLE');
  assert.deepEqual(calls, ['reserve:jev']);
});

test('uncalibrated answer and non-synthetic owner cannot start a provider', async () => {
  const { deps, calls } = setup();
  deps.approval = async () => { throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED'); };
  const run = createPrivateHandler(deps);
  assert.equal(code(await run({ operation: 'answer-fixture', fixtureId: fixture.id })), 'LIVE_POLICY_NOT_CONFIGURED');
  assert.equal(code(await run({ operation: 'query', ownerId: 'actual-user', body: '{}', requestId: 'r' })), 'INVALID_INPUT');
  assert.equal(calls.length, 0);
});
