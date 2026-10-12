/**
 * Indexing worker slice tests — C21/C23 lease fencing, canonical re-reads, vector reuse,
 * budget/reservation, fail-closed ports and cleanup semantics, against cached ports that
 * emulate a real conditional-lease store (CAS on token and canonical fingerprint).
 * Runner: node --import tsx --test amplify/rag/indexing/worker.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CONSENT_VERSION } from '../contract';
import { JOB_POLICY_VERSION, IndexFailure, LEASE_MS, WORKER_MS } from './types';
import type { Counter } from '../types';
import type {
  Artifacts, Embedding, IndexNote, IndexState, IndexStore, Job, JobResult,
  JobStatus, Lease, Manifest, Snapshot,
} from './types';
import { checksum, decodeSnapshot, encodeSnapshot } from './snapshot';
import { fingerprint } from './jobs';
import { createIndexWorker } from './worker';

const unitWith = (value: number): readonly number[] => {
  const vector = new Array<number>(1024).fill(0);
  vector[0] = value;
  return vector;
};

class MemoryStore implements IndexStore {
  lease: Readonly<{ token: string; fingerprint: string; expiresAt: number }> | null = null;
  budget = Number.POSITIVE_INFINITY;
  failPublish = false;
  loads = 0;
  reserves = 0;
  publishes = 0;
  finishes: Readonly<{ status: string; code: string }>[] = [];
  beforeLoad: (() => void) | null = null;
  private counter = 0;
  constructor(public state: IndexState) {}
  async load(): Promise<IndexState> {
    this.loads += 1;
    const hook = this.beforeLoad;
    this.beforeLoad = null;
    hook?.();
    return structuredClone(this.state);
  }
  async acquire(state: IndexState, requested: string, nowMs: number): Promise<Lease | null> {
    if (this.lease !== null && this.lease.expiresAt > nowMs) return null;
    if (state.manifest !== null && state.manifest.fingerprint === requested) return null;
    this.counter += 1;
    const token = `lease-${this.counter}`;
    this.lease = { token, fingerprint: requested, expiresAt: nowMs + LEASE_MS };
    return Object.freeze({ token, fingerprint: requested, expiresAt: this.lease.expiresAt });
  }
  async publish(state: IndexState, lease: Lease, manifest: Manifest, nowMs: number): Promise<boolean> {
    if (this.failPublish) return false;
    if (this.lease === null || this.lease.token !== lease.token) return false;
    if (this.lease.expiresAt <= nowMs) {
      this.lease = null;
      return false;
    }
    if (manifest.ownerId !== this.state.ownerId) return false;
    if (manifest.generation !== (this.state.manifest?.generation ?? 0) + 1) return false;
    if (fingerprint(this.state) !== lease.fingerprint) return false;
    this.state = structuredClone({ ...this.state, manifest });
    this.publishes += 1;
    return true;
  }
  async finish(ownerId: string, lease: Lease, status: JobStatus, code: string): Promise<void> {
    this.finishes.push({ status, code });
    // Conditional on the fencing token: an expired or replaced lease is never released.
    if (this.lease !== null && this.lease.token === lease.token) this.lease = null;
  }
  async reserveEmbedding(): Promise<void> {
    this.reserves += 1;
    if (this.reserves > this.budget) throw new IndexFailure('BUDGET_EXHAUSTED', true);
  }
}

class MemoryArtifacts implements Artifacts {
  snapshots = new Map<string, string>();
  vectorsByVersion = new Map<string, Map<string, readonly number[]>>();
  vectors = new Map<string, readonly number[]>();
  cleanupVersions: string[] = [];
  reads = 0;
  failRead = false;
  failPut = false;
  failCleanup = false;
  corruptChecksum = false;
  async read(manifest: Manifest): Promise<Snapshot> {
    this.reads += 1;
    if (this.failRead) throw new IndexFailure('INDEX_NOT_READY', false);
    const text = this.snapshots.get(manifest.version);
    if (text === undefined) throw new IndexFailure('INDEX_NOT_READY', false);
    return decodeSnapshot(text);
  }
  async put(snapshot: Snapshot): Promise<Readonly<{ key: string; checksum: string }>> {
    if (this.failPut) throw new IndexFailure('ARTIFACT_WRITE_FAILED', false);
    this.snapshots.set(snapshot.version, encodeSnapshot(snapshot));
    return {
      key: `snapshot#${snapshot.version}`,
      checksum: this.corruptChecksum ? 'f'.repeat(64) : checksum(snapshot),
    };
  }
  async putVectors(snapshot: Snapshot, vectors: ReadonlyMap<string, readonly number[]>): Promise<void> {
    this.vectorsByVersion.set(snapshot.version, new Map(vectors));
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
  async query(): Promise<readonly string[]> {
    return [];
  }
  async cleanup(manifest: Manifest): Promise<void> {
    if (this.failCleanup) throw new IndexFailure('PORT_FAILURE', true);
    this.cleanupVersions.push(manifest.version);
    const owned = this.vectorsByVersion.get(manifest.version);
    if (owned !== undefined) for (const key of owned.keys()) this.vectors.delete(key);
    this.vectorsByVersion.delete(manifest.version);
    this.snapshots.delete(manifest.version);
  }
}

class MemoryEmbedding implements Embedding {
  calls: string[][] = [];
  count: Counter = (text) => Array.from(text).length;
  hook: (() => void | Promise<void>) | null = null;
  respond: ((texts: readonly string[]) => readonly (readonly number[])[]) | null = null;
  async embed(texts: readonly string[]): Promise<readonly (readonly number[])[]> {
    this.calls.push([...texts]);
    if (this.hook !== null) await this.hook();
    if (this.respond !== null) return this.respond(texts);
    return texts.map(() => unitWith(this.calls.length));
  }
}

const note = (over: Partial<IndexNote> = {}): IndexNote => ({
  ownerId: 'u1', noteId: 'n1', revision: 1, title: 'T', content: 'hello world',
  synced: true, protected: false, deleted: false, available: true, protectionRevision: 0, ...over,
});

const baseState = (over: Partial<IndexState> = {}): IndexState => ({
  ownerId: 'u1', accountEpoch: 1,
  consent: { accepted: true, version: CONSENT_VERSION, generation: 1 },
  notes: [note()], manifest: null, ...over,
});

const job = (over: Partial<Job> = {}): Job => ({
  jobVersion: 1, kind: 'RECONCILE_NOTE', ownerId: 'u1', noteId: 'n1',
  sourceRevisionHint: 1, policyVersion: JOB_POLICY_VERSION, eventId: 'evt-1', ...over,
});

const rig = (options: Readonly<{ state?: IndexState; clock?: () => number; budget?: number }> = {}) => {
  const store = new MemoryStore(options.state ?? baseState());
  if (options.budget !== undefined) store.budget = options.budget;
  const artifacts = new MemoryArtifacts();
  const embedding = new MemoryEmbedding();
  const logs: Record<string, string | number>[] = [];
  const clock = options.clock ?? (() => 1_000);
  const worker = createIndexWorker({
    store, artifacts, embedding, now: clock, log: (metadata) => logs.push({ ...metadata }),
  });
  return { store, artifacts, embedding, logs, worker };
};

const update = (rigged: ReturnType<typeof rig>, over: Partial<IndexState>): void => {
  rigged.store.state = structuredClone({ ...rigged.store.state, ...over });
};

const versionOf = (result: JobResult): string => {
  assert.ok(result.manifestVersion, 'result carries a manifest version');
  return result.manifestVersion;
};

const published = (artifacts: MemoryArtifacts, version: string): Snapshot =>
  decodeSnapshot(artifacts.snapshots.get(version) as string);

test('publishes READY from the latest canonical state and reserves before embedding', async () => {
  const rigged = rig();
  const result = await rigged.worker(job({ sourceRevisionHint: 1 }));
  assert.equal(result.status, 'SUCCEEDED');
  assert.equal(result.code, 'READY');
  assert.equal(rigged.store.publishes, 1);
  assert.equal(rigged.store.reserves, 1);
  assert.equal(rigged.embedding.calls.length, 1);
  const snapshot = published(rigged.artifacts, versionOf(result));
  assert.equal(snapshot.documents.length, 1);
  assert.equal(snapshot.documents[0]?.chunk.ownerId, 'u1');
  assert.equal(snapshot.documents[0]?.chunk.revision, 1);
  assert.equal(snapshot.documents[0]?.embeddingDigest.length, 64);
  assert.deepEqual(rigged.store.finishes, [{ status: 'SUCCEEDED', code: 'READY' }]);
  assert.equal(rigged.store.state.manifest?.generation, 1);
});

test('a stale revision hint reconciles the latest canonical revision', async () => {
  const rigged = rig({ state: baseState({ notes: [note({ revision: 2 })] }) });
  const result = await rigged.worker(job({ sourceRevisionHint: 1 }));
  assert.equal(result.status, 'SUCCEEDED');
  assert.equal(published(rigged.artifacts, versionOf(result)).documents[0]?.chunk.revision, 2);
});

test('a duplicate job is superseded with no model call and no new generation', async () => {
  const rigged = rig();
  const first = await rigged.worker(job());
  const second = await rigged.worker(job());
  assert.equal(first.status, 'SUCCEEDED');
  assert.deepEqual(second, { status: 'SUPERSEDED', code: 'ALREADY_DONE' });
  assert.equal(rigged.embedding.calls.length, 1);
  assert.equal(rigged.store.publishes, 1);
});

test('a live lease returns SUPERSEDED without touching the model', async () => {
  const rigged = rig();
  rigged.store.lease = { token: 'held', fingerprint: 'a'.repeat(64), expiresAt: 10_000 };
  assert.deepEqual(await rigged.worker(job()), { status: 'SUPERSEDED', code: 'LEASE_BUSY' });
  assert.equal(rigged.embedding.calls.length, 0);
  assert.equal(rigged.store.publishes, 0);
});

test('a canonical change after embedding aborts before publish and flags the staged prefix', async () => {
  const rigged = rig();
  rigged.embedding.hook = () => {
    rigged.store.beforeLoad = () => update(rigged, { notes: [note({ revision: 2 })] });
  };
  const result = await rigged.worker(job());
  assert.deepEqual(result, { status: 'SUPERSEDED', code: 'SOURCE_CHANGED' });
  assert.equal(rigged.store.publishes, 0);
  assert.equal(rigged.store.state.manifest, null);
  assert.ok(rigged.logs.some((entry) => entry['event'] === 'index.orphan.staged'));
  assert.ok(rigged.store.finishes.some((entry) => entry.status === 'SUPERSEDED'));
});

test('a consent revoke before publish aborts instead of publishing stale readiness', async () => {
  const rigged = rig();
  rigged.embedding.hook = () => {
    rigged.store.beforeLoad = () => update(rigged, {
      consent: { accepted: false, version: CONSENT_VERSION, generation: 2 },
    });
  };
  assert.deepEqual(await rigged.worker(job()), { status: 'SUPERSEDED', code: 'SOURCE_CHANGED' });
  assert.equal(rigged.store.publishes, 0);
  assert.equal(rigged.store.state.manifest, null);
});

test('a protection change before publish aborts instead of indexing a locked note', async () => {
  const rigged = rig();
  rigged.embedding.hook = () => {
    rigged.store.beforeLoad = () => update(rigged, {
      notes: [note({ protected: true, protectionRevision: 1 })],
    });
  };
  assert.deepEqual(await rigged.worker(job()), { status: 'SUPERSEDED', code: 'SOURCE_CHANGED' });
  assert.equal(rigged.store.publishes, 0);
});

test('a metadata-only revision reuses floats under a new immutable lineage', async () => {
  const rigged = rig();
  const first = await rigged.worker(job());
  const firstVersion = versionOf(first);
  const oldDocument = published(rigged.artifacts, firstVersion).documents[0];
  assert.ok(oldDocument);
  const oldVector = rigged.artifacts.vectors.get(oldDocument.vectorKey);
  update(rigged, { notes: [note({ revision: 2 })] });
  const second = await rigged.worker(job({ sourceRevisionHint: 2 }));
  assert.equal(second.status, 'SUCCEEDED');
  assert.equal(rigged.embedding.calls.length, 1, 'no new embedding call');
  const newDocument = published(rigged.artifacts, versionOf(second)).documents[0];
  assert.ok(newDocument);
  assert.notEqual(newDocument.vectorKey, oldDocument.vectorKey);
  assert.notEqual(newDocument.chunk.revision, oldDocument.chunk.revision);
  assert.equal(newDocument.embeddingDigest, oldDocument.embeddingDigest);
  assert.deepEqual(rigged.artifacts.vectors.get(newDocument.vectorKey), oldVector);
  assert.equal(oldVector?.[0], 1);
  assert.deepEqual(rigged.artifacts.cleanupVersions, [firstVersion]);
  assert.equal(rigged.store.state.manifest?.generation, 2);
});

test('a lost previous vector is INDEX_NOT_READY instead of an invented vector', async () => {
  const rigged = rig();
  const first = await rigged.worker(job());
  for (const document of published(rigged.artifacts, versionOf(first)).documents) {
    rigged.artifacts.vectors.delete(document.vectorKey);
  }
  update(rigged, { notes: [note({ revision: 2 })] });
  assert.deepEqual(await rigged.worker(job({ sourceRevisionHint: 2 })),
    { status: 'FAILED', code: 'INDEX_NOT_READY' });
  assert.equal(rigged.embedding.calls.length, 1, 'no new embedding call');
  assert.equal(rigged.store.publishes, 1);
});

test('a damaged previous vector is INDEX_NOT_READY instead of a stale score', async () => {
  const rigged = rig();
  const first = await rigged.worker(job());
  const document = published(rigged.artifacts, versionOf(first)).documents[0];
  assert.ok(document);
  rigged.artifacts.vectors.set(document.vectorKey, [1, 2, 3]);
  update(rigged, { notes: [note({ revision: 2 })] });
  assert.deepEqual(await rigged.worker(job({ sourceRevisionHint: 2 })),
    { status: 'FAILED', code: 'INDEX_NOT_READY' });
  assert.equal(rigged.embedding.calls.length, 1);
});

test('a previous snapshot under a different policy is rebuilt, never reused', async () => {
  const rigged = rig();
  const first = await rigged.worker(job());
  const firstVersion = versionOf(first);
  const oldDigest = published(rigged.artifacts, firstVersion).documents[0]?.embeddingDigest;
  const parsed = JSON.parse(rigged.artifacts.snapshots.get(firstVersion) as string) as Record<string, unknown>;
  rigged.artifacts.snapshots.set(firstVersion, JSON.stringify({ ...parsed, policyIdentity: 'b'.repeat(64) }));
  update(rigged, { notes: [note({ revision: 2 })] });
  const second = await rigged.worker(job({ sourceRevisionHint: 2 }));
  assert.equal(second.status, 'SUCCEEDED');
  assert.equal(rigged.embedding.calls.length, 2, 'current embeddings were rebuilt');
  assert.equal(published(rigged.artifacts, versionOf(second)).documents[0]?.embeddingDigest, oldDigest);
});

test('revoked consent publishes BLOCKED with zero model calls and retires old artifacts', async () => {
  const rigged = rig();
  const first = await rigged.worker(job());
  const firstVersion = versionOf(first);
  update(rigged, { consent: { accepted: false, version: CONSENT_VERSION, generation: 2 } });
  const second = await rigged.worker(job());
  assert.equal(second.status, 'BLOCKED');
  assert.equal(second.code, 'CONSENT_REQUIRED');
  assert.equal(rigged.embedding.calls.length, 1, 'no embedding after revocation');
  assert.equal(rigged.store.reserves, 1);
  assert.equal(rigged.store.state.manifest?.status, 'BLOCKED');
  assert.equal(rigged.store.state.manifest?.generation, 2);
  assert.deepEqual(published(rigged.artifacts, versionOf(second)).documents, []);
  assert.deepEqual(rigged.artifacts.cleanupVersions, [firstVersion]);
  assert.equal(rigged.artifacts.snapshots.has(firstVersion), false);
});

test('an accepted consent with an empty eligible corpus publishes an empty READY index', async () => {
  const rigged = rig({
    state: baseState({
      notes: [
        note({ noteId: 'p', protected: true, protectionRevision: 1 }),
        note({ noteId: 'd', deleted: true }),
        note({ noteId: 'u', available: false }),
        note({ noteId: 's', synced: false }),
        note({ noteId: 'i', incomingShared: true }),
      ],
    }),
  });
  const result = await rigged.worker(job());
  assert.equal(result.status, 'SUCCEEDED');
  assert.equal(rigged.embedding.calls.length, 0);
  assert.deepEqual(published(rigged.artifacts, versionOf(result)).documents, []);
  assert.equal(rigged.store.state.manifest?.status, 'READY');
});

test('an unlocked note (protection removed) is eligible again', async () => {
  const rigged = rig({
    state: baseState({ notes: [note({ protected: false, protectionRevision: 3 })] }),
  });
  const result = await rigged.worker(job());
  assert.equal(result.status, 'SUCCEEDED');
  assert.equal(rigged.embedding.calls.length, 1);
  assert.equal(published(rigged.artifacts, versionOf(result)).documents.length, 1);
});

test('protecting one note retires its artifacts while other eligible notes stay indexed', async () => {
  const rigged = rig({
    state: baseState({
      notes: [note({ noteId: 'n1' }), note({ noteId: 'n2', content: 'second body' })],
    }),
  });
  const first = await rigged.worker(job());
  const firstVersion = versionOf(first);
  const firstSnapshot = published(rigged.artifacts, firstVersion);
  const oldSecond = firstSnapshot.documents.find((entry) => entry.chunk.noteId === 'n2');
  assert.ok(oldSecond);
  const oldSecondVector = rigged.artifacts.vectors.get(oldSecond.vectorKey);
  update(rigged, {
    notes: [
      note({ noteId: 'n1', protected: true, protectionRevision: 1 }),
      note({ noteId: 'n2', content: 'second body' }),
    ],
  });
  const second = await rigged.worker(job({ noteId: 'n1' }));
  assert.equal(second.status, 'SUCCEEDED');
  assert.equal(rigged.embedding.calls.length, 1, 'the preserved note reused its float');
  const secondSnapshot = published(rigged.artifacts, versionOf(second));
  assert.deepEqual(secondSnapshot.documents.map((entry) => entry.chunk.noteId), ['n2']);
  assert.deepEqual(
    rigged.artifacts.vectors.get(secondSnapshot.documents[0]?.vectorKey as string), oldSecondVector,
  );
  assert.equal(rigged.artifacts.snapshots.has(firstVersion), false);
});

test('a cleanup failure surfaces FAILED metadata and keeps the new manifest current', async () => {
  const rigged = rig();
  const first = await rigged.worker(job());
  rigged.artifacts.failCleanup = true;
  update(rigged, { notes: [note({ revision: 2 })] });
  const second = await rigged.worker(job({ sourceRevisionHint: 2 }));
  assert.equal(second.status, 'FAILED');
  assert.equal(second.code, 'CLEANUP_FAILED');
  assert.equal(second.manifestVersion, rigged.store.state.manifest?.version);
  assert.equal(rigged.store.state.manifest?.generation, 2);
  assert.equal(rigged.store.state.manifest?.status, 'READY');
  assert.equal(rigged.artifacts.snapshots.has(versionOf(first)), true, 'old version retained for recovery');
  assert.ok(rigged.logs.some((entry) => entry['event'] === 'index.cleanup.failed'));
});

test('a failed snapshot write keeps the previous manifest as the current ready index', async () => {
  const rigged = rig();
  const first = await rigged.worker(job());
  rigged.artifacts.failPut = true;
  update(rigged, { notes: [note({ revision: 2 })] });
  assert.deepEqual(await rigged.worker(job({ sourceRevisionHint: 2 })),
    { status: 'FAILED', code: 'ARTIFACT_WRITE_FAILED' });
  assert.equal(rigged.store.publishes, 1);
  assert.equal(rigged.store.state.manifest?.version, versionOf(first));
  assert.equal(rigged.store.state.manifest?.generation, 1);
  assert.deepEqual(rigged.artifacts.cleanupVersions, []);
  assert.ok(rigged.logs.some((entry) => entry['event'] === 'index.orphan.staged'));
});

test('a wrong artifact checksum is rejected before the publish transaction', async () => {
  const rigged = rig();
  rigged.artifacts.corruptChecksum = true;
  assert.deepEqual(await rigged.worker(job()), { status: 'FAILED', code: 'ARTIFACT_WRITE_FAILED' });
  assert.equal(rigged.store.publishes, 0);
});

test('an expired lease is fenced: the new worker publishes and the old token cannot', async () => {
  const store = new MemoryStore(baseState());
  const artifacts = new MemoryArtifacts();
  const first = new MemoryEmbedding();
  const late = new MemoryEmbedding();
  const workerA = createIndexWorker({ store, artifacts, embedding: first, now: () => 0 });
  const workerB = createIndexWorker({ store, artifacts, embedding: late, now: () => 200_000 });
  let resultB: JobResult | null = null;
  first.hook = async () => {
    resultB = await workerB(job());
  };
  const resultA = await workerA(job());
  assert.ok(resultB !== null, 'B published while A was still embedding');
  assert.equal((resultB as JobResult).status, 'SUCCEEDED');
  assert.deepEqual(resultA, { status: 'SUPERSEDED', code: 'PUBLISH_REJECTED' });
  assert.equal(store.publishes, 1);
  assert.equal(store.state.manifest?.version, versionOf(resultB as JobResult));
  assert.notEqual(store.state.manifest?.version, 'lease-1');
});

test('embedding stops at the batch limit and reserves before every paid call', async () => {
  const content = Array.from({ length: 97 },
    (_, index) => `${'a'.repeat(298)}${String(index).padStart(3, '0')}\n\n`).join('');
  const many = baseState({ notes: [note({ content })] });
  const limited = rig({ state: many, budget: 1 });
  await assert.rejects(limited.worker(job()), (error: unknown) =>
    error instanceof IndexFailure && error.code === 'BUDGET_EXHAUSTED' && error.retryable === true);
  assert.equal(limited.embedding.calls.length, 1);
  assert.equal(limited.embedding.calls[0]?.length, 96);
  assert.equal(limited.store.reserves, 2);
  assert.equal(limited.store.publishes, 0);
  assert.ok(limited.store.finishes.some((entry) => entry.status === 'FAILED' && entry.code === 'BUDGET_EXHAUSTED'));

  const full = rig({ state: many });
  const result = await full.worker(job());
  assert.equal(result.status, 'SUCCEEDED');
  assert.deepEqual(full.embedding.calls.map((call) => call.length), [96, 1]);
  assert.equal(published(full.artifacts, versionOf(result)).documents.length, 97);
});

test('wrong provider cardinality, dimensions or a zero vector are terminal', async () => {
  const cases: readonly ((texts: readonly string[]) => readonly (readonly number[])[])[] = [
    () => [unitWith(1), unitWith(2)],
    () => [[1, 2, 3]],
    () => [new Array<number>(1024).fill(0)],
  ];
  for (const respond of cases) {
    const rigged = rig();
    rigged.embedding.respond = respond;
    assert.deepEqual(await rigged.worker(job()), { status: 'FAILED', code: 'INVALID_PROVIDER_OUTPUT' });
    assert.equal(rigged.store.publishes, 0);
  }
});

test('an invalid token counter fails closed before any embedding', async () => {
  const throwing = rig();
  throwing.embedding.count = () => {
    throw new Error('counter unavailable');
  };
  assert.deepEqual(await throwing.worker(job()),
    { status: 'FAILED', code: 'EVIDENCE_VALIDATION_UNAVAILABLE' });
  assert.equal(throwing.embedding.calls.length, 0);

  const fractional = rig();
  fractional.embedding.count = () => 1.5;
  assert.deepEqual(await fractional.worker(job()),
    { status: 'FAILED', code: 'EVIDENCE_VALIDATION_UNAVAILABLE' });
  assert.equal(fractional.embedding.calls.length, 0);
});

test('an expired worker deadline is retryable and publishes nothing', async () => {
  let time = 0;
  const rigged = rig({ clock: () => time });
  rigged.embedding.hook = () => {
    time = WORKER_MS + 1;
  };
  await assert.rejects(rigged.worker(job()), (error: unknown) =>
    error instanceof IndexFailure && error.retryable === true && error.code === 'TIMEOUT');
  assert.equal(rigged.store.publishes, 0);
  assert.ok(rigged.store.finishes.some((entry) => entry.status === 'FAILED' && entry.code === 'TIMEOUT'));
});

test('foreign owners and malformed jobs fail closed before any model call', async () => {
  const foreign = rig({ state: baseState({ ownerId: 'u2', notes: [note({ ownerId: 'u2' })] }) });
  assert.deepEqual(await foreign.worker(job()), { status: 'FAILED', code: 'INVALID_STATE' });
  assert.equal(foreign.embedding.calls.length, 0);
  assert.equal(foreign.store.publishes, 0);

  const mixed = rig({ state: baseState({ notes: [note(), note({ noteId: 'n2', ownerId: 'u2' })] }) });
  assert.deepEqual(await mixed.worker(job()), { status: 'FAILED', code: 'INVALID_STATE' });
  assert.equal(mixed.embedding.calls.length, 0);

  const malformed = rig();
  assert.deepEqual(await malformed.worker({ ...job(), ownerId: '' } as Job),
    { status: 'FAILED', code: 'INVALID_JOB' });
  assert.equal(malformed.store.loads, 0);
});

test('identical embedding inputs share one paid call but keep distinct identities', async () => {
  const rigged = rig({
    state: baseState({ notes: [note({ noteId: 'n1' }), note({ noteId: 'n2' })] }),
  });
  const first = await rigged.worker(job());
  assert.equal(first.status, 'SUCCEEDED');
  assert.equal(rigged.embedding.calls.length, 1);
  assert.equal(rigged.embedding.calls[0]?.length, 1, 'one unique embedding input');
  const firstSnapshot = published(rigged.artifacts, versionOf(first));
  assert.equal(firstSnapshot.documents.length, 2, 'conflicting sources stay distinct');
  assert.equal(new Set(firstSnapshot.documents.map((entry) => entry.vectorKey)).size, 2);
  assert.equal(new Set(firstSnapshot.documents.map((entry) => entry.chunk.noteId)).size, 2);

  update(rigged, {
    notes: [note({ noteId: 'n1' }), note({ noteId: 'n2', revision: 2, content: 'changed body' })],
  });
  const second = await rigged.worker(job({ noteId: 'n2', sourceRevisionHint: 2 }));
  assert.equal(second.status, 'SUCCEEDED');
  assert.equal(rigged.embedding.calls.length, 2, 'only the changed digest is embedded');
  assert.equal(rigged.embedding.calls[1]?.length, 1);
  assert.equal(published(rigged.artifacts, versionOf(second)).documents.length, 2);
});
