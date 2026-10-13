/**
 * Phase 5 consent handler tests: the exact wire envelope, identity taken only from the
 * authorizer claims, the exact PUT body (no owner, no duplicate key — raw or escaped),
 * permission injected as `assertActor`, the revoke path staying open when admission is off,
 * the disabled/malformed admission gate never reaching the store, and the documented error
 * mapping. The store and permission are test doubles; no AWS, network or provider call is made.
 *
 * Runner: node --import tsx --test amplify/rag/phase5/consent_handler.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { APIGatewayProxyEventV2WithJWTAuthorizer as Event } from 'aws-lambda';
import { CONSENT_VERSION } from '../contract';
import { RagFailure } from '../types';
import type { ErrorCode } from '../types';
import type { RagHttpResponse } from '../handler';
import { DEFAULT_CONSENT } from './consent_store';
import type { ConsentGrant, ConsentStore, ConsentWrite } from './consent_store';
import { CONSENT_PATH, createConsentHandler } from './consent_handler';
import { PILOT_MODEL, assertPilotActor, isPilotOwner, readPilotPolicy } from './pilot_policy';

const ACTOR = '00000001-0000-4000-8000-000000000001';
const OTHER = '00000002-0000-4000-8000-000000000002';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const PUT = JSON.stringify({ accepted: true, version: CONSENT_VERSION, expectedGeneration: 0 });

type Seen = Readonly<{ reads: string[]; writes: Array<{ actor: string; next: ConsentWrite }> }>;

const fakeStore = (): Readonly<{ store: ConsentStore; seen: Seen }> => {
  const seen = { reads: [] as string[], writes: [] as Array<{ actor: string; next: ConsentWrite }> };
  const store: ConsentStore = Object.freeze({
    async read(actor: string): Promise<ConsentGrant> {
      seen.reads.push(actor);
      return DEFAULT_CONSENT;
    },
    async write(actor: string, next: ConsentWrite): Promise<ConsentGrant> {
      seen.writes.push({ actor, next });
      return { accepted: next.accepted, version: next.version, generation: next.expectedGeneration + 1 };
    },
  });
  return { store, seen };
};

const failingStore = (code: ErrorCode): ConsentStore =>
  Object.freeze({
    async read(): Promise<ConsentGrant> {
      throw new RagFailure(code);
    },
    async write(): Promise<ConsentGrant> {
      throw new RagFailure(code);
    },
  });

/** The root composition: only a listed owner of the pilot policy may touch this endpoint. */
const pilotOnly = (actor: string): void => {
  if (actor !== ACTOR) throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
};

const handlerFor = (
  store: ConsentStore,
  assertActor: (actor: string) => void = pilotOnly,
  requestId?: () => string,
) => createConsentHandler({ store, assertActor, ...(requestId === undefined ? {} : { requestId }) });

type Overrides = Readonly<{
  method?: string;
  path?: string;
  body?: string;
  headers?: Record<string, string>;
  claims?: unknown;
  withAuthorizer?: boolean;
  isBase64Encoded?: boolean;
}>;

const event = (over: Overrides = {}): Event => {
  const claims = over.claims === undefined ? { sub: ACTOR, token_use: 'access' } : over.claims;
  const value: Record<string, unknown> = {
    rawPath: over.path ?? CONSENT_PATH,
    headers: over.headers ?? {},
    requestContext: {
      http: { method: over.method ?? 'GET' },
      ...(over.withAuthorizer === false ? {} : { authorizer: { jwt: { claims } } }),
    },
  };
  if (over.body !== undefined) value['body'] = over.body;
  if (over.isBase64Encoded !== undefined) value['isBase64Encoded'] = over.isBase64Encoded;
  return value as unknown as Event;
};

const putEvent = (body: string = PUT, over: Overrides = {}): Event =>
  event({ method: 'PUT', body, headers: { 'content-type': 'application/json' }, ...over });

const parse = (result: RagHttpResponse): Record<string, unknown> =>
  JSON.parse(result.body) as Record<string, unknown>;

