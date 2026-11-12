/**
 * Self-hosted EmbeddingGemma-2 port tests: fixed endpoint/headers, batch=1, bounded streaming
 * response, strict 768-dimension finite/non-zero/normalized output, caller-linked deadlines and
 * no-retry failure mapping. All I/O is an injected fake; no provider or network is contacted.
 * Runner: node --import tsx --test amplify/rag/indexing/self_hosted_embedding.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { RagFailure, type Counter } from '../types';
import { IndexFailure } from './types';
import {
  SELF_HOSTED_EMBEDDING_DIMENSIONS,
  SELF_HOSTED_EMBEDDING_ENCODING_FORMAT,
  SELF_HOSTED_EMBEDDING_ENDPOINT,
  SELF_HOSTED_EMBEDDING_MODEL,
  SELF_HOSTED_INDEX_TIMEOUT_MS,
  SELF_HOSTED_QUERY_TIMEOUT_MS,
  createSelfHostedEmbedding,
} from './self_hosted_embedding';
import {
  hangingBody,
  jsonResponse,
  oversizedChunkedBody,
  recordingFetch,
  requestJson,
} from '../providers/test_fakes';

const SIGNAL = new AbortController().signal;
const COUNTER: Counter = (text) => text.length;
const CONFIG = Object.freeze({ clientId: 'cf-id', clientSecret: 'cf-secret' });

const vector = (head: readonly number[] = []): number[] => {
  const values = new Array<number>(SELF_HOSTED_EMBEDDING_DIMENSIONS).fill(0);
  head.forEach((value, index) => { values[index] = value; });
  return values;
};

const payload = (embedding: unknown, index: unknown = 0): Record<string, unknown> => ({
  data: [{ index, embedding }],
});

const failureOf = async (run: () => Promise<unknown>): Promise<IndexFailure> => {
  try {
    await run();
  } catch (error) {
    assert.ok(error instanceof IndexFailure, `expected IndexFailure, got ${String(error)}`);
    return error;
  }
  throw new Error('expected the call to fail');
};

const headersOf = (call: Readonly<{ init: RequestInit }>): Headers => new Headers(call.init.headers);

test('one POST to the fixed endpoint carries CF Access headers and returns one normalized 768-dim vector', async () => {
  const io = recordingFetch(() => jsonResponse(payload(vector([3, 4]))));
  const embedding = createSelfHostedEmbedding(CONFIG, COUNTER, io.impl);
  assert.equal(embedding.count, COUNTER);
  assert.equal(SELF_HOSTED_EMBEDDING_ENDPOINT, 'https://embedding-noteflow.trananhminh.uk/v1/embeddings');
  assert.equal(SELF_HOSTED_EMBEDDING_DIMENSIONS, 768);
  assert.equal(SELF_HOSTED_EMBEDDING_MODEL, 'embeddinggemma2');
  assert.equal(SELF_HOSTED_EMBEDDING_ENCODING_FORMAT, 'float');
  assert.equal(SELF_HOSTED_QUERY_TIMEOUT_MS, 3000);
  assert.equal(SELF_HOSTED_INDEX_TIMEOUT_MS, 10000);

  const produced = await embedding.embed(['alpha'], 'search_document', SIGNAL);
  assert.equal(io.calls.length, 1);
  const call = io.calls[0]!;
  assert.equal(call.url, SELF_HOSTED_EMBEDDING_ENDPOINT);
  assert.equal(call.init.method, 'POST');
  assert.equal(call.init.redirect, 'error');
  assert.ok(call.init.signal instanceof AbortSignal);
  const headers = headersOf(call);
  assert.equal(headers.get('content-type'), 'application/json');
  assert.equal(headers.get('CF-Access-Client-Id'), CONFIG.clientId);
  assert.equal(headers.get('CF-Access-Client-Secret'), CONFIG.clientSecret);
  assert.deepEqual(requestJson(call), {
    model: 'embeddinggemma2',
    input: ['alpha'],
    encoding_format: 'float',
  });

  assert.equal(produced.length, 1);
  assert.equal(produced[0].length, 768);
  assert.ok(Math.abs(produced[0][0] - 0.6) < 1e-12);
  assert.ok(Math.abs(produced[0][1] - 0.8) < 1e-12);
  assert.ok(Math.abs(Math.hypot(...produced[0]) - 1) < 1e-12);
  assert.ok(Object.isFrozen(produced) && Object.isFrozen(produced[0]));
  assert.deepEqual(Object.keys(embedding), ['count', 'embed']);
  assert.equal('reserveEmbedding' in embedding, false);
});

test('a query embeds exactly one text and batch>1 is refused before any fetch', async () => {
  const io = recordingFetch(() => jsonResponse(payload(vector([1]))));
  const embedding = createSelfHostedEmbedding(CONFIG, COUNTER, io.impl);
  await embedding.embed(['question?'], 'search_query', SIGNAL);
  assert.deepEqual(requestJson(io.calls[0]!), {
    model: 'embeddinggemma2',
    input: ['question?'],
    encoding_format: 'float',
  });

  for (const texts of [[], ['a', 'b'], 'not-an-array' as unknown as string[]]) {
    const error = await failureOf(() => embedding.embed(texts, 'search_document', SIGNAL));
    assert.equal(error.code, 'INVALID_INPUT');
  }
  const purpose = await failureOf(() =>
    embedding.embed(['x'], 'search_document ' as 'search_document', SIGNAL));
  assert.equal(purpose.code, 'INVALID_INPUT');
  assert.equal(io.calls.length, 1);
});

test('a valid envelope is accepted with or without a response model display field', async () => {
  // The request pins `model`; the response `model` is a display echo whose exact value is not a
  // pinned operational identity. Rejecting a valid envelope for this field would break indexing.
  const envelopes: readonly Record<string, unknown>[] = [
    payload(vector([1])),
    { model: 'embeddinggemma2', ...payload(vector([1])) },
    { model: 'embeddinggemma-2-Q8_0.gguf', ...payload(vector([1])) },
  ];
  for (const [index, reply] of envelopes.entries()) {
    const io = recordingFetch(() => jsonResponse(reply));
    const embedding = createSelfHostedEmbedding(CONFIG, COUNTER, io.impl);
    const produced = await embedding.embed(['alpha'], 'search_document', SIGNAL);
    assert.deepEqual([produced.length, produced[0].length], [1, 768], `envelope ${index}`);
    assert.equal(io.calls.length, 1);
  }
});

test('bad texts and a broken counter fail closed without a fetch', async () => {
  const io = recordingFetch(() => jsonResponse(payload(vector([1]))));
  const embedding = createSelfHostedEmbedding(CONFIG, COUNTER, io.impl);
  for (const text of [42, '', '\ud800', null]) {
    const error = await failureOf(() =>
      embedding.embed([text as unknown as string], 'search_document', SIGNAL));
    assert.equal(error.code, 'INVALID_INPUT');
  }
  for (const broken of [() => -1, () => Number.NaN, () => { throw new Error('tokenizer'); }]) {
    const guarded = createSelfHostedEmbedding(CONFIG, broken as Counter, io.impl);
    await assert.rejects(
      () => guarded.embed(['x'], 'search_document', SIGNAL),
      (error: unknown) =>
        error instanceof RagFailure && error.code === 'EVIDENCE_VALIDATION_UNAVAILABLE',
    );
  }
  assert.equal(io.calls.length, 0);
});

test('the injected counter bounds both the 2048-character and 512-token caps', async () => {
  const io = recordingFetch(() => jsonResponse(payload(vector([1]))));
  const embedding = createSelfHostedEmbedding(CONFIG, COUNTER, io.impl);

  await embedding.embed(['b'.repeat(512)], 'search_document', SIGNAL);
  const overToken = await failureOf(() => embedding.embed(['c'.repeat(513)], 'search_document', SIGNAL));
  assert.deepEqual([overToken.code, overToken.retryable], ['INPUT_TOO_LONG', false]);

  const charIo = recordingFetch(() => jsonResponse(payload(vector([1]))));
  const charOnly = createSelfHostedEmbedding(CONFIG, () => 0, charIo.impl);
  await charOnly.embed(['a'.repeat(2048)], 'search_document', SIGNAL);
  const charOver = await failureOf(() => charOnly.embed(['a'.repeat(2049)], 'search_document', SIGNAL));
  assert.equal(charOver.code, 'INPUT_TOO_LONG');
  await charOnly.embed(['😀'.repeat(2048)], 'search_document', SIGNAL);
  const astralOver = await failureOf(() => charOnly.embed(['😀'.repeat(2049)], 'search_document', SIGNAL));
  assert.equal(astralOver.code, 'INPUT_TOO_LONG');
  assert.equal(io.calls.length, 1);
  assert.equal(charIo.calls.length, 2);
});

test('the response must be exactly data[0], index 0, one finite non-zero 768-dim embedding', async () => {
  const bad: readonly (readonly [string, unknown])[] = [
    ['missing envelope', null],
    ['missing data', {}],
    ['data not an array', { data: {} }],
    ['empty data', { data: [] }],
    ['two entries', { data: [{ index: 0, embedding: vector([1]) }, { index: 1, embedding: vector([1]) }] }],
    ['entry not an object', { data: [[]] }],
    ['missing index', { data: [{ embedding: vector([1]) }] }],
    ['index one', payload(vector([1]), 1)],
    ['index string', payload(vector([1]), '0')],
    ['767 dimensions', payload(vector([1]).slice(0, 767))],
    ['769 dimensions', payload([...vector([1]), 0])],
    ['string component', payload(vector([1]).map((value, index) => (index === 3 ? 'x' : value)))],
    ['null component', payload(vector([1]).map((value, index) => (index === 3 ? null : value)))],
    ['null vector', payload(null)],
    ['zero vector', payload(new Array<number>(768).fill(0))],
  ];
  for (const [label, reply] of bad) {
    const io = recordingFetch(() => jsonResponse(reply));
    const embedding = createSelfHostedEmbedding(CONFIG, COUNTER, io.impl);
    const error = await failureOf(() => embedding.embed(['a'], 'search_document', SIGNAL));
    assert.deepEqual([error.code, error.retryable], ['INVALID_PROVIDER_OUTPUT', false], label);
    assert.equal(io.calls.length, 1, label);
  }
});

test('HTTP statuses map to terminal or replayable codes without a retry', async () => {
  const cases: readonly (readonly [number, string, boolean])[] = [
    [400, 'PROVIDER_UNAVAILABLE', false],
    [401, 'UNAUTHORIZED', false],
    [403, 'UNAUTHORIZED', false],
    [404, 'PROVIDER_UNAVAILABLE', false],
    [408, 'TIMEOUT', true],
    [429, 'RATE_LIMITED', true],
    [500, 'PROVIDER_UNAVAILABLE', true],
    [503, 'PROVIDER_UNAVAILABLE', true],
  ];
  for (const [status, code, retryable] of cases) {
    const io = recordingFetch(() => new Response('{}', { status }));
    const embedding = createSelfHostedEmbedding(CONFIG, COUNTER, io.impl);
    const error = await failureOf(() => embedding.embed(['a'], 'search_document', SIGNAL));
    assert.deepEqual([error.code, error.retryable], [code, retryable], String(status));
    assert.equal(error.message, code);
    assert.equal(error.message.includes(CONFIG.clientSecret), false);
    assert.equal(io.calls.length, 1, 'no retry');
  }
});

test('malformed, non-UTF8, empty and oversized bodies fail closed', async () => {
  const responses: readonly (readonly [string, () => Response])[] = [
    ['HTML', () => new Response('<html>bad gateway</html>', { status: 200 })],
    ['empty', () => new Response(null, { status: 200 })],
    ['invalid UTF-8', () => new Response(new Uint8Array([0xff, 0xfe]), { status: 200 })],
    ['declared oversized', () =>
      new Response('{}', { status: 200, headers: { 'content-length': '65537' } })],
    ['streamed oversized', oversizedChunkedBody],
  ];
  for (const [label, response] of responses) {
    const io = recordingFetch(response);
    const embedding = createSelfHostedEmbedding(CONFIG, COUNTER, io.impl);
    const error = await failureOf(() => embedding.embed(['a'], 'search_document', SIGNAL));
    assert.deepEqual([error.code, error.retryable], ['INVALID_PROVIDER_OUTPUT', false], label);
  }

  const network = recordingFetch(() => { throw new TypeError('fetch failed'); });
  const error = await failureOf(() =>
    createSelfHostedEmbedding(CONFIG, COUNTER, network.impl).embed(['a'], 'search_document', SIGNAL));
  assert.deepEqual([error.code, error.retryable], ['PROVIDER_UNAVAILABLE', false]);
  assert.equal(network.calls.length, 1, 'no retry');
});

test('beforeDispatch runs once immediately before fetch and its typed refusal is preserved', async () => {
  const order: string[] = [];
  const io = recordingFetch(() => {
    order.push('fetch');
    return jsonResponse(payload(vector([1])));
  });
  const embedding = createSelfHostedEmbedding(CONFIG, COUNTER, io.impl);
  await embedding.embed(['alpha'], 'search_document', SIGNAL, async () => { order.push('before'); });
  assert.deepEqual(order, ['before', 'fetch']);

  const refused = new IndexFailure('SOURCE_CHANGED', false);
  const refusal = await failureOf(() =>
    embedding.embed(['alpha'], 'search_document', SIGNAL, async () => { throw refused; }));
  assert.equal(refusal, refused);
  assert.equal(io.calls.length, 1, 'the refused call never reaches fetch');

  const consent = new RagFailure('CONSENT_REQUIRED');
  await assert.rejects(
    () => embedding.embed(['alpha'], 'search_document', SIGNAL, async () => { throw consent; }),
    (error: unknown) => error === consent,
  );
  const superseded = new Error('SUPERSEDED');
  await assert.rejects(
    () => embedding.embed(['alpha'], 'search_document', SIGNAL, async () => { throw superseded; }),
    (error: unknown) => error === superseded,
  );
  assert.equal(io.calls.length, 1, 'typed refusals never reach fetch');
});

test('caller abort and a fired deadline stop before fetch or cancel a pending body', async () => {
  const aborted = new AbortController();
  aborted.abort();
  const io = recordingFetch(() => jsonResponse(payload(vector([1]))));
  const embedding = createSelfHostedEmbedding(CONFIG, COUNTER, io.impl);
  const beforeFetch = await failureOf(() => embedding.embed(['a'], 'search_query', aborted.signal));
  assert.deepEqual([beforeFetch.code, beforeFetch.retryable], ['TIMEOUT', true]);
  assert.equal(io.calls.length, 0, 'an already-expired deadline never reaches fetch');

  const cancelled = new AbortController();
  const hanging = hangingBody();
  const hangingIo = recordingFetch(() => hanging.response);
  const hangingEmbedding = createSelfHostedEmbedding(CONFIG, COUNTER, hangingIo.impl);
  const run = hangingEmbedding.embed(['a'], 'search_document', cancelled.signal);
  setTimeout(() => cancelled.abort(), 5);
  const timeout = await failureOf(() => run);
  assert.deepEqual([timeout.code, timeout.retryable], ['TIMEOUT', true]);
  await new Promise((resolve) => setTimeout(resolve, 10));
  assert.equal(hanging.wasCancelled(), true, 'the abandoned body read is cancelled');
});

test('construction validates config, counter, fetch and the dispatch callback', () => {
  const invalid: readonly (() => unknown)[] = [
    () => createSelfHostedEmbedding({ clientId: '', clientSecret: 's' }, COUNTER),
    () => createSelfHostedEmbedding({ clientId: 'id', clientSecret: '' }, COUNTER),
    () => createSelfHostedEmbedding(null as never, COUNTER),
    () => createSelfHostedEmbedding(CONFIG, 'counter' as unknown as Counter),
    () => createSelfHostedEmbedding(CONFIG, COUNTER, 'fetch' as unknown as typeof fetch),
  ];
  for (const build of invalid) {
    assert.throws(build, (error: unknown) =>
      error instanceof IndexFailure && error.code === 'INVALID_STATE' && error.retryable === false);
  }
  const embedding = createSelfHostedEmbedding(CONFIG, COUNTER);
  assert.equal(embedding.count, COUNTER);
  const invalidCallback = embedding.embed(
    ['a'],
    'search_document',
    SIGNAL,
    'not-a-function' as unknown as () => Promise<void>,
  );
  return assert.rejects(invalidCallback, (error: unknown) =>
    error instanceof IndexFailure && error.code === 'INVALID_INPUT');
});
