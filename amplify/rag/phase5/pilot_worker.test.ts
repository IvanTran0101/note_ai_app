/**
 * Phase 5 pilot worker adapter tests (plan 5.3B). Everything runs through the real
 * `createPilotWorkerHandler` → guarded `createPilotIndexStore` → `createIndexWorker` →
 * `createStreamHandler`/`runManualJob` chain over injected fakes; no AWS, network or model call.
 *
 * Runner: node --import tsx --test amplify/rag/phase5/pilot_worker.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CONSENT_VERSION } from '../contract';
import { embeddingInputDigest, checksum, decodeSnapshot, encodeSnapshot, sha256Hex } from '../indexing/snapshot';
import { fingerprint } from '../indexing/jobs';
import type {
  Artifacts, Embedding, IndexNote, IndexState, IndexStore, Job, JobStatus, Lease, Manifest, Snapshot,
} from '../indexing/types';
import { IndexFailure, JOB_POLICY_VERSION, LEASE_MS, WORKER_MS } from '../indexing/types';
import { WORKER_MARGIN_MS } from '../indexing/stream';
import type { Counter } from '../types';
import { RagFailure } from '../types';
import { RUNTIME_CASE_HASH, parseRuntimeConfig } from './runtime_config';
import type { RuntimeConfig } from './runtime_config';
import { createPilotWorkerHandler, sanitizePilotMetadata } from './pilot_worker';

const ACTOR = '00000001-0000-4000-8000-000000000001';
const OTHER = '00000009-0000-4000-8000-000000000009';
const STREAM = 'arn:aws:dynamodb:ap-southeast-1:111111111111:table/notes/stream/pilot';
const TITLE = 'Pilot note';
const CONTENT = 'Approved synthetic body';
const DIGEST = embeddingInputDigest(TITLE, CONTENT);
type Row = Record<string, unknown>;

const unitWith = (value: number): readonly number[] => {
  const vector = new Array<number>(1024).fill(0);
  vector[0] = value;
  return Object.freeze(vector);
};

const isFailure = (code: string, retryable?: boolean) => (error: unknown): boolean =>
  error instanceof IndexFailure && error.code === code &&
  (retryable === undefined || error.retryable === retryable);

const note = (over: Partial<IndexNote> = {}): IndexNote => ({
  ownerId: ACTOR, noteId: 'n1', revision: 1, title: TITLE, content: CONTENT,
  synced: true, protected: false, deleted: false, available: true, protectionRevision: 0, ...over,
});
const consent = (accepted: boolean, generation = 1): IndexState['consent'] =>
  ({ accepted, version: CONSENT_VERSION, generation });
const state = (over: Partial<IndexState> = {}): IndexState =>
  ({ ownerId: ACTOR, accountEpoch: 0, consent: consent(true), notes: [note()], manifest: null, ...over });

const policyRaw = (enabled = true, owners: readonly string[] = [ACTOR]): Row => ({
  enabled, owners: [...owners], model: 'jev-1.13.0',
  thresholds: { answerabilityMin: 0.85, conflictMax: 0.1 },
});
const rawConfig = (patch: Row = {}): Row => ({
  version: 'rag-pilot-config.v1',
  generation: 1,
  policy: policyRaw(),
  corpus: {
    kind: 'reviewed-pilot', caseHash: RUNTIME_CASE_HASH,
    owners: { [ACTOR]: [{ noteId: 'n1', inputDigest: DIGEST }] },
  },
  ...patch,
});

const recordFor = (
  ownerId: string, sortKey: string, sequence: string,
  eventName = 'MODIFY', extra: Row = {},
): Row => ({
  eventSourceARN: STREAM,
  eventSource: 'aws:dynamodb',
  eventName,
  eventID: `evt-${sequence}`,
  dynamodb: {
    Keys: { ownerId: { S: `OWNER#${ownerId}` }, noteId: { S: sortKey } },
    ...(eventName === 'REMOVE' ? {} : { NewImage: { revision: { N: '1' } } }),
    SequenceNumber: sequence,
  },
  ...extra,
});
const stream = (...records: Row[]): Row => ({ Records: records });
const manualJob = (over: Partial<Job> = {}): Job => ({
  jobVersion: 1, kind: 'RECONCILE_NOTE', ownerId: ACTOR, noteId: 'n1',
  sourceRevisionHint: 1, policyVersion: JOB_POLICY_VERSION, eventId: 'manual-1', ...over,
});

class MemoryStore implements IndexStore {
  lease: Readonly<{ token: string; fingerprint: string; expiresAt: number }> | null = null;
  loads = 0;
  reserves = 0;
  publishes = 0;
  loadedOwners: string[] = [];
  finishes: Readonly<{ status: string; code: string }>[] = [];
  manifests: Manifest[] = [];
  constructor(public state: IndexState) {}
  async load(ownerId: string): Promise<IndexState> {
    this.loads += 1;
    this.loadedOwners.push(ownerId);
    return this.state;
  }
  async acquire(state_: IndexState, requested: string, nowMs: number): Promise<Lease | null> {
    if (this.lease !== null && this.lease.expiresAt > nowMs) return null;
    if (state_.manifest !== null && state_.manifest.fingerprint === requested) return null;
    const token = `lease-${this.loads}-${this.publishes}`;
    this.lease = { token, fingerprint: requested, expiresAt: nowMs + LEASE_MS };
    return Object.freeze({ token, fingerprint: requested, expiresAt: this.lease.expiresAt });
  }
  async publish(state_: IndexState, lease: Lease, manifest: Manifest, nowMs: number): Promise<boolean> {
    if (this.lease === null || this.lease.token !== lease.token) return false;
    if (this.lease.expiresAt <= nowMs) { this.lease = null; return false; }
    if (manifest.ownerId !== this.state.ownerId) return false;
    if (manifest.generation !== (this.state.manifest?.generation ?? 0) + 1) return false;
    if (fingerprint(this.state) !== lease.fingerprint) return false;
    this.state = { ...this.state, manifest };
    this.manifests.push(manifest);
    this.publishes += 1;
    return true;
  }
  async finish(_ownerId: string, lease: Lease, status: JobStatus, code: string): Promise<void> {
    this.finishes.push({ status, code });
    if (this.lease !== null && this.lease.token === lease.token) this.lease = null;
  }
  async reserveEmbedding(): Promise<void> { this.reserves += 1; }
}

class MemoryArtifacts implements Artifacts {
  snapshots = new Map<string, string>();
  vectors = new Map<string, readonly number[]>();
  cleanupVersions: string[] = [];
  async read(manifest: Manifest): Promise<Snapshot> {
    const text = this.snapshots.get(manifest.version);
    if (text === undefined) throw new IndexFailure('INDEX_NOT_READY', false);
    return decodeSnapshot(text);
  }
  async put(snapshot: Snapshot): Promise<Readonly<{ key: string; checksum: string }>> {
    this.snapshots.set(snapshot.version, encodeSnapshot(snapshot));
    return { key: `snap#${snapshot.version}`, checksum: checksum(snapshot) };
  }
  async putVectors(_snapshot: Snapshot, vectors: ReadonlyMap<string, readonly number[]>): Promise<void> {
    for (const [key, vector] of vectors) this.vectors.set(key, vector);
  }
  async getVectors(keys: readonly string[]): Promise<ReadonlyMap<string, readonly number[]>> {
    const found = new Map<string, readonly number[]>();
    for (const key of keys) {
      const vector = this.vectors.get(key);
      if (vector !== undefined) found.set(key, vector);
    }
    return found;
  }
  async query(): Promise<readonly string[]> { return []; }
  async cleanup(manifest: Manifest): Promise<void> {
    this.cleanupVersions.push(manifest.version);
    this.snapshots.delete(manifest.version);
  }
}

class MemoryEmbedding implements Embedding {
  calls: string[][] = [];
  count: Counter = (text) => Array.from(text).length;
  hook: (() => void | Promise<void>) | null = null;
  dispatch: ((beforeDispatch?: () => Promise<void>) => Promise<void>) | null = null;
  failWith: IndexFailure | null = null;
  async embed(
    texts: readonly string[],
    _purpose?: 'search_document' | 'search_query',
    _signal?: AbortSignal,
    beforeDispatch?: () => Promise<void>,
  ): Promise<readonly (readonly number[])[]> {
    this.calls.push([...texts]);
    if (this.hook !== null) await this.hook();
    if (this.dispatch !== null) await this.dispatch(beforeDispatch);
    if (this.failWith !== null) throw this.failWith;
    return texts.map(() => unitWith(this.calls.length));
  }
}

type RigOptions = Readonly<{
  state?: IndexState;
  config?: Row;
  onRead?: (call: number) => void;
  onCohere?: () => void | Promise<void>;
  onEmbed?: () => void | Promise<void>;
  onRecover?: () => void | Promise<void>;
  now?: () => number;
}>;

const rig = (options: RigOptions = {}) => {
  let current = options.config ?? rawConfig();
  const store = new MemoryStore(options.state ?? state());
  const artifacts = new MemoryArtifacts();
  const embedding = new MemoryEmbedding();
  if (options.onEmbed !== undefined) embedding.hook = options.onEmbed;
  const budgetCalls: number[] = [];
  const recoverCalls: Array<{ owner: string; signal: AbortSignal; store: IndexStore }> = [];
  const logs: Array<Record<string, unknown>> = [];
  let reads = 0;
  const readConfig = async (): Promise<RuntimeConfig> => {
    reads += 1;
    options.onRead?.(reads);
    return parseRuntimeConfig(current);
  };
  const handler = createPilotWorkerHandler({
    readConfig,
    runtime: () => ({ store, artifacts, embedding, log: (metadata) => logs.push({ ...metadata }) }),
    budget: {
      async acquireCohere(): Promise<void> {
        budgetCalls.push(1);
        if (options.onCohere !== undefined) await options.onCohere();
      },
    },
    recover: async (owner, signal, guarded) => {
      recoverCalls.push({ owner, signal, store: guarded });
      if (options.onRecover !== undefined) await options.onRecover();
      return { retired: 0, orphans: 0 };
    },
    streamArn: STREAM,
    log: (metadata) => logs.push({ ...metadata }),
    ...(options.now !== undefined ? { now: options.now } : {}),
  });
  return {
    handler, store, artifacts, embedding, logs, budgetCalls, recoverCalls,
    setConfig: (raw: Row): void => { current = raw; },
    get reads(): number { return reads; },
  };
};

const failuresOf = (result: unknown): readonly Readonly<{ itemIdentifier: string }>[] =>
  (result as { batchItemFailures: readonly Readonly<{ itemIdentifier: string }>[] }).batchItemFailures;

test('the pilot log sanitizer hashes identities and drops everything unsafe', () => {
  const sanitized = sanitizePilotMetadata({
    event: 'index.failed',
    code: 'SECRET-LEAK-PAYLOAD',
    ownerId: ACTOR,
    noteId: 'n1',
    eventId: 'evt-1',
    error: 'raw provider payload',
    title: 'private title',
    content: 'private body',
    token: 'env-secret',
    status: 'FAILED',
    documents: 3,
    bogus: 1,
  });
  assert.equal(sanitized.event, 'index.failed');
  assert.equal(sanitized.code, 'UNKNOWN');
  assert.equal(sanitized.owner, sha256Hex(ACTOR));
  assert.equal(sanitized.note, sha256Hex('n1'));
  assert.equal(sanitized.eventRef, sha256Hex('evt-1'));
  assert.equal(sanitized.status, 'FAILED');
  assert.equal(sanitized.documents, 3);
  for (const raw of ['SECRET-LEAK-PAYLOAD', 'raw provider payload', 'private title', 'private body', 'env-secret']) {
    assert.ok(!JSON.stringify(sanitized).includes(raw), `sanitized log must not contain ${raw}`);
  }
  assert.equal('bogus' in sanitized, false);
  assert.equal('error' in sanitized, false);
  // Unknown event/status/kind tokens are dropped, never echoed.
  const unknown = sanitizePilotMetadata({ event: 'evil.event', status: 'PWNED', kind: 'X', code: 42 });
  assert.deepEqual({ ...unknown }, { code: 'UNKNOWN' });
});

test('an ARN or eventSource mismatch rejects the whole batch before any load', async () => {
  const badArn = rig();
  await assert.rejects(
    badArn.handler(stream(recordFor(ACTOR, 'NOTE#n1', '1', 'MODIFY', { eventSourceARN: 'arn:other' }))),
    isFailure('UNTRUSTED_STREAM', false),
  );
  assert.equal(badArn.store.loads, 0);
  assert.equal(badArn.embedding.calls.length, 0);

  const badSource = rig();
  await assert.rejects(
    badSource.handler(stream(recordFor(ACTOR, 'NOTE#n1', '1', 'MODIFY', { eventSource: 'aws:s3' }))),
    isFailure('UNTRUSTED_STREAM', false),
  );
  assert.equal(badSource.store.loads, 0);
});

test('a mixed batch loads only listed/approved rows and never reads non-pilot bodies', async () => {
  const h = rig();
  const result = await h.handler(stream(
    recordFor(ACTOR, 'NOTE#n1', '1'),
    recordFor(OTHER, 'NOTE#n1', '2'),
    recordFor(ACTOR, 'NOTE#n2', '3'),
    recordFor(ACTOR, 'META#x', '4'),
    recordFor(ACTOR, 'RAG#RETIRE#v1', '5'),
  ));
  assert.deepEqual(failuresOf(result), []);
  assert.deepEqual([...new Set(h.store.loadedOwners)], [ACTOR]);
  assert.equal(h.embedding.calls.length, 1);
  assert.equal(h.store.manifests.length, 1);
  assert.equal(h.store.manifests[0]?.status, 'READY');
});

test('original huge BigInt sequences coalesce into the earliest account replay point', async () => {
  const h = rig({ now: () => 1_000 });
  h.store.lease = Object.freeze({ token: 'held', fingerprint: 'a'.repeat(64), expiresAt: 10_000 });
  const result = await h.handler(stream(
    recordFor(ACTOR, 'NOTE#n1', '10000000000000000000000001'),
    recordFor(ACTOR, 'PROTECTION#n1', '10000000000000000000000001'),
    recordFor(ACTOR, 'RAG#CONSENT', '10000000000000000000000003'),
  ));
  assert.deepEqual(failuresOf(result), [{ itemIdentifier: '10000000000000000000000001' }]);
  assert.equal(h.embedding.calls.length, 0);
});

test('a disabled policy with revoked consent still publishes BLOCKED cleanup with no paid work', async () => {
  const h = rig({
    config: rawConfig({ policy: policyRaw(false) }),
    state: state({ consent: consent(false, 2) }),
  });
  const result = await h.handler(stream(recordFor(ACTOR, 'NOTE#n1', '1')));
  assert.deepEqual(failuresOf(result), []);
  assert.equal(h.embedding.calls.length, 0);
  assert.equal(h.budgetCalls.length, 0);
  assert.equal(h.store.manifests[0]?.status, 'BLOCKED');
  assert.ok(h.store.finishes.some((entry) => entry.status === 'BLOCKED' && entry.code === 'CONSENT_REQUIRED'));
});

test('a disabled policy with accepted consent is refused with no READY and no paid work', async () => {
  const h = rig({ config: rawConfig({ policy: policyRaw(false) }), state: state() });
  const result = await h.handler(stream(recordFor(ACTOR, 'NOTE#n1', '1')));
  assert.deepEqual(failuresOf(result), []);
  assert.equal(h.embedding.calls.length, 0);
  assert.equal(h.budgetCalls.length, 0);
  assert.equal(h.store.manifests.length, 0);
  assert.ok(h.logs.some((entry) => entry['code'] === 'LIVE_POLICY_NOT_CONFIGURED'));
});

test('a missing or malformed config fails closed with no fallback and no load', async () => {
  const missing = rig({ onRead: () => { throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED'); } });
  await assert.rejects(
    missing.handler(stream(recordFor(ACTOR, 'NOTE#n1', '1'))),
    (error: unknown) => error instanceof RagFailure && error.code === 'LIVE_POLICY_NOT_CONFIGURED',
  );
  assert.equal(missing.store.loads, 0);

  const malformed = rig({ config: { version: 'bad' } });
  await assert.rejects(malformed.handler(stream(recordFor(ACTOR, 'NOTE#n1', '1'))));
  assert.equal(malformed.store.loads, 0);
});

test('a warm invocation re-reads config and builds a fresh guard instead of reusing the captured one', async () => {
  const h = rig();
  const first = await h.handler(stream(recordFor(ACTOR, 'NOTE#n1', '1')));
  assert.deepEqual(failuresOf(first), []);
  assert.equal(h.store.manifests.length, 1);
  assert.equal(h.embedding.calls.length, 1);

  // The next invocation's config is both newer and disabled; the canonical state also moved so
  // this is not a simple ALREADY_DONE. A reused gen-1 guard would embed and publish READY again.
  h.setConfig(rawConfig({ generation: 2, policy: policyRaw(false) }));
  h.store.state = state({ notes: [note({ revision: 2 })] });
  const second = await h.handler(stream(recordFor(ACTOR, 'NOTE#n1', '2')));
  assert.deepEqual(failuresOf(second), []);
  assert.equal(h.store.manifests.length, 1, 'the fresh guard refuses the now-disabled config');
  assert.equal(h.embedding.calls.length, 1, 'no new paid embedding under the fresh guard');
  assert.equal(h.budgetCalls.length, 1);
});

test('a config move during the run is a retryable partial failure with no embedding or READY', async () => {
  const h = rig({ onCohere: () => h.setConfig(rawConfig({ generation: 2 })) });
  const result = await h.handler(stream(recordFor(ACTOR, 'NOTE#n1', '7')));
  assert.deepEqual(failuresOf(result), [{ itemIdentifier: '7' }]);
  assert.equal(h.embedding.calls.length, 0);
  assert.equal(h.budgetCalls.length, 1, 'the one reservation was consumed exactly once');
  assert.equal(h.store.manifests.length, 0);
});

test('a source, protection or consent move before publish ends SUPERSEDED with no READY', async () => {
  const mutations: Array<[string, (h: ReturnType<typeof rig>) => void]> = [
    ['revision', (h) => { h.store.state = state({ notes: [note({ revision: 2 })] }); }],
    ['protection', (h) => { h.store.state = state({ notes: [note({ protected: true, protectionRevision: 1 })] }); }],
    ['consent', (h) => { h.store.state = state({ consent: consent(false, 2) }); }],
  ];
  for (const [name, mutate] of mutations) {
    const h = rig();
    h.embedding.dispatch = async (beforeDispatch) => {
      mutate(h);
      if (typeof beforeDispatch === 'function') await beforeDispatch();
    };
    const result = await h.handler(stream(recordFor(ACTOR, 'NOTE#n1', '1')));
    assert.deepEqual(failuresOf(result), [], `${name} move is terminal/acked`);
    assert.equal(h.store.manifests.length, 0, `${name} move publishes nothing`);
    assert.ok(h.store.finishes.some((entry) => entry.status === 'SUPERSEDED'), `${name} superseded`);
  }
});

test('a transient config failure after the paid embed retries the earliest sequence only once', async () => {
  const control = { paid: false };
  const h = rig({
    onRead: () => { if (control.paid) throw new RagFailure('RATE_LIMITED'); },
    onEmbed: () => { control.paid = true; },
    state: state(),
  });
  const result = await h.handler(stream(recordFor(ACTOR, 'NOTE#n1', '42')));
  assert.deepEqual(failuresOf(result), [{ itemIdentifier: '42' }]);
  assert.equal(h.embedding.calls.length, 1, 'exactly one paid embed, no silent extra retry');
  assert.equal(h.budgetCalls.length, 1);
  assert.equal(h.store.manifests.length, 0, 'no READY under a transient config failure');

  // A new invocation re-reads the latest config and can still run the revoked cleanup path.
  control.paid = false;
  h.setConfig(rawConfig({ generation: 2 }));
  h.store.state = state({ consent: consent(false, 3) });
  const recovered = await h.handler(stream(recordFor(ACTOR, 'NOTE#n1', '43')));
  assert.deepEqual(failuresOf(recovered), []);
  assert.equal(h.store.manifests.length, 1);
  assert.equal(h.store.manifests[0]?.status, 'BLOCKED');
  assert.equal(h.embedding.calls.length, 1, 'cleanup stays unpaid');
});

test('a terminal config failure during the run is acknowledged, not replayed', async () => {
  const h = rig({
    onRead: (call) => { if (call >= 2) throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED'); },
  });
  const result = await h.handler(stream(recordFor(ACTOR, 'NOTE#n1', '9')));
  assert.deepEqual(failuresOf(result), []);
  assert.equal(h.embedding.calls.length, 0);
  assert.equal(h.store.manifests.length, 0);
});

test('a malformed approved row is terminal and never fails the whole batch', async () => {
  const h = rig();
  const malformed = { ...recordFor(ACTOR, 'NOTE#n1', '8'), eventName: 'BROKEN' };
  const result = await h.handler(stream(malformed, recordFor(ACTOR, 'NOTE#n1', '9')));
  assert.deepEqual(failuresOf(result), []);
  assert.equal(h.store.manifests.length, 1, 'the valid approved row still reconciles');
  assert.ok(h.logs.some((entry) => entry['event'] === 'index.stream.rejected' && entry['code'] === 'INVALID_JOB'));
  assert.ok(!JSON.stringify(h.logs).includes('BROKEN'));
});

test('manual pilot reconcile requires a listed owner and an approved note', async () => {
  const ok = rig();
  const result = await ok.handler({ operation: 'reconcile', job: manualJob() });
  assert.equal((result as { status: string }).status, 'SUCCEEDED');
  assert.equal((result as { code: string }).code, 'READY');
  assert.equal(ok.embedding.calls.length, 1);

  const foreign = rig();
  await assert.rejects(foreign.handler({ operation: 'reconcile', job: manualJob({ ownerId: OTHER }) }),
    isFailure('LIVE_POLICY_NOT_CONFIGURED', false));
  assert.equal(foreign.store.loads, 0);

  const unapproved = rig();
  await assert.rejects(unapproved.handler({ operation: 'reconcile', job: manualJob({ noteId: 'n9' }) }),
    isFailure('LIVE_POLICY_NOT_CONFIGURED', false));
  assert.equal(unapproved.store.loads, 0);

  // A requester body can never widen the exact manual shape.
  const widened = rig();
  await assert.rejects(widened.handler({ operation: 'reconcile', job: manualJob(), body: '{}' }),
    isFailure('INVALID_JOB', false));
  assert.equal(widened.store.loads, 0);
});

test('manual pilot recover binds the guarded store and a bounded independent signal', async () => {
  const h = rig();
  const result = await h.handler({ operation: 'recover', ownerId: ACTOR });
  assert.deepEqual(result, { retired: 0, orphans: 0 });
  assert.equal(h.recoverCalls.length, 1);
  assert.equal(h.recoverCalls[0]?.owner, ACTOR);
  assert.ok(h.recoverCalls[0]?.signal instanceof AbortSignal);
  assert.equal(typeof h.recoverCalls[0]?.store.load, 'function');
  assert.equal(typeof h.recoverCalls[0]?.store.reserveEmbedding, 'function');

  const foreign = rig();
  await assert.rejects(foreign.handler({ operation: 'recover', ownerId: OTHER }),
    isFailure('LIVE_POLICY_NOT_CONFIGURED', false));
  assert.equal(foreign.recoverCalls.length, 0);
});

test('unknown or HTTP-shaped invocations are rejected without a synthetic bypass', async () => {
  for (const event of [
    { operation: 'nope' },
    { body: '{}', requestContext: { authorizer: { jwt: { claims: { sub: ACTOR } } } } },
    { operation: 'retrieve', ownerId: ACTOR, body: '{}' },
    null,
    'not-an-event',
  ]) {
    const h = rig();
    await assert.rejects(h.handler(event), isFailure('INVALID_JOB', false));
    assert.equal(h.store.loads, 0);
  }
});

test('pilot logs contain only hashed identities, counters and safe codes', async () => {
  const h = rig();
  await h.handler(stream(
    recordFor(ACTOR, 'NOTE#n1', '5'),
    recordFor(OTHER, 'NOTE#n1', '6'),
    { ...recordFor(ACTOR, 'NOTE#n1', '7'), eventName: 'BROKEN' },
  ));
  const serialized = JSON.stringify(h.logs);
  for (const raw of [ACTOR, OTHER, TITLE, CONTENT]) {
    assert.ok(!serialized.includes(raw), `logs must not contain ${raw}`);
  }
  for (const entry of h.logs) {
    assert.equal('ownerId' in entry, false);
    assert.equal('noteId' in entry, false);
    if (typeof entry['code'] === 'string') assert.match(entry['code'], /^[A-Z][A-Z0-9_]*$/);
  }
  assert.ok(h.logs.some((entry) => entry['owner'] === sha256Hex(ACTOR)));
});

test('an untrusted provider error string is normalized away from the logs', async () => {
  const h = rig();
  h.embedding.failWith = new IndexFailure('EVIL PAYLOAD <script>', false);
  const result = await h.handler(stream(recordFor(ACTOR, 'NOTE#n1', '1')));
  assert.deepEqual(failuresOf(result), []);
  assert.ok(!JSON.stringify(h.logs).includes('EVIL PAYLOAD'));
  assert.ok(h.logs.some((entry) => entry['code'] === 'UNKNOWN'));
});

test('construction validates the injected dependencies', () => {
  const base = {
    readConfig: async (): Promise<RuntimeConfig> => parseRuntimeConfig(rawConfig()),
    runtime: () => ({ store: new MemoryStore(state()) }) as never,
    budget: { async acquireCohere(): Promise<void> {} },
    recover: async () => ({}),
    streamArn: STREAM,
  };
  assert.ok(createPilotWorkerHandler(base));
  assert.throws(() => createPilotWorkerHandler(null as never), isFailure('INVALID_STATE', false));
  assert.throws(() => createPilotWorkerHandler({ ...base, streamArn: '' }), isFailure('INVALID_STATE', false));
  assert.throws(() => createPilotWorkerHandler({ ...base, budget: {} as never }), isFailure('INVALID_STATE', false));
  assert.throws(() => createPilotWorkerHandler({ ...base, recover: 'no' as never }), isFailure('INVALID_STATE', false));
});

test('a 105s cold config read plus a 10s embed loses the cutoff margin, so no READY', async () => {
  const realNow = Date.now;
  let clock = realNow();
  const start = clock;
  Date.now = () => clock;
  try {
    const h = rig({
      onRead: (call) => { if (call === 1) clock += 105_000; },
      onEmbed: () => { clock += 10_000; },
      now: () => clock,
    });
    const output = await h.handler(stream(recordFor(ACTOR, 'NOTE#n1', '1')));
    assert.equal(clock - start, 115_000, '105s config plus 10s embed is past the 110s fallback');
    assert.equal(h.store.manifests.length, 0, 'the 10s Lambda cutoff margin can no longer be lost to a late READY');
    assert.deepEqual(failuresOf(output), [{ itemIdentifier: '1' }]);
  } finally { Date.now = realNow; }
});

test('cold config time is charged to the one trusted invocation deadline before the worker', async () => {
  const realNow = Date.now;
  let clock = realNow();
  const start = clock;
  Date.now = () => clock;
  try {
    // 4s of a 5s trusted deadline is spent reading config; only 1s is left for the paid work.
    const h = rig({
      onRead: (call) => { if (call === 1) clock += 4_000; },
      onEmbed: () => { clock += 2_000; },
      now: () => clock,
    });
    const output = await h.handler(stream(recordFor(ACTOR, 'NOTE#n1', '1')), start + 5_000);
    assert.equal(clock - start, 6_000, 'the cold config slice is not replenished before the embed');
    assert.equal(h.store.manifests.length, 0, 'config time is charged to the one trusted deadline');
    assert.deepEqual(failuresOf(output), [{ itemIdentifier: '1' }]);
  } finally { Date.now = realNow; }
});

test('a late initial config read never dispatches recovery at a zero deadline', async () => {
  const realNow = Date.now;
  let clock = realNow();
  const start = clock;
  Date.now = () => clock;
  try {
    const h = rig({ onRead: () => { clock += 121_000; } });
    await assert.rejects(
      h.handler({ operation: 'recover', ownerId: ACTOR }, start + WORKER_MS - WORKER_MARGIN_MS),
      isFailure('TIMEOUT', true),
    );
    assert.equal(h.reads, 1, 'the config read happened before the post-await guard refused it');
    assert.equal(h.recoverCalls.length, 0, 'recovery is never dispatched at a zero deadline');
    assert.equal(h.store.loads, 0);
  } finally { Date.now = realNow; }
});

test('an already-expired trusted deadline refuses before any config read or port', async () => {
  const h = rig();
  await assert.rejects(
    h.handler({ operation: 'recover', ownerId: ACTOR }, Date.now() - 1),
    isFailure('TIMEOUT', true),
  );
  assert.equal(h.reads, 0, 'an expired invocation never reads trusted config');
  assert.equal(h.recoverCalls.length, 0);
  assert.equal(h.store.loads, 0);
});

test('a recovery that returns after the deadline is refused, never reported as success', async () => {
  const realNow = Date.now;
  let clock = realNow();
  const start = clock;
  Date.now = () => clock;
  try {
    const h = rig({ onRecover: () => { clock += 111_000; } });
    await assert.rejects(
      h.handler({ operation: 'recover', ownerId: ACTOR }, start + WORKER_MS - WORKER_MARGIN_MS),
      isFailure('TIMEOUT', true),
    );
    assert.equal(h.recoverCalls.length, 1, 'the sweep was reached once, then its late success refused');
  } finally { Date.now = realNow; }
});

test('a policy withdrawal during the awaited dispatch canonical read blocks the paid send', async () => {
  const h = rig();
  const original = h.store.load.bind(h.store);
  let dispatchRead = false;
  let actualPaid = 0;
  h.store.load = async (owner) => {
    const value = await original(owner);
    if (dispatchRead) h.setConfig(rawConfig({ generation: 2, policy: policyRaw(false) }));
    return value;
  };
  h.embedding.embed = async (texts, _purpose, _signal, beforeDispatch) => {
    dispatchRead = true;
    await beforeDispatch?.();
    actualPaid += 1;
    return texts.map(() => unitWith(1));
  };
  const output = await h.handler(stream(recordFor(ACTOR, 'NOTE#n1', '1')));
  assert.equal(actualPaid, 0, 'a withdrawal during the awaited canonical read must not reach paid transport');
  assert.equal(h.store.manifests.length, 0);
  assert.deepEqual(failuresOf(output), [{ itemIdentifier: '1' }]);
});

test('a policy withdrawal during the final publish canonical read blocks READY', async () => {
  const h = rig();
  const original = h.store.load.bind(h.store);
  h.embedding.dispatch = async (beforeDispatch) => { await beforeDispatch?.(); };
  h.store.load = async (owner) => {
    const value = await original(owner);
    if (h.store.loads === 8) h.setConfig(rawConfig({ generation: 2, policy: policyRaw(false) }));
    return value;
  };
  const output = await h.handler(stream(recordFor(ACTOR, 'NOTE#n1', '1')));
  assert.equal(h.store.manifests.length, 0, 'a withdrawal during the final authorize must refuse READY');
  assert.deepEqual(failuresOf(output), [{ itemIdentifier: '1' }]);
});

test('an injected shorter invocation deadline bounds the worker instead of a fresh window', async () => {
  const realNow = Date.now;
  let clock = realNow();
  const start = clock;
  Date.now = () => clock;
  try {
    const h = rig({ onEmbed: () => { clock += 20_000; }, now: () => clock });
    const output = await h.handler(stream(recordFor(ACTOR, 'NOTE#n1', '1')), start + 5_000);
    assert.equal(h.store.manifests.length, 0, 'the 5s deadline must not reset into a fresh 110s window');
    assert.deepEqual(failuresOf(output), [{ itemIdentifier: '1' }]);
  } finally { Date.now = realNow; }
});

test('a non-finite injected invocation deadline fails closed before any load', async () => {
  const h = rig();
  await assert.rejects(
    h.handler(stream(recordFor(ACTOR, 'NOTE#n1', '1')), Number.NaN),
    isFailure('INVALID_STATE', false),
  );
  assert.equal(h.store.loads, 0);
  assert.equal(h.embedding.calls.length, 0);
});
