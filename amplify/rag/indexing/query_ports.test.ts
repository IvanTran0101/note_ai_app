/**
 * Phase 4 query-port tests: canonical authority currentness, per-request scope, immutable snapshot
 * cache warm/concurrent isolation, empty eligible scope, partial vectors and the one query call.
 * Synthetic notes only; the store, artifacts and embedding provider are in-process fakes.
 *
 * Runner: node --import tsx --test amplify/rag/indexing/query_ports.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { beginContext } from '../authority';
import { chunkNote } from '../chunking';
import { CONSENT_VERSION } from '../contract';
import { countSyntheticTokens } from '../mock';
import { policy, sourceKey } from '../types';
import type { CanonicalNote, Chunk, Counter, Ranked, RagRequest, RequestContext } from '../types';
import { fingerprint } from './jobs';
import { createQueryPorts } from './query_ports';
import { checksum, policyIdentity, sha256Hex } from './snapshot';
import { IndexFailure } from './types';
import type { Artifacts, Document, IndexDeps, IndexState, IndexStore, Manifest, Snapshot } from './types';

const ACCOUNT: RagRequest = { wireVersion: 1, question: 'alpha beta gamma', scope: { type: 'account' } };
const NOTE_SCOPE = (noteId: string): RagRequest => ({
  wireVersion: 1,
  question: 'alpha beta gamma',
  scope: { type: 'note', noteId },
});

const longContent = (label: string): string =>
  Array.from({ length: 220 }, (_, index) => `doan ${index} noi ve alpha beta gamma cua ${label}`).join('. ');

const noteOf = (ownerId: string, noteId: string, content: string): CanonicalNote => ({
  ownerId,
  noteId,
  revision: 7,
  title: `Tieu de ${noteId}`,
  content,
  synced: true,
  protected: false,
  deleted: false,
  available: true,
});

const vector1024 = (seed: number): readonly number[] =>
  Object.freeze(Array.from({ length: policy.embedding.dimensions }, (_, index) => (index === seed % 8 ? 1 : 0)));

type Counts = {
  loads: number;
  reserves: number;
  reads: number;
  queries: number;
  getVectors: number;
  embeds: number;
  order: string[];
  queryNoteIds: (string | null)[];
};

type Fixture = Readonly<{
  deps: IndexDeps;
  counts: Counts;
  states: Map<string, IndexState>;
  snapshots: Map<string, Snapshot>;
  events: string[];
}>;

/** One owner fixture: a current manifest, its snapshot and the fake ports over both. */
const fixtureFor = (
  owners: Readonly<Record<string, readonly CanonicalNote[]>>,
  options: Readonly<{ version?: string; tamperManifest?: boolean }> = {},
): Fixture => {
  const counts: Counts = {
    loads: 0, reserves: 0, reads: 0, queries: 0, getVectors: 0, embeds: 0, order: [], queryNoteIds: [],
  };
  const states = new Map<string, IndexState>();
  const snapshots = new Map<string, Snapshot>();
  const documentsByOwner = new Map<string, readonly Document[]>();

  for (const [ownerId, notes] of Object.entries(owners)) {
    const documents = notes.flatMap((note) =>
      chunkNote(note, countSyntheticTokens).map((chunk) => ({
        chunk,
        vectorKey: sha256Hex(`vector\u0000${sourceKey(chunk)}`),
        embeddingDigest: sha256Hex(`digest\u0000${sourceKey(chunk)}`),
      })),
    );
    const base: IndexState = {
      ownerId,
      accountEpoch: 3,
      consent: Object.freeze({ accepted: true, version: CONSENT_VERSION, generation: 2 }),
      notes: notes.map((note) => Object.freeze({ ...note, protectionRevision: 0 })),
      manifest: null,
    };
    const version = options.version ?? 'v1';
    const snapshot: Snapshot = Object.freeze({
      schemaVersion: 1,
      ownerId,
      version,
      consentGeneration: base.consent.generation,
      accountEpoch: base.accountEpoch,
      policyIdentity: policyIdentity(),
      documents: Object.freeze(documents),
    });
    const manifest: Manifest = Object.freeze({
      ownerId,
      generation: 1,
      version,
      fingerprint: options.tamperManifest === true ? sha256Hex('tampered') : fingerprint(base),
      consentGeneration: base.consent.generation,
      accountEpoch: base.accountEpoch,
      status: 'READY',
      snapshotKey: `rag/snapshots/${sha256Hex(ownerId)}/${version}.json`,
      checksum: checksum(snapshot),
      policyIdentity: policyIdentity(),
    });
    const state: IndexState = Object.freeze({ ...base, manifest });
    states.set(ownerId, state);
    snapshots.set(`${ownerId}/${version}/${manifest.checksum}`, snapshot);
    documentsByOwner.set(ownerId, documents);
  }

  const store: IndexStore = {
    load: async (ownerId, signal) => {
      counts.loads += 1;
      if (signal.aborted) throw new IndexFailure('TIMEOUT', true);
      const state = states.get(ownerId);
      if (state === undefined) throw new IndexFailure('INVALID_INPUT', false);
      return state;
    },
    acquire: async () => null,
    publish: async () => false,
    finish: async () => {},
    reserveEmbedding: async (_ownerId, signal) => {
      counts.reserves += 1;
      counts.order.push('reserve');
      if (signal.aborted) throw new IndexFailure('TIMEOUT', true);
    },
  };

  const artifacts: Artifacts = {
    read: async (manifest, signal) => {
      counts.reads += 1;
      if (signal.aborted) throw new IndexFailure('TIMEOUT', true);
      const found = snapshots.get(`${manifest.ownerId}/${manifest.version}/${manifest.checksum}`);
      if (found === undefined) throw new IndexFailure('SNAPSHOT_NOT_FOUND', false);
      return found;
    },
    put: async () => ({ key: '', checksum: sha256Hex('put') }),
    putVectors: async () => {},
    getVectors: async (keys, signal) => {
      counts.getVectors += 1;
      if (signal.aborted) throw new IndexFailure('TIMEOUT', true);
      const found = new Map<string, readonly number[]>();
      // A partial response: the last requested key is deliberately missing.
      for (const [index, key] of keys.entries()) {
        if (index === keys.length - 1) break;
        found.set(key, vector1024(index));
      }
      return found;
    },
    query: async (vector, ownerId, version, noteId, signal) => {
      counts.queries += 1;
      counts.queryNoteIds.push(noteId);
      if (signal.aborted) throw new IndexFailure('TIMEOUT', true);
      assert.equal(vector.length, policy.embedding.dimensions);
      const documents = documentsByOwner.get(ownerId) ?? [];
      return documents
        .filter((document) => document.chunk.ownerId === ownerId && (noteId === null || document.chunk.noteId === noteId))
        .map((document) => document.vectorKey);
    },
    cleanup: async () => {},
  };

  const embedding = {
    count: countSyntheticTokens as Counter,
    embed: async (texts: readonly string[], purpose: 'search_document' | 'search_query', signal: AbortSignal) => {
      counts.embeds += 1;
      counts.order.push('embed');
      if (signal.aborted) throw new IndexFailure('TIMEOUT', true);
      assert.equal(purpose, 'search_query');
      return texts.map((_text, index) => vector1024(index));
    },
  };

  return Object.freeze({ deps: { store, artifacts, embedding }, counts, states, snapshots, events: counts.order });
};

