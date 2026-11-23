/**
 * Indexing artifact codec: the exact policy identity, a fail-closed snapshot schema and the
 * content checksum the manifest records.
 *
 * A snapshot carries chunk identity, an immutable vector key and the embedding-input digest —
 * never vector floats, provider payloads or canonical text beyond the chunk itself. Every
 * rejected value throws `INDEX_NOT_READY` with a code only: no raw text in messages or logs.
 *
 * The policy identity is a SHA-256 over the complete indexing policy (model identity, artifact
 * hash, quantization, runtime build, tokenizer files, dimensions, document/query input formats,
 * pooling/normalization, chunk parameters, UTF-16 exclusive spans and the exact embedding text),
 * so any drift forces a rebuild instead of a silent score reuse across profiles. A Cohere-era
 * manifest re-derives to a different identity and is therefore never treated as current.
 */
import { ANALYZER_VERSION, BM25_K1, BM25_B } from '../keyword';
import tokenizerManifest from '../../../docs/rag/embeddinggemma_tokenizer_manifest.json';
import profile from '../../../docs/rag/embeddinggemma_profile_v1.json';
import { createHash } from 'node:crypto';
import { policy, sourceKey } from '../types';
import type { Chunk } from '../types';
import type { Document, Manifest, Snapshot } from './types';
import { IndexFailure } from './types';
import { assertChunk, isSafeInteger, isWellFormed } from '../chunking';
import { isValidIdentifier } from '../contract';

export const SNAPSHOT_SCHEMA_VERSION = 1;
export const SHA256_HEX = /^[0-9a-f]{64}$/;
/** Domain tag kept inside the digest so the input never depends on bare concatenation. */
export const INPUT_DIGEST_DOMAIN = 'rag-embedding-input.v1';

/** The active profile plus every field that decides whether a vector may be reused. */
export const POLICY_IDENTITY_FIELDS = Object.freeze({
  profile,
  tokenizer: tokenizerManifest,
  lexical: Object.freeze({ analyzer: ANALYZER_VERSION, k1: BM25_K1, b: BM25_B }),
  model: policy.embedding.model,
  dimensions: policy.embedding.dimensions,
  documentInputType: policy.embedding.documentInputType,
  queryInputType: policy.embedding.queryInputType,
  truncate: policy.embedding.truncate,
  pooling: profile.model.pooling,
  normalization: profile.model.normalization,
  quantization: profile.model.quantization,
  chunking: Object.freeze({ ...policy.chunking }),
  offsetUnit: policy.technicalDefaults.offsetUnit,
  spanEnd: policy.technicalDefaults.spanEnd,
  embeddingText: policy.technicalDefaults.embeddingText,
  queryEmbeddingText: policy.technicalDefaults.queryEmbeddingText,
});

export const sha256Hex = (text: string): string =>
  createHash('sha256').update(text, 'utf8').digest('hex');

const POLICY_IDENTITY = sha256Hex(JSON.stringify(POLICY_IDENTITY_FIELDS));

/** The full indexing policy hash; equal only when every embedding/chunking/span input matches. */
export const policyIdentity = (): string => POLICY_IDENTITY;

/** Embedding-input digest: full policy + exact title + exact text, no revision or note id. */
export function embeddingInputDigest(title: string, text: string): string {
  if (
    typeof title !== 'string' ||
    typeof text !== 'string' ||
    !isWellFormed(title) ||
    !isWellFormed(text)
  ) {
    throw new IndexFailure('INVALID_INPUT', false);
  }
  return sha256Hex(JSON.stringify([INPUT_DIGEST_DOMAIN, POLICY_IDENTITY, title, text]));
}

const SNAPSHOT_KEYS = [
  'schemaVersion', 'ownerId', 'version', 'consentGeneration', 'accountEpoch', 'policyIdentity',
  'documents',
] as const;
const DOCUMENT_KEYS = ['chunk', 'vectorKey', 'embeddingDigest'] as const;
const CHUNK_KEYS = [
  'ownerId', 'noteId', 'revision', 'sectionId', 'chunkId', 'ordinal', 'title',
  'startOffset', 'endOffset', 'text',
] as const;
const MANIFEST_KEYS = [
  'ownerId', 'generation', 'version', 'fingerprint', 'consentGeneration', 'accountEpoch',
  'status', 'snapshotKey', 'checksum', 'policyIdentity',
] as const;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const hasExactKeys = (value: Record<string, unknown>, required: readonly string[]): boolean =>
  Object.keys(value).length === required.length &&
  required.every((key) => Object.prototype.hasOwnProperty.call(value, key));

const broken: () => never = () => {
  throw new IndexFailure('INDEX_NOT_READY', false);
};

/** Canonical field order keeps `encodeSnapshot` byte-stable for a given snapshot. */
const canonicalChunk = (chunk: Chunk): Chunk =>
  Object.freeze({
    ownerId: chunk.ownerId,
    noteId: chunk.noteId,
    revision: chunk.revision,
    sectionId: chunk.sectionId,
    chunkId: chunk.chunkId,
    ordinal: chunk.ordinal,
    title: chunk.title,
    startOffset: chunk.startOffset,
    endOffset: chunk.endOffset,
    text: chunk.text,
  });

