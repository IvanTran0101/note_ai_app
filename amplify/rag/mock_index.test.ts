/**
 * Phase 2 mock index tests: snapshot codec round-trip and rejections, canonical coherence checks,
 * tenant/scope filtering, batched getVectors reuse and +/-1 neighbour expansion. Fixture data only;
 * no disk, cloud or provider call.
 *
 * Runner: node --import tsx --test amplify/rag/mock_index.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { beginContext } from './authority';
import { CONSENT_VERSION } from './contract';
import { ANALYZER_VERSION } from './keyword';
import {
  INDEX_ANALYZER_VERSION,
  INDEX_CHUNKING_POLICY,
  INDEX_DIMENSIONS,
  INDEX_MODEL,
  SNAPSHOT_VERSION,
  buildLexicalSnapshot,
  createMockIndex,
  decodeLexicalSnapshot,
  embedSearchDocument,
  embedSearchQuery,
  encodeLexicalSnapshot,
} from './mock_index';
import type { LexicalSnapshot } from './mock_index';
import { RagFailure, policy, sourceKey } from './types';
import type {
  AuthorityStore,
  CanonicalNote,
  CanonicalState,
  Chunk,
  Counter,
  RequestContext,
  Scope,
} from './types';

const MANIFEST = 'mock-1';
/** Same deterministic synthetic counter as the runtime: ceil(code points / 4). */
const counter: Counter = (text) => Math.ceil(Array.from(text).length / 4);

const noteOf = (over: Partial<CanonicalNote> = {}): CanonicalNote => ({
  ownerId: 'actor-a',
  noteId: 'n-1',
  revision: 1,
  title: 'Ghi chú',
  content: 'alpha beta gamma',
  synced: true,
  protected: false,
  deleted: false,
  available: true,
  ...over,
});

const stateOf = (notes: readonly CanonicalNote[], over: Partial<CanonicalState> = {}): CanonicalState => ({
  actorId: 'actor-a',
  sessionGeneration: 1,
  consent: { accepted: true, version: CONSENT_VERSION, generation: 1 },
  indexReady: true,
  manifestVersion: MANIFEST,
  notes,
  ...over,
});

const storeOf = (state: CanonicalState): AuthorityStore => ({ read: async () => state });

const contextFor = async (
  actor: string,
  state: CanonicalState,
  scope: Scope,
  question = 'alpha beta?',
): Promise<RequestContext> =>
  beginContext(actor, { wireVersion: 1, question, scope }, storeOf(state), new AbortController().signal);

const codeOf = async (run: () => unknown): Promise<string> => {
  try {
    await run();
  } catch (error) {
    if (error instanceof RagFailure) return error.code;
    throw error;
  }
  throw new Error('expected a RagFailure');
};

const mutateJson = (snapshot: LexicalSnapshot, mutate: (value: Record<string, any>) => void): string => {
  const value = JSON.parse(encodeLexicalSnapshot(snapshot)) as Record<string, any>;
  mutate(value);
  return JSON.stringify(value);
};

const PARAGRAPHS = ['a'.repeat(1600), 'b'.repeat(1600), 'c'.repeat(1600), 'd'.repeat(1600)];
const multiNote = noteOf({ noteId: 'n-multi', title: 'T', content: PARAGRAPHS.join('\n\n') });

test('a canonically empty note is an empty corpus, not a missing index artifact', async () => {
  const state = stateOf([noteOf({ content: ' \n ' })]);
  const index = createMockIndex(buildLexicalSnapshot('actor-a', state, counter));
  const context = await contextFor('actor-a', state, { type: 'account' });
  assert.deepEqual(await index.keywordSearch('alpha', context), []);
  assert.deepEqual(await index.vectorSearch(embedSearchQuery('alpha'), context), []);
});
test('same strategy with different numeric chunk limits is still a different policy', () => {
  const snapshot = buildLexicalSnapshot('actor-a', stateOf([noteOf()]), counter);
  const encoded = mutateJson(snapshot, value => {
    const identity = JSON.parse(value.metadata.chunkingPolicy);
    identity.chunking.maxEmbeddingTokens = 513;
    value.metadata.chunkingPolicy = JSON.stringify(identity);
  });
  assert.throws(() => decodeLexicalSnapshot(encoded), /INDEX_NOT_READY/);
});

