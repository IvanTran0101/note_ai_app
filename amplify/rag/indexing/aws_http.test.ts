/**
 * aws_http port tests — fixed endpoints, SigV4 scope, closed operation whitelist, failure
 * taxonomy, single-fetch/no-retry and the no-body/no-secret disclosure guarantee.
 * Runner: node --import tsx --test amplify/rag/indexing/aws_http.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { policy, RagFailure } from '../types';
import { IndexFailure } from './types';
import {
  BEDROCK_INVOKE_MODEL_PATH, createAwsJson, failureForStatus, isAwsRegion,
  type AwsFetch, type AwsFetchInit, type AwsService,
} from './aws_http';

const CREDENTIALS = Object.freeze({
  accessKeyId: 'AKIDEXAMPLE',
  secretAccessKey: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
  sessionToken: 'SESSION-TOKEN-SENTINEL',
});
const SIGNAL = new AbortController().signal;
const SENTINEL = 'CANONICAL-TEXT-SENTINEL';

type Captured = Readonly<{ url: string; init: AwsFetchInit }>;

const transport = (
  reply: (url: string, init: AwsFetchInit) => Response,
): Readonly<{ calls: Captured[]; fetch: AwsFetch }> => {
  const calls: Captured[] = [];
  const fetch: AwsFetch = async (url, init) => {
    calls.push({ url, init });
    return reply(url, init);
  };
  return { calls, fetch };
};

const json = (body: unknown, status = 200): Response =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

const failureOf = async (run: () => Promise<unknown>): Promise<IndexFailure> => {
  try {
    await run();
  } catch (error) {
    assert.ok(error instanceof IndexFailure, `expected IndexFailure, got ${String(error)}`);
    return error;
  }
  throw new Error('expected the call to fail');
};

test('bedrock invoke signs the fixed endpoint, service and escaped model path', async () => {
  const io = transport(() => json({ embeddings: [] }));
  const call = createAwsJson('us-east-1', { fetch: io.fetch, credentials: CREDENTIALS });
  const reply = await call('bedrock', BEDROCK_INVOKE_MODEL_PATH, { texts: ['x'] }, SIGNAL);

  assert.deepEqual(reply, { embeddings: [] });
  assert.equal(BEDROCK_INVOKE_MODEL_PATH, '/model/cohere.embed-multilingual-v3/invoke');
  // The signed Bedrock whitelist is frozen to policy_v1; the active profile is self-hosted 768.
  assert.equal(policy.embedding.model, 'embeddinggemma-2-q8');
  assert.equal(policy.embedding.dimensions, 768);
  assert.notEqual(BEDROCK_INVOKE_MODEL_PATH, `/model/${policy.embedding.model}/invoke`);
  assert.equal(io.calls.length, 1);
  const { url, init } = io.calls[0];
  assert.equal(url, 'https://bedrock-runtime.us-east-1.amazonaws.com/model/cohere.embed-multilingual-v3/invoke');
  assert.equal(init.method, 'POST');
  assert.equal(init.body, JSON.stringify({ texts: ['x'] }));
  assert.equal(init.signal, SIGNAL);
  assert.equal(init.headers['host'], 'bedrock-runtime.us-east-1.amazonaws.com');
  assert.equal(init.headers['content-type'], 'application/json');
  assert.match(
    init.headers['authorization'] ?? '',
    /^AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE\/\d{8}\/us-east-1\/bedrock\/aws4_request, SignedHeaders=[a-z0-9;-]+, Signature=[0-9a-f]{64}$/,
  );
  assert.match(init.headers['x-amz-date'] ?? '', /^\d{8}T\d{6}Z$/);
  // Secrets only ever appear inside signature headers, never in the URL or body.
  assert.ok(!url.includes(CREDENTIALS.secretAccessKey) && !init.body.includes(CREDENTIALS.secretAccessKey));
});

test('s3vectors signs its own endpoint and service scope for every whitelisted operation', async () => {
  const io = transport(() => json({}));
  const call = createAwsJson('ap-southeast-1', { fetch: io.fetch, credentials: CREDENTIALS });
  for (const path of ['/PutVectors', '/GetVectors', '/QueryVectors', '/DeleteVectors']) {
    await call('s3vectors', path, {}, SIGNAL);
  }
  assert.equal(io.calls.length, 4);
  for (const [index, path] of ['/PutVectors', '/GetVectors', '/QueryVectors', '/DeleteVectors'].entries()) {
    const { url, init } = io.calls[index];
    assert.equal(url, `https://s3vectors.ap-southeast-1.api.aws${path}`);
    assert.equal(init.headers['host'], 's3vectors.ap-southeast-1.api.aws');
    assert.match(
      init.headers['authorization'] ?? '',
      /\/ap-southeast-1\/s3vectors\/aws4_request, SignedHeaders=/,
    );
  }
});

test('region validation refuses anything that could move the fixed host', () => {
  for (const region of ['us-east-1', 'ap-southeast-1', 'us-gov-west-1', 'cn-north-1', 'us-iso-east-1', 'eusc-de-east-1']) {
    assert.equal(isAwsRegion(region), true, region);
  }
  for (const region of ['', 'us east 1', 'US-EAST-1', 'us-east-1.evil.com', 'us-east-1/', 'a', 'x'.repeat(40), 42]) {
    assert.equal(isAwsRegion(region), false, String(region));
  }
  for (const region of ['', 'us-east-1.evil.com', 'US-EAST-1']) {
    assert.throws(
      () => createAwsJson(region, { credentials: CREDENTIALS }),
      (error: unknown) =>
        error instanceof IndexFailure && error.code === 'INVALID_STATE' && error.retryable === false,
    );
  }
});

test('operation whitelist refuses foreign paths, cross-service paths and unknown services', async () => {
  const io = transport(() => json({}));
  const call = createAwsJson('us-east-1', { fetch: io.fetch, credentials: CREDENTIALS });
  const cases: readonly (readonly [AwsService, string])[] = [
    ['s3vectors', '/ListVectors'],
    ['s3vectors', '/DeleteVectors/../ListVectors'],
    ['s3vectors', 'PutVectors'],
    ['bedrock', '/model/cohere.embed-english-v3/invoke'],
    ['bedrock', '/model/cohere.embed-multilingual-v3/invoke?x=1'],
    ['bedrock', 'https://evil.example.com/PutVectors'],
  ];
  for (const [service, path] of cases) {
    const error = await failureOf(() => call(service, path, {}, SIGNAL));
    assert.equal(error.code, 'INVALID_INPUT', `${service} ${path}`);
    assert.equal(error.retryable, false);
  }
  const unknown = await failureOf(() => call('lambda' as AwsService, '/PutVectors', {}, SIGNAL));
  assert.equal(unknown.code, 'INVALID_INPUT');
  assert.equal(io.calls.length, 0);
});

test('HTTP status maps to a code and only timeout/429/5xx are retryable', async () => {
  const expected: readonly (readonly [number, string, boolean])[] = [
    [408, 'TIMEOUT', true],
    [429, 'RATE_LIMITED', true],
    [500, 'PROVIDER_UNAVAILABLE', true],
    [503, 'PROVIDER_UNAVAILABLE', true],
    [401, 'UNAUTHORIZED', false],
    [403, 'UNAUTHORIZED', false],
    [404, 'INDEX_NOT_READY', false],
    [409, 'INDEX_NOT_READY', false],
    [400, 'INVALID_INPUT', false],
    [422, 'INVALID_INPUT', false],
  ];
  for (const [status, code, retryable] of expected) {
    const direct = failureForStatus(status);
    assert.deepEqual([direct.code, direct.retryable], [code, retryable], String(status));
    const io = transport(() => json({ error: SENTINEL }, status));
    const call = createAwsJson('us-east-1', { fetch: io.fetch, credentials: CREDENTIALS });
    const error = await failureOf(() => call('s3vectors', '/PutVectors', {}, SIGNAL));
    assert.deepEqual([error.code, error.retryable], [code, retryable], String(status));
    assert.equal(io.calls.length, 1, 'no internal retry');
    assert.ok(!error.message.includes(SENTINEL) && !String(error).includes(SENTINEL));
  }
  assert.equal(failureForStatus(500, true).code, 'TIMEOUT');
});

test('malformed success payloads are terminal and never echo the provider body', async () => {
  const io = transport(() => new Response(`not-json:${SENTINEL}`, { status: 200 }));
  const call = createAwsJson('us-east-1', { fetch: io.fetch, credentials: CREDENTIALS });
  const error = await failureOf(() => call('s3vectors', '/QueryVectors', {}, SIGNAL));
  assert.deepEqual([error.code, error.retryable], ['INVALID_PROVIDER_OUTPUT', false]);
  assert.ok(!error.message.includes(SENTINEL) && !String(error).includes(SENTINEL));
  assert.equal(io.calls.length, 1);
});

test('an empty success body is an empty object, not a parse failure', async () => {
  const io = transport(() => new Response('', { status: 200 }));
  const call = createAwsJson('us-east-1', { fetch: io.fetch, credentials: CREDENTIALS });
  assert.deepEqual(await call('s3vectors', '/DeleteVectors', {}, SIGNAL), {});
});

test('abort is a retryable timeout: before the call and during the fetch', async () => {
  const io = transport(() => json({}));
  const call = createAwsJson('us-east-1', { fetch: io.fetch, credentials: CREDENTIALS });
  const preAborted = new AbortController();
  preAborted.abort();
  const before = await failureOf(() => call('bedrock', BEDROCK_INVOKE_MODEL_PATH, {}, preAborted.signal));
  assert.deepEqual([before.code, before.retryable], ['TIMEOUT', true]);
  assert.equal(io.calls.length, 0);

  const inFlight: AwsFetch = (_url, init) => new Promise((_resolve, reject) => {
    if (init.signal.aborted) {
      reject(new Error('transport abort'));
      return;
    }
    init.signal.addEventListener('abort', () => reject(new Error('transport abort')), { once: true });
  });
  const controller = new AbortController();
  const pending = createAwsJson('us-east-1', { fetch: inFlight, credentials: CREDENTIALS })(
    'bedrock', BEDROCK_INVOKE_MODEL_PATH, {}, controller.signal,
  );
  controller.abort();
  const during = await failureOf(() => pending);
  assert.deepEqual([during.code, during.retryable], ['TIMEOUT', true]);
});

test('signing/credential failure is a terminal access error with no fetch and no leak', async () => {
  const io = transport(() => json({}));
  const call = createAwsJson('us-east-1', {
    fetch: io.fetch,
    credentials: async () => {
      throw new Error(`no credentials: ${CREDENTIALS.secretAccessKey}`);
    },
  });
  const error = await failureOf(() => call('bedrock', BEDROCK_INVOKE_MODEL_PATH, {}, SIGNAL));
  assert.deepEqual([error.code, error.retryable], ['UNAUTHORIZED', false]);
  assert.ok(!error.message.includes(CREDENTIALS.secretAccessKey) && !String(error).includes(CREDENTIALS.secretAccessKey));
  assert.equal(io.calls.length, 0);
});

test('body and signal validation fail closed before signing or fetching', async () => {
  const io = transport(() => json({}));
  const call = createAwsJson('us-east-1', { fetch: io.fetch, credentials: CREDENTIALS });
  const circular: Record<string, unknown> = {};
  circular['self'] = circular;
  for (const body of [circular, undefined, () => 1]) {
    const error = await failureOf(() => call('s3vectors', '/PutVectors', body, SIGNAL));
    assert.equal(error.code, 'INVALID_INPUT');
  }
  const noSignal = await failureOf(() =>
    call('s3vectors', '/PutVectors', {}, undefined as unknown as AbortSignal));
  assert.equal(noSignal.code, 'INVALID_INPUT');
  assert.equal(io.calls.length, 0);
});

/* ------------------------------------------------------------------ *
 * The post-sign dispatch window: credentials and signing are awaited
 * before the callback and the transport fetch, so a permit revoked
 * during that window must never produce an egress.
 * ------------------------------------------------------------------ */

