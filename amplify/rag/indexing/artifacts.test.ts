/**
 * Artifacts port tests — owner/version-derived snapshot keys, checksum/identity tamper checks,
 * batched vector writes with minimal metadata, paginated reads, mandatory enhanced-mode query
 * filters, and retry-safe exact-key cleanup. All S3 and S3 Vectors IO is injected.
 * Runner: node --import tsx --test amplify/rag/indexing/artifacts.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import {
  DeleteObjectCommand, GetObjectCommand, PutObjectCommand,
} from '@aws-sdk/client-s3';
import type { Chunk } from '../types';
import { IndexFailure, type Manifest, type Snapshot } from './types';
import type { Document } from './types';
import { checksum, encodeSnapshot, policyIdentity, validateSnapshot } from './snapshot';
import { EMBEDDING_DIMENSIONS } from '../retrieval';
import type { AwsJson } from './aws_http';
import {
  QUERY_TOP_K, createArtifacts, type ArtifactsConfig, type S3Command, type S3Port,
  type S3SendOptions,
} from './artifacts';

const OWNER = 'u1';
const VERSION = 'lease-1';
const REGION = 'us-east-1';
const BUCKET = 'noteflow-rag-snapshots';
const INDEX_ARN = `arn:aws:s3vectors:${REGION}:123456789012:bucket/${BUCKET}/index/rag-index`;
const SIGNAL = new AbortController().signal;
const TEXT_SENTINEL = 'RAW-CANONICAL-TEXT-SENTINEL';
const TITLE_SENTINEL = 'TITLE-SENTINEL';
const sha256 = (text: string): string => createHash('sha256').update(text, 'utf8').digest('hex');
const SNAPSHOT_KEY = `rag/snapshots/${sha256(OWNER)}/${VERSION}.json`;

const VECTOR: readonly number[] = Object.freeze([1, ...new Array<number>(EMBEDDING_DIMENSIONS - 1).fill(0)]);
const jsonVector = (): number[] => [...VECTOR];

const chunk = (over: Partial<Chunk> = {}): Chunk => ({
  ownerId: OWNER, noteId: 'n1', revision: 1, sectionId: 'body', chunkId: 'body-0', ordinal: 0,
  title: 'T', startOffset: 0, endOffset: 5, text: 'hello', ...over,
});

const document = (index: number, over: Partial<Chunk> = {}): Document => ({
  chunk: chunk({ chunkId: `body-${index}`, ...over }),
  vectorKey: sha256(`vector-${index}`),
  embeddingDigest: sha256(`digest-${index}`),
});

const snapshotOf = (documents: readonly Document[], over: Partial<Snapshot> = {}): Snapshot =>
  validateSnapshot({
    schemaVersion: 1, ownerId: OWNER, version: VERSION, consentGeneration: 1, accountEpoch: 1,
    policyIdentity: policyIdentity(), documents, ...over,
  });

const manifestOf = (snapshot: Snapshot, over: Partial<Manifest> = {}): Manifest => Object.freeze({
  ownerId: snapshot.ownerId, generation: 1, version: snapshot.version, fingerprint: sha256('fingerprint'),
  consentGeneration: snapshot.consentGeneration, accountEpoch: snapshot.accountEpoch, status: 'READY',
  snapshotKey: SNAPSHOT_KEY, checksum: checksum(snapshot), policyIdentity: snapshot.policyIdentity,
  ...over,
});

const vectorsFor = (
  snapshot: Snapshot,
  vector: readonly number[] = VECTOR,
): Map<string, readonly number[]> =>
  new Map(snapshot.documents.map((entry) => [entry.vectorKey, vector]));

type Sent = Readonly<{ command: S3Command; options?: S3SendOptions }>;

const notFound = (): Error => {
  const error = new Error('not found');
  error.name = 'NoSuchKey';
  (error as unknown as { $metadata: unknown }).$metadata = { httpStatusCode: 404 };
  return error;
};

const s3Fake = (): Readonly<{ objects: Map<string, string>; sent: Sent[]; port: S3Port }> => {
  const objects = new Map<string, string>();
  const sent: Sent[] = [];
  const port: S3Port = {
    async send(command, options) {
      sent.push({ command, options });
      if (command instanceof PutObjectCommand) {
        objects.set(command.input.Key as string, String(command.input.Body));
        return {};
      }
      if (command instanceof GetObjectCommand) {
        const text = objects.get(command.input.Key as string);
        if (text === undefined) throw notFound();
        return { Body: { transformToString: async () => text } };
      }
      if (command instanceof DeleteObjectCommand) {
        objects.delete(command.input.Key as string);
        return {};
      }
      throw new Error('unexpected S3 command');
    },
  };
  return { objects, sent, port };
};

type VectorCall = Readonly<{ path: string; body: Record<string, unknown> }>;

const vectorFake = (
  handler: (call: VectorCall, index: number) => unknown = () => ({}),
): Readonly<{ calls: VectorCall[]; request: AwsJson }> => {
  const calls: VectorCall[] = [];
  const request: AwsJson = async (service, path, body) => {
    assert.equal(service, 's3vectors');
    const call = { path, body: body as Record<string, unknown> };
    calls.push(call);
    return handler(call, calls.length - 1);
  };
  return { calls, request };
};

const build = (over: Partial<ArtifactsConfig> = {}) => {
  const s3 = s3Fake();
  const vectors = vectorFake();
  const artifacts = createArtifacts(
    { region: REGION, snapshotBucket: BUCKET, vectorIndexArn: INDEX_ARN, ...over },
    { s3: s3.port, request: vectors.request },
  );
  return { ...s3, vectors, artifacts };
};

const failureOf = async (run: () => Promise<unknown>): Promise<IndexFailure> => {
  try {
    await run();
  } catch (error) {
    assert.ok(error instanceof IndexFailure, `expected IndexFailure, got ${String(error)}`);
    return error;
  }
  throw new Error('expected the call to fail');
};

const entriesOf = (call: VectorCall): readonly Record<string, unknown>[] =>
  call.body['vectors'] as readonly Record<string, unknown>[];
const keysOf = (call: VectorCall): readonly string[] => call.body['keys'] as readonly string[];
const hit = (
  key: string,
  distance = 0.5,
  metadata: Record<string, unknown> = {},
): Readonly<Record<string, unknown>> => ({
  key,
  distance,
  metadata: {
    ownerId: OWNER, manifestVersion: VERSION, noteId: 'n1', revision: 1, chunkId: 'body-0', ...metadata,
  },
});

test('configuration is validated at construction and fails closed', () => {
  const s3 = s3Fake();
  const request = vectorFake().request;
  const invalid: readonly Partial<ArtifactsConfig>[] = [
    { region: 'not-a-region' },
    { region: 'eu-west-1' },
    { snapshotBucket: 'Bad_Bucket' },
    { snapshotBucket: 'ab' },
    { vectorIndexArn: 'arn:aws:s3vectors:eu-west-1:123456789012:bucket/b/index/i' },
    { vectorIndexArn: 'arn:aws:s3:::bucket/index/i' },
    { vectorIndexArn: `arn:aws:s3vectors:${REGION}:123456789012:bucket/${BUCKET}` },
    { vectorIndexArn: `${INDEX_ARN} ` },
  ];
  for (const over of invalid) {
    assert.throws(
      () => createArtifacts(
        { region: REGION, snapshotBucket: BUCKET, vectorIndexArn: INDEX_ARN, ...over },
        { s3: s3.port, request },
      ),
      (error: unknown) =>
        error instanceof IndexFailure && error.code === 'INVALID_STATE' && error.retryable === false,
      JSON.stringify(over),
    );
  }
  assert.equal(s3.sent.length, 0);
});

test('put derives the immutable owner/version key and stores canonical JSON with bucket SSE', async () => {
  const { artifacts, sent } = build();
  const snapshot = snapshotOf([document(0), document(1)]);
  const result = await artifacts.put(snapshot, SIGNAL);

  assert.deepEqual(result, { key: SNAPSHOT_KEY, checksum: checksum(snapshot) });
  assert.ok(!SNAPSHOT_KEY.includes(OWNER), 'owner id is hashed out of the key space');
  assert.equal(sent.length, 1);
  const command = sent[0].command;
  assert.ok(command instanceof PutObjectCommand);
  assert.equal(command.input.Key, SNAPSHOT_KEY);
  assert.equal(command.input.ContentType, 'application/json');
  assert.equal(command.input.ServerSideEncryption, undefined);
  assert.equal(command.input.Body, encodeSnapshot(snapshot));
  assert.deepEqual(sent[0].options, { abortSignal: SIGNAL });
});

test('read round-trips the exact snapshot object and demands the derived key', async () => {
  const { artifacts, sent, vectors } = build();
  const snapshot = snapshotOf([document(0), document(1)]);
  await artifacts.put(snapshot, SIGNAL);
  sent.length = 0;

  const read = await artifacts.read(manifestOf(snapshot), SIGNAL);
  assert.deepEqual(read, snapshot);
  assert.equal(sent.length, 1);
  const command = sent[0].command;
  assert.ok(command instanceof GetObjectCommand);
  assert.equal(command.input.Key, SNAPSHOT_KEY);
  assert.deepEqual(sent[0].options, { abortSignal: SIGNAL });

  // The manifest may only name the key derived from its own owner and version.
  sent.length = 0;
  const foreignKey = await failureOf(() =>
    artifacts.read(manifestOf(snapshot, { snapshotKey: 'rag/snapshots/evil/lease-1.json' }), SIGNAL));
  assert.deepEqual([foreignKey.code, foreignKey.retryable], ['INDEX_NOT_READY', false]);
  const crossOwner = await failureOf(() =>
    artifacts.read(manifestOf(snapshot, { ownerId: 'u2' }), SIGNAL));
  assert.deepEqual([crossOwner.code, crossOwner.retryable], ['INDEX_NOT_READY', false]);
  const unsafeVersion = await failureOf(() =>
    artifacts.read(manifestOf(snapshot, { version: '../escape' }), SIGNAL));
  assert.deepEqual([unsafeVersion.code, unsafeVersion.retryable], ['INDEX_NOT_READY', false]);
  assert.equal(sent.length, 0, 'tamper checks happen before any S3 read');
  assert.equal(vectors.calls.length, 0);
});

test('a previous-policy snapshot stays readable and cleanable under its manifest identity', async () => {
  const { artifacts, objects, sent, vectors } = build();
  const oldPolicy = sha256('previous-policy-identity');
  const drifted = validateSnapshot({
    schemaVersion: 1, ownerId: OWNER, version: VERSION, consentGeneration: 1, accountEpoch: 1,
    policyIdentity: oldPolicy, documents: [document(0)],
  }, oldPolicy);
  objects.set(SNAPSHOT_KEY, encodeSnapshot(drifted));
  const oldManifest = manifestOf(drifted);

  assert.deepEqual(await artifacts.read(oldManifest, SIGNAL), drifted);
  await artifacts.cleanup(oldManifest, SIGNAL);
  assert.deepEqual(vectors.calls.map((call) => keysOf(call)), [[drifted.documents[0].vectorKey]]);
  assert.equal(objects.has(SNAPSHOT_KEY), false);
  assert.equal(sent.filter((entry) => entry.command instanceof DeleteObjectCommand).length, 1);

  // The same object under a manifest claiming the current policy must still fail closed.
  const staleObject = encodeSnapshot(snapshotOf([document(0)]));
  objects.set(SNAPSHOT_KEY, staleObject);
  const mismatch = await failureOf(() => artifacts.read(oldManifest, SIGNAL));
  assert.deepEqual([mismatch.code, mismatch.retryable], ['INDEX_NOT_READY', false]);
});

test('read fails closed on checksum, policy, object and transport tampering', async () => {
  const { artifacts, objects } = build();
  const snapshot = snapshotOf([document(0)]);
  await artifacts.put(snapshot, SIGNAL);

  // Stored bytes changed under the recorded checksum.
  const other = snapshotOf([document(1), document(2)]);
  objects.set(SNAPSHOT_KEY, encodeSnapshot(other));
  const checksumTamper = await failureOf(() => artifacts.read(manifestOf(snapshot), SIGNAL));
  assert.equal(checksumTamper.code, 'INDEX_NOT_READY');

  // Manifest policy identity no longer matches the stored snapshot.
  objects.set(SNAPSHOT_KEY, encodeSnapshot(snapshot));
  const policyTamper = await failureOf(() =>
    artifacts.read(manifestOf(snapshot, { policyIdentity: sha256('other-policy') }), SIGNAL));
  assert.equal(policyTamper.code, 'INDEX_NOT_READY');

  // Missing, unparsable and unreadable objects are all INDEX_NOT_READY.
  objects.clear();
  assert.equal((await failureOf(() => artifacts.read(manifestOf(snapshot), SIGNAL))).code, 'INDEX_NOT_READY');
  objects.set(SNAPSHOT_KEY, 'not-json');
  assert.equal((await failureOf(() => artifacts.read(manifestOf(snapshot), SIGNAL))).code, 'INDEX_NOT_READY');
  objects.clear();
  objects.set(SNAPSHOT_KEY, encodeSnapshot(snapshot));
  const bodyless = createArtifacts(
    { region: REGION, snapshotBucket: BUCKET, vectorIndexArn: INDEX_ARN },
    { s3: { send: async () => ({}) }, request: vectorFake().request },
  );
  assert.equal((await failureOf(() => bodyless.read(manifestOf(snapshot), SIGNAL))).code, 'INDEX_NOT_READY');

  // SDK status classes map to the shared taxonomy without echoing the SDK message.
  for (const [status, code, retryable] of [[500, 'PROVIDER_UNAVAILABLE', true], [403, 'UNAUTHORIZED', false]] as const) {
    const failing = createArtifacts(
      { region: REGION, snapshotBucket: BUCKET, vectorIndexArn: INDEX_ARN },
      {
        s3: {
          send: async () => {
            throw Object.assign(new Error(TEXT_SENTINEL), { $metadata: { httpStatusCode: status } });
          },
        },
        request: vectorFake().request,
      },
    );
    const error = await failureOf(() => failing.read(manifestOf(snapshot), SIGNAL));
    assert.deepEqual([error.code, error.retryable], [code, retryable]);
    assert.ok(!error.message.includes(TEXT_SENTINEL) && !String(error).includes(TEXT_SENTINEL));
  }
});

test('putVectors writes exact-key batches of at most 500 with minimal metadata and float32 data', async () => {
  const { artifacts, vectors } = build();
  const snapshot = snapshotOf(
    Array.from({ length: 501 }, (_value, index) =>
      document(index, { title: TITLE_SENTINEL, text: TEXT_SENTINEL, endOffset: TEXT_SENTINEL.length })),
  );
  await artifacts.putVectors(snapshot, vectorsFor(snapshot), SIGNAL);

  assert.equal(vectors.calls.length, 2);
  assert.deepEqual(vectors.calls.map((call) => entriesOf(call).length), [500, 1]);
  for (const call of vectors.calls) {
    assert.equal(call.path, '/PutVectors');
    assert.deepEqual(Object.keys(call.body).sort(), ['indexArn', 'vectors']);
    assert.equal(call.body['indexArn'], INDEX_ARN);
  }
  const entries = vectors.calls.flatMap((call) => [...entriesOf(call)]);
  assert.deepEqual(entries.map((entry) => entry['key']), snapshot.documents.map((doc) => doc.vectorKey));
  for (const [index, entry] of entries.entries()) {
    assert.deepEqual(Object.keys(entry).sort(), ['data', 'key', 'metadata']);
    assert.deepEqual(
      Object.keys(entry['metadata'] as Record<string, unknown>).sort(),
      ['chunkId', 'manifestVersion', 'noteId', 'ownerId', 'revision'],
    );
    assert.deepEqual(entry['metadata'], {
      ownerId: OWNER, manifestVersion: VERSION, noteId: 'n1', revision: 1, chunkId: `body-${index}`,
    });
    const data = entry['data'] as { float32: readonly number[] };
    assert.equal(data.float32.length, EMBEDDING_DIMENSIONS);
    assert.deepEqual([...data.float32], [...VECTOR]);
  }
  // No raw chunk text and no title ever leaves the process inside a vector payload.
  const wire = JSON.stringify(vectors.calls.map((call) => call.body));
  assert.ok(!wire.includes(TEXT_SENTINEL) && !wire.includes(TITLE_SENTINEL));
});

test('putVectors narrows to float32 before writing and refuses non-representable values', async () => {
  const { artifacts, vectors } = build();
  const snapshot = snapshotOf([document(0)]);
  const imprecise = [...VECTOR];
  imprecise[5] = 0.1;
  await artifacts.putVectors(snapshot, vectorsFor(snapshot, imprecise), SIGNAL);
  const written = (entriesOf(vectors.calls[0])[0]['data'] as { float32: readonly number[] }).float32;
  assert.equal(written[5], Math.fround(0.1));
  assert.notEqual(written[5], 0.1);

  const bad: readonly (readonly [string, readonly number[]])[] = [
    ['too few dimensions', new Array<number>(512).fill(1)],
    ['zero vector', new Array<number>(EMBEDDING_DIMENSIONS).fill(0)],
    ['non-finite component', [...VECTOR].map((value, index) => (index === 2 ? Number.NaN : value))],
    ['overflow past float32', [...VECTOR].map((value, index) => (index === 2 ? 1e39 : value))],
  ];
  for (const [label, vector] of bad) {
    const calls = vectors.calls.length;
    const error = await failureOf(() => artifacts.putVectors(snapshot, vectorsFor(snapshot, vector), SIGNAL));
    assert.deepEqual([error.code, error.retryable], ['INVALID_STATE', false], label);
    assert.equal(vectors.calls.length, calls, label);
  }
});

test('putVectors requires exact map cardinality against the snapshot documents', async () => {
  const { artifacts, vectors } = build();
  const snapshot = snapshotOf([document(0), document(1)]);
  const exact = vectorsFor(snapshot);

  const missing = new Map(exact);
  missing.delete(snapshot.documents[0].vectorKey);
  assert.equal(
    (await failureOf(() => artifacts.putVectors(snapshot, missing, SIGNAL))).code, 'INVALID_STATE');
  const extra = new Map(exact);
  extra.set(sha256('foreign'), VECTOR);
  assert.equal(
    (await failureOf(() => artifacts.putVectors(snapshot, extra, SIGNAL))).code, 'INVALID_STATE');
  assert.equal(vectors.calls.length, 0);

  // Duplicate document vector keys can only be caught while walking the snapshot documents.
  const duplicated = validateSnapshot({
    ...snapshot,
    documents: [
      snapshot.documents[0],
      { ...snapshot.documents[1], vectorKey: snapshot.documents[0].vectorKey },
      document(2),
    ],
  });
  const withForeign = new Map<string, readonly number[]>([
    [snapshot.documents[0].vectorKey, VECTOR],
    [snapshot.documents[1].vectorKey, VECTOR],
    [sha256('foreign'), VECTOR],
  ]);
  assert.equal(
    (await failureOf(() => artifacts.putVectors(duplicated, withForeign, SIGNAL))).code, 'INVALID_STATE');

  // A snapshot that does not validate never reaches the wire.
  const invalid = { ...snapshot, policyIdentity: sha256('stale') };
  assert.equal(
    (await failureOf(() => artifacts.putVectors(invalid as Snapshot, exact, SIGNAL))).code,
    'INDEX_NOT_READY',
  );
  assert.equal(vectors.calls.length, 0);
});

test('getVectors batches 100 keys and follows nextToken with a repeated-token guard', async () => {
  const keys = Array.from({ length: 101 }, (_value, index) => sha256(`key-${index}`));
  const batched = vectorFake((call) => ({
    vectors: keysOf(call).map((key) => ({ key, data: { float32: jsonVector() } })),
  }));
  const artifacts = createArtifacts(
    { region: REGION, snapshotBucket: BUCKET, vectorIndexArn: INDEX_ARN },
    { s3: s3Fake().port, request: batched.request },
  );
  const found = await artifacts.getVectors(keys, SIGNAL);
  assert.equal(found.size, 101);
  assert.deepEqual(batched.calls.map((call) => keysOf(call).length), [100, 1]);
  for (const call of batched.calls) {
    assert.equal(call.path, '/GetVectors');
    assert.deepEqual(Object.keys(call.body).sort(), ['indexArn', 'keys', 'returnData']);
    assert.equal(call.body['returnData'], true);
    assert.equal(call.body['nextToken'], undefined);
  }

  const pageOne = keys.slice(0, 2);
  const paged = vectorFake((call) => {
    const batch = keysOf(call);
    return call.body['nextToken'] === undefined
      ? { vectors: [{ key: batch[0], data: { float32: jsonVector() } }], nextToken: 'page-2' }
      : { vectors: [{ key: batch[1], data: { float32: jsonVector() } }] };
  });
  const pagedArtifacts = createArtifacts(
    { region: REGION, snapshotBucket: BUCKET, vectorIndexArn: INDEX_ARN },
    { s3: s3Fake().port, request: paged.request },
  );
  const complete = await pagedArtifacts.getVectors(pageOne, SIGNAL);
  assert.deepEqual([...complete.keys()], pageOne);
  assert.equal(paged.calls.length, 2);
  assert.equal(paged.calls[1].body['nextToken'], 'page-2');

  const looping = vectorFake(() => ({ vectors: [], nextToken: 'loop' }));
  const looped = createArtifacts(
    { region: REGION, snapshotBucket: BUCKET, vectorIndexArn: INDEX_ARN },
    { s3: s3Fake().port, request: looping.request },
  );
  const error = await failureOf(() => looped.getVectors([sha256('k')], SIGNAL));
  assert.deepEqual([error.code, error.retryable], ['INVALID_PROVIDER_OUTPUT', false]);
  assert.equal(looping.calls.length, 2);

  const none = vectorFake();
  const empty = createArtifacts(
    { region: REGION, snapshotBucket: BUCKET, vectorIndexArn: INDEX_ARN },
    { s3: s3Fake().port, request: none.request },
  );
  assert.equal((await empty.getVectors([], SIGNAL)).size, 0);
  assert.equal(none.calls.length, 0);
});

test('getVectors rejects foreign, duplicate, missing and malformed vector entries', async () => {
  const key = sha256('wanted');
  const cases: readonly (readonly [string, string, unknown])[] = [
    ['foreign key', 'INVALID_PROVIDER_OUTPUT', { vectors: [{ key: sha256('other'), data: { float32: jsonVector() } }] }],
    ['envelope not an object', 'INVALID_PROVIDER_OUTPUT', 'nope'],
    ['vectors missing', 'INVALID_PROVIDER_OUTPUT', {}],
    ['entry not an object', 'INVALID_PROVIDER_OUTPUT', { vectors: ['x'] }],
    ['duplicate key', 'INVALID_PROVIDER_OUTPUT', {
      vectors: [
        { key, data: { float32: jsonVector() } },
        { key, data: { float32: jsonVector() } },
      ],
    }],
    ['data missing', 'INDEX_NOT_READY', { vectors: [{ key }] }],
    ['float32 missing', 'INDEX_NOT_READY', { vectors: [{ key, data: {} }] }],
    ['wrong dimensions', 'INDEX_NOT_READY', { vectors: [{ key, data: { float32: [1, 2, 3] } }] }],
    ['zero vector', 'INDEX_NOT_READY', { vectors: [{ key, data: { float32: new Array<number>(EMBEDDING_DIMENSIONS).fill(0) } }] }],
    ['missing key', 'INDEX_NOT_READY', { vectors: [] }],
  ];
  for (const [label, code, reply] of cases) {
    const vectors = vectorFake(() => reply);
    const artifacts = createArtifacts(
      { region: REGION, snapshotBucket: BUCKET, vectorIndexArn: INDEX_ARN },
      { s3: s3Fake().port, request: vectors.request },
    );
    const error = await failureOf(() => artifacts.getVectors([key], SIGNAL));
    assert.deepEqual([error.code, error.retryable], [code, false], label);
    assert.equal(vectors.calls.length, 1, label);
  }

  const invalid = vectorFake();
  const artifacts = createArtifacts(
    { region: REGION, snapshotBucket: BUCKET, vectorIndexArn: INDEX_ARN },
    { s3: s3Fake().port, request: invalid.request },
  );
  for (const keys of [[key, key], ['not-a-hash'], [42 as unknown as string]]) {
    assert.equal((await failureOf(() => artifacts.getVectors(keys, SIGNAL))).code, 'INVALID_INPUT');
  }
  assert.equal(invalid.calls.length, 0);
});

test('query sends mandatory owner/version filters with topK 20 and enhanced mode', async () => {
  const key = sha256('hit');
  const vectors = vectorFake(() => ({ vectors: [hit(key)] }));
  const artifacts = createArtifacts(
    { region: REGION, snapshotBucket: BUCKET, vectorIndexArn: INDEX_ARN },
    { s3: s3Fake().port, request: vectors.request },
  );
  assert.equal(QUERY_TOP_K, 20);
  const keys = await artifacts.query(VECTOR, OWNER, VERSION, null, SIGNAL);
  assert.deepEqual([...keys], [key]);
  assert.ok(Object.isFrozen(keys));

  const account = vectors.calls[0];
  assert.equal(account.path, '/QueryVectors');
  assert.equal(account.body['indexArn'], INDEX_ARN);
  assert.equal(account.body['topK'], 20);
  assert.equal(account.body['queryMode'], 'ENHANCED');
  assert.equal(account.body['returnDistance'], true);
  assert.equal(account.body['returnMetadata'], true);
  assert.deepEqual(account.body['filter'], { $and: [{ ownerId: { $eq: OWNER } }, { manifestVersion: { $eq: VERSION } }] });
  assert.deepEqual(
    (account.body['queryVector'] as { float32: readonly number[] }).float32, [...VECTOR]);

  await artifacts.query([...VECTOR].map((value, index) => (index === 0 ? 0.1 : value)), OWNER, VERSION, 'n1', SIGNAL);
  const scoped = vectors.calls[1];
  assert.deepEqual(scoped.body['filter'], { $and: [{ ownerId: { $eq: OWNER } }, { manifestVersion: { $eq: VERSION } }, { noteId: { $eq: 'n1' } }] });
  assert.equal(
    (scoped.body['queryVector'] as { float32: readonly number[] }).float32[0], Math.fround(0.1));
});

test('query returns response order and rejects scope, distance, key and mode violations', async () => {
  const keyA = sha256('a');
  const keyB = sha256('b');
  const ordered = vectorFake(() => ({ vectors: [hit(keyB, 0.25), hit(keyA, 1.75)] }));
  const artifacts = createArtifacts(
    { region: REGION, snapshotBucket: BUCKET, vectorIndexArn: INDEX_ARN },
    { s3: s3Fake().port, request: ordered.request },
  );
  assert.deepEqual([...(await artifacts.query(VECTOR, OWNER, VERSION, null, SIGNAL))], [keyB, keyA]);

  const key = sha256('k');
  const cases: readonly (readonly [string, unknown])[] = [
    ['foreign owner metadata', { vectors: [hit(key, 0.5, { ownerId: 'u2' })] }],
    ['other manifest version', { vectors: [hit(key, 0.5, { manifestVersion: 'lease-9' })] }],
    ['extra metadata key', { vectors: [hit(key, 0.5, { text: TEXT_SENTINEL })] }],
    ['missing metadata key', { vectors: [{ key, distance: 0.5, metadata: { ownerId: OWNER, manifestVersion: VERSION, noteId: 'n1' } }] }],
    ['metadata not an object', { vectors: [{ key, distance: 0.5, metadata: 'x' }] }],
    ['distance missing', { vectors: [{ key, metadata: hit(key)['metadata'] }] }],
    ['distance above cosine range', { vectors: [hit(key, 2.5)] }],
    ['distance below cosine range', { vectors: [hit(key, -0.5)] }],
    ['distance not finite', { vectors: [hit(key, Number.NaN)] }],
    ['distance wrong type', { vectors: [hit(key, '0.5' as unknown as number)] }],
    ['duplicate keys', { vectors: [hit(key, 0.4), hit(key, 0.6)] }],
    ['non-hash key', { vectors: [hit('plain-key')] }],
    ['more than topK', { vectors: Array.from({ length: QUERY_TOP_K + 1 }, (_value, index) => hit(sha256(`x${index}`))) }],
    ['vectors missing', {}],
    ['queryMode downgraded', { queryMode: 'NON_ENHANCED', vectors: [hit(key)] }],
  ];
  for (const [label, reply] of cases) {
    const vectors = vectorFake(() => reply);
    const scoped = createArtifacts(
      { region: REGION, snapshotBucket: BUCKET, vectorIndexArn: INDEX_ARN },
      { s3: s3Fake().port, request: vectors.request },
    );
    const error = await failureOf(() => scoped.query(VECTOR, OWNER, VERSION, null, SIGNAL));
    assert.deepEqual([error.code, error.retryable], ['INVALID_PROVIDER_OUTPUT', false], label);
    assert.equal(vectors.calls.length, 1, label);
  }

  // Note-scoped queries demand that exact note in every returned metadata record.
  const noteScope = vectorFake(() => ({ vectors: [hit(key, 0.5, { noteId: 'n2' })] }));
  const scoped = createArtifacts(
    { region: REGION, snapshotBucket: BUCKET, vectorIndexArn: INDEX_ARN },
    { s3: s3Fake().port, request: noteScope.request },
  );
  assert.equal(
    (await failureOf(() => scoped.query(VECTOR, OWNER, VERSION, 'n1', SIGNAL))).code,
    'INVALID_PROVIDER_OUTPUT',
  );
  // Distance boundaries 0 and 2 are valid cosine distances.
  const boundaries = vectorFake(() => ({ vectors: [hit(keyA, 0), hit(keyB, 2)] }));
  const boundaryArtifacts = createArtifacts(
    { region: REGION, snapshotBucket: BUCKET, vectorIndexArn: INDEX_ARN },
    { s3: s3Fake().port, request: boundaries.request },
  );
  assert.deepEqual(
    [...(await boundaryArtifacts.query(VECTOR, OWNER, VERSION, null, SIGNAL))], [keyA, keyB]);
});

test('queryScored shares the legacy query operation and returns validated key/distance hits', async () => {
  const keyA = sha256('a');
  const keyB = sha256('b');
  const vectors = vectorFake(() => ({ vectors: [hit(keyB, 0.25), hit(keyA, 1.75)] }));
  const artifacts = createArtifacts(
    { region: REGION, snapshotBucket: BUCKET, vectorIndexArn: INDEX_ARN },
    { s3: s3Fake().port, request: vectors.request },
  );
  const queryScored = artifacts.queryScored;
  assert.ok(queryScored, 'production artifacts always expose the scored query');
  const hits = await queryScored(VECTOR, OWNER, VERSION, null, SIGNAL);
  assert.deepEqual(
    hits.map((entry) => ({ key: entry.key, distance: entry.distance })),
    [{ key: keyB, distance: 0.25 }, { key: keyA, distance: 1.75 }],
    'response order and validated distances are preserved',
  );
  assert.equal(vectors.calls.length, 1, 'scored query is one QueryVectors request');
  assert.ok(Object.isFrozen(hits));
  for (const entry of hits) assert.ok(Object.isFrozen(entry));

  // The legacy projection is exactly the same keys from the same request shape.
  assert.deepEqual(await artifacts.query(VECTOR, OWNER, VERSION, null, SIGNAL), [keyB, keyA]);
  assert.equal(vectors.calls.length, 2);
  assert.deepEqual(vectors.calls[0].body, vectors.calls[1].body);
});

test('queryScored paginates with the same filters and rejects malformed scored records', async () => {
  const metadata = { ownerId: OWNER, manifestVersion: VERSION, noteId: 'n1', revision: 1, chunkId: 'body-0' };
  const first = sha256('first');
  const second = sha256('second');
  const requests: Record<string, unknown>[] = [];
  const request: AwsJson = async (_service, _path, body) => {
    requests.push(body as Record<string, unknown>);
    return requests.length === 1
      ? { vectors: [{ key: first, distance: 0.1, metadata }], nextToken: 'page-2' }
      : { vectors: [{ key: second, distance: 0.2, metadata }], nextToken: '' };
  };
  const paged = createArtifacts(
    { region: REGION, snapshotBucket: BUCKET, vectorIndexArn: INDEX_ARN },
    { request },
  );
  assert.ok(paged.queryScored);
  assert.deepEqual(
    (await paged.queryScored(VECTOR, OWNER, VERSION, null, SIGNAL)).map((entry) => ({ ...entry })),
    [{ key: first, distance: 0.1 }, { key: second, distance: 0.2 }],
  );
  assert.equal(requests[1]?.['nextToken'], 'page-2');
  assert.deepEqual(requests[0]?.['filter'], requests[1]?.['filter']);

  const key = sha256('k');
  const cases: readonly (readonly [string, unknown])[] = [
    ['missing distance', { vectors: [{ key, metadata: hit(key)['metadata'] }] }],
    ['non-finite distance', { vectors: [hit(key, Number.NaN)] }],
    ['out-of-range distance', { vectors: [hit(key, 2.5)] }],
    ['foreign owner metadata', { vectors: [hit(key, 0.5, { ownerId: 'u2' })] }],
    ['extra metadata key', { vectors: [hit(key, 0.5, { text: TEXT_SENTINEL })] }],
    ['duplicate keys', { vectors: [hit(key, 0.4), hit(key, 0.6)] }],
    ['vectors missing', {}],
  ];
  for (const [label, reply] of cases) {
    const vectors = vectorFake(() => reply);
    const strict = createArtifacts(
      { region: REGION, snapshotBucket: BUCKET, vectorIndexArn: INDEX_ARN },
      { s3: s3Fake().port, request: vectors.request },
    );
    assert.ok(strict.queryScored);
    const error = await failureOf(() => strict.queryScored!(VECTOR, OWNER, VERSION, null, SIGNAL));
    assert.deepEqual([error.code, error.retryable], ['INVALID_PROVIDER_OUTPUT', false], label);
    assert.equal(vectors.calls.length, 1, label);
  }
});

test('query validates its own arguments and never downgrades a refused enhanced mode', async () => {
  const vectors = vectorFake();
  const artifacts = createArtifacts(
    { region: REGION, snapshotBucket: BUCKET, vectorIndexArn: INDEX_ARN },
    { s3: s3Fake().port, request: vectors.request },
  );
  const badVectors: readonly unknown[] = [
    [1, 2, 3], new Array<number>(EMBEDDING_DIMENSIONS).fill(0), 'vector',
    [...VECTOR].map((value, index) => (index === 0 ? Number.NaN : value)),
  ];
  for (const vector of badVectors) {
    const error = await failureOf(() =>
      artifacts.query(vector as readonly number[], OWNER, VERSION, null, SIGNAL));
    assert.deepEqual([error.code, error.retryable], ['INVALID_INPUT', false]);
  }
  for (const args of [
    ['', VERSION, null], [OWNER, 'bad version', null], [OWNER, VERSION, ''],
  ] as const) {
    assert.equal(
      (await failureOf(() => artifacts.query(VECTOR, args[0], args[1], args[2], SIGNAL))).code,
      'INVALID_INPUT',
    );
  }
  assert.equal(vectors.calls.length, 0);

  // The service refusing ENHANCED fails the call; no plain-mode retry is ever attempted.
  const refusing = vectorFake(() => {
    throw new IndexFailure('INVALID_INPUT', false);
  });
  const strict = createArtifacts(
    { region: REGION, snapshotBucket: BUCKET, vectorIndexArn: INDEX_ARN },
    { s3: s3Fake().port, request: refusing.request },
  );
  const refused = await failureOf(() => strict.query(VECTOR, OWNER, VERSION, null, SIGNAL));
  assert.deepEqual([refused.code, refused.retryable], ['INVALID_INPUT', false]);
  assert.equal(refusing.calls.length, 1);
  assert.equal(refusing.calls[0].body['queryMode'], 'ENHANCED');
});

test('cleanup deletes exactly the previous snapshot keys, then the snapshot object', async () => {
  const { artifacts, sent, objects, vectors } = build();
  const snapshot = snapshotOf(
    Array.from({ length: 501 }, (_value, index) => document(index)),
  );
  await artifacts.put(snapshot, SIGNAL);
  sent.length = 0;

  await artifacts.cleanup(manifestOf(snapshot), SIGNAL);

  assert.deepEqual(vectors.calls.map((call) => call.path), ['/DeleteVectors', '/DeleteVectors']);
  assert.deepEqual(vectors.calls.map((call) => keysOf(call).length), [500, 1]);
  const deleted = vectors.calls.flatMap((call) => [...keysOf(call)]);
  assert.deepEqual(deleted, snapshot.documents.map((doc) => doc.vectorKey));
  for (const call of vectors.calls) {
    assert.deepEqual(Object.keys(call.body).sort(), ['indexArn', 'keys']);
    assert.equal(call.body['indexArn'], INDEX_ARN);
  }
  // One exact GetObject for the verified snapshot, one exact DeleteObject; never a list or prefix.
  assert.deepEqual(sent.map((entry) => entry.command.constructor.name), ['GetObjectCommand', 'DeleteObjectCommand']);
  const remove = sent[1].command;
  assert.ok(remove instanceof DeleteObjectCommand);
  assert.equal(remove.input.Key, SNAPSHOT_KEY);
  assert.equal(objects.has(SNAPSHOT_KEY), false);
  assert.equal(objects.size, 0);
});

test('interrupted cleanup stays retryable, fails closed and never deletes a foreign key', async () => {
  const s3 = s3Fake();
  let failOnce = true;
  const vectors = vectorFake((_call, index) => {
    if (failOnce && index === 1) {
      failOnce = false;
      throw new IndexFailure('PROVIDER_UNAVAILABLE', true);
    }
    return {};
  });
  const artifacts = createArtifacts(
    { region: REGION, snapshotBucket: BUCKET, vectorIndexArn: INDEX_ARN },
    { s3: s3.port, request: vectors.request },
  );
  const snapshot = snapshotOf(Array.from({ length: 501 }, (_value, index) => document(index)));
  await artifacts.put(snapshot, SIGNAL);

  const interrupted = await failureOf(() => artifacts.cleanup(manifestOf(snapshot), SIGNAL));
  assert.deepEqual([interrupted.code, interrupted.retryable], ['PROVIDER_UNAVAILABLE', true]);
  assert.equal(s3.objects.has(SNAPSHOT_KEY), true, 'the snapshot stays readable for the retry');
  assert.equal(
    s3.sent.filter((entry) => entry.command instanceof DeleteObjectCommand).length, 0,
    'the snapshot object is deleted only after every vector batch succeeds',
  );

  await artifacts.cleanup(manifestOf(snapshot), SIGNAL);
  assert.equal(s3.objects.has(SNAPSHOT_KEY), false);
  const allDeleted = vectors.calls
    .filter((call) => call.path === '/DeleteVectors')
    .flatMap((call) => [...keysOf(call)]);
  const allowed = new Set(snapshot.documents.map((doc) => doc.vectorKey));
  assert.ok(allDeleted.every((key) => allowed.has(key)));

  // A missing snapshot means no deletion at all.
  const absent = vectorFake();
  const before = vectors.calls.length;
  const empty = createArtifacts(
    { region: REGION, snapshotBucket: BUCKET, vectorIndexArn: INDEX_ARN },
    { s3: s3.port, request: absent.request },
  );
  await empty.cleanup(manifestOf(snapshot), SIGNAL);
  assert.equal(absent.calls.length, 0);
  assert.equal(vectors.calls.length, before);

  const tampered = await failureOf(() =>
    empty.cleanup(manifestOf(snapshot, { snapshotKey: 'rag/snapshots/other/x.json' }), SIGNAL));
  assert.deepEqual([tampered.code, tampered.retryable], ['INDEX_NOT_READY', false]);
});

test('query pagination keeps filters and rejects a repeated cursor', async () => {
  const metadata={ownerId:OWNER,manifestVersion:VERSION,noteId:'n1',revision:1,chunkId:'body-0'};
  const first=sha256('first'),second=sha256('second');
  const requests:Record<string,unknown>[]=[];
  const request:AwsJson=async(_service,_path,body)=>{
    requests.push(body as Record<string,unknown>);
    return requests.length===1?{vectors:[{key:first,distance:0.1,metadata}],nextToken:'page-2'}
      :{vectors:[{key:second,distance:0.2,metadata}],nextToken:''};
  };
  const a=createArtifacts({region:REGION,snapshotBucket:BUCKET,vectorIndexArn:INDEX_ARN},{request});
  assert.deepEqual(await a.query(VECTOR,OWNER,VERSION,null,SIGNAL),[first,second]);
  assert.equal(requests[1].nextToken,'page-2');
  assert.deepEqual(requests[0].filter,requests[1].filter);
  const repeated=createArtifacts({region:REGION,snapshotBucket:BUCKET,vectorIndexArn:INDEX_ARN},
    {request:async()=>({vectors:[],nextToken:'same'})});
  await assert.rejects(repeated.query(VECTOR,OWNER,VERSION,null,SIGNAL));
});
