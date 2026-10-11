import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { APIGatewayProxyEventV2WithJWTAuthorizer as Event } from 'aws-lambda';
import { RESPONSE_MAX_BYTES, REQUEST_MAX_BYTES } from './contract';
import { createRagHandler } from './handler';
import type { RagHttpResponse } from './handler';
import { RagFailure } from './types';
import type { RagRequest, RagResponse, Source } from './types';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const validBody = JSON.stringify({ wireVersion: 1, question: 'q?', scope: { type: 'account' } });

type EventOverrides = Readonly<{
  body?: string;
  headers?: Record<string, string>;
  isBase64Encoded?: boolean;
  method?: string;
  path?: string;
  claims?: unknown;
  withAuthorizer?: boolean;
}>;

const event = (over: EventOverrides = {}): Event => {
  const claims = over.claims === undefined ? { sub: 'actor-a', token_use: 'access' } : over.claims;
  const value: Record<string, unknown> = {
    rawPath: over.path ?? '/ai/rag/query',
    headers: over.headers ?? { 'content-type': 'application/json' },
    body: over.body ?? validBody,
    requestContext: {
      http: { method: over.method ?? 'POST' },
      ...(over.withAuthorizer === false ? {} : { authorizer: { jwt: { claims } } }),
    },
  };
  if (over.isBase64Encoded !== undefined) value['isBase64Encoded'] = over.isBase64Encoded;
  return value as unknown as Event;
};

const parse = (result: RagHttpResponse): Record<string, unknown> =>
  JSON.parse(result.body) as Record<string, unknown>;

const source: Source = {
  sourceId: 'S1',
  noteId: 'n-watch',
  revision: 1,
  title: 'SLGH031',
  startOffset: 0,
  endOffset: 5,
  quote: 'alpha',
};

const answered = (requestId: string): RagResponse => ({
  wireVersion: 1,
  requestId,
  status: 'ANSWERED',
  answer: 'Answer. [S1]',
  sources: [source],
});

const countingHandler = (
  build: (requestId: string) => RagResponse,
  requestId?: () => string,
): Readonly<{ handler: ReturnType<typeof createRagHandler>; calls: () => number }> => {
  let calls = 0;
  const handler = createRagHandler(async (_actor, _request, id) => {
    calls += 1;
    return build(id);
  }, requestId);
  return { handler, calls: () => calls };
};

test('handler forwards the verified access-token sub and parsed request, echoing the server id', async () => {
  let seen: Readonly<{ actor: string; request: RagRequest; requestId: string }> | undefined;
  const handler = createRagHandler(async (actor, request, requestId) => {
    seen = { actor, request, requestId };
    return answered(requestId);
  }, () => 'req-1');
  const result = await handler(event());
  assert.equal(result.statusCode, 200);
  assert.equal(seen?.actor, 'actor-a');
  assert.deepEqual(seen?.request, { wireVersion: 1, question: 'q?', scope: { type: 'account' } });
  assert.equal(seen?.requestId, 'req-1');
  assert.equal(parse(result)['status'], 'ANSWERED');
  assert.equal(parse(result)['requestId'], 'req-1');
});

test('handler requires a verified access-token sub and never trusts the Authorization header', async () => {
  const { handler } = countingHandler(answered);
  for (const claims of [
    { sub: 'actor-a', token_use: 'id' },
    { sub: 'actor-a' },
    { token_use: 'access' },
    { sub: '', token_use: 'access' },
    { sub: ' actor-a', token_use: 'access' },
    { sub: 42, token_use: 'access' },
    { sub: 'a'.repeat(129), token_use: 'access' },
    { sub: 'a\uD800', token_use: 'access' },
    null,
  ]) {
    const result = await handler(event({ claims }));
    assert.equal(result.statusCode, 401, JSON.stringify(claims));
    assert.equal(parse(result)['code'], 'UNAUTHORIZED');
  }
  const noAuthorizer = await handler(event({ withAuthorizer: false }));
  assert.equal(noAuthorizer.statusCode, 401);
  const headerOnly = await handler(
    event({
      withAuthorizer: false,
      headers: { 'content-type': 'application/json', authorization: 'Bearer attacker-controlled' },
    }),
  );
  assert.equal(headerOnly.statusCode, 401);

  const trusted = await handler(
    event({ headers: { 'content-type': 'application/json', authorization: 'Bearer attacker-controlled' } }),
  );
  assert.equal(trusted.statusCode, 200);
});