test('snapshot metadata carries the policy identity and the codec round-trips exactly', async () => {
  const state = stateOf([noteOf()]);
  const snapshot = buildLexicalSnapshot('actor-a', state, counter);
  assert.equal(snapshot.codec, 'rag-lexical-snapshot.v1');
  assert.equal(snapshot.metadata.snapshotVersion, SNAPSHOT_VERSION);
  assert.equal(snapshot.metadata.model, INDEX_MODEL);
  assert.equal(snapshot.metadata.model, policy.embedding.model);
  assert.equal(snapshot.metadata.dimensions, INDEX_DIMENSIONS);
  assert.equal(snapshot.metadata.dimensions, policy.embedding.dimensions);
  assert.equal(snapshot.metadata.chunkingPolicy, INDEX_CHUNKING_POLICY);
  assert.deepEqual(JSON.parse(snapshot.metadata.chunkingPolicy), {
    contract: policy.contractVersion, chunking: policy.chunking,
    text: policy.technicalDefaults.embeddingText, offset: policy.technicalDefaults.offsetUnit,
  });
  assert.equal(snapshot.metadata.analyzerVersion, INDEX_ANALYZER_VERSION);
  assert.equal(snapshot.metadata.analyzerVersion, ANALYZER_VERSION);
  assert.equal(snapshot.metadata.manifestVersion, MANIFEST);
  assert.equal(snapshot.metadata.consentGeneration, 1);
  assert.equal(snapshot.metadata.ownerId, 'actor-a');

  const encoded = encodeLexicalSnapshot(snapshot);
  const decoded = decodeLexicalSnapshot(encoded);
  assert.deepEqual(decoded, snapshot);
  const rebuilt = createMockIndex(decoded);
  assert.equal(rebuilt.encodeLexicalSnapshot(), encoded);
  assert.deepEqual(rebuilt.metadata, snapshot.metadata);

  const context = await contextFor('actor-a', state, { type: 'note', noteId: 'n-1' });
  const ranked = await rebuilt.vectorSearch(embedSearchQuery('alpha'), context);
  assert.equal(ranked.length, 1);
  assert.equal(ranked[0]?.rank, 1);
  assert.equal(ranked[0]?.chunk.noteId, 'n-1');
  const keyword = await rebuilt.keywordSearch('alpha', context);
  assert.equal(keyword.length, 1);
  assert.equal(keyword[0]?.rank, 1);
});

test('the codec refuses malformed, wrong-identity, wrong-owner and inconsistent snapshots', async () => {
  const snapshot = buildLexicalSnapshot('actor-a', stateOf([noteOf(), noteOf({ noteId: 'n-2', content: 'delta epsilon' })]), counter);
  const cases: readonly (readonly [string, string])[] = [
    ['malformed JSON', '{'],
    ['wrong codec', mutateJson(snapshot, (value) => { value['codec'] = 'rag-lexical-snapshot.v2'; })],
    ['wrong snapshot version', mutateJson(snapshot, (value) => { value['metadata']['snapshotVersion'] = 2; })],
    ['wrong model', mutateJson(snapshot, (value) => { value['metadata']['model'] = 'other-embed'; })],
    ['wrong dimensions', mutateJson(snapshot, (value) => { value['metadata']['dimensions'] = 768; })],
    ['wrong analyzer', mutateJson(snapshot, (value) => { value['metadata']['analyzerVersion'] = 'rag-analyzer.v0'; })],
    ['wrong chunking policy', mutateJson(snapshot, (value) => { value['metadata']['chunkingPolicy'] = 'fixed-window'; })],
    ['extra metadata key', mutateJson(snapshot, (value) => { value['metadata']['cacheHint'] = 'trust-me'; })],
    ['loose chunk shape', mutateJson(snapshot, (value) => { value['documents'][0]['chunk']['endOffset'] = 999; })],
    ['unbound source key', mutateJson(snapshot, (value) => { value['documents'][0]['sourceKey'] = `${value['documents'][0]['sourceKey']}x`; })],
    ['duplicate source key', mutateJson(snapshot, (value) => { value['documents'].push({ ...value['documents'][0] }); })],
    ['non-array documents', mutateJson(snapshot, (value) => { value['documents'] = {}; })],
  ];
  for (const [name, encoded] of cases) {
    assert.equal(await codeOf(() => decodeLexicalSnapshot(encoded)), 'INDEX_NOT_READY', name);
  }
});

