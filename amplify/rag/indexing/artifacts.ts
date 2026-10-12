/**
 * Phase 3 artifact ports: the immutable snapshot object and the S3 Vectors namespace it names.
 *
 * Snapshot objects live at `rag/snapshots/<sha256(ownerId)>/<version>.json` — the key is always
 * derived from the manifest owner and version, never taken on faith, so a manifest cannot point
 * at another owner or an arbitrary key. Text is stored via the S3 SDK with bucket-default SSE
 * (no explicit encryption field) and `maxAttempts: 1`; every send carries the caller signal.
 * Reading decodes under the manifest's own policy identity and re-checks owner, version, policy
 * identity and the recorded checksum before the snapshot is trusted — so a previous, drifted
 * generation stays readable for cleanup while never being mistaken for a current one.
 *
 * Vectors are written to the configured S3 Vectors index over the signed JSON port. Only
 * whitelisted operations reach the wire (`PutVectors`, `GetVectors`, `QueryVectors`,
 * `DeleteVectors`), writes/reads are batched (500 / 100), components are narrowed with
 * `Math.fround` before writing, and metadata carries exactly
 * `ownerId, manifestVersion, noteId, revision, chunkId` — never chunk text or a title.
 *
 * Queries always filter `ownerId` AND `manifestVersion` (plus `noteId` when scoped) and always
 * request `queryMode: ENHANCED` with distance and metadata. A service that refuses enhanced mode
 * fails the call: there is no fallback request and no silent downgrade. Cleanup reads the exact
 * previous snapshot, deletes exactly its vector keys, and deletes the snapshot object last, so
 * an interrupted cleanup can be retried and always fails closed.
 */
import {
  DeleteObjectCommand, GetObjectCommand, PutObjectCommand, S3Client,
} from '@aws-sdk/client-s3';
import { isValidIdentifier } from '../contract';
import { isSafeInteger } from '../chunking';
import { EMBEDDING_DIMENSIONS } from '../retrieval';
import { policy, type Chunk } from '../types';
import { IndexFailure, type Artifacts, type Manifest, type Snapshot } from './types';
import {
  SHA256_HEX, checksum, decodeSnapshot, encodeSnapshot, sha256Hex, validateManifest,
  validateSnapshot,
} from './snapshot';
import {
  createAwsJson, failureForStatus, isAwsRegion, type AwsJson,
} from './aws_http';

export const SNAPSHOT_PREFIX = 'rag/snapshots/';
/** S3 Vectors accepts at most 500 keys per PutVectors/DeleteVectors call. */
export const VECTOR_WRITE_BATCH = 500;
/** GetVectors accepts at most 100 keys per call. */
export const VECTOR_READ_BATCH = 100;
/** policy.retrieval.vectorTopK: the query asks for exactly this many neighbours. */
export const QUERY_TOP_K: number = policy.retrieval.vectorTopK;
const MAX_GET_PAGES = 1_000;
const SNAPSHOT_CONTENT_TYPE = 'application/json';

