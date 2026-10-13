/**
 * Phase 5 runtime config tests: the exact stored shape, the pinned reviewed case hash, the
 * corpus-owners-equals-policy-owners rule, the unfrozen-storage/deep-freeze contract and the
 * strongly consistent reader with its typed SDK/abort mapping. No AWS, network or provider call
 * is made; the injected port records the one command the reader issues.
 *
 * Runner: node --import tsx --test amplify/rag/phase5/runtime_config.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { GetCommand } from '@aws-sdk/lib-dynamodb';
import { RagFailure } from '../types';
import {
  RUNTIME_CASE_HASH, RUNTIME_CONFIG_KEY, RUNTIME_CONFIG_VERSION, RUNTIME_CORPUS_KIND,
  createRuntimeConfigReader, parseRuntimeConfig, sameRuntimeConfig,
} from './runtime_config';
import type { RuntimeConfig, RuntimeConfigReaderPort, RuntimeConfigSendOptions } from './runtime_config';

const OWNER = '00000001-0000-4000-8000-000000000001';
const OWNER_2 = '00000002-0000-4000-8000-000000000002';
const DIGEST = 'a'.repeat(64);

type Row = Record<string, unknown>;

const note = (noteId: string, inputDigest = DIGEST): Row => ({ noteId, inputDigest });
const policy = (patch: Row = {}): Row => ({
  enabled: true,
  owners: [OWNER],
  model: 'jev-1.13.0',
  thresholds: { answerabilityMin: 0.85, conflictMax: 0.1 },
  ...patch,
});
const rawConfig = (patch: Row = {}, corpusPatch: Row = {}): Row => ({
  version: RUNTIME_CONFIG_VERSION,
  generation: 1,
  policy: policy(),
  corpus: {
    kind: RUNTIME_CORPUS_KIND,
    caseHash: RUNTIME_CASE_HASH,
    owners: { [OWNER]: [note('n1')] },
    ...corpusPatch,
  },
  ...patch,
});

const refused = (fn: () => unknown): boolean => {
  try {
    fn();
    return false;
  } catch (error) {
    return error instanceof RagFailure && error.code === 'LIVE_POLICY_NOT_CONFIGURED';
  }
};

const refusedAsync = async (fn: () => Promise<unknown>): Promise<boolean> => {
  try {
    await fn();
    return false;
  } catch (error) {
    return error instanceof RagFailure && error.code === 'LIVE_POLICY_NOT_CONFIGURED';
  }
};

/** A whole stored row: the two key attributes plus the `config` payload. */
const row = (patch: Row = {}): Row => ({ ...RUNTIME_CONFIG_KEY, config: rawConfig(), ...patch });

test('a valid unfrozen stored config parses into a deep-frozen snapshot', () => {
  const input = rawConfig();
  const parsed = parseRuntimeConfig(input);
  assert.equal(parsed.version, RUNTIME_CONFIG_VERSION);
  assert.equal(parsed.generation, 1);
  assert.equal(parsed.policy.enabled, true);
  assert.deepEqual(parsed.policy.owners, [OWNER]);
  assert.equal(parsed.corpus.caseHash, RUNTIME_CASE_HASH);
  assert.deepEqual(parsed.corpus.owners[OWNER], [{ noteId: 'n1', inputDigest: DIGEST }]);
  assert.ok(Object.isFrozen(parsed));
  assert.ok(Object.isFrozen(parsed.policy) && Object.isFrozen(parsed.policy.owners));
  assert.ok(Object.isFrozen(parsed.corpus) && Object.isFrozen(parsed.corpus.owners));
  assert.ok(Object.isFrozen(parsed.corpus.owners[OWNER]) && Object.isFrozen(parsed.corpus.owners[OWNER][0]));
  // The caller's stored object is copied, never frozen in place or mutated.
  assert.ok(!Object.isFrozen(input));
  assert.ok(!Object.isFrozen((input['corpus'] as Row)['owners']));
});

test('a six-note reviewed pilot is trusted, and the legacy or unknown kind is refused', () => {
  const reviewedNotes = Array.from({ length: 6 }, (_, index) =>
    note(`n${index + 1}`, (index + 1).toString(16).repeat(64).slice(0, 64)));
  const parsed = parseRuntimeConfig(rawConfig({}, {
    kind: 'reviewed-pilot', owners: { [OWNER]: reviewedNotes },
  }));
  assert.equal(RUNTIME_CORPUS_KIND, 'reviewed-pilot');
  assert.equal(parsed.corpus.kind, 'reviewed-pilot');
  assert.equal(parsed.corpus.owners[OWNER].length, 6);
  assert.deepEqual(parsed.corpus.owners[OWNER], reviewedNotes);
  assert.ok(Object.isFrozen(parsed.corpus.owners[OWNER]));
  // The previous `synthetic-quality` kind and any unknown kind are not configured; no fallback.
  assert.ok(refused(() => parseRuntimeConfig(rawConfig({}, { kind: 'synthetic-quality' }))));
  assert.ok(refused(() => parseRuntimeConfig(rawConfig({}, { kind: 'reviewed-pilot-v2' }))));
});

