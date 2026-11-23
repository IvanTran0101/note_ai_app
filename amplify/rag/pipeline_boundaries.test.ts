import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createMockRuntime } from './mock';
import { createQuery } from './pipeline';
import { parseRequest } from './contract';

const request = () => parseRequest(JSON.stringify({ wireVersion: 1, question: 'SLGH031?',
  scope: { type: 'note', noteId: 'n-watch' } }));

test('mock flow completes with global fetch blocked: no outbound RAG provider request', async () => {
  const runtime = createMockRuntime();
  const fetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async () => { calls++; throw Error('outbound blocked'); };
  try {
    const result = await createQuery(runtime.deps)('actor-a', request(), 'mock-network');
    assert.equal(result.status, 'ANSWERED');
    assert.equal(calls, 0);
    assert.equal(runtime.counts.generation, 1);
  } finally { globalThis.fetch = fetch; }
});
test('fully configured live mode still cannot bypass the globally disabled live policy', async () => {
  const runtime = createMockRuntime();
  const query = createQuery({ ...runtime.deps, config: { ...runtime.deps.config, mode: 'live',
    model: 'jev-configured-but-not-approved', thresholds: { answerabilityMin: .9, conflictMax: .1 } } });
  const result = await query('actor-a', request(), 'mock-live-block');
  assert.equal(result.status === 'ERROR' && result.code, 'LIVE_POLICY_NOT_CONFIGURED');
  assert.equal(runtime.counts.embedding, 0);
  assert.equal(runtime.counts.jev, 0);
  assert.equal(runtime.counts.generation, 0);
});
test('revocation after the Jev verdict prevents generation instead of reusing the old permit', async () => {
  const runtime = createMockRuntime();
  const query = createQuery({ ...runtime.deps, providers: { ...runtime.deps.providers,
    async jev(input, signal) {
      const result = await runtime.deps.providers.jev(input, signal);
      const state = runtime.store.states.get('actor-a')!;
      runtime.store.states.set('actor-a', { ...state, consent: { ...state.consent, accepted: false,
        generation: state.consent.generation + 1 } });
      return result;
    },
  } });
  const result = await query('actor-a', request(), 'mock-revoke');
  assert.equal(result.status === 'ERROR' && result.code, 'CONSENT_REQUIRED');
  assert.equal(runtime.counts.generation, 0);
});
test('session changes during generation block answer release', async () => {
  const runtime = createMockRuntime();
  const query = createQuery({ ...runtime.deps, providers: { ...runtime.deps.providers,
    async generate(input, signal) {
      const result = await runtime.deps.providers.generate(input, signal);
      const state = runtime.store.states.get('actor-a')!;
      runtime.store.states.set('actor-a', { ...state, sessionGeneration: state.sessionGeneration + 1 });
      return result;
    },
  } });
  const result = await query('actor-a', request(), 'mock-session');
  assert.equal(result.status === 'ERROR' && result.code, 'SOURCE_CHANGED');
  assert.equal('answer' in result, false);
});
test('revocation after vector search prevents the next retrieval stage', async () => {
  const runtime = createMockRuntime();
  const query = createQuery({ ...runtime.deps, retrieval: { ...runtime.deps.retrieval,
    async vectorSearch(vector, context) {
      const result = await runtime.deps.retrieval.vectorSearch(vector, context);
      const state = runtime.store.states.get('actor-a')!;
      runtime.store.states.set('actor-a', { ...state, consent: { ...state.consent, accepted: false } });
      return result;
    },
  } });
  const result = await query('actor-a', request(), 'mock-retrieval-revoke');
  assert.equal(result.status === 'ERROR' && result.code, 'CONSENT_REQUIRED');
  assert.equal(runtime.counts.keyword, 0);
});
test('closing one concurrent query never cancels the other query signal', async () => {
  const runtime = createMockRuntime();
  const signals: AbortSignal[] = [];
  const waiting: (() => void)[] = [];
  const query = createQuery({ ...runtime.deps, providers: { ...runtime.deps.providers,
    async generate(input, signal) {
      signals.push(signal);
      await new Promise<void>(resolve => {
        waiting.push(resolve);
        if (waiting.length === 2) waiting[0]();
      });
      return runtime.deps.providers.generate(input, signal);
    },
  } });
  const first = query('actor-a', request(), 'mock-concurrent-1');
  const second = query('actor-a', request(), 'mock-concurrent-2');
  const doneFirst = await first;
  assert.equal(doneFirst.status, 'ANSWERED');
  assert.equal(signals[0].aborted, true);
  assert.equal(signals[1].aborted, false);
  assert.notEqual(signals[0], signals[1]);
  waiting[1]();
  assert.equal((await second).status, 'ANSWERED');
});