test('GET returns the exact consent envelope built from the authorizer actor', async () => {
  const { store, seen } = fakeStore();
  const result = await handlerFor(store)(event());
  assert.equal(result.statusCode, 200);
  assert.equal(result.headers['cache-control'], 'no-store');
  assert.equal(result.headers['content-type'], 'application/json; charset=utf-8');
  const body = parse(result);
  assert.deepEqual(Object.keys(body).sort(), ['consent', 'requestId', 'wireVersion']);
  assert.equal(body['wireVersion'], 1);
  assert.deepEqual(Object.keys(body['consent'] as object).sort(), ['accepted', 'generation', 'version']);
  assert.deepEqual(body['consent'], { accepted: false, version: CONSENT_VERSION, generation: 0 });
  assert.deepEqual(seen.reads, [ACTOR]);
  assert.deepEqual(seen.writes, []);
});

test('PUT returns the new generation and never accepts an owner from the body', async () => {
  const { store, seen } = fakeStore();
  const accepted = await handlerFor(store)(putEvent());
  assert.equal(accepted.statusCode, 200);
  assert.deepEqual(parse(accepted)['consent'], { accepted: true, version: CONSENT_VERSION, generation: 1 });
  assert.deepEqual(seen.writes, [{
    actor: ACTOR,
    next: { accepted: true, version: CONSENT_VERSION, expectedGeneration: 0 },
  }]);

  const injected = await handlerFor(store)(putEvent(
    JSON.stringify({ accepted: true, version: CONSENT_VERSION, expectedGeneration: 0, ownerId: OTHER }),
  ));
  assert.equal(injected.statusCode, 400);
  assert.equal(parse(injected)['code'], 'INVALID_INPUT');
  assert.equal(seen.writes.length, 1);
});

test('revoke stays available to a listed owner while query admission is off', async () => {
  const { store, seen } = fakeStore();
  const disabled = readPilotPolicy(Object.freeze({
    enabled: false,
    owners: Object.freeze([ACTOR]),
    model: 'jev-1.13.0',
    thresholds: Object.freeze({ answerabilityMin: 0.85, conflictMax: 0.1 }),
  }));
  const handler = handlerFor(store, (actor) => {
    if (!isPilotOwner(disabled, actor)) throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  });
  const revoked = await handler(putEvent(
    JSON.stringify({ accepted: false, version: CONSENT_VERSION, expectedGeneration: 3 }),
  ));
  assert.equal(revoked.statusCode, 200);
  assert.deepEqual(parse(revoked)['consent'], { accepted: false, version: CONSENT_VERSION, generation: 4 });
  assert.deepEqual(seen.writes, [{
    actor: ACTOR,
    next: { accepted: false, version: CONSENT_VERSION, expectedGeneration: 3 },
  }]);

  const outsider = await handler(putEvent(undefined, { claims: { sub: OTHER, token_use: 'access' } }));
  assert.equal(outsider.statusCode, 503);
  assert.equal(parse(outsider)['code'], 'LIVE_POLICY_NOT_CONFIGURED');
  assert.equal(seen.writes.length, 1);
});

test('a non-pilot actor is refused before the store is touched', async () => {
  const { store, seen } = fakeStore();
  const handler = handlerFor(store);
  const claims = { sub: OTHER, token_use: 'access' };
  for (const request of [event({ claims }), putEvent(undefined, { claims })]) {
    const result = await handler(request);
    assert.equal(result.statusCode, 503);
    assert.equal(parse(result)['code'], 'LIVE_POLICY_NOT_CONFIGURED');
  }
  // A syntactically valid but non-pilot subject never reaches a stored value either.
  const unusual = await handler(event({ claims: { sub: `${ACTOR}#x`, token_use: 'access' } }));
  assert.equal(unusual.statusCode, 503);
  assert.deepEqual(seen.reads, []);
  assert.deepEqual(seen.writes, []);
});