const contextFor = async (
  ports: ReturnType<typeof createQueryPorts>,
  actor: string,
  request: RagRequest,
): Promise<RequestContext> => {
  const signal = AbortSignal.timeout(26_000);
  return beginContext(actor, request, ports.authority, signal);
};

test('authority requires a current manifest and never reaches artifacts when it is not current', async () => {
  const current = fixtureFor({ 'rag-smoke-a': [noteOf('rag-smoke-a', 'n-a', longContent('a'))] });
  const ports = createQueryPorts(current.deps);
  const context = await contextFor(ports, 'rag-smoke-a', ACCOUNT);
  assert.equal(context.state.indexReady, true);
  assert.equal(context.state.manifestVersion, 'v1');

  const tampered = fixtureFor(
    { 'rag-smoke-a': [noteOf('rag-smoke-a', 'n-a', longContent('a'))] },
    { tamperManifest: true },
  );
  await assert.rejects(
    () => contextFor(createQueryPorts(tampered.deps), 'rag-smoke-a', ACCOUNT),
    (error: unknown) => (error as { code?: string }).code === 'INDEX_NOT_READY',
  );
  assert.equal(tampered.counts.reads, 0);
  assert.equal(tampered.counts.queries, 0);
  assert.equal(tampered.counts.embeds, 0);
});

