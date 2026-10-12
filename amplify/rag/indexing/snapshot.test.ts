/**
 * Indexing snapshot codec tests — policy identity, exact schema, checksum and rebuild triggers.
 * Runner: node --import tsx --test amplify/rag/indexing/snapshot.test.ts
 */
import tokenizerManifest from '../../../docs/rag/tokenizer_manifest.json';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { policy } from '../types';
import type { Chunk } from '../types';
import type { Document, Manifest, Snapshot } from './types';
import { IndexFailure } from './types';
import {
  POLICY_IDENTITY_FIELDS, SNAPSHOT_SCHEMA_VERSION, checksum, decodeSnapshot,
  embeddingInputDigest, encodeSnapshot, policyIdentity, sha256Hex, validateManifest,
  validateSnapshot,
} from './snapshot';

const sha256 = (text: string) => createHash('sha256').update(text, 'utf8').digest('hex');
const DIGEST = sha256('x');

const chunk = (over: Partial<Chunk> = {}): Chunk => ({
  ownerId: 'u1', noteId: 'n1', revision: 1, sectionId: 'body', chunkId: 'body-0',
  ordinal: 0, title: 'T', startOffset: 0, endOffset: 5, text: 'hello', ...over,
});

const document = (over: Partial<Document> = {}): Document => ({
  chunk: chunk(), vectorKey: DIGEST, embeddingDigest: DIGEST, ...over,
});

const snapshot = (over: Partial<Snapshot> = {}): Snapshot => ({
  schemaVersion: SNAPSHOT_SCHEMA_VERSION, ownerId: 'u1', version: 'lease-1',
  consentGeneration: 2, accountEpoch: 1, policyIdentity: policyIdentity(),
  documents: [document()], ...over,
});

const manifest = (over: Partial<Manifest> = {}): Manifest => ({
  ownerId: 'u1', generation: 1, version: 'lease-1', fingerprint: DIGEST,
  consentGeneration: 2, accountEpoch: 1, status: 'READY', snapshotKey: 'snapshot#lease-1',
  checksum: DIGEST, policyIdentity: policyIdentity(), ...over,
});

const rejectsSnapshot = (value: unknown): void => {
  assert.throws(() => validateSnapshot(value), (error: unknown) =>
    error instanceof IndexFailure && error.code === 'INDEX_NOT_READY' && error.retryable === false);
};

test('policy identity pins the full embedding, chunking and UTF-16 policy', () => {
  assert.deepEqual(POLICY_IDENTITY_FIELDS, {
    tokenizer: tokenizerManifest,
    lexical: { analyzer: 'rag-analyzer.v1', k1: 1.2, b: 0.75 },
    model: 'cohere.embed-multilingual-v3',
    dimensions: 1024,
    documentInputType: 'search_document',
    queryInputType: 'search_query',
    truncate: 'NONE',
    chunking: {
      strategy: 'paragraph-sentence-token-then-pack',
      targetTokens: 400,
      maxEmbeddingTokens: 512,
      overlapTokens: 0,
      maxEmbeddingCharacters: 2048,
    },
    offsetUnit: 'utf16-code-unit',
    spanEnd: 'exclusive',
    embeddingText: 'title-newline-content-span',
  });
  assert.equal(policy.embedding.dimensions, 1024);
  assert.match(policyIdentity(), /^[0-9a-f]{64}$/);
  assert.equal(policyIdentity(), sha256(JSON.stringify(POLICY_IDENTITY_FIELDS)));
  assert.equal(policyIdentity(), policyIdentity());
});

test('embedding input digest depends on policy, title and text, never on note identity', () => {
  const base = embeddingInputDigest('T', 'hello');
  assert.match(base, /^[0-9a-f]{64}$/);
  assert.equal(embeddingInputDigest('T', 'hello'), base);
  assert.notEqual(embeddingInputDigest('T2', 'hello'), base);
  assert.notEqual(embeddingInputDigest('T', 'hello2'), base);
  // Unambiguous pairing: "a\nb"+"c" must not collide with "a"+"b\nc".
  assert.notEqual(embeddingInputDigest('a\nb', 'c'), embeddingInputDigest('a', 'b\nc'));
  assert.throws(() => embeddingInputDigest('T', '\ud800'), IndexFailure);
});

test('validate/encode/decode round-trips exactly and keeps a stable encoding', () => {
  const value = snapshot({ documents: [document(), document({ chunk: chunk({ chunkId: 'body-1', ordinal: 1 }) })] });
  const validated = validateSnapshot(value);
  assert.deepEqual(validated, value);
  const encoded = encodeSnapshot(value);
  assert.equal(encoded, encodeSnapshot(validated));
  assert.deepEqual(decodeSnapshot(encoded), validated);
  const documents = (JSON.parse(encoded) as { documents: readonly Document[] }).documents;
  // No vector floats or dimension data travel inside the snapshot artifact.
  assert.equal(documents.every((entry) => typeof entry.vectorKey === 'string'), true);
  // No vector floats (a decimal number) travel inside the snapshot artifact.
  assert.equal(/\d\.\d/.test(encoded), false);
});