test('handler defaults the correlation id to a random UUID and survives a broken factory', async () => {
  const { handler } = countingHandler(answered);
  assert.match(String(parse(await handler(event()))['requestId']), UUID);

  const throwing = createRagHandler(async (_actor, _request, id) => answered(id), () => {
    throw new Error('id factory down');
  });
  assert.match(String(parse(await throwing(event()))['requestId']), UUID);

  const unsafe = createRagHandler(async (_actor, _request, id) => answered(id), () => 'bad id\u0000');
  assert.match(String(parse(await unsafe(event()))['requestId']), UUID);
});

test('handler serves only POST /ai/rag/query and never reaches the query otherwise', async () => {
  const { handler, calls } = countingHandler(answered);
  assert.equal((await handler(event({ method: 'GET' }))).statusCode, 400);
  assert.equal((await handler(event({ path: '/ai/rag/other' }))).statusCode, 400);
  assert.equal((await handler(event({ method: 'GET' }))).statusCode, 400);
  assert.equal(calls(), 0);
});

test('handler requires application/json with an optional UTF-8 charset', async () => {
  const { handler, calls } = countingHandler(answered);
  const badHeaders: readonly Record<string, string>[] = [
    {},
    { 'content-type': 'text/plain' },
    { 'content-type': 'application/json; charset=latin1' },
    { 'content-type': 'application/json; charset=utf-16' },
  ];
  for (const headers of badHeaders) {
    const result = await handler(event({ headers }));
    assert.equal(result.statusCode, 400, JSON.stringify(headers));
    assert.equal(parse(result)['code'], 'INVALID_INPUT');
  }
  for (const contentType of ['application/json; charset=utf-8', 'application/json;charset=UTF-8', 'Application/JSON']) {
    assert.equal((await handler(event({ headers: { 'content-type': contentType } }))).statusCode, 200, contentType);
  }
  assert.equal(calls(), 3);
});

test('handler enforces the raw 16 KiB body cap before parsing', async () => {
  const { handler } = countingHandler(answered);
  const size = new TextEncoder().encode(validBody).byteLength;
  const atCap = validBody + ' '.repeat(REQUEST_MAX_BYTES - size);
  assert.equal((await handler(event({ body: atCap }))).statusCode, 200);
  const over = await handler(event({ body: `${atCap} ` }));
  assert.equal(over.statusCode, 413);
  assert.equal(parse(over)['code'], 'INPUT_TOO_LONG');
  assert.equal((await handler(event({ body: '' }))).statusCode, 400);
});

test('handler refuses duplicate keys and lone surrogates through the strict parser', async () => {
  const { handler } = countingHandler(answered);
  const duplicate = '{"wireVersion":1,"question":"a","\\u0071uestion":"b","scope":{"type":"account"}}';
  assert.equal((await handler(event({ body: duplicate }))).statusCode, 400);
  assert.equal((await handler(event({ body: `${validBody}\uD800` }))).statusCode, 400);
  assert.equal((await handler(event({ body: '{"wireVersion":1,"question":"q"}' }))).statusCode, 400);
});

test('handler decodes canonical base64 strictly and refuses invalid bytes or sizes', async () => {
  const { handler } = countingHandler(answered);
  const encoded = Buffer.from(validBody, 'utf8').toString('base64');
  const ok = await handler(event({ body: encoded, isBase64Encoded: true }));
  assert.equal(ok.statusCode, 200);
  assert.equal(parse(ok)['status'], 'ANSWERED');

  const invalidUtf8 = await handler(
    event({ body: Buffer.from([0xc3, 0x28]).toString('base64'), isBase64Encoded: true }),
  );
  assert.equal(invalidUtf8.statusCode, 400);
  assert.equal(parse(invalidUtf8)['code'], 'INVALID_INPUT');

  for (const body of ['!!!not-base64!!!', 'AAAAA', 'AB=C', encoded.slice(0, 6) + '=']) {
    const result = await handler(event({ body, isBase64Encoded: true }));
    assert.equal(result.statusCode, 400, body);
    assert.equal(parse(result)['code'], 'INVALID_INPUT');
  }

  const oversized = await handler(event({ body: 'A'.repeat(30_000), isBase64Encoded: true }));
  assert.equal(oversized.statusCode, 413);
  const decodedTooLarge = await handler(
    event({ body: Buffer.alloc(REQUEST_MAX_BYTES + 1, 0x20).toString('base64'), isBase64Encoded: true }),
  );
  assert.equal(decodedTooLarge.statusCode, 413);
});