test('a disabled policy and an empty owner set are valid configuration', () => {
  const disabled = parseRuntimeConfig(rawConfig({
    policy: policy({ enabled: false, owners: [] }),
    corpus: { kind: RUNTIME_CORPUS_KIND, caseHash: RUNTIME_CASE_HASH, owners: {} },
  }));
  assert.equal(disabled.policy.enabled, false);
  assert.deepEqual(disabled.corpus.owners, {});
});

test('malformed version, generation, policy and corpus keys are refused', () => {
  const cases: ReadonlyArray<readonly [string, Row]> = [
    ['missing config key', (() => { const c = rawConfig(); delete c['generation']; return c; })()],
    ['unknown config key', rawConfig({ extra: true })],
    ['wrong version', rawConfig({ version: 'rag-pilot-config.v2' })],
    ['generation zero', rawConfig({ generation: 0 })],
    ['generation negative', rawConfig({ generation: -1 })],
    ['generation fractional', rawConfig({ generation: 1.5 })],
    ['generation NaN', rawConfig({ generation: Number.NaN })],
    ['generation string', rawConfig({ generation: '1' })],
    ['generation unsafe', rawConfig({ generation: Number.MAX_SAFE_INTEGER + 1 })],
    ['missing policy', rawConfig({ policy: undefined })],
    ['policy model drift', rawConfig({ policy: policy({ model: 'jev-1.12.0' }) })],
    ['policy threshold drift', rawConfig({ policy: policy({ thresholds: { answerabilityMin: 0.9, conflictMax: 0.1 } }) })],
    ['policy unknown key', rawConfig({ policy: policy({ extra: 1 }) })],
    ['policy six owners', rawConfig({
      policy: policy({ owners: [OWNER, OWNER_2, '00000003-0000-4000-8000-000000000003',
        '00000004-0000-4000-8000-000000000004', '00000005-0000-4000-8000-000000000005',
        '00000006-0000-4000-8000-000000000006'] }),
    })],
    ['corpus unknown key', rawConfig({}, { extra: true })],
    ['corpus kind mismatch', rawConfig({}, { kind: 'real-notes' })],
    ['corpus case hash mismatch', rawConfig({}, { caseHash: `sha256:${'0'.repeat(64)}` })],
    ['owners not a record', rawConfig({}, { owners: [note('n1')] })],
    ['owner not a cognito sub', rawConfig({}, { owners: { actor: [note('n1')] } })],
    ['owner missing from policy', rawConfig({}, { owners: { [OWNER]: [note('n1')], [OWNER_2]: [note('n2')] } })],
    ['policy owner missing from corpus', rawConfig({ policy: policy({ owners: [OWNER, OWNER_2] }) })],
    ['empty owner list', rawConfig({}, { owners: { [OWNER]: [] } })],
    ['note unknown key', rawConfig({}, { owners: { [OWNER]: [{ noteId: 'n1', inputDigest: DIGEST, extra: 1 }] } })],
    ['note missing digest', rawConfig({}, { owners: { [OWNER]: [{ noteId: 'n1' }] } })],
    ['note id invalid', rawConfig({}, { owners: { [OWNER]: [{ noteId: ' n1', inputDigest: DIGEST }] } })],
    ['duplicate note id', rawConfig({}, { owners: { [OWNER]: [note('n1'), note('n1')] } })],
    ['digest uppercase', rawConfig({}, { owners: { [OWNER]: [note('n1', 'A'.repeat(64))] } })],
    ['digest short', rawConfig({}, { owners: { [OWNER]: [note('n1', 'a'.repeat(63))] } })],
    ['digest non-hex', rawConfig({}, { owners: { [OWNER]: [note('n1', `${'a'.repeat(63)}z`)] } })],
    ['digest non-string', rawConfig({}, { owners: { [OWNER]: [note('n1', 7 as unknown as string)] } })],
  ];
  for (const [label, value] of cases) {
    assert.ok(refused(() => parseRuntimeConfig(value)), label);
  }
  assert.ok(refused(() => parseRuntimeConfig(null)));
  assert.ok(refused(() => parseRuntimeConfig([])));
  assert.ok(refused(() => parseRuntimeConfig('config')));
});