test('a canonical note changed after authorization is refused on revalidation before any snapshot read', async () => {
  const notes = [noteOf('rag-smoke-a', 'n-a', longContent('a'))];
  const fixture = fixtureFor({ 'rag-smoke-a': notes });
  const ports = createQueryPorts(fixture.deps);
  const context = await contextFor(ports, 'rag-smoke-a', ACCOUNT);
  fixture.states.set(
    'rag-smoke-a',
    Object.freeze({
      ...fixture.states.get('rag-smoke-a')!,
      notes: Object.freeze([Object.freeze({ ...notes[0]!, content: longContent('changed'), protectionRevision: 0 })]),
    }),
  );
  // The recomputed fingerprint no longer matches the manifest, so the index is not ready for the
  // changed canonical state; either way it is refused before the snapshot is touched.
  await assert.rejects(
    () => context.revalidate(),
    (error: unknown) => (error as { code?: string }).code === 'INDEX_NOT_READY',
  );
  assert.equal(fixture.counts.reads, 0);
});

test('the scoped corpus is canonical-validated and the note scope never leaks other notes', async () => {
  const notes = [
    noteOf('rag-smoke-a', 'n-a', longContent('a')),
    noteOf('rag-smoke-a', 'n-b', longContent('b')),
  ];
  const fixture = fixtureFor({ 'rag-smoke-a': notes });
  const ports = createQueryPorts(fixture.deps);

  const account = await contextFor(ports, 'rag-smoke-a', ACCOUNT);
  await ports.retrieval.keywordSearch(ACCOUNT.question, account);
  const accountKeys = await ports.retrieval.vectorSearch(vector1024(0), account);
  assert.ok(accountKeys.length > 2, 'account scope sees both notes');

  const noteOnly = await contextFor(ports, 'rag-smoke-a', NOTE_SCOPE('n-a'));
  const scopedKeys = await ports.retrieval.vectorSearch(vector1024(0), noteOnly);
  assert.ok(scopedKeys.length > 0);
  assert.ok(scopedKeys.every((entry) => entry.chunk.noteId === 'n-a'));
  const keyword = await ports.retrieval.keywordSearch(NOTE_SCOPE('n-a').question, noteOnly);
  assert.ok(keyword.every((entry) => entry.chunk.noteId === 'n-a'));
  assert.deepEqual(fixture.counts.queryNoteIds, [null, 'n-a'], 'owner/version AND note filter per scope');
});

test('a vector key outside the scoped snapshot is SOURCE_CHANGED, never an answer', async () => {
  const notes = [noteOf('rag-smoke-a', 'n-a', longContent('a'))];
  const fixture = fixtureFor({ 'rag-smoke-a': notes });
  const deps: IndexDeps = {
    ...fixture.deps,
    artifacts: { ...fixture.deps.artifacts, query: async () => [sha256Hex('foreign-key')] },
  };
  const ports = createQueryPorts(deps);
  const context = await contextFor(ports, 'rag-smoke-a', ACCOUNT);
  await assert.rejects(
    () => ports.retrieval.vectorSearch(vector1024(0), context),
    (error: unknown) => (error as { code?: string }).code === 'SOURCE_CHANGED',
  );
});