test('a snapshot for another actor is refused, never searched', async () => {
  const foreign = buildLexicalSnapshot('actor-b', stateOf([noteOf({ ownerId: 'actor-b', content: 'foreign secret' })], { actorId: 'actor-b' }), counter);
  const index = createMockIndex(foreign);
  const context = await contextFor('actor-a', stateOf([noteOf()]), { type: 'account' });
  assert.equal(await codeOf(() => index.vectorSearch(embedSearchQuery('alpha'), context)), 'SCOPE_DENIED');
  assert.equal(await codeOf(() => index.keywordSearch('alpha', context)), 'SCOPE_DENIED');
  assert.equal(await codeOf(() => index.getVectors([], context)), 'SCOPE_DENIED');
  assert.equal(await codeOf(() => index.neighbors([], context)), 'SCOPE_DENIED');
});

test('a stale manifest, consent generation or artifact revision is INDEX_NOT_READY before search', async () => {
  const state = stateOf([noteOf()]);
  const index = createMockIndex(buildLexicalSnapshot('actor-a', state, counter));

  const staleManifest = await contextFor('actor-a', stateOf([noteOf()], { manifestVersion: 'mock-2' }), { type: 'account' });
  assert.equal(await codeOf(() => index.vectorSearch(embedSearchQuery('alpha'), staleManifest)), 'INDEX_NOT_READY');

  const staleConsent = await contextFor(
    'actor-a',
    stateOf([noteOf()], { consent: { accepted: true, version: CONSENT_VERSION, generation: 7 } }),
    { type: 'account' },
  );
  assert.equal(await codeOf(() => index.keywordSearch('alpha', staleConsent)), 'INDEX_NOT_READY');

  const newerRevision = await contextFor('actor-a', stateOf([noteOf({ revision: 2 })]), { type: 'account' });
  assert.equal(await codeOf(() => index.vectorSearch(embedSearchQuery('alpha'), newerRevision)), 'INDEX_NOT_READY');
  assert.equal(await codeOf(() => index.keywordSearch('alpha', newerRevision)), 'INDEX_NOT_READY');
  assert.equal(await codeOf(() => index.getVectors([], newerRevision)), 'INDEX_NOT_READY');
});

test('a scoped note without an artifact is index-not-ready while a coherent empty corpus is empty', async () => {
  const emptySnapshot = buildLexicalSnapshot('actor-a', stateOf([]), counter);
  const emptyIndex = createMockIndex(emptySnapshot);

  const emptyContext = await contextFor('actor-a', stateOf([]), { type: 'account' });
  assert.deepEqual(await emptyIndex.vectorSearch(embedSearchQuery('alpha'), emptyContext), []);
  assert.deepEqual(await emptyIndex.keywordSearch('alpha', emptyContext), []);
  assert.equal((await emptyIndex.getVectors([], emptyContext)).size, 0);
  assert.deepEqual(await emptyIndex.neighbors([], emptyContext), []);

  const missingArtifact = await contextFor('actor-a', stateOf([noteOf()]), { type: 'account' });
  assert.equal(await codeOf(() => emptyIndex.vectorSearch(embedSearchQuery('alpha'), missingArtifact)), 'INDEX_NOT_READY');
  assert.equal(await codeOf(() => emptyIndex.keywordSearch('alpha', missingArtifact)), 'INDEX_NOT_READY');
});