test('the post-sign dispatch callback runs immediately before fetch and can refuse with no fetch', async () => {
  const io = transport(() => json({}));
  let release!: (value: typeof CREDENTIALS) => void;
  const credentials = new Promise<typeof CREDENTIALS>((resolve) => { release = resolve; });
  let dispatched = 0;
  const pending = createAwsJson('us-east-1', {
    fetch: io.fetch,
    credentials: async () => credentials,
  })('bedrock', BEDROCK_INVOKE_MODEL_PATH, {}, SIGNAL, async () => {
    dispatched += 1;
    throw new RagFailure('SOURCE_CHANGED');
  });
  // The callback belongs after signing: while the credential promise is pending it must not run.
  await Promise.resolve();
  assert.equal(dispatched, 0);
  assert.equal(io.calls.length, 0);
  release(CREDENTIALS);
  await assert.rejects(pending, (error: unknown) =>
    error instanceof RagFailure && error.code === 'SOURCE_CHANGED');
  assert.equal(dispatched, 1);
  assert.equal(io.calls.length, 0, 'a refused dispatch never reaches the transport');
});

test('the post-sign dispatch callback runs once after signing and before exactly one signed fetch', async () => {
  const order: string[] = [];
  const calls: Captured[] = [];
  const fetch: AwsFetch = async (url, init) => {
    order.push('fetch');
    calls.push({ url, init });
    return json({});
  };
  const call = createAwsJson('us-east-1', {
    fetch,
    credentials: async () => {
      order.push('credentials');
      return CREDENTIALS;
    },
  });
  await call('bedrock', BEDROCK_INVOKE_MODEL_PATH, {}, SIGNAL, async () => { order.push('dispatch'); });
  assert.deepEqual(order, ['credentials', 'dispatch', 'fetch']);
  assert.equal(calls.length, 1);
  assert.match(calls[0]!.init.headers['authorization'] ?? '', /^AWS4-HMAC-SHA256 /);
});

test('an abort inside the post-sign dispatch callback is a timeout with no fetch', async () => {
  const io = transport(() => json({}));
  const controller = new AbortController();
  const pending = createAwsJson('us-east-1', { fetch: io.fetch, credentials: CREDENTIALS })(
    'bedrock', BEDROCK_INVOKE_MODEL_PATH, {}, controller.signal, async () => { controller.abort(); },
  );
  const error = await failureOf(() => pending);
  assert.deepEqual([error.code, error.retryable], ['TIMEOUT', true]);
  assert.equal(io.calls.length, 0);
});