test('checksum covers the canonical encoding and changes with content', () => {
  const value = snapshot();
  assert.equal(checksum(value), sha256(encodeSnapshot(value)));
  assert.match(checksum(value), /^[0-9a-f]{64}$/);
  const changed = snapshot({ documents: [document({ embeddingDigest: sha256('y') })] });
  assert.notEqual(checksum(changed), checksum(value));
  assert.notEqual(checksum(snapshot({ version: 'lease-2' })), checksum(value));
});

test('snapshot schema rejects unsupported keys, foreign owners and bad digests', () => {
  const bad: readonly unknown[] = [
    null,
    { ...snapshot(), extra: 1 },
    (() => { const { version, ...rest } = snapshot(); return rest; })(),
    snapshot({ schemaVersion: 2 as 1 }),
    snapshot({ ownerId: ' ' }),
    snapshot({ ownerId: 'u\u0000' }),
    snapshot({ version: '' }),
    snapshot({ consentGeneration: -1 }),
    snapshot({ consentGeneration: 1.5 }),
    snapshot({ accountEpoch: -1 }),
    snapshot({ policyIdentity: sha256('other-policy') }),
    snapshot({ documents: 'nope' as never }),
    snapshot({ documents: [document({ chunk: chunk({ ownerId: 'u2' }) })] }),
    snapshot({ documents: [document(), document()] }),
    snapshot({ documents: [{ ...document(), extra: 1 } as unknown as Document] }),
    snapshot({
      documents: [{
        chunk: { ...chunk(), extra: 1 }, vectorKey: DIGEST, embeddingDigest: DIGEST,
      } as unknown as Document],
    }),
    snapshot({ documents: [document({ vectorKey: 'abc' })] }),
    snapshot({ documents: [document({ vectorKey: DIGEST.toUpperCase() })] }),
    snapshot({ documents: [document({ embeddingDigest: 'not-hex' })] }),
  ];
  for (const value of bad) rejectsSnapshot(value);
  assert.deepEqual(validateSnapshot(snapshot({ documents: [] })).documents, []);
});

test('snapshot schema rejects bad spans, unicode and chunk lineage', () => {
  const bad: readonly Chunk[] = [
    chunk({ text: 'hell', endOffset: 5 }),
    chunk({ startOffset: 2, endOffset: 2, text: '' }),
    chunk({ startOffset: -1 }),
    chunk({ endOffset: 99 }),
    chunk({ text: 'he\ud800lo' }),
    chunk({ title: 'T\udfff' }),
    chunk({ revision: 0 }),
    chunk({ ordinal: -1 }),
    chunk({ chunkId: '' }),
    chunk({ sectionId: 'body\u0007' }),
    { ...chunk(), endOffset: '5' } as unknown as Chunk,
    { ...chunk(), extra: 1 } as unknown as Chunk,
  ];
  for (const value of bad) rejectsSnapshot(snapshot({ documents: [document({ chunk: value })] }));
});

test('decode fails closed on malformed JSON and invalid payloads', () => {
  for (const text of ['', '{', 'null', '[]', JSON.stringify({ ...snapshot(), schemaVersion: 3 })]) {
    assert.throws(() => decodeSnapshot(text), (error: unknown) =>
      error instanceof IndexFailure && error.code === 'INDEX_NOT_READY');
  }
});

test('manifest guard keeps the store honest about generation, status and digests', () => {
  assert.deepEqual(validateManifest(manifest(), 'u1'), manifest());
  const bad: readonly unknown[] = [
    null,
    manifest({ ownerId: 'u2' }),
    manifest({ generation: -1 }),
    manifest({ generation: 1.5 }),
    manifest({ version: '' }),
    manifest({ fingerprint: 'abc' }),
    manifest({ checksum: 'ABC' }),
    manifest({ status: 'STALE' as 'READY' }),
    manifest({ snapshotKey: '' }),
    manifest({ consentGeneration: -1 }),
    manifest({ accountEpoch: -1 }),
    manifest({ policyIdentity: 'short' }),
    { ...manifest(), extra: 1 },
  ];
  for (const value of bad) {
    assert.throws(() => validateManifest(value, 'u1'), (error: unknown) =>
      error instanceof IndexFailure && error.code === 'INDEX_NOT_READY');
  }
  // A manifest from an older policy is readable: it only forces a rebuild.
  assert.equal(validateManifest(manifest({ policyIdentity: sha256('old') }), 'u1').policyIdentity, sha256('old'));
});