test('the snapshot indexes own eligible notes only, and no consent means no documents', async () => {
  const notes = [
    noteOf({ noteId: 'n-own' }),
    noteOf({ noteId: 'n-protected', protected: true }),
    noteOf({ noteId: 'n-deleted', deleted: true }),
    noteOf({ noteId: 'n-local', synced: false }),
    noteOf({ noteId: 'n-unavailable', available: false }),
    noteOf({ noteId: 'n-shared', incomingShared: true }),
    noteOf({ ownerId: 'actor-b', noteId: 'n-foreign', title: 'Foreign', content: 'foreign secret text' }),
    noteOf({ noteId: 'n-old', revision: 0 }),
  ];
  const snapshot = buildLexicalSnapshot('actor-a', stateOf(notes), counter);
  assert.deepEqual(snapshot.documents.map((document) => document.chunk.noteId), ['n-own']);

  const withoutConsent = buildLexicalSnapshot(
    'actor-a',
    stateOf([noteOf()], { consent: { accepted: false, version: CONSENT_VERSION, generation: 1 } }),
    counter,
  );
  assert.deepEqual(withoutConsent.documents, []);
});

test('each search filters by the request context scope, not by the snapshot claim', async () => {
  const state = stateOf([
    noteOf({ noteId: 'n-1', title: 'Alpha', content: 'alpha alpha alpha' }),
    noteOf({ noteId: 'n-2', title: 'Beta', content: 'beta beta beta' }),
  ]);
  const index = createMockIndex(buildLexicalSnapshot('actor-a', state, counter));

  const noteContext = await contextFor('actor-a', state, { type: 'note', noteId: 'n-1' });
  const scopedKeyword = await index.keywordSearch('alpha beta', noteContext);
  assert.ok(scopedKeyword.length > 0);
  assert.ok(scopedKeyword.every((entry) => entry.chunk.noteId === 'n-1'));
  const scopedVector = await index.vectorSearch(embedSearchQuery('alpha beta'), noteContext);
  assert.ok(scopedVector.length > 0);
  assert.ok(scopedVector.every((entry) => entry.chunk.noteId === 'n-1'));

  const accountContext = await contextFor('actor-a', state, { type: 'account' });
  const both = await index.keywordSearch('alpha beta', accountContext);
  assert.deepEqual([...new Set(both.map((entry) => entry.chunk.noteId))].sort(), ['n-1', 'n-2']);

  const alphaOnly = await index.vectorSearch(embedSearchQuery('alpha'), accountContext);
  assert.deepEqual(alphaOnly.map((entry) => entry.chunk.noteId), ['n-1']);
  assert.equal(alphaOnly[0]?.rank, 1);
  // Token-disjoint queries produce no positive match instead of a zero-score candidate.
  assert.deepEqual(await index.vectorSearch(embedSearchQuery('qqqq'), accountContext), []);
  assert.deepEqual(await index.keywordSearch('qqqq', accountContext), []);
});

test('embeddings are deterministic, 1024-dimensional, finite and unit-length', () => {
  const first = embedSearchQuery('alpha beta');
  const second = embedSearchQuery('alpha beta');
  assert.deepEqual(first, second);
  assert.equal(first.length, INDEX_DIMENSIONS);
  assert.ok(first.every((value) => Number.isFinite(value)));
  assert.ok(Math.abs(Math.hypot(...first) - 1) < 1e-9);
  assert.notDeepEqual(embedSearchQuery('alpha'), embedSearchQuery('gamma'));
  const document = embedSearchDocument('alpha beta');
  assert.equal(document.length, INDEX_DIMENSIONS);
  assert.ok(document.every((value) => Number.isFinite(value)));
  assert.ok(Math.abs(Math.hypot(...document) - 1) < 1e-9);
  // Lexical toy: the same tokens hash the same way for search_query and search_document.
  assert.deepEqual(first, document);
});