test('snapshots are cached by owner/version/checksum and two warm owners stay isolated', async () => {
  const fixture = fixtureFor({
    'rag-smoke-a': [noteOf('rag-smoke-a', 'n-a', longContent('a'))],
    'rag-smoke-b': [noteOf('rag-smoke-b', 'n-b', longContent('b'))],
  });
  const ports = createQueryPorts(fixture.deps);

  const [contextA, contextB] = await Promise.all([
    contextFor(ports, 'rag-smoke-a', ACCOUNT),
    contextFor(ports, 'rag-smoke-b', ACCOUNT),
  ]);
  const [a, b] = await Promise.all([
    ports.retrieval.vectorSearch(vector1024(0), contextA),
    ports.retrieval.vectorSearch(vector1024(1), contextB),
  ]);
  assert.equal(fixture.counts.reads, 2, 'one snapshot read per owner');
  assert.ok(a.every((entry) => entry.chunk.ownerId === 'rag-smoke-a'));
  assert.ok(b.every((entry) => entry.chunk.ownerId === 'rag-smoke-b'));
  assert.ok(!a.some((left) => b.some((right) => sourceKey(left.chunk) === sourceKey(right.chunk))));

  // One cached generation bounds memory; switching owners evicts A without sharing B's data.
  const warmA = await contextFor(ports, 'rag-smoke-a', ACCOUNT);
  await ports.retrieval.vectorSearch(vector1024(0), warmA);
  assert.equal(fixture.counts.reads, 3);
  const sameOwner = await contextFor(ports, 'rag-smoke-a', ACCOUNT);
  await ports.retrieval.vectorSearch(vector1024(0), sameOwner);
  assert.equal(fixture.counts.reads, 3, 'same owner/version/checksum is warm');

  const changed = fixtureFor({ 'rag-smoke-a': [noteOf('rag-smoke-a', 'n-a', longContent('a'))] }, { version: 'v2' });
  const changedPorts = createQueryPorts(changed.deps);
  const changedContext = await contextFor(changedPorts, 'rag-smoke-a', ACCOUNT);
  await changedPorts.retrieval.vectorSearch(vector1024(0), changedContext);
  assert.equal(changed.counts.reads, 1);
  assert.equal((await changedPorts.authority.read('rag-smoke-a', AbortSignal.timeout(1_000))).manifestVersion, 'v2');
});

test('an empty eligible scope costs zero snapshot reads and zero embeddings', async () => {
  const fixture = fixtureFor({ 'rag-smoke-a': [] });
  const ports = createQueryPorts(fixture.deps);
  const context = await contextFor(ports, 'rag-smoke-a', ACCOUNT);
  assert.equal(context.notes.length, 0);
  assert.deepEqual(await ports.retrieval.keywordSearch(ACCOUNT.question, context), []);
  assert.deepEqual(await ports.retrieval.vectorSearch(vector1024(0), context), []);
  assert.deepEqual(await ports.retrieval.neighbors([], context), []);
  assert.equal((await ports.retrieval.getVectors([], context)).size, 0);
  assert.equal(fixture.counts.reads, 0);
  assert.equal(fixture.counts.queries, 0);
  assert.equal(fixture.counts.embeds, 0);
});

test('getVectors matches every requested chunk and fails closed on a partial response', async () => {
  const notes = [noteOf('rag-smoke-a', 'n-a', longContent('a'))];
  const fixture = fixtureFor({ 'rag-smoke-a': notes });
  const ports = createQueryPorts(fixture.deps);
  const context = await contextFor(ports, 'rag-smoke-a', ACCOUNT);
  const ranked = await ports.retrieval.vectorSearch(vector1024(0), context);
  assert.ok(ranked.length >= 2, 'the long note yields several chunks');
  const anchors = ranked.slice(0, 2).map((entry) => entry.chunk);

  const complete = fixtureFor({ 'rag-smoke-a': notes });
  const completePorts = createQueryPorts({
    ...complete.deps,
    artifacts: {
      ...complete.deps.artifacts,
      getVectors: async (keys) => new Map(keys.map((key, index) => [key, vector1024(index)] as const)),
    },
  });
  const completeContext = await contextFor(completePorts, 'rag-smoke-a', ACCOUNT);
  const vectors = await completePorts.retrieval.getVectors(anchors, completeContext);
  assert.equal(vectors.size, anchors.length);
  for (const anchor of anchors) assert.ok(vectors.has(sourceKey(anchor)));

  await assert.rejects(
    () => ports.retrieval.getVectors(anchors, context),
    (error: unknown) => (error as { code?: string }).code === 'INDEX_NOT_READY',
  );
});