test('the handler refuses to build without an injected permission check', () => {
  const { store } = fakeStore();
  const missing: unknown = { store };
  assert.throws(() => createConsentHandler(missing as never), (error: unknown) =>
    error instanceof RagFailure && error.code === 'LIVE_POLICY_NOT_CONFIGURED');
  assert.throws(() => createConsentHandler({ store, assertActor: 'allow-all' } as never), (error: unknown) =>
    error instanceof RagFailure && error.code === 'LIVE_POLICY_NOT_CONFIGURED');
  assert.throws(() => createConsentHandler({ assertActor: pilotOnly } as never), (error: unknown) =>
    error instanceof RagFailure && error.code === 'LIVE_POLICY_NOT_CONFIGURED');
});

test('identity comes only from access-token claims', async () => {
  const { store, seen } = fakeStore();
  const unauthorized: unknown[] = [
    { withAuthorizer: false },
    { claims: { sub: ACTOR, token_use: 'id' } },
    { claims: { token_use: 'access' } },
    { claims: { sub: '', token_use: 'access' } },
    { claims: { sub: ` ${ACTOR}`, token_use: 'access' } },
    { claims: 'actor-a' },
  ];
  for (const override of unauthorized) {
    const result = await handlerFor(store)(event(override as Overrides));
    assert.equal(result.statusCode, 401, JSON.stringify(override));
    assert.equal(parse(result)['code'], 'UNAUTHORIZED');
  }
  assert.deepEqual(seen.reads, []);
  // The Authorization header is never an identity source: with no authorizer claims it is refused.
  const headerOnly = await handlerFor(store)(
    event({ headers: { authorization: `Bearer ${ACTOR}` }, withAuthorizer: false }),
  );
  assert.equal(headerOnly.statusCode, 401);
});

test('path and method are refused with the documented status', async () => {
  const { store, seen } = fakeStore();
  const handler = handlerFor(store);
  const wrongPath = await handler(event({ path: '/ai/rag/consent/extra' }));
  assert.equal(wrongPath.statusCode, 404);
  assert.equal(parse(wrongPath)['code'], 'SCOPE_DENIED');
  for (const method of ['POST', 'DELETE', 'HEAD', 'PATCH']) {
    const result = await handler(event({ method, body: PUT, headers: { 'content-type': 'application/json' } }));
    assert.equal(result.statusCode, 400, method);
    assert.equal(parse(result)['code'], 'INVALID_INPUT');
  }
  // A GET does not need a JSON content type and never reads a body.
  const getWithBody = await handler(event({ body: 'not json' }));
  assert.equal(getWithBody.statusCode, 200);
  assert.deepEqual(seen.writes, []);
});

