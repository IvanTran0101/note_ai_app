/**
 * Indexing worker slice tests — C21/C23 lease fencing, canonical re-reads, vector reuse,
 * budget/reservation, fail-closed ports and cleanup semantics, against cached ports that
 * emulate a real conditional-lease store (CAS on token and canonical fingerprint). Patch 5B
 * adds the durable checkpoint section: deadline-aware stops, resume, binding fencing, budget
 * honesty, lease-scoped keys and the checkpoint-less legacy fallback.
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
import { decodeCheckpoint, encodeCheckpoint } from './checkpoint';
import type { Checkpoint } from './checkpoint';
import { fingerprint, markersOf } from './jobs';
import { createIndexWorker } from './worker';
import { EMBEDDING_DIMENSIONS } from '../retrieval';

const unitWith = (value: number): readonly number[] => {
  const vector = new Array<number>(EMBEDDING_DIMENSIONS).fill(0);
  vector[0] = value;
  return vector;
};

class MemoryStore implements IndexStore {
  lease: Readonly<{ token: string; fingerprint: string; expiresAt: number }> | null = null;
  budget = Number.POSITIVE_INFINITY;
  failPublish = false;
  loads = 0;
  markerLoads = 0;
  publishes = 0;
  reserves = 0;
  finishes: Readonly<{ status: string; code: string }>[] = [];
  beforeLoad: (() => void) | null = null;
  /** Runs inside `reserveEmbedding`, i.e. while the async paid reservation is in flight. */
  reserveHook: (() => void) | null = null;
  /**
   * Assigned by a test to expose the light marker read (Patch 5A); left undefined the store keeps
   * the exact legacy behavior and the worker falls back to full re-reads.
   */
  loadMarkers?: IndexStore['loadMarkers'];
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
    const hook = this.reserveHook;
    this.reserveHook = null;
    hook?.();
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

/**
 * Patch 5B fake: the base in-memory artifacts plus the four OPTIONAL checkpoint ports, backed
 * by encoded checkpoint objects per lease token and recording every checkpoint key touched.
 * Corrupt objects are skipped exactly like the production list path.
 */
class CheckpointArtifacts extends MemoryArtifacts {
  checkpoints = new Map<string, string>();
  checkpointKeys: string[] = [];
  stagedKeys: string[] = [];
  vectorReads: string[] = [];
  deletedTokens: string[] = [];
  failPutCheckpointOnce = false;
  failPutVectorsOnce = false;
  async stageVector(entry: Readonly<{ key: string; vector: readonly number[] }>): Promise<void> {
    this.stagedKeys.push(entry.key);
    this.vectors.set(entry.key, entry.vector);
  }
  async putVectors(snapshot: Snapshot, vectors: ReadonlyMap<string, readonly number[]>): Promise<void> {
    if (this.failPutVectorsOnce) {
      this.failPutVectorsOnce = false;
      throw new IndexFailure('PROVIDER_UNAVAILABLE', true);
    }
    return super.putVectors(snapshot, vectors);
  }
  async getVectors(keys: readonly string[]): Promise<ReadonlyMap<string, readonly number[]>> {
    for (const key of keys) this.vectorReads.push(key);
    return super.getVectors(keys);
  }
  async listCheckpoints(): Promise<readonly Checkpoint[]> {
    const decoded: Checkpoint[] = [];
    for (const text of this.checkpoints.values()) {
      try {
        decoded.push(decodeCheckpoint(text));
      } catch {
        // A corrupt checkpoint only ever means "rebuild".
      }
    }
    decoded.sort((left, right) => right.createdAt - left.createdAt);
    return decoded;
  }
  async putCheckpoint(checkpoint: Checkpoint): Promise<void> {
    if (this.failPutCheckpointOnce) {
      this.failPutCheckpointOnce = false;
      throw new IndexFailure('PROVIDER_UNAVAILABLE', true);
    }
    this.checkpointKeys.push(`checkpoint#${checkpoint.ownerId}#${checkpoint.leaseToken}`);
    this.checkpoints.set(checkpoint.leaseToken, encodeCheckpoint(checkpoint));
  }
  async deleteCheckpoints(ownerId: string, _signal: AbortSignal, ...tokens: string[]): Promise<void> {
    for (const token of tokens) {
      this.deletedTokens.push(token);
      this.checkpointKeys.push(`checkpoint#${ownerId}#${token}`);
      this.checkpoints.delete(token);
    }
  }
}

