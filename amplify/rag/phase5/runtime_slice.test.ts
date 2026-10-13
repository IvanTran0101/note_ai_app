/**
 * Focused tests for the Phase 5 runtime slice changes: the explicit pilot branch of
 * `readRuntimeConfig`, the late-abort guard of the runtime-config reader, the enclosing deadline
 * of the consent handler, the preserved typed authority failures and the two new guarded
 * `IndexFailure`→`RagFailure` mappings. All fakes; no AWS, network, provider or model call.
 *
 * Runner: node --import tsx --test amplify/rag/phase5/runtime_slice.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { APIGatewayProxyEventV2WithJWTAuthorizer } from 'aws-lambda';
import { beginContext } from '../authority';
import { parseRequest } from '../contract';
import { createQueryPorts } from '../indexing/query_ports';
import { IndexFailure } from '../indexing/types';
import { readLiveApproval, readRuntimeConfig } from '../live_policy';
import { policy, RagFailure } from '../types';
import type { RuntimeConfig } from '../types';
import { createConsentHandler } from './consent_handler';
import type { ConsentGrant, ConsentStore } from './consent_store';
import { RUNTIME_CONFIG_KEY, createRuntimeConfigReader } from './runtime_config';
import type { RuntimeConfigReaderPort } from './runtime_config';

const ACTOR = '00000001-0000-4000-8000-000000000001';
const OTHER = '00000002-0000-4000-8000-000000000002';

const isCode = (code: string) => (error: unknown): boolean =>
  error instanceof RagFailure && error.code === code;

const pilotPolicy = (enabled: boolean, owners: readonly string[] = [ACTOR]) =>
  Object.freeze({
    enabled,
    owners: Object.freeze([...owners]),
    model: 'jev-1.13.0',
    thresholds: Object.freeze({ answerabilityMin: 0.85, conflictMax: 0.1 }),
  });

const runtimeConfig = (patch: Partial<RuntimeConfig> = {}): RuntimeConfig =>
  Object.freeze({
    mode: 'live',
    model: 'jev-1.13.0',
    thresholds: Object.freeze({ answerabilityMin: 0.85, conflictMax: 0.1 }),
    jevMaxTokens: 32_000,
    requestTimeoutMs: 26_000,
    ...patch,
  });

const approval = () =>
  readLiveApproval(Object.freeze({
    model: 'jev-1.13.0',
    thresholds: Object.freeze({ answerabilityMin: 0.85, conflictMax: 0.1 }),
    fixtureVersion: 'fix-1',
    calibrationVersion: 'cal-1',
  }));

test('an explicit enabled listed pilot policy opens live mode with the frozen binding', () => {
  const runtime = readRuntimeConfig(runtimeConfig(), ACTOR, approval(), pilotPolicy(true));
  assert.equal(runtime.model, 'jev-1.13.0');
  assert.deepEqual(runtime.thresholds, { answerabilityMin: 0.85, conflictMax: 0.1 });
});

test('the no-argument phase 4 smoke branch is unchanged', () => {
  const runtime = readRuntimeConfig(runtimeConfig(), 'rag-smoke-a', approval());
  assert.equal(runtime.model, 'jev-1.13.0');
  assert.throws(() => readRuntimeConfig(runtimeConfig(), ACTOR, approval()), isCode('LIVE_POLICY_NOT_CONFIGURED'));
});

test('an invalid explicit pilot never falls back to the smoke seam', () => {
  // The actor would pass the smoke branch, but the explicit pilot does not list them.
  assert.throws(
    () => readRuntimeConfig(runtimeConfig(), 'rag-smoke-a', approval(), pilotPolicy(true, [ACTOR])),
    isCode('LIVE_POLICY_NOT_CONFIGURED'),
  );
  for (const value of [
    pilotPolicy(false),
    pilotPolicy(true, [OTHER]),
    { enabled: true, owners: [ACTOR], model: 'jev-1.13.0', thresholds: { answerabilityMin: 0.85, conflictMax: 0.1 } },
    Object.freeze({ ...pilotPolicy(true), extra: true }),
    Object.freeze({
      enabled: true,
      owners: Object.freeze([ACTOR]),
      model: 'jev-1.13.0',
      thresholds: Object.freeze({ answerabilityMin: 0.9, conflictMax: 0.1 }),
    }),
  ]) {
    assert.throws(() => readRuntimeConfig(runtimeConfig(), ACTOR, approval(), value), isCode('LIVE_POLICY_NOT_CONFIGURED'));
  }
});

test('an explicit pilot still requires the immutable calibrated approval', () => {
  assert.throws(
    () => readRuntimeConfig(runtimeConfig(), ACTOR, undefined, pilotPolicy(true)),
    isCode('LIVE_POLICY_NOT_CONFIGURED'),
  );
  const mismatched = readLiveApproval(Object.freeze({
    model: 'jev-1.13.0',
    thresholds: Object.freeze({ answerabilityMin: 0.9, conflictMax: 0.1 }),
    fixtureVersion: 'fix-1',
    calibrationVersion: 'cal-1',
  }));
  assert.throws(
    () => readRuntimeConfig(runtimeConfig(), ACTOR, mismatched, pilotPolicy(true)),
    isCode('LIVE_POLICY_NOT_CONFIGURED'),
  );
});

test('the runtime-config reader refuses a late completion after the signal aborted', async () => {
  let deliver: ((value: unknown) => void) | undefined;
  const port: RuntimeConfigReaderPort = {
    send: () => new Promise((resolve) => { deliver = resolve; }),
  };
  const reader = createRuntimeConfigReader({ region: 'ap-southeast-1', stateTable: 'state', client: port });
  const controller = new AbortController();
  const pending = reader.read(controller.signal);
  controller.abort();
  deliver?.({ Item: { ...RUNTIME_CONFIG_KEY, config: null } });
  await assert.rejects(pending, isCode('TIMEOUT'));
});

test('a consent handler parented to an aborted enclosing budget refuses before any store read', async () => {
  let reads = 0;
  const store: ConsentStore = {
    async read(): Promise<ConsentGrant> { reads += 1; return Object.freeze({ accepted: false, version: 'rag-consent.v1', generation: 0 }); },
    async write(): Promise<ConsentGrant> { return Object.freeze({ accepted: false, version: 'rag-consent.v1', generation: 0 }); },
  };
  const controller = new AbortController();
  controller.abort();
  const handler = createConsentHandler({
    store,
    assertActor: () => {},
    signal: controller.signal,
  });
  const response = await handler({
    rawPath: '/ai/rag/consent',
    requestContext: { http: { method: 'GET' }, authorizer: { jwt: { claims: { sub: ACTOR, token_use: 'access' } } } },
  } as unknown as APIGatewayProxyEventV2WithJWTAuthorizer);
  assert.equal(response.statusCode, 504);
  assert.match(response.body, /"code":"TIMEOUT"/);
  assert.equal(reads, 0);
  assert.throws(() => createConsentHandler({ store, assertActor: () => {}, signal: 'nope' as unknown as AbortSignal }), isCode('LIVE_POLICY_NOT_CONFIGURED'));
});

test('authority preserves typed SOURCE_CHANGED and INDEX_NOT_READY store failures', async () => {
  const request = parseRequest(JSON.stringify({ wireVersion: 1, question: 'q', scope: { type: 'account' } }));
  for (const code of ['SOURCE_CHANGED', 'INDEX_NOT_READY'] as const) {
    await assert.rejects(
      () => beginContext(ACTOR, request, { async read() { throw new RagFailure(code); } }, new AbortController().signal),
      isCode(code),
    );
  }
  await assert.rejects(
    () => beginContext(ACTOR, request, { async read() { throw new Error('plain'); } }, new AbortController().signal),
    isCode('PROVIDER_UNAVAILABLE'),
  );
});

test('the query ports keep LIVE_POLICY_NOT_CONFIGURED and CONSENT_REQUIRED from the guarded store', async () => {
  const depsFor = (code: string) => ({
    store: {
      async load(): Promise<never> { throw new IndexFailure(code, false); },
      async acquire() { return null; }, async publish() { return false; },
      async finish() {}, async reserveEmbedding() {},
    },
    artifacts: { async read() { throw new IndexFailure('INDEX_NOT_READY', false); } },
    embedding: { count: () => 0, async embed() { return []; } },
  });
  for (const code of ['LIVE_POLICY_NOT_CONFIGURED', 'CONSENT_REQUIRED'] as const) {
    const ports = createQueryPorts(depsFor(code) as never);
    await assert.rejects(() => ports.authority.read(ACTOR, new AbortController().signal), isCode(code));
  }
  // An unknown port failure still falls back to INDEX_NOT_READY, as before.
  const ports = createQueryPorts(depsFor('SOMETHING_ELSE') as never);
  await assert.rejects(() => ports.authority.read(ACTOR, new AbortController().signal), isCode('INDEX_NOT_READY'));
});

test('the shipped public policy stays closed', () => {
  assert.equal(policy.runtimeEnabled, false);
  assert.equal(policy.jev.liveModel, null);
  assert.equal(policy.jev.liveThresholds, null);
});