test('PUT requires a bounded JSON UTF-8 body and an exact shape', async () => {
  const { store, seen } = fakeStore();
  const handler = handlerFor(store);
  const missingType = await handler(event({ method: 'PUT', body: PUT }));
  assert.equal(missingType.statusCode, 400);
  const wrongType = await handler(putEvent(PUT, { headers: { 'content-type': 'text/plain' } }));
  assert.equal(wrongType.statusCode, 400);
  const charset = await handler(putEvent(PUT, { headers: { 'content-type': 'application/json; charset=UTF-8' } }));
  assert.equal(charset.statusCode, 200);
  const written = seen.writes.length;
  assert.equal(written, 1);

  const bodies: ReadonlyArray<readonly [string, string]> = [
    ['malformed JSON', '{"accepted":'],
    ['array body', '[true]'],
    ['scalar body', '"rag-consent.v1"'],
    ['null body', 'null'],
    ['empty body', ''],
    ['missing key', JSON.stringify({ accepted: true, version: CONSENT_VERSION })],
    ['unknown key', JSON.stringify({ accepted: true, version: CONSENT_VERSION, expectedGeneration: 0, extra: 1 })],
    ['accepted not boolean', JSON.stringify({ accepted: 'true', version: CONSENT_VERSION, expectedGeneration: 0 })],
    ['version drift', JSON.stringify({ accepted: true, version: 'rag-consent.v2', expectedGeneration: 0 })],
    ['version not a string', JSON.stringify({ accepted: true, version: 1, expectedGeneration: 0 })],
    ['expectedGeneration null', JSON.stringify({ accepted: true, version: CONSENT_VERSION, expectedGeneration: null })],
    ['expectedGeneration fractional', JSON.stringify({ accepted: true, version: CONSENT_VERSION, expectedGeneration: 1.5 })],
    ['expectedGeneration negative', JSON.stringify({ accepted: true, version: CONSENT_VERSION, expectedGeneration: -1 })],
    ['expectedGeneration unsafe', `{"accepted":true,"version":"${CONSENT_VERSION}","expectedGeneration":9007199254740993}`],
    ['expectedGeneration infinite', `{"accepted":true,"version":"${CONSENT_VERSION}","expectedGeneration":1e999}`],
    ['expectedGeneration string', JSON.stringify({ accepted: true, version: CONSENT_VERSION, expectedGeneration: '0' })],
  ];
  for (const [label, body] of bodies) {
    const result = await handler(putEvent(body));
    assert.equal(result.statusCode, 400, label);
    assert.equal(parse(result)['code'], 'INVALID_INPUT', label);
  }
  // No unknown, missing or mistyped field reached the store; only the charset write above did.
  assert.equal(seen.writes.length, written);
  const tooLong = await handler(putEvent(`"${'a'.repeat(20_000)}"`));
  assert.equal(tooLong.statusCode, 413);
  assert.equal(parse(tooLong)['code'], 'INPUT_TOO_LONG');
  assert.equal(seen.writes.length, written);
});

test('a duplicated authority field is refused before the store is touched', async () => {
  const { store, seen } = fakeStore();
  const handler = handlerFor(store);
  const duplicates: ReadonlyArray<readonly [string, string]> = [
    ['raw duplicate accepted',
      `{"accepted":true,"accepted":false,"version":"${CONSENT_VERSION}","expectedGeneration":0}`],
    ['escaped duplicate accepted',
      `{"accepted":true,"\\u0061ccepted":false,"version":"${CONSENT_VERSION}","expectedGeneration":0}`],
    ['raw duplicate version',
      `{"accepted":true,"version":"${CONSENT_VERSION}","version":"rag-consent.v2","expectedGeneration":0}`],
    ['escaped duplicate version',
      `{"accepted":true,"version":"${CONSENT_VERSION}","\\u0076ersion":"rag-consent.v2","expectedGeneration":0}`],
    ['raw duplicate expectedGeneration',
      `{"accepted":true,"version":"${CONSENT_VERSION}","expectedGeneration":0,"expectedGeneration":9}`],
    ['escaped duplicate expectedGeneration',
      `{"accepted":true,"version":"${CONSENT_VERSION}","expectedGeneration":0,"\\u0065xpectedGeneration":9}`],
    ['duplicate owner field',
      `{"accepted":true,"version":"${CONSENT_VERSION}","expectedGeneration":0,"ownerId":"${OTHER}","ownerId":"${ACTOR}"}`],
  ];
  for (const [label, body] of duplicates) {
    const result = await handler(putEvent(body));
    assert.equal(result.statusCode, 400, label);
    assert.equal(parse(result)['code'], 'INVALID_INPUT', label);
  }
  // The last value a plain JSON.parse would have kept never reached a stored grant.
  assert.deepEqual(seen.writes, []);

  // An escaped key that is not a duplicate is decoded, not refused.
  const escaped = await handler(putEvent(
    `{"\\u0061ccepted":true,"version":"${CONSENT_VERSION}","expectedGeneration":0}`,
  ));
  assert.equal(escaped.statusCode, 200);
  assert.deepEqual(parse(escaped)['consent'], { accepted: true, version: CONSENT_VERSION, generation: 1 });
  assert.deepEqual(seen.writes, [{
    actor: ACTOR,
    next: { accepted: true, version: CONSENT_VERSION, expectedGeneration: 0 },
  }]);
});