test('identity comparison covers version, generation, policy and the whole corpus', () => {
  const base = parseRuntimeConfig(rawConfig());
  const same = parseRuntimeConfig(rawConfig());
  assert.ok(sameRuntimeConfig(base, same));
  assert.ok(!sameRuntimeConfig(base, parseRuntimeConfig(rawConfig({ generation: 2 }))));
  assert.ok(!sameRuntimeConfig(base, parseRuntimeConfig(rawConfig({ policy: policy({ enabled: false }) }))));
  assert.ok(!sameRuntimeConfig(base, parseRuntimeConfig(rawConfig({}, { owners: { [OWNER]: [note('n2')] } }))));
  assert.ok(!sameRuntimeConfig(base, parseRuntimeConfig(rawConfig({}, {
    owners: { [OWNER]: [note('n1', 'b'.repeat(64))] },
  }))));
});

test('the reader issues one strongly consistent keyed Get with the caller signal', async () => {
  const calls: Array<{ command: GetCommand; options: RuntimeConfigSendOptions | undefined }> = [];
  const port: RuntimeConfigReaderPort = {
    async send(command, options) { calls.push({ command, options }); return { Item: row() }; },
  };
  const reader = createRuntimeConfigReader({ region: 'ap-southeast-1', stateTable: 'state', client: port });
  const controller = new AbortController();
  const parsed = await reader.read(controller.signal);
  assert.equal(parsed.generation, 1);
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].command.input, {
    TableName: 'state', Key: RUNTIME_CONFIG_KEY, ConsistentRead: true,
  });
  assert.equal(calls[0].options?.abortSignal, controller.signal);
});

test('an absent, foreign-keyed or unknown-keyed row is not configured', async () => {
  const respond = async (item: unknown): Promise<boolean> => {
    const reader = createRuntimeConfigReader({
      region: 'ap-southeast-1', stateTable: 'state',
      client: { async send() { return item === undefined ? {} : { Item: item }; } },
    });
    return refusedAsync(() => reader.read(new AbortController().signal));
  };
  assert.ok(await respond(undefined));
  assert.ok(await respond(row({ ownerId: 'CONFIG#OTHER' })));
  assert.ok(await respond(row({ noteId: 'PILOT#2' })));
  assert.ok(await respond(row({ ttl: 1 })));
  assert.ok(await respond(row({ config: rawConfig({ generation: 0 }) })));
  assert.ok(await respond(row({ config: rawConfig({}, { caseHash: 'sha256:nope' }) })));
});

test('SDK failures keep a typed code, and a fired deadline wins', async () => {
  const failure = (error: unknown, abort = false) => {
    const controller = new AbortController();
    const reader = createRuntimeConfigReader({
      region: 'ap-southeast-1', stateTable: 'state',
      client: { async send() { if (abort) controller.abort(); throw error; } },
    });
    return reader.read(controller.signal);
  };
  const codeOf = async (promise: Promise<unknown>): Promise<string | null> => {
    try { await promise; return null; } catch (error) { return error instanceof RagFailure ? error.code : 'NOT_RAG'; }
  };
  assert.equal(await codeOf(failure(Object.assign(new Error('x'), { name: 'ThrottlingException' }))), 'RATE_LIMITED');
  assert.equal(await codeOf(failure(Object.assign(new Error('x'), {
    name: 'InternalServerError', $metadata: { httpStatusCode: 503 },
  }))), 'PROVIDER_UNAVAILABLE');
  assert.equal(await codeOf(failure(Object.assign(new Error('x'), {
    name: 'ValidationException', $metadata: { httpStatusCode: 400 },
  }))), 'LIVE_POLICY_NOT_CONFIGURED');
  assert.equal(await codeOf(failure(Object.assign(new Error('x'), {
    name: 'AccessDeniedException', $metadata: { httpStatusCode: 403 },
  }))), 'LIVE_POLICY_NOT_CONFIGURED');
  assert.equal(await codeOf(failure(Object.assign(new Error('x'), {
    name: 'ResourceNotFoundException', $metadata: { httpStatusCode: 404 },
  }))), 'LIVE_POLICY_NOT_CONFIGURED');
  assert.equal(await codeOf(failure(new Error('socket hang up'))), 'PROVIDER_UNAVAILABLE');
  assert.equal(await codeOf(failure(new Error('aborted'), true)), 'TIMEOUT');
});

test('construction validates the region, table and injected port', () => {
  assert.ok(createRuntimeConfigReader({ region: 'ap-southeast-1', stateTable: 'state' }));
  assert.ok(refused(() => createRuntimeConfigReader({ region: 'not-a-region', stateTable: 'state' })));
  assert.ok(refused(() => createRuntimeConfigReader({ region: 'ap-southeast-1', stateTable: '' })));
  assert.ok(refused(() => createRuntimeConfigReader({ region: 'ap-southeast-1', stateTable: 'state', client: {} as never })));
  assert.ok(refused(() => createRuntimeConfigReader(null as never)));
});