class MemoryEmbedding implements Embedding {
  calls: string[][] = [];
  count: Counter = (text) => Array.from(text).length;
  hook: (() => void | Promise<void>) | null = null;
  respond: ((texts: readonly string[]) => readonly (readonly number[])[]) | null = null;
  /** Simulates the signed transport invoking the forwarded post-reservation dispatch callback. */
  dispatch: ((beforeDispatch?: () => Promise<void>) => Promise<void>) | null = null;
  async embed(
    texts: readonly string[],
    _purpose?: 'search_document' | 'search_query',
    _signal?: AbortSignal,
    beforeDispatch?: () => Promise<void>,
  ): Promise<readonly (readonly number[])[]> {
    this.calls.push([...texts]);
    if (this.hook !== null) await this.hook();
    if (this.dispatch !== null) await this.dispatch(beforeDispatch);
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

const rig = (
  options: Readonly<{ state?: IndexState; clock?: () => number; budget?: number; artifacts?: MemoryArtifacts }> = {},
) => {
  const store = new MemoryStore(options.state ?? baseState());
  if (options.budget !== undefined) store.budget = options.budget;
  const artifacts = options.artifacts ?? new MemoryArtifacts();
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

/**
 * Group 3 worker race regression: the canonical state moves while `reserveEmbedding` is in
 * flight. The reservation is consumed, but the worker re-reads the fingerprint after it and
 * before `embedding.embed`, so the paid provider is never called and nothing is published.
 */
test('a canonical change during the embedding reservation blocks the paid embed and READY', async () => {
  const rigged = rig();
  rigged.store.reserveHook = () => update(rigged, { notes: [note({ revision: 2 })] });
  const result = await rigged.worker(job());
  assert.deepEqual(result, { status: 'SUPERSEDED', code: 'SOURCE_CHANGED' });
  assert.equal(rigged.store.reserves, 1, 'the reservation is still consumed');
  assert.equal(rigged.embedding.calls.length, 0, 'no paid embed after the canonical move');
  assert.equal(rigged.store.publishes, 0);
  assert.equal(rigged.store.state.manifest, null);
});

test('the worker forwards a post-reservation dispatch callback into the paid embed', async () => {
  const rigged = rig();
  let forwarded: unknown;
  rigged.embedding.dispatch = async (beforeDispatch) => {
    forwarded = beforeDispatch;
    // The canonical state moves during the signed transport's own signing window; the forwarded
    // callback must observe it before the produced vector can be accepted.
    update(rigged, { notes: [note({ revision: 2 })] });
    if (typeof beforeDispatch === 'function') await beforeDispatch();
  };
  const result = await rigged.worker(job());
  assert.equal(typeof forwarded, 'function', 'the worker forwards its reread callback');
  assert.deepEqual(result, { status: 'SUPERSEDED', code: 'SOURCE_CHANGED' });
  assert.equal(rigged.store.reserves, 1, 'the reservation is still consumed');
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

test('a migration to another embedding profile retains the old generation for rollback', async () => {
  const rigged = rig();
  const first = await rigged.worker(job());
  const firstVersion = versionOf(first);
  const oldProfile = 'c'.repeat(64);
  // The current generation was produced under the previous (Cohere) profile: both the manifest
  // and its snapshot carry that identity, exactly like a pre-migration index.
  const current = rigged.store.state.manifest;
  assert.ok(current !== null);
  rigged.store.state = structuredClone({
    ...rigged.store.state, manifest: { ...current, policyIdentity: oldProfile },
  });
  const parsed = JSON.parse(rigged.artifacts.snapshots.get(firstVersion) as string) as Record<string, unknown>;
  rigged.artifacts.snapshots.set(firstVersion, JSON.stringify({ ...parsed, policyIdentity: oldProfile }));
  update(rigged, { notes: [note({ revision: 2 })] });
  const second = await rigged.worker(job({ sourceRevisionHint: 2 }));
  assert.equal(second.status, 'SUCCEEDED');
  assert.equal(rigged.embedding.calls.length, 2, 'the old-profile vector is never reused');
  assert.deepEqual(rigged.artifacts.cleanupVersions, [], 'migration cleanup retains the old generation');
  assert.equal(rigged.artifacts.snapshots.has(firstVersion), true);
  assert.ok(rigged.logs.some((entry) => entry['event'] === 'index.cleanup.retained'));
  assert.notEqual(rigged.store.state.manifest?.policyIdentity, oldProfile, 'the new profile is published');
  assert.equal(rigged.store.state.manifest?.generation, 2);
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
  assert.equal(rigged.embedding.calls.length, 2, 'the preserved note reused its float (two original samples)');
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

test('embedding dispatches one sample at a time and reserves before every paid call', async () => {
  const content = Array.from({ length: 97 },
    (_, index) => `${'a'.repeat(298)}${String(index).padStart(3, '0')}\n\n`).join('');
  const many = baseState({ notes: [note({ content })] });
  const limited = rig({ state: many, budget: 1 });
  await assert.rejects(limited.worker(job()), (error: unknown) =>
    error instanceof IndexFailure && error.code === 'BUDGET_EXHAUSTED' && error.retryable === true);
  assert.equal(limited.embedding.calls.length, 1);
  assert.equal(limited.embedding.calls[0]?.length, 1, 'pilot batch is exactly one sample');
  assert.equal(limited.store.reserves, 2);
  assert.equal(limited.store.publishes, 0);
  assert.ok(limited.store.finishes.some((entry) => entry.status === 'FAILED' && entry.code === 'BUDGET_EXHAUSTED'));

  const full = rig({ state: many });
  const result = await full.worker(job());
  assert.equal(result.status, 'SUCCEEDED');
  assert.deepEqual(full.embedding.calls.map((call) => call.length), new Array(97).fill(1));
  assert.equal(full.store.reserves, 97, 'one reserve+dispatch pair per unique sample');
  assert.equal(published(full.artifacts, versionOf(result)).documents.length, 97);
});

test('wrong provider cardinality, dimensions or a zero vector are terminal', async () => {
  const cases: readonly ((texts: readonly string[]) => readonly (readonly number[])[])[] = [
    () => [unitWith(1), unitWith(2)],
    () => [[1, 2, 3]],
    () => [new Array<number>(EMBEDDING_DIMENSIONS).fill(0)],
  ];
  for (const respond of cases) {
    const rigged = rig();
    rigged.embedding.respond = respond;
    assert.deepEqual(await rigged.worker(job()), { status: 'FAILED', code: 'INVALID_PROVIDER_OUTPUT' });
    assert.equal(rigged.embedding.calls.length, 1, 'one failed dispatch is never retried in-process');
    assert.equal(rigged.store.reserves, 1, 'the failed attempt stays counted');
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

// ---------------------------------------------------------------------------------------------
// Light mid-flight revalidation (Patch 5A): marker reads replace per-chunk full re-reads.
// ---------------------------------------------------------------------------------------------

/** Exposes the store's light marker read over its live canonical state. */
const exposeMarkers = (rigged: ReturnType<typeof rig>): void => {
  rigged.store.loadMarkers = async () => {
    rigged.store.markerLoads += 1;
    return markersOf(rigged.store.state);
  };
};

/** One blank-line-separated paragraph per segment: the counter makes each segment one chunk. */
const chunkedContent = (segments: number): string => Array.from({ length: segments },
  (_, index) => `${'a'.repeat(298)}${String(index).padStart(3, '0')}\n\n`).join('');

test('a marker-capable store revalidates every chunk without full loads beyond bind and publish', async () => {
  const segments = 4;
  const rigged = rig({ state: baseState({ notes: [note({ content: chunkedContent(segments) })] }) });
  exposeMarkers(rigged);
  const result = await rigged.worker(job());
  assert.equal(result.status, 'SUCCEEDED');
  assert.equal(result.code, 'READY');
  assert.equal(rigged.embedding.calls.length, segments, 'one paid dispatch per chunk');
  assert.equal(rigged.store.reserves, segments, 'one reservation per chunk');
  assert.equal(rigged.store.publishes, 1);
  // The full load runs exactly twice: the initial bind and the pre-publish re-read.
  assert.ok(rigged.store.loads <= 2, `full loads must stay at 2, saw ${rigged.store.loads}`);
  assert.equal(rigged.store.loads, 2);
  assert.equal(rigged.store.markerLoads, segments * 2,
    'the light marker read covers both mid-flight sites of every chunk');
});

test('a marker change mid-run aborts on the light path and publishes nothing', async () => {
  const segments = 4;
  const content = chunkedContent(segments);
  const rigged = rig({ state: baseState({ notes: [note({ content })] }) });
  exposeMarkers(rigged);
  rigged.embedding.hook = () => {
    rigged.embedding.hook = null;
    update(rigged, { notes: [note({ revision: 2, content })] });
  };
  const result = await rigged.worker(job());
  assert.deepEqual(result, { status: 'SUPERSEDED', code: 'SOURCE_CHANGED' });
  assert.equal(rigged.embedding.calls.length, 1, 'the first chunk was paid, the second never dispatched');
  assert.equal(rigged.store.publishes, 0);
  assert.equal(rigged.store.state.manifest, null);
  // The abort came from the marker read: no full re-read ever ran after the bind.
  assert.equal(rigged.store.loads, 1);
  assert.ok(rigged.store.markerLoads >= 2, 'the light path observed the moved marker');
  assert.ok(rigged.store.finishes.some((entry) =>
    entry.status === 'SUPERSEDED' && entry.code === 'SOURCE_CHANGED'));
});

test('a marker-less store keeps the exact legacy full-reread behavior per chunk', async () => {
  const segments = 4;
  const content = chunkedContent(segments);

  const steady = rig({ state: baseState({ notes: [note({ content })] }) });
  const done = await steady.worker(job());
  assert.equal(done.status, 'SUCCEEDED');
  assert.equal(done.code, 'READY');
  assert.equal(steady.embedding.calls.length, segments);
  assert.equal(steady.store.publishes, 1);
  assert.equal(steady.store.markerLoads, 0, 'no marker read without the optional store method');
  // Legacy revalidation is a full re-read at every mid-flight site, plus bind and pre-publish.
  assert.equal(steady.store.loads, 2 + segments * 2);

  const moved = rig({ state: baseState({ notes: [note({ content })] }) });
  moved.embedding.hook = () => {
    moved.embedding.hook = null;
    update(moved, { notes: [note({ revision: 2, content })] });
  };
  const result = await moved.worker(job());
  assert.deepEqual(result, { status: 'SUPERSEDED', code: 'SOURCE_CHANGED' },
    'the same outcome as the light path');
  assert.equal(moved.embedding.calls.length, 1);
  assert.equal(moved.store.publishes, 0);
  assert.equal(moved.store.state.manifest, null);
  assert.equal(moved.store.markerLoads, 0);
  assert.ok(moved.store.loads >= 4, 'the fallback aborts through full re-reads, not markers');
});

// ---------------------------------------------------------------------------------------------
// Durable embedding checkpoints (Patch 5B): deadline-aware stop, resume, binding fencing,
// budget honesty, lease-scoped keys and the checkpoint-less legacy fallback. No real sleeps:
// every deadline is driven by a fake clock the embedding hook advances deterministically.
// ---------------------------------------------------------------------------------------------

/** Checkpoint rig: fake clock plus checkpoint-capable artifacts; the tick is the embed cost. */
const checkpointRig = (options: Readonly<{ state?: IndexState }> = {}) => {
  let time = 0;
  const artifacts = new CheckpointArtifacts();
  const rigged = rig({ clock: () => time, artifacts, state: options.state });
  return {
    rigged,
    artifacts,
    tickPerEmbed: (ms: number) => {
      rigged.embedding.hook = () => {
        time += ms;
      };
    },
    stopTicking: () => {
      rigged.embedding.hook = null;
    },
  };
};

const rejectsWith = async (run: () => Promise<JobResult>, code: string): Promise<void> => {
  await assert.rejects(run(), (error: unknown) =>
    error instanceof IndexFailure && error.code === code && error.retryable === true);
};

const entriesIn = (artifacts: CheckpointArtifacts, token: string): number =>
  decodeCheckpoint(artifacts.checkpoints.get(token) as string).entries.length;

test('a deadline-stopped attempt resumes from its checkpoint and publishes', async () => {
  const segments = 6;
  const rig0 = checkpointRig({ state: baseState({ notes: [note({ content: chunkedContent(segments) })] }) });
  const { rigged, artifacts } = rig0;
  rig0.tickPerEmbed(20_000);

  // Attempt 1: the stop margin ends the run cleanly after 5 of 6 chunks (no absolute deadline
  // is reached; the checkpoint is current when the run stops).
  await rejectsWith(() => rigged.worker(job()), 'TIMEOUT');
  assert.equal(rigged.embedding.calls.length, 5);
  assert.equal(entriesIn(artifacts, 'lease-1'), 5);
  assert.deepEqual([...new Set(artifacts.checkpointKeys)], ['checkpoint#u1#lease-1']);
  assert.ok(rigged.store.finishes.some((entry) => entry.status === 'FAILED' && entry.code === 'TIMEOUT'));

  // Attempt 2: only the sixth chunk is paid; the first five come back through getVectors.
  rig0.stopTicking();
  const result = await rigged.worker(job());
  assert.equal(result.status, 'SUCCEEDED');
  assert.equal(rigged.embedding.calls.length, 5 + 1, 'only the missing digest is embedded');
  assert.equal(rigged.store.reserves, 6, 'a resumed chunk never reserves');
  assert.equal(artifacts.vectorReads.length, 5, 'resumed vectors were fetched by staged key');
  const resumed = rigged.logs.filter((entry) => entry['event'] === 'index.checkpoint.resumed');
  assert.equal(resumed.length, 1);
  assert.equal(resumed[0]?.['entries'], 5);

  const snapshot = published(artifacts, versionOf(result));
  assert.equal(snapshot.documents.length, segments, 'the final snapshot contains every chunk');
  // The staged key of the attempt-2 chunk is exactly the key the published snapshot names.
  assert.equal(artifacts.stagedKeys.at(-1), snapshot.documents.at(-1)?.vectorKey);

  // Publish success deletes NO checkpoints: both leases' objects stay exactly as the publish
  // left them. The next run's binding match ignores this obsolete progress (only still-pending
  // digests are ever resumed) and recovery reaping owns the removal.
  assert.equal(artifacts.checkpoints.size, 2);
  assert.deepEqual([...artifacts.checkpoints.keys()].sort(), ['lease-1', 'lease-2']);
  assert.deepEqual(artifacts.deletedTokens, []);
  assert.equal(rigged.store.state.manifest?.generation, 1);
});

test('a checkpoint is dropped when owner, policy identity or consent generation differs', async () => {
  const segments = 3;
  const start = () => checkpointRig({
    state: baseState({ notes: [note({ content: chunkedContent(segments) })] }),
  });

  // A real consent transition between attempts: the binding no longer matches, so the paid
  // progress of the previous consent generation is discarded, never reused across the boundary.
  const consented = start();
  consented.tickPerEmbed(40_000); // stops after 2 of 3
  await rejectsWith(() => consented.rigged.worker(job()), 'TIMEOUT');
  assert.equal(consented.rigged.embedding.calls.length, 2);
  consented.stopTicking();
  update(consented.rigged, { consent: { accepted: true, version: CONSENT_VERSION, generation: 2 } });
  const consentResult = await consented.rigged.worker(job());
  assert.equal(consentResult.status, 'SUCCEEDED');
  assert.equal(consented.rigged.embedding.calls.length, 2 + segments, 'full re-embed after the consent move');
  assert.equal(consented.rigged.logs.filter((entry) => entry['event'] === 'index.checkpoint.resumed').length, 0);

  // A tampered policy identity or owner inside the stored checkpoint: the same drop.
  for (const field of ['policyIdentity', 'ownerId'] as const) {
    const tampered = start();
    tampered.tickPerEmbed(40_000);
    await rejectsWith(() => tampered.rigged.worker(job()), 'TIMEOUT');
    const token = [...tampered.artifacts.checkpoints.keys()][0] as string;
    const raw = JSON.parse(tampered.artifacts.checkpoints.get(token) as string) as Record<string, unknown>;
    tampered.artifacts.checkpoints.set(token, JSON.stringify({
      ...raw,
      [field]: field === 'policyIdentity' ? 'b'.repeat(64) : 'u2',
    }));
    tampered.stopTicking();
    const result = await tampered.rigged.worker(job());
    assert.equal(result.status, 'SUCCEEDED');
    assert.equal(tampered.rigged.embedding.calls.length, 2 + segments, `${field} mismatch drops the checkpoint`);
    assert.equal(tampered.rigged.logs.filter((entry) => entry['event'] === 'index.checkpoint.resumed').length, 0);
  }
});

test('a source change between attempts re-embeds only the changed digest', async () => {
  const segments = 3;
  // Every segment of n2 differs from n1's: shared paragraph text would dedupe digests.
  const n2Content = (firstChar: string): string =>
    Array.from({ length: segments }, (_value, index) =>
      `${(index === 0 ? firstChar : 'c').repeat(298)}${String(index).padStart(3, '0')}\n\n`).join('');
  const rig0 = checkpointRig({
    state: baseState({
      notes: [
        note({ noteId: 'n1', content: chunkedContent(segments) }),
        note({ noteId: 'n2', content: n2Content('c') }),
      ],
    }),
  });
  rig0.tickPerEmbed(20_000); // five of six chunks fit: all of n1 plus the first two of n2
  await rejectsWith(() => rig0.rigged.worker(job()), 'TIMEOUT');
  assert.equal(rig0.rigged.embedding.calls.length, 5);

  // One paragraph of n2 changes: exactly that digest becomes invalid; every other digest —
  // including n2's unchanged second chunk — stays resumable (digest-level validity).
  rig0.stopTicking();
  update(rig0.rigged, {
    notes: [
      note({ noteId: 'n1', content: chunkedContent(segments) }),
      note({ noteId: 'n2', revision: 2, content: n2Content('b') }),
    ],
  });
  const result = await rig0.rigged.worker(job());
  assert.equal(result.status, 'SUCCEEDED');
  assert.equal(rig0.rigged.embedding.calls.length, 5 + 2,
    'only the changed digest and the never-attempted tail chunk are paid');
  const resumed = rig0.rigged.logs.find((entry) => entry['event'] === 'index.checkpoint.resumed');
  assert.equal(resumed?.['entries'], 4, 'n1 entirely plus the unchanged n2 paragraph resumed');
  const snapshot = published(rig0.artifacts, versionOf(result));
  assert.equal(snapshot.documents.length, 6);
  assert.deepEqual(snapshot.documents.map((entry) => entry.chunk.noteId), ['n1', 'n1', 'n1', 'n2', 'n2', 'n2']);
  const firstN1 = snapshot.documents.find((entry) => entry.chunk.noteId === 'n1' && entry.chunk.ordinal === 0);
  assert.ok(firstN1);
  assert.deepEqual(rig0.artifacts.vectors.get(firstN1.vectorKey), unitWith(1),
    'the resumed vector is exactly the attempt-1 value');
});

test('budget honesty: reserves mirror paid embeds and a lost checkpoint write re-bills one chunk', async () => {
  const rig0 = checkpointRig({ state: baseState({ notes: [note({ content: chunkedContent(3) })] }) });
  // Attempt 1 dies between stageVector and putCheckpoint on the second chunk: the vector is
  // staged but not durably recorded, so exactly that one chunk re-bills on resume. The flag is
  // armed by the second embed itself — arming it up front would kill the FIRST checkpoint write.
  let embedCalls = 0;
  rig0.rigged.embedding.hook = () => {
    embedCalls += 1;
    if (embedCalls === 2) rig0.artifacts.failPutCheckpointOnce = true;
  };
  await rejectsWith(() => rig0.rigged.worker(job()), 'PROVIDER_UNAVAILABLE');
  assert.equal(rig0.rigged.embedding.calls.length, 2);
  assert.equal(rig0.artifacts.stagedKeys.length, 2, 'the second vector was staged before the death');
  assert.equal(entriesIn(rig0.artifacts, 'lease-1'), 1, 'only the first chunk was durably recorded');

  const result = await rig0.rigged.worker(job());
  assert.equal(result.status, 'SUCCEEDED');
  assert.equal(rig0.rigged.embedding.calls.length, 4, 'one re-billed chunk plus the never-attempted tail');
  assert.equal(rig0.rigged.store.reserves, rig0.rigged.embedding.calls.length,
    'every paid embed reserved exactly once and resumed chunks never reserved');
  const counts = new Map<string, number>();
  for (const call of rig0.rigged.embedding.calls) {
    for (const text of call) counts.set(text, (counts.get(text) ?? 0) + 1);
  }
  assert.deepEqual([...counts.values()].sort(), [1, 1, 2], 'exactly one chunk was re-billed');
});

test('lease fencing: leases checkpoint under distinct keys and publish deletes nothing', async () => {
  const rig0 = checkpointRig({ state: baseState({ notes: [note({ content: chunkedContent(7) })] }) });
  rig0.tickPerEmbed(40_000); // two chunks per attempt

  await rejectsWith(() => rig0.rigged.worker(job()), 'TIMEOUT');
  await rejectsWith(() => rig0.rigged.worker(job()), 'TIMEOUT');
  await rejectsWith(() => rig0.rigged.worker(job()), 'TIMEOUT');
  // Three live leases, three distinct lease-scoped checkpoint objects; an older lease's release
  // or finish never deleted or overwrote a newer lease's progress.
  assert.deepEqual([...rig0.artifacts.checkpoints.keys()].sort(), ['lease-1', 'lease-2', 'lease-3']);
  assert.deepEqual([...new Set(rig0.artifacts.checkpointKeys)],
    ['checkpoint#u1#lease-1', 'checkpoint#u1#lease-2', 'checkpoint#u1#lease-3']);
  assert.equal(entriesIn(rig0.artifacts, 'lease-1'), 2);
  assert.equal(entriesIn(rig0.artifacts, 'lease-2'), 4);
  assert.equal(entriesIn(rig0.artifacts, 'lease-3'), 6);
  assert.deepEqual(rig0.artifacts.deletedTokens, [], 'nothing is deleted before a publish succeeds');

  rig0.stopTicking();
  const result = await rig0.rigged.worker(job());
  assert.equal(result.status, 'SUCCEEDED');
  assert.equal(rig0.rigged.embedding.calls.length, 7, 'monotonic progress across attempts, no re-bill');
  assert.equal(rig0.artifacts.checkpoints.size, 4, 'publish deletes nothing: every checkpoint stays');
  // The publishing attempt checkpointed its own final chunk first (lease-4); no lease's object —
  // its own included — is ever deleted by the publish path (recovery reaping owns the removal).
  assert.deepEqual([...rig0.artifacts.checkpoints.keys()].sort(),
    ['lease-1', 'lease-2', 'lease-3', 'lease-4']);
  assert.deepEqual(rig0.artifacts.deletedTokens, []);
  assert.equal(published(rig0.artifacts, versionOf(result)).documents.length, 7);
});

test('a 300-chunk account progresses 100/200/300 across deadline-stopped attempts', async () => {
  const rig0 = checkpointRig({ state: baseState({ notes: [note({ content: chunkedContent(300) })] }) });
  exposeMarkers(rig0.rigged);
  rig0.tickPerEmbed(953); // keeps the stop margin at 15s: exactly 100 chunks fit per attempt
  const mark = () => ({ embeds: rig0.rigged.embedding.calls.length, loads: rig0.rigged.store.loads });

  let start = mark();
  await rejectsWith(() => rig0.rigged.worker(job()), 'TIMEOUT');
  assert.equal(rig0.rigged.embedding.calls.length - start.embeds, 100, 'attempt 1 embeds exactly 100');
  assert.equal(entriesIn(rig0.artifacts, 'lease-1'), 100);
  assert.ok(rig0.rigged.store.loads - start.loads <= 2, 'full loads stay bounded (5A guarantee intact)');

  start = mark();
  await rejectsWith(() => rig0.rigged.worker(job()), 'TIMEOUT');
  assert.equal(rig0.rigged.embedding.calls.length - start.embeds, 100, 'attempt 2 pays only the next 100');
  assert.equal(entriesIn(rig0.artifacts, 'lease-2'), 200, 'resumed + new progress accumulates monotonically');
  assert.ok(rig0.rigged.store.loads - start.loads <= 2);

  start = mark();
  const result = await rig0.rigged.worker(job());
  assert.equal(result.status, 'SUCCEEDED', 'attempt 3 finishes and publishes');
  assert.equal(rig0.rigged.embedding.calls.length - start.embeds, 100);
  assert.ok(rig0.rigged.store.loads - start.loads <= 2);
  assert.equal(rig0.rigged.store.reserves, rig0.rigged.embedding.calls.length, 'no chunk was ever re-billed');
  assert.equal(published(rig0.artifacts, versionOf(result)).documents.length, 300);
  assert.equal(rig0.artifacts.checkpoints.size, 3, 'all three leases\' checkpoints stay for recovery reaping');

  // The stream retry budget may be exhausted by then; a further invocation still terminates.
  assert.deepEqual(await rig0.rigged.worker(job()), { status: 'SUPERSEDED', code: 'ALREADY_DONE' });
  assert.equal(rig0.rigged.embedding.calls.length, 300, 'no infinite loop, no extra paid call');
});

test('a manual invocation finishes from the checkpoint when the stream retries are exhausted', async () => {
  const rig0 = checkpointRig({ state: baseState({ notes: [note({ content: chunkedContent(300) })] }) });
  exposeMarkers(rig0.rigged);
  rig0.tickPerEmbed(953);
  await rejectsWith(() => rig0.rigged.worker(job()), 'TIMEOUT');
  await rejectsWith(() => rig0.rigged.worker(job()), 'TIMEOUT');
  // Attempt 3 pays the last 100 chunks but dies at the publish write: the stream has now spent
  // its bounded retries and would route the record to the failure destination.
  rig0.artifacts.failPutVectorsOnce = true;
  await rejectsWith(() => rig0.rigged.worker(job()), 'PROVIDER_UNAVAILABLE');
  assert.equal(entriesIn(rig0.artifacts, 'lease-3'), 300, 'all paid work survived the failed publish');

  // A manual backfill invocation finishes from the checkpoint with zero further paid calls.
  rig0.stopTicking();
  const result = await rig0.rigged.worker(job());
  assert.equal(result.status, 'SUCCEEDED');
  assert.equal(rig0.rigged.embedding.calls.length, 300, 'every digest came from the checkpoint');
  assert.equal(rig0.rigged.store.reserves, 300);
  assert.equal(published(rig0.artifacts, versionOf(result)).documents.length, 300);
  // The publishing attempt resumed every digest, so it wrote no checkpoint of its own: the
  // three earlier leases' objects all survive the publish, awaiting recovery reaping.
  assert.equal(rig0.artifacts.checkpoints.size, 3);
  assert.deepEqual([...rig0.artifacts.checkpoints.keys()].sort(), ['lease-1', 'lease-2', 'lease-3']);
});

test('a checkpoint-less artifacts port keeps the exact legacy deadline behavior', async () => {
  const segments = 6;
  let time = 0;
  const rigged = rig({
    clock: () => time,
    state: baseState({ notes: [note({ content: chunkedContent(segments) })] }),
  });
  assert.equal('stageVector' in rigged.artifacts, false);
  assert.equal('putCheckpoint' in rigged.artifacts, false);
  rigged.embedding.hook = () => {
    time += 20_000;
  };

  // No stop margin without the ports: the run embeds every chunk and dies at the hard deadline.
  await rejectsWith(() => rigged.worker(job()), 'TIMEOUT');
  assert.equal(rigged.embedding.calls.length, segments, 'legacy behavior runs to the hard deadline');
  assert.equal(rigged.store.publishes, 0);
  assert.ok(!rigged.logs.some((entry) => String(entry['event']).startsWith('index.checkpoint')),
    'no checkpoint key or event is ever touched');

  // With no checkpoint to resume, a replay pays for everything again.
  rigged.embedding.hook = null;
  const result = await rigged.worker(job());
  assert.equal(result.status, 'SUCCEEDED');
  assert.equal(rigged.embedding.calls.length, segments * 2, 'no resume without the ports');
  assert.ok(!rigged.logs.some((entry) => String(entry['event']).startsWith('index.checkpoint')));
});