test('neighbors are the exactly adjacent ordinals of the same note revision and section', async () => {
  const notes = [noteOf('rag-smoke-a', 'n-a', longContent('a'))];
  const fixture = fixtureFor({ 'rag-smoke-a': notes });
  const ports = createQueryPorts(fixture.deps);
  const context = await contextFor(ports, 'rag-smoke-a', ACCOUNT);
  const ranked = await ports.retrieval.vectorSearch(vector1024(0), context);
  const anchor = ranked[1]!.chunk;
  const neighbors = await ports.retrieval.neighbors([anchor], context);
  assert.ok(neighbors.length > 0);
  for (const neighbor of neighbors) {
    assert.equal(neighbor.noteId, anchor.noteId);
    assert.equal(neighbor.revision, anchor.revision);
    assert.equal(Math.abs(neighbor.ordinal - anchor.ordinal), 1);
  }
});

test('embedQuery reserves the shared counter before exactly one search_query call', async () => {
  const fixture = fixtureFor({ 'rag-smoke-a': [noteOf('rag-smoke-a', 'n-a', longContent('a'))] });
  const ports = createQueryPorts(fixture.deps);
  const context = await contextFor(ports, 'rag-smoke-a', ACCOUNT);
  const vector = await ports.retrieval.embedQuery(ACCOUNT.question, context.signal);
  assert.equal(vector.length, policy.embedding.dimensions);
  assert.deepEqual(fixture.counts.order, ['reserve', 'embed']);
  assert.equal(fixture.counts.reserves, 1);
  assert.equal(fixture.counts.embeds, 1);

  const oversized = await contextFor(ports, 'rag-smoke-a', ACCOUNT);
  await assert.rejects(
    () => ports.retrieval.embedQuery('a'.repeat(policy.chunking.maxEmbeddingCharacters + 1), oversized.signal),
    (error: unknown) => (error as { code?: string }).code === 'INPUT_TOO_LONG',
  );
  assert.equal(fixture.counts.reserves, 1, 'no reservation for a rejected input');
  assert.equal(fixture.counts.embeds, 1);
});

test('retrieval called without an authorized request signal fails closed', async () => {
  const fixture = fixtureFor({ 'rag-smoke-a': [noteOf('rag-smoke-a', 'n-a', longContent('a'))] });
  const ports = createQueryPorts(fixture.deps);
  const orphan = AbortSignal.timeout(1_000);
  await assert.rejects(
    () => ports.retrieval.embedQuery(ACCOUNT.question, orphan),
    (error: unknown) => (error as { code?: string }).code === 'INDEX_NOT_READY',
  );
  assert.equal(fixture.counts.reserves, 0);
});

test('a retrieval Ranked entry is returned unmodified: no fusion or evidence work in the ports', async () => {
  const fixture = fixtureFor({ 'rag-smoke-a': [noteOf('rag-smoke-a', 'n-a', longContent('a'))] });
  const ports = createQueryPorts(fixture.deps);
  const context = await contextFor(ports, 'rag-smoke-a', ACCOUNT);
  const keyword: readonly Ranked[] = await ports.retrieval.keywordSearch(ACCOUNT.question, context);
  assert.ok(keyword.length > 0);
  assert.deepEqual(keyword.map((entry) => entry.rank), keyword.map((_entry, index) => index + 1));
  for (const entry of keyword) assert.ok(entry.chunk instanceof Object && typeof entry.chunk.chunkId === 'string');
  // The ports expose only retrieval primitives; RRF/MMR/evidence remain pipeline responsibilities.
  assert.deepEqual(Object.keys(ports).sort(), ['authority', 'retrieval']);
  assert.deepEqual(
    Object.keys(ports.retrieval).sort(),
    ['embedQuery', 'getVectors', 'keywordSearch', 'neighbors', 'vectorSearch'],
  );
});