test('handler maps query failures to safe envelopes without leaking messages or stacks', async () => {
  const timedOut = createRagHandler(async () => {
    throw new RagFailure('TIMEOUT');
  });
  const timeout = await timedOut(event());
  assert.equal(timeout.statusCode, 504);
  assert.equal(parse(timeout)['code'], 'TIMEOUT');

  const refused = createRagHandler(async () => {
    throw new RagFailure('CONSENT_REQUIRED');
  });
  assert.equal((await refused(event())).statusCode, 403);

  const broken = createRagHandler(async () => {
    throw new Error('raw-provider-body-secret at /var/task/handler.js:10');
  });
  const result = await broken(event());
  assert.equal(result.statusCode, 503);
  assert.equal(parse(result)['code'], 'PROVIDER_UNAVAILABLE');
  assert.ok(!result.body.includes('secret'));
  assert.ok(!result.body.includes('handler.js'));
});

test('handler refuses a malformed or inconsistent query result as invalid provider output', async () => {
  const cases: readonly unknown[] = [
    null,
    'not-an-envelope',
    { wireVersion: 2, requestId: 'id', status: 'ERROR', code: 'TIMEOUT' },
    { wireVersion: 1, requestId: 'other', status: 'ANSWERED', answer: 'A. [S1]', sources: [source] },
    { wireVersion: 1, requestId: 'id', status: 'ANSWERED', answer: 'A. [S1]', sources: [] },
    { wireVersion: 1, requestId: 'id', status: 'ANSWERED', answer: 'A. [S1]', sources: [source], confidence: 0.9 },
    { wireVersion: 1, requestId: 'id', status: 'ERROR', code: 'HIDDEN_PROVIDER_ERROR' },
    { wireVersion: 1, requestId: 'id', status: 'NOT_ENOUGH_CONTEXT', reason: 'NOPE', answer: null, sources: [] },
    { wireVersion: 1, requestId: 'id', status: 'NOT_ENOUGH_CONTEXT', reason: 'UNCERTAIN', answer: 'x', sources: [] },
    { wireVersion: 1, requestId: 'id', status: 'ANSWERED', answer: 'bad \uD800', sources: [source] },
  ];
  for (const value of cases) {
    const handler = createRagHandler(async () => value as RagResponse, () => 'id');
    const result = await handler(event());
    assert.equal(result.statusCode, 502, JSON.stringify(value));
    assert.equal(parse(result)['code'], 'INVALID_PROVIDER_OUTPUT');
  }
});

test('handler passes abstention and query error envelopes through with the policy status', async () => {
  const abstain = createRagHandler(
    async (_actor, _request, id): Promise<RagResponse> => ({
      wireVersion: 1,
      requestId: id,
      status: 'NOT_ENOUGH_CONTEXT',
      reason: 'UNRESOLVED_CONFLICT',
      answer: null,
      sources: [],
    }),
    () => 'id',
  );
  const abstained = await abstain(event());
  assert.equal(abstained.statusCode, 200);
  assert.equal(parse(abstained)['reason'], 'UNRESOLVED_CONFLICT');

  const errored = createRagHandler(
    async (_actor, _request, id): Promise<RagResponse> => ({
      wireVersion: 1,
      requestId: id,
      status: 'ERROR',
      code: 'INDEX_NOT_READY',
    }),
    () => 'id',
  );
  assert.equal((await errored(event())).statusCode, 409);
});

test('handler replaces an oversized outbound envelope with a bounded provider-output error', async () => {
  const handler = createRagHandler(
    async (_actor, _request, id): Promise<RagResponse> => ({
      wireVersion: 1,
      requestId: id,
      status: 'ANSWERED',
      answer: 'x'.repeat(RESPONSE_MAX_BYTES),
      sources: [source],
    }),
    () => 'id',
  );
  const result = await handler(event());
  assert.equal(result.statusCode, 502);
  assert.equal(parse(result)['code'], 'INVALID_PROVIDER_OUTPUT');
  assert.ok(new TextEncoder().encode(result.body).byteLength <= RESPONSE_MAX_BYTES);
});