test('getVectors returns one batched map of stored vectors and refuses unknown or bad input', async () => {
  const state = stateOf([
    noteOf({ noteId: 'n-1', content: 'alpha alpha' }),
    noteOf({ noteId: 'n-2', content: 'beta beta' }),
  ]);
  const snapshot = buildLexicalSnapshot('actor-a', state, counter);
  const index = createMockIndex(snapshot);
  const context = await contextFor('actor-a', state, { type: 'account' });
  const chunks = snapshot.documents.map((document) => document.chunk);

  const batched = await index.getVectors(chunks, context);
  assert.equal(batched.size, chunks.length);
  for (const chunk of chunks) {
    const vector = batched.get(sourceKey(chunk));
    assert.ok(vector, sourceKey(chunk));
    assert.equal(vector.length, INDEX_DIMENSIONS);
    assert.ok(vector.every((value) => Number.isFinite(value)));
    assert.ok(Math.hypot(...vector) > 0);
  }
  // A second batch of the same chunks reuses the stored vector objects (no re-embedding path).
  const again = await index.getVectors([chunks[0] as Chunk], context);
  assert.equal(again.get(sourceKey(chunks[0] as Chunk)), batched.get(sourceKey(chunks[0] as Chunk)));

  const unknown = { ...(chunks[0] as Chunk), chunkId: 'body-9' };
  assert.equal(await codeOf(() => index.getVectors([unknown], context)), 'INDEX_NOT_READY');

  for (const vector of [
    new Array<number>(1023).fill(0.5),
    new Array<number>(INDEX_DIMENSIONS).fill(0),
    new Array<number>(INDEX_DIMENSIONS).fill(Number.NaN),
  ]) {
    assert.equal(await codeOf(() => index.vectorSearch(vector, context)), 'INDEX_NOT_READY');
  }
});

test('neighbours expand exactly +/-1 ordinal inside the same note/revision/section, without recursion', async () => {
  const state = stateOf([multiNote]);
  const snapshot = buildLexicalSnapshot('actor-a', state, counter);
  const index = createMockIndex(snapshot);
  const context = await contextFor('actor-a', state, { type: 'note', noteId: 'n-multi' });
  const chunks = snapshot.documents.map((document) => document.chunk);
  assert.deepEqual(chunks.map((chunk) => chunk.ordinal), [0, 1, 2, 3]);
  assert.ok(chunks.every((chunk) => chunk.noteId === 'n-multi' && chunk.revision === 1 && chunk.sectionId === 'body'));

  const middle = await index.neighbors([chunks[1] as Chunk], context);
  assert.deepEqual(middle.map((chunk) => chunk.ordinal), [0, 2]);
  const first = await index.neighbors([chunks[0] as Chunk], context);
  // No recursion: the far neighbour of the first chunk is never pulled through chunk 1.
  assert.deepEqual(first.map((chunk) => chunk.ordinal), [1]);
  const edges = await index.neighbors([chunks[0] as Chunk, chunks[3] as Chunk], context);
  assert.deepEqual(edges.map((chunk) => chunk.ordinal), [1, 2]);
  // Anchors are never returned as their own neighbours.
  const adjacentAnchors = await index.neighbors([chunks[1] as Chunk, chunks[2] as Chunk], context);
  assert.deepEqual(adjacentAnchors.map((chunk) => chunk.ordinal), [0, 3]);

  const single = noteOf({ noteId: 'n-single' });
  const singleSnapshot = buildLexicalSnapshot('actor-a', stateOf([single]), counter);
  const singleIndex = createMockIndex(singleSnapshot);
  const singleContext = await contextFor('actor-a', stateOf([single]), { type: 'note', noteId: 'n-single' });
  assert.deepEqual(
    await singleIndex.neighbors([singleSnapshot.documents[0]?.chunk as Chunk], singleContext),
    [],
  );
});
