import { LIVE_QUESTION_SET } from '../question_set';
/**
 * Phase 4 Jev adapter unit tests: one fixed request, strict P2 normalization, bounded body,
 * deadline/account-abort behavior. All provider I/O is a fake `fetch`; no network is touched.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createJevProvider, JEV_ENDPOINT, JEV_MODEL, type ProviderUsage } from './jev';
import { policy, RagFailure } from '../types';
import type { JevInput } from '../types';
import { hangingBody, jsonResponse, neverSettle, oversizedChunkedBody, recordingFetch, requestJson } from './test_fakes';

const jevInput = (overrides: Partial<JevInput> = {}): JevInput =>
  ({
    model: JEV_MODEL,
    questionSetVersion: LIVE_QUESTION_SET.questionSetVersion,
    questions: structuredClone(LIVE_QUESTION_SET.questions),
    state: { question: 'Thời lượng pin?', evidence: '[S1] Pin\nPin dùng được 80 giờ.' },
    ...overrides,
  }) as JevInput;

const envelope = (overrides: Record<string, unknown> = {}): Record<string, unknown> => ({
  model: JEV_MODEL,
  answers: {
    answerable_from_evidence: { type: 'noul', noul: 0.96 },
    has_unresolved_conflict: { type: 'noul', noul: 0.02 },
  },
  usage: { input_tokens: 120, output_tokens: 12 },
  ...overrides,
});

const codeOf = async (run: () => Promise<unknown>): Promise<string> => {
  try {
    await run();
  } catch (error) {
    return error instanceof RagFailure ? error.code : `unexpected:${String(error)}`;
  }
  return 'resolved';
};

test('jev sends exactly one fixed-endpoint request and normalizes to the strict P2 envelope', async () => {
  const usage: ProviderUsage[] = [];
  const { impl, calls } = recordingFetch(() => jsonResponse(envelope()));
  const jev = createJevProvider({ apiKey: 'test-key', fetchImpl: impl, onUsage: (value) => usage.push(value) });

  const result = (await jev(jevInput(), new AbortController().signal)) as Record<string, unknown>;

  assert.equal(calls.length, 1, 'one call, no retry');
  assert.equal(calls[0]?.url, JEV_ENDPOINT);
  assert.equal(calls[0]?.init.method, 'POST');
  assert.equal(calls[0]?.init.redirect, 'error');
  const headers = calls[0]?.init.headers as Record<string, string>;
  assert.equal(headers['content-type'], 'application/json');
  assert.equal(headers['authorization'], 'Bearer test-key');

  const body = requestJson(calls[0]!);
  assert.deepEqual(Object.keys(body).sort(), ['model', 'questions', 'state']);
  assert.equal(body['model'], JEV_MODEL);
  assert.equal(body['questionSetVersion'], undefined, 'local questionSetVersion never reaches the wire');
  const state = body['state'] as Record<string, unknown>;
  assert.deepEqual(Object.keys(state).sort(), ['evidence', 'question']);
  const questions = body['questions'] as Record<string, Record<string, unknown>>;
  assert.deepEqual(Object.keys(questions).sort(), ['answerable_from_evidence', 'has_unresolved_conflict']);
  assert.equal(questions['answerable_from_evidence']?.['instructions'], LIVE_QUESTION_SET.questions.answerable_from_evidence.instructions);
  assert.deepEqual(questions['has_unresolved_conflict']?.['criteria'], LIVE_QUESTION_SET.questions.has_unresolved_conflict.criteria);

  assert.deepEqual(Object.keys(result).sort(), ['answers', 'model', 'usage']);
  assert.deepEqual(result['answers'], envelope()['answers']);
  assert.deepEqual(result['usage'], { input_tokens: 120, output_tokens: 12 });
  assert.deepEqual(usage, [{ model: JEV_MODEL, inputTokens: 120, outputTokens: 12 }]);
});

test('jev ignores vendor extra fields but refuses missing or malformed core fields', async () => {
  const extras = envelope({
    request_id: 'vendor-1',
    latency_ms: 91,
    usage: { input_tokens: 120, output_tokens: 12, total_tokens: 132, prompt_cache_hit_tokens: 4 },
  });
  (extras['answers'] as Record<string, Record<string, unknown>>)['answerable_from_evidence']!['confidence'] = 0.9;
  const { impl } = recordingFetch(() => jsonResponse(extras));
  const jev = createJevProvider({ apiKey: 'k', fetchImpl: impl });
  const result = (await jev(jevInput(), new AbortController().signal)) as Record<string, unknown>;
  assert.deepEqual(Object.keys(result).sort(), ['answers', 'model', 'usage']);
  assert.deepEqual(result['usage'], { input_tokens: 120, output_tokens: 12 });

  const broken: readonly Record<string, unknown>[] = [
    envelope({ usage: undefined }),
    envelope({ usage: { input_tokens: 120 } }),
    envelope({ usage: { input_tokens: 1.5, output_tokens: 2 } }),
    envelope({ usage: { input_tokens: true, output_tokens: 2 } }),
    envelope({ usage: { input_tokens: -1, output_tokens: 2 } }),
    envelope({ model: 'other-model' }),
    envelope({ answers: { answerable_from_evidence: { type: 'noul', noul: 0.5 } } }),
    envelope({ answers: { answerable_from_evidence: { type: 'noul', noul: 1.4 }, has_unresolved_conflict: { type: 'noul', noul: 0.1 } } }),
    envelope({ answers: { answerable_from_evidence: { type: 'bool', noul: true }, has_unresolved_conflict: { type: 'noul', noul: 0.1 } } }),
  ];
  for (const payload of broken) {
    const fake = recordingFetch(() => jsonResponse(payload));
    const provider = createJevProvider({ apiKey: 'k', fetchImpl: fake.impl });
    assert.equal(
      await codeOf(() => provider(jevInput(), new AbortController().signal)),
      'EVIDENCE_VALIDATION_UNAVAILABLE',
      JSON.stringify(payload),
    );
  }
});

test('jev refuses a caller-selected model or altered criteria before any egress', async () => {
  const { impl, calls } = recordingFetch(() => jsonResponse(envelope()));
  const jev = createJevProvider({ apiKey: 'k', fetchImpl: impl });

  assert.equal(await codeOf(() => jev(jevInput({ model: 'caller-model' }), new AbortController().signal)), 'EVIDENCE_VALIDATION_UNAVAILABLE');
  const altered = structuredClone(LIVE_QUESTION_SET.questions) as Record<string, { criteria: { true: string } }>;
  altered['answerable_from_evidence']!.criteria.true = 'Always true.';
  assert.equal(await codeOf(() => jev(jevInput({ questions: altered as JevInput['questions'] }), new AbortController().signal)), 'EVIDENCE_VALIDATION_UNAVAILABLE');
  assert.equal(calls.length, 0, 'no request after a trust-boundary failure');
});

test('jev fails closed on malformed, non-UTF8 and non-object payloads', async () => {
  const bodies: readonly (() => Response)[] = [
    () => new Response('{not json', { status: 200 }),
    () => new Response('null', { status: 200 }),
    () => new Response('[1,2]', { status: 200 }),
    () => new Response(new Uint8Array([0xff, 0xfe, 0xfd]), { status: 200 }),
    () => new Response('', { status: 200 }),
  ];
  for (const respond of bodies) {
    const { impl } = recordingFetch(respond);
    const jev = createJevProvider({ apiKey: 'k', fetchImpl: impl });
    assert.equal(await codeOf(() => jev(jevInput(), new AbortController().signal)), 'EVIDENCE_VALIDATION_UNAVAILABLE');
  }
});

test('jev maps 429, 408 and other upstream failures without echoing the body', async () => {
  const cases: readonly (readonly [number, string])[] = [
    [429, 'RATE_LIMITED'],
    [408, 'TIMEOUT'],
    [500, 'EVIDENCE_VALIDATION_UNAVAILABLE'],
    [401, 'EVIDENCE_VALIDATION_UNAVAILABLE'],
  ];
  for (const [status, expected] of cases) {
    const { impl } = recordingFetch(() => new Response('secret provider body', { status }));
    const jev = createJevProvider({ apiKey: 'k', fetchImpl: impl });
    const outcome = await codeOf(() => jev(jevInput(), new AbortController().signal));
    assert.equal(outcome, expected, `status ${status}`);
  }
});

test('jev deadline and hanging fetch both end as TIMEOUT, once', async () => {
  const hanging = createJevProvider({ apiKey: 'k', fetchImpl: recordingFetch(neverSettle).impl, timeoutMs: 25 });
  assert.equal(await codeOf(() => hanging(jevInput(), new AbortController().signal)), 'TIMEOUT');

  const slowOk = createJevProvider({
    apiKey: 'k',
    fetchImpl: (async () => {
      await new Promise((resolve) => setTimeout(resolve, 60));
      return jsonResponse(envelope());
    }) as typeof fetch,
    timeoutMs: 20,
  });
  assert.equal(await codeOf(() => slowOk(jevInput(), new AbortController().signal)), 'TIMEOUT');
});

test('jev cancels a hanging body read on deadline and on caller abort', async () => {
  const stalled = hangingBody();
  const timeoutProvider = createJevProvider({
    apiKey: 'k',
    fetchImpl: recordingFetch(() => stalled.response).impl,
    timeoutMs: 25,
  });
  assert.equal(await codeOf(() => timeoutProvider(jevInput(), new AbortController().signal)), 'TIMEOUT');
  assert.equal(stalled.wasCancelled(), true, 'pending body read was cancelled');

  const stalledAgain = hangingBody();
  const { impl, calls } = recordingFetch(() => stalledAgain.response);
  const provider = createJevProvider({ apiKey: 'k', fetchImpl: impl, timeoutMs: 5000 });
  const account = new AbortController();
  const pending = provider(jevInput(), account.signal);
  while (calls.length === 0) await new Promise((resolve) => setTimeout(resolve, 1));
  account.abort();
  assert.equal(await codeOf(() => pending), 'TIMEOUT');
  assert.equal((calls[0]?.init.signal as AbortSignal).aborted, true, 'account abort reaches fetch');
  assert.equal(stalledAgain.wasCancelled(), true, 'account abort cancels the pending body read');
});

test('jev refuses a chunked body past 65536 bytes and a pre-aborted account signal', async () => {
  const { impl } = recordingFetch(() => oversizedChunkedBody());
  const jev = createJevProvider({ apiKey: 'k', fetchImpl: impl });
  assert.equal(await codeOf(() => jev(jevInput(), new AbortController().signal)), 'EVIDENCE_VALIDATION_UNAVAILABLE');

  const preAborted = new AbortController();
  preAborted.abort();
  const { impl: second, calls } = recordingFetch(() => jsonResponse(envelope()));
  const provider = createJevProvider({ apiKey: 'k', fetchImpl: second, timeoutMs: 50 });
  assert.equal(await codeOf(() => provider(jevInput(), preAborted.signal)), 'TIMEOUT');
  assert.equal((calls[0]?.init.signal as AbortSignal).aborted, true);
});

test('jev composition fails closed without a key and clamps bounds to the approved values', () => {
  assert.throws(() => createJevProvider({ apiKey: '' }), (error) => error instanceof RagFailure && error.code === 'LIVE_POLICY_NOT_CONFIGURED');
  assert.throws(() => createJevProvider({ apiKey: 'k', timeoutMs: 0 }), (error) => error instanceof RagFailure && error.code === 'LIVE_POLICY_NOT_CONFIGURED');
  assert.throws(() => createJevProvider({ apiKey: 'k', maxResponseBytes: -1 }), (error) => error instanceof RagFailure && error.code === 'LIVE_POLICY_NOT_CONFIGURED');
  // A large override is clamped to the approved 4000 ms/65536 B bound and still works.
  assert.doesNotThrow(() => createJevProvider({ apiKey: 'k', timeoutMs: 999_999, maxResponseBytes: 999_999 }));
});