test('an admission gate built from a disabled or malformed policy never reaches the store', async () => {
  const { store, seen } = fakeStore();
  const candidates: ReadonlyArray<unknown> = [
    readPilotPolicy(Object.freeze({
      enabled: false,
      owners: Object.freeze([ACTOR]),
      model: PILOT_MODEL,
      thresholds: Object.freeze({ answerabilityMin: 0.85, conflictMax: 0.1 }),
    })),
    // Frozen, names this actor, but missing the pinned thresholds: not a configured policy.
    Object.freeze({ enabled: true, owners: Object.freeze([ACTOR]), model: PILOT_MODEL }),
  ];
  for (const policy of candidates) {
    const handler = handlerFor(store, (actor) => assertPilotActor(policy as never, actor));
    for (const request of [event(), putEvent()]) {
      const result = await handler(request);
      assert.equal(result.statusCode, 503);
      assert.equal(parse(result)['code'], 'LIVE_POLICY_NOT_CONFIGURED');
    }
  }
  assert.deepEqual(seen.reads, []);
  assert.deepEqual(seen.writes, []);
});

test('a base64-encoded body is decoded with the same bounds', async () => {
  const { store, seen } = fakeStore();
  const handler = handlerFor(store);
  const encoded = await handler(putEvent(undefined, {
    body: Buffer.from(PUT, 'utf8').toString('base64'),
    isBase64Encoded: true,
  }));
  assert.equal(encoded.statusCode, 200);
  assert.equal(seen.writes.length, 1);
  for (const body of ['not base64!!', Buffer.from([0xff, 0xfe, 0xfd]).toString('base64')]) {
    const result = await handler(putEvent(undefined, { body, isBase64Encoded: true }));
    assert.equal(result.statusCode, 400, body);
  }
  assert.equal(seen.writes.length, 1);
});

test('store failures map to the documented status without leaking detail', async () => {
  const cases: ReadonlyArray<readonly [ErrorCode, number]> = [
    ['SOURCE_CHANGED', 409],
    ['PROVIDER_UNAVAILABLE', 503],
    ['TIMEOUT', 504],
    ['RATE_LIMITED', 429],
    ['INVALID_PROVIDER_OUTPUT', 502],
  ];
  for (const [code, status] of cases) {
    const result = await handlerFor(failingStore(code))(event());
    assert.equal(result.statusCode, status, code);
    const body = parse(result);
    assert.deepEqual(Object.keys(body).sort(), ['code', 'requestId', 'status', 'wireVersion']);
    assert.equal(body['code'], code);
    assert.equal(body['status'], 'ERROR');
    assert.equal(body['wireVersion'], 1);
    assert.ok(UUID.test(body['requestId'] as string));
    assert.ok(!result.body.includes('stack') && !result.body.includes('Error'));
  }
  const assertFails = createConsentHandler({
    store: fakeStore().store,
    assertActor: () => {
      throw new Error('permission table offline');
    },
  });
  const mapped = await assertFails(event());
  assert.equal(mapped.statusCode, 503);
  assert.equal(parse(mapped)['code'], 'PROVIDER_UNAVAILABLE');
});

test('the requestId is validated server-side and echoed in success and error envelopes', async () => {
  const { store } = fakeStore();
  const echoed = await handlerFor(store, pilotOnly, () => 'req-42')(event());
  assert.equal(parse(echoed)['requestId'], 'req-42');
  const replaced = await handlerFor(store, pilotOnly, () => ' ')(event());
  const id = parse(replaced)['requestId'] as string;
  assert.ok(UUID.test(id));
  assert.notEqual(id, ' ');
  const failing = await handlerFor(failingStore('SOURCE_CHANGED'), pilotOnly, () => 'x'.repeat(129))(event());
  assert.ok(UUID.test(parse(failing)['requestId'] as string));
});