test('embedQuery awaits the dispatch callback after reservation and before the paid embed', async () => {
  const fixture = fixtureFor({ 'rag-smoke-a': [noteOf('rag-smoke-a', 'n-a', longContent('a'))] });
  const ports = createQueryPorts(fixture.deps);
  const context = await contextFor(ports, 'rag-smoke-a', ACCOUNT);
  const vector = await ports.retrieval.embedQuery(ACCOUNT.question, context.signal, async () => {
    fixture.counts.order.push('dispatch');
  });
  assert.equal(vector.length, policy.embedding.dimensions);
  assert.deepEqual(fixture.counts.order, ['reserve', 'dispatch', 'embed']);
  assert.equal(fixture.counts.reserves, 1);
  assert.equal(fixture.counts.embeds, 1);
});

test('embedQuery without a dispatch callback fails closed on a canonical fingerprint move', async () => {
  const notes = [noteOf('rag-smoke-a', 'n-a', longContent('a'))];
  const fixture = fixtureFor({ 'rag-smoke-a': notes });
  const ports = createQueryPorts(fixture.deps);
  const context = await contextFor(ports, 'rag-smoke-a', ACCOUNT);
  // The canonical state moves after authorization; a direct caller has no captured revalidate,
  // so the port must re-read and demand the exact fingerprint before the paid embed.
  fixture.states.set(
    'rag-smoke-a',
    Object.freeze({
      ...fixture.states.get('rag-smoke-a')!,
      notes: Object.freeze([Object.freeze({ ...notes[0]!, content: longContent('changed'), protectionRevision: 0 })]),
    }),
  );
  await assert.rejects(
    () => ports.retrieval.embedQuery(ACCOUNT.question, context.signal),
    (error: unknown) => (error as { code?: string }).code === 'SOURCE_CHANGED',
  );
  assert.equal(fixture.counts.reserves, 1, 'the reservation still ran');
  assert.equal(fixture.counts.embeds, 0, 'no paid embed after the fingerprint moved');
});

test('embedQuery forwards the dispatch callback into the embedding port reservation window', async () => {
  const fixture = fixtureFor({ 'rag-smoke-a': [noteOf('rag-smoke-a', 'n-a', longContent('a'))] });
  let dispatches = 0;
  let rawEmbeds = 0;
  let forwarded: unknown;
  const deps: IndexDeps = {
    ...fixture.deps,
    embedding: {
      count: fixture.deps.embedding.count,
      embed: async (texts, _purpose, _signal, beforeDispatch) => {
        forwarded = beforeDispatch;
        // Simulate the private Cohere reservation: an async window before the raw paid call.
        await Promise.resolve();
        if (typeof beforeDispatch === 'function') {
          dispatches += 1;
          await beforeDispatch();
        }
        rawEmbeds += 1;
        return texts.map((_text, index) => vector1024(index));
      },
    },
  };
  const ports = createQueryPorts(deps);
  const context = await contextFor(ports, 'rag-smoke-a', ACCOUNT);
  let calls = 0;
  // The first invocation is the port's own pre-embed revalidation; the second is the forwarded
  // one after the embedding port's async reservation window, where the permit is withdrawn.
  const callback = async () => {
    calls += 1;
    if (calls >= 2) throw new IndexFailure('SOURCE_CHANGED', false);
  };
  await assert.rejects(
    () => ports.retrieval.embedQuery(ACCOUNT.question, context.signal, callback),
    (error: unknown) => (error as { code?: string }).code === 'SOURCE_CHANGED',
  );
  assert.equal(typeof forwarded, 'function', 'the callback is forwarded to the embedding port');
  assert.equal(dispatches, 1, 'the embedding port re-runs the revalidation before the raw call');
  assert.equal(rawEmbeds, 0, 'no raw embed after the withdrawal during the reservation window');
  assert.equal(fixture.counts.reserves, 1, 'the reservation is retained, never refunded');
});