const decodeDocument = (value: unknown, ownerId: string, seen: Set<string>): Document => {
  if (!isRecord(value) || !hasExactKeys(value, DOCUMENT_KEYS)) broken();
  const chunkValue = value['chunk'];
  if (!isRecord(chunkValue) || !hasExactKeys(chunkValue, CHUNK_KEYS)) broken();
  try {
    assertChunk(chunkValue);
  } catch {
    broken();
  }
  const chunk = chunkValue as unknown as Chunk;
  if (chunk.ownerId !== ownerId) broken();
  if (!isWellFormed(chunk.title) || !isWellFormed(chunk.text)) broken();
  const vectorKey = value['vectorKey'];
  const embeddingDigest = value['embeddingDigest'];
  if (typeof vectorKey !== 'string' || !SHA256_HEX.test(vectorKey)) broken();
  if (typeof embeddingDigest !== 'string' || !SHA256_HEX.test(embeddingDigest)) broken();
  const key = sourceKey(chunk);
  if (seen.has(key)) broken();
  seen.add(key);
  return Object.freeze({
    chunk: canonicalChunk(chunk),
    vectorKey,
    embeddingDigest,
  });
};

/** Exact-shape snapshot guard: no unsupported key, foreign owner, bad span, bad digest or dim data. */
export function validateSnapshot(value: unknown, expectedPolicy = POLICY_IDENTITY): Snapshot {
  if (!isRecord(value) || !hasExactKeys(value, SNAPSHOT_KEYS)) broken();
  if (value['schemaVersion'] !== SNAPSHOT_SCHEMA_VERSION) broken();
  const ownerId = value['ownerId'];
  if (!isValidIdentifier(ownerId)) broken();
  const version = value['version'];
  if (!isValidIdentifier(version)) broken();
  const consentGeneration = value['consentGeneration'];
  if (!isSafeInteger(consentGeneration) || consentGeneration < 0) broken();
  const accountEpoch = value['accountEpoch'];
  if (!isSafeInteger(accountEpoch) || accountEpoch < 0) broken();
  if (!SHA256_HEX.test(expectedPolicy) || value['policyIdentity'] !== expectedPolicy) broken();
  const rawDocuments = value['documents'];
  if (!Array.isArray(rawDocuments)) broken();
  const seen = new Set<string>();
  const documents: Document[] = [];
  for (const entry of rawDocuments) documents.push(decodeDocument(entry, ownerId, seen));
  return Object.freeze({
    schemaVersion: SNAPSHOT_SCHEMA_VERSION,
    ownerId,
    version,
    consentGeneration,
    accountEpoch,
    policyIdentity: expectedPolicy,
    documents: Object.freeze(documents),
  });
}

/** Canonical JSON for the artifact; validation runs first so an invalid snapshot is never staged. */
export function encodeSnapshot(snapshot: Snapshot): string {
  return JSON.stringify(validateSnapshot(snapshot, snapshot.policyIdentity));
}

export function decodeSnapshot(text: string, expectedPolicy = POLICY_IDENTITY): Snapshot {
  if (typeof text !== 'string' || text.length === 0) broken();
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    broken();
  }
  return validateSnapshot(value, expectedPolicy);
}

/** Content checksum over the canonical encoding; the manifest records exactly this value. */
export function checksum(snapshot: Snapshot): string {
  return sha256Hex(encodeSnapshot(snapshot));
}

/** Manifest schema guard for states read back from the store. */
export function validateManifest(value: unknown, ownerId: string): Manifest {
  if (!isRecord(value) || !hasExactKeys(value, MANIFEST_KEYS)) broken();
  if (value['ownerId'] !== ownerId) broken();
  const generation = value['generation'];
  if (!isSafeInteger(generation) || generation < 0) broken();
  if (!isValidIdentifier(value['version'])) broken();
  const fingerprint = value['fingerprint'];
  if (typeof fingerprint !== 'string' || !SHA256_HEX.test(fingerprint)) broken();
  const consentGeneration = value['consentGeneration'];
  if (!isSafeInteger(consentGeneration) || consentGeneration < 0) broken();
  const accountEpoch = value['accountEpoch'];
  if (!isSafeInteger(accountEpoch) || accountEpoch < 0) broken();
  if (value['status'] !== 'READY' && value['status'] !== 'BLOCKED') broken();
  const snapshotKey = value['snapshotKey'];
  if (typeof snapshotKey !== 'string' || snapshotKey.length === 0) broken();
  const manifestChecksum = value['checksum'];
  if (typeof manifestChecksum !== 'string' || !SHA256_HEX.test(manifestChecksum)) broken();
  // The previous policy identity may differ: that only forces a rebuild, not a failure.
  if (typeof value['policyIdentity'] !== 'string' || !SHA256_HEX.test(value['policyIdentity'])) broken();
  return Object.freeze({
    ownerId,
    generation,
    version: value['version'],
    fingerprint,
    consentGeneration,
    accountEpoch,
    status: value['status'],
    snapshotKey,
    checksum: manifestChecksum,
    policyIdentity: value['policyIdentity'],
  });
}