/** Version tokens are path/key segments: no slash, no leading dot, bounded length. */
const SAFE_VERSION = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;
const BUCKET = /^(?!.*\.\.)[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$/;
const INDEX_NAME = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;
const INDEX_ARN = /^arn:(aws[a-z-]*):s3vectors:([a-z0-9-]+):(\d{12}):bucket\/([^/]+)\/index\/([^/]+)$/;

export type ArtifactsConfig = Readonly<{
  region: string;
  snapshotBucket: string;
  vectorIndexArn: string;
}>;

export type S3SendOptions = Readonly<{ abortSignal?: AbortSignal }>;
export type S3Command = PutObjectCommand | GetObjectCommand | DeleteObjectCommand;

/** Injected S3 client port (`{ send }`); production passes an `S3Client` with maxAttempts 1. */
export interface S3Port {
  send(command: S3Command, options?: S3SendOptions): Promise<unknown>;
}

export type ArtifactsOptions = Readonly<{ s3?: S3Port; request?: AwsJson }>;

type VectorMetadata = Readonly<{
  ownerId: string; manifestVersion: string; noteId: string; revision: number; chunkId: string;
}>;
type VectorEntry = Readonly<{
  key: string;
  data: Readonly<{ float32: readonly number[] }>;
  metadata: VectorMetadata;
}>;

const METADATA_KEYS = [
  'ownerId', 'manifestVersion', 'noteId', 'revision', 'chunkId',
] as const;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const hasExactKeys = (value: Record<string, unknown>, required: readonly string[]): boolean =>
  Object.keys(value).length === required.length &&
  required.every((key) => Object.prototype.hasOwnProperty.call(value, key));

const invalidInput: () => never = () => {
  throw new IndexFailure('INVALID_INPUT', false);
};
const invalidOutput: () => never = () => {
  throw new IndexFailure('INVALID_PROVIDER_OUTPUT', false);
};
const notReady: () => never = () => {
  throw new IndexFailure('INDEX_NOT_READY', false);
};

const requireSignal = (signal: unknown): AbortSignal => {
  if (!(signal instanceof AbortSignal)) invalidInput();
  return signal;
};

const isSafeVersion = (value: unknown): value is string =>
  typeof value === 'string' && SAFE_VERSION.test(value);

/** The only snapshot key shape this code reads, writes or deletes. */
const snapshotKeyFor = (ownerId: string, version: string): string =>
  `${SNAPSHOT_PREFIX}${sha256Hex(ownerId)}/${version}.json`;

const requireManifest = (value: unknown): Manifest => {
  if (!isRecord(value) || typeof value['ownerId'] !== 'string') notReady();
  // validateManifest throws INDEX_NOT_READY for any shape, owner or digest violation.
  return validateManifest(value, value['ownerId']);
};

const batchesOf = <T>(items: readonly T[], size: number): readonly (readonly T[])[] => {
  const out: T[][] = [];
  for (let offset = 0; offset < items.length; offset += size) out.push(items.slice(offset, offset + size));
  return out;
};

/** S3 SDK failures collapse to the same taxonomy as the JSON transport; message text is dropped. */
const mapS3Failure = (error: unknown, signal: AbortSignal): IndexFailure => {
  if (signal.aborted) return new IndexFailure('TIMEOUT', true);
  const name = isRecord(error) && typeof error['name'] === 'string' ? error['name'] : '';
  if (name === 'NoSuchKey' || name === 'NotFound' || name === 'NoSuchVersion') {
    return new IndexFailure('SNAPSHOT_NOT_FOUND', false);
  }
  const metadata = isRecord(error) ? error['$metadata'] : undefined;
  const status = isRecord(metadata) ? metadata['httpStatusCode'] : undefined;
  if (typeof status === 'number') return failureForStatus(status, false);
  return new IndexFailure('PROVIDER_UNAVAILABLE', false);
};

const sendS3 = async (port: S3Port, command: S3Command, signal: AbortSignal): Promise<unknown> => {
  try {
    return await port.send(command, { abortSignal: signal });
  } catch (error) {
    throw mapS3Failure(error, signal);
  }
};

/** GetObject body: the SDK stream's `transformToString`, or any async byte iterable. */
const readBody = async (Body: unknown, signal: AbortSignal): Promise<string> => {
  if (!isRecord(Body)) notReady();
  const transform = Body['transformToString'];
  if (typeof transform === 'function') {
    try {
      const text = await (transform as () => Promise<unknown>).call(Body);
      if (typeof text === 'string') return text;
    } catch {
      if (signal.aborted) throw new IndexFailure('TIMEOUT', true);
      notReady();
    }
    notReady();
  }
  if (typeof (Body as { [Symbol.asyncIterator]?: unknown })[Symbol.asyncIterator] === 'function') {
    const chunks: Uint8Array[] = [];
    for await (const chunk of Body as unknown as AsyncIterable<Uint8Array>) chunks.push(chunk);
    return Buffer.concat(chunks).toString('utf8');
  }
  notReady();
};

/**
 * Float32 narrowing for the index. The caller's vector must already be a finite, non-zero
 * 1024-dimensional embedding; narrowing may round but must never produce Infinity.
 */
const float32 = (vector: unknown, code: string): readonly number[] => {
  if (!Array.isArray(vector) || vector.length !== EMBEDDING_DIMENSIONS) {
    throw new IndexFailure(code, false);
  }
  const out: number[] = [];
  for (const value of vector) {
    if (typeof value !== 'number' || !Number.isFinite(value)) throw new IndexFailure(code, false);
    const narrowed = Math.fround(value);
    if (!Number.isFinite(narrowed)) throw new IndexFailure(code, false);
    out.push(narrowed);
  }
  const norm = Math.hypot(...out);
  if (!Number.isFinite(norm) || norm <= 0) throw new IndexFailure(code, false);
  return Object.freeze(out);
};

/** Vector data present in a GetVectors response: missing data means the index is not usable. */
const readVectorData = (entry: Record<string, unknown>): readonly number[] => {
  const data = entry['data'];
  if (data === undefined) notReady();
  if (!isRecord(data)) invalidOutput();
  const list = data['float32'];
  if (list === undefined) notReady();
  if (!Array.isArray(list)) invalidOutput();
  return float32(list, 'INDEX_NOT_READY');
};

const metadataFor = (version: string, chunk: Chunk): VectorMetadata => Object.freeze({
  ownerId: chunk.ownerId,
  manifestVersion: version,
  noteId: chunk.noteId,
  revision: chunk.revision,
  chunkId: chunk.chunkId,
});

const requireConfig = (config: unknown): ArtifactsConfig => {
  if (!isRecord(config)) throw new IndexFailure('INVALID_STATE', false);
  const region = config['region'];
  if (!isAwsRegion(region)) throw new IndexFailure('INVALID_STATE', false);
  const snapshotBucket = config['snapshotBucket'];
  if (typeof snapshotBucket !== 'string' || !BUCKET.test(snapshotBucket)) {
    throw new IndexFailure('INVALID_STATE', false);
  }
  const vectorIndexArn = config['vectorIndexArn'];
  if (typeof vectorIndexArn !== 'string') throw new IndexFailure('INVALID_STATE', false);
  const match = INDEX_ARN.exec(vectorIndexArn);
  // The index must be a well-formed name in the configured region: the signing region and the
  // ARN can never disagree, and no whitespace or foreign resource reaches the request body.
  if (
    match === null || match[2] !== region || !BUCKET.test(match[4]) || !INDEX_NAME.test(match[5])
  ) {
    throw new IndexFailure('INVALID_STATE', false);
  }
  return Object.freeze({ region, snapshotBucket, vectorIndexArn });
};

/**
 * `options.s3` is the send port (an `S3Client` configured with `maxAttempts: 1`); when absent a
 * client is built here with that bound. `options.request` is the signed JSON port.
 */
export function createArtifacts(config: ArtifactsConfig, options?: ArtifactsOptions): Artifacts {
  const exact = requireConfig(config);
  if (options !== undefined && !isRecord(options)) throw new IndexFailure('INVALID_STATE', false);
  const request = options?.request ?? createAwsJson(exact.region);
  if (typeof request !== 'function') throw new IndexFailure('INVALID_STATE', false);
  const s3 = options?.s3 ?? new S3Client({ region: exact.region, maxAttempts: 1 });
  const indexArn = exact.vectorIndexArn;
  const bucket = exact.snapshotBucket;

  /** Derive, read and fully verify one snapshot; the callers below share exactly this check. */
  const readSnapshot = async (
    manifest: Manifest,
    signal: AbortSignal,
  ): Promise<Readonly<{ snapshot: Snapshot; key: string }>> => {
    const version = isSafeVersion(manifest.version) ? manifest.version : notReady();
    const key = snapshotKeyFor(manifest.ownerId, version);
    // A manifest naming a different key is tampered or stale: fail before touching S3.
    if (manifest.snapshotKey !== key) notReady();
    const output = await sendS3(s3, new GetObjectCommand({ Bucket: bucket, Key: key }), signal);
    if (!isRecord(output)) notReady();
    // Decode under the manifest's own policy identity: a previous, drifted generation is still
    // readable for reuse checks and cleanup; only an identity mismatch with the object fails.
    const snapshot = decodeSnapshot(await readBody(output['Body'], signal), manifest.policyIdentity);
    if (
      snapshot.ownerId !== manifest.ownerId ||
      snapshot.version !== manifest.version ||
      snapshot.policyIdentity !== manifest.policyIdentity
    ) {
      notReady();
    }
    if (checksum(snapshot) !== manifest.checksum) notReady();
    return Object.freeze({ snapshot, key });
  };

  return Object.freeze({
    read: async (manifest, signal) => {
      const bound = requireManifest(manifest);
      try { return (await readSnapshot(bound, requireSignal(signal))).snapshot; }
      catch (error) {
        if (error instanceof IndexFailure && error.code === 'SNAPSHOT_NOT_FOUND') notReady();
        throw error;
      }
    },

    put: async (snapshot, signal) => {
      const validated = validateSnapshot(snapshot);
      const version = isSafeVersion(validated.version) ? validated.version : notReady();
      const key = snapshotKeyFor(validated.ownerId, version);
      const text = encodeSnapshot(validated);
      const digest = checksum(validated);
      // Bucket-default SSE: no ServerSideEncryption field is set here.
      await sendS3(s3, new PutObjectCommand({
        Bucket: bucket, Key: key, Body: text, ContentType: SNAPSHOT_CONTENT_TYPE,
      }), requireSignal(signal));
      return Object.freeze({ key, checksum: digest });
    },

    putVectors: async (snapshot, vectors, signal) => {
      const validated = validateSnapshot(snapshot);
      const version = isSafeVersion(validated.version) ? validated.version : notReady();
      const deadline = requireSignal(signal);
      if (
        !isRecord(vectors) || typeof (vectors as ReadonlyMap<string, unknown>).get !== 'function' ||
        !Number.isSafeInteger((vectors as ReadonlyMap<string, unknown>).size)
      ) {
        throw new IndexFailure('INVALID_STATE', false);
      }
      if (validated.documents.length !== vectors.size) throw new IndexFailure('INVALID_STATE', false);
      const entries: VectorEntry[] = [];
      const written = new Set<string>();
      for (const document of validated.documents) {
        if (written.has(document.vectorKey)) throw new IndexFailure('INVALID_STATE', false);
        written.add(document.vectorKey);
        const vector = vectors.get(document.vectorKey);
        if (vector === undefined) throw new IndexFailure('INVALID_STATE', false);
        entries.push(Object.freeze({
          key: document.vectorKey,
          data: Object.freeze({ float32: float32(vector, 'INVALID_STATE') }),
          metadata: metadataFor(version, document.chunk),
        }));
      }
      for (const batch of batchesOf(entries, VECTOR_WRITE_BATCH)) {
        await request('s3vectors', '/PutVectors', { indexArn, vectors: batch }, deadline);
      }
    },

    getVectors: async (keys, signal) => {
      if (!Array.isArray(keys)) invalidInput();
      const deadline = requireSignal(signal);
      const requested: string[] = [];
      const known = new Set<string>();
      for (const key of keys) {
        if (typeof key !== 'string' || !SHA256_HEX.test(key) || known.has(key)) invalidInput();
        known.add(key);
        requested.push(key);
      }
      const found = new Map<string, readonly number[]>();
      for (const batch of batchesOf(requested, VECTOR_READ_BATCH)) {
        const allowed = new Set(batch);
        const tokens = new Set<string>();
        let nextToken: string | undefined;
        for (let page = 0; ; page += 1) {
          if (page >= MAX_GET_PAGES) invalidOutput();
          const body: Record<string, unknown> = { indexArn, keys: batch, returnData: true };
          if (nextToken !== undefined) body['nextToken'] = nextToken;
          const payload = await request('s3vectors', '/GetVectors', body, deadline);
          if (!isRecord(payload) || !Array.isArray(payload['vectors'])) invalidOutput();
          for (const entry of payload['vectors']) {
            if (!isRecord(entry)) invalidOutput();
            const key = entry['key'];
            // Foreign, repeated or duplicated keys make the whole page untrustworthy.
            if (typeof key !== 'string' || !allowed.has(key) || found.has(key)) invalidOutput();
            found.set(key, readVectorData(entry));
          }
          const token = payload['nextToken'];
          if (token === undefined || token === null) break;
          if (typeof token !== 'string' || token.length === 0 || tokens.has(token)) invalidOutput();
          tokens.add(token);
          nextToken = token;
        }
        for (const key of batch) if (!found.has(key)) notReady();
      }
      return found;
    },

    query: async (vector, ownerId, version, noteId, signal) => {
      if (!isValidIdentifier(ownerId) || !isSafeVersion(version)) invalidInput();
      if (noteId !== null && !isValidIdentifier(noteId)) invalidInput();
      const deadline = requireSignal(signal);
      const query = float32(vector, 'INVALID_INPUT');
      const constraints: Record<string, unknown>[] = [{ ownerId: { $eq: ownerId } }, { manifestVersion: { $eq: version } }];
      if (noteId !== null) constraints.push({ noteId: { $eq: noteId } });
      const filter = { $and: constraints };
      const keys: string[] = [];
      const seen = new Set<string>();
      const tokens = new Set<string>();
      let nextToken: string | undefined;
      for (let page = 0; page < QUERY_TOP_K; page++) {
      const payload = await request('s3vectors', '/QueryVectors', {
        indexArn,
        ...(nextToken ? { nextToken } : {}),
        queryVector: { float32: query },
        topK: QUERY_TOP_K,
        filter,
        // Enhanced mode is required, never negotiated down: a refusal fails the call.
        queryMode: 'ENHANCED',
        returnDistance: true,
        returnMetadata: true,
      }, deadline);
      if (!isRecord(payload) || !Array.isArray(payload['vectors'])) invalidOutput();
      if (payload['queryMode'] !== undefined && payload['queryMode'] !== 'ENHANCED') invalidOutput();
      const entries = payload['vectors'];
      if (entries.length + keys.length > QUERY_TOP_K) invalidOutput();
      if (payload['distanceMetric'] !== undefined && payload['distanceMetric'] !== 'cosine') invalidOutput();
      for (const entry of entries) {
        if (!isRecord(entry)) invalidOutput();
        const key = entry['key'];
        if (typeof key !== 'string' || !SHA256_HEX.test(key) || seen.has(key)) invalidOutput();
        const distance = entry['distance'];
        if (typeof distance !== 'number' || !Number.isFinite(distance) || distance < 0 || distance > 2) {
          invalidOutput();
        }
        const metadata = entry['metadata'];
        if (!isRecord(metadata) || !hasExactKeys(metadata, METADATA_KEYS)) invalidOutput();
        if (metadata['ownerId'] !== ownerId || metadata['manifestVersion'] !== version) invalidOutput();
        if (noteId !== null && metadata['noteId'] !== noteId) invalidOutput();
        if (
          !isValidIdentifier(metadata['noteId']) ||
          !isSafeInteger(metadata['revision']) || metadata['revision'] < 1 ||
          !isValidIdentifier(metadata['chunkId'])
        ) {
          invalidOutput();
        }
        seen.add(key);
        keys.push(key);
      }
      const token = payload['nextToken'];
      if (token === undefined || token === null || token === '' || keys.length === QUERY_TOP_K) return Object.freeze(keys);
      if (typeof token !== 'string' || tokens.has(token)) invalidOutput();
      tokens.add(token); nextToken = token;
      }
      invalidOutput();
    },

    cleanup: async (manifest, signal) => {
      const bound = requireManifest(manifest);
      const deadline = requireSignal(signal);
      let stored: Awaited<ReturnType<typeof readSnapshot>>;
      try { stored = await readSnapshot(bound, deadline); }
      catch (error) {
        // DeleteObject is last; replay after its lost ACK needs no further deletion.
        if (error instanceof IndexFailure && error.code === 'SNAPSHOT_NOT_FOUND') return;
        throw error;
      }
      const { snapshot, key } = stored;
      const keys = snapshot.documents.map((document) => document.vectorKey);
      // Vectors first, snapshot object last: an interruption leaves the map readable for a retry.
      for (const batch of batchesOf(keys, VECTOR_WRITE_BATCH)) {
        await request('s3vectors', '/DeleteVectors', { indexArn, keys: batch }, deadline);
      }
      // Only these exact keys: no list, no prefix delete, no current/other-owner namespace.
      await sendS3(s3, new DeleteObjectCommand({ Bucket: bucket, Key: key }), deadline);
    },
  });
}
