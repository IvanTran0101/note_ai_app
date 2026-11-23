/**
 * Checkpoint codec tests (Patch 5B) — exact schema, frozen decode, duplicate rejection, the
 * strict binding contract, the shared vector-key formula and the newest-first resume merge.
 * Runner: node --import tsx --test amplify/rag/indexing/checkpoint.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { RagFailure } from '../types';
import { policyIdentity } from './snapshot';
import { EMBEDDING_DIMENSIONS } from '../retrieval';
import {
  CHECKPOINT_SCHEMA_VERSION, checkpointMatches, decodeCheckpoint, encodeCheckpoint,
  resumeFromCheckpoint, validateCheckpoint, vectorKeyFor,
} from './checkpoint';
import type { Checkpoint, CheckpointEntry } from './checkpoint';

const sha256 = (text: string) => createHash('sha256').update(text, 'utf8').digest('hex');
const entry = (digestSeed: string, keySeed: string): CheckpointEntry =>
  Object.freeze({ embeddingDigest: sha256(digestSeed), vectorKey: sha256(keySeed) });

const checkpoint = (over: Partial<Checkpoint> = {}): Checkpoint => ({
  schemaVersion: CHECKPOINT_SCHEMA_VERSION, ownerId: 'u1', policyIdentity: policyIdentity(),
  consentGeneration: 1, leaseToken: 'lease-1', createdAt: 1_000,
  entries: [entry('digest-1', 'key-1'), entry('digest-2', 'key-2')], ...over,
});

const rejectsCheckpoint = (value: unknown): void => {
  assert.throws(() => validateCheckpoint(value), (error: unknown) =>
    error instanceof RagFailure && error.code === 'INDEX_NOT_READY');
};

test('validate/encode/decode round-trips exactly and freezes the result', () => {
  const value = checkpoint();
  const validated = validateCheckpoint(value);
  assert.deepEqual(validated, value);
  assert.ok(Object.isFrozen(validated) && Object.isFrozen(validated.entries));
  for (const item of validated.entries) assert.ok(Object.isFrozen(item));
  const encoded = encodeCheckpoint(value);
  assert.equal(encoded, encodeCheckpoint(validated));
  assert.deepEqual(decodeCheckpoint(encoded), validated);
  // No floats and no chunk text: only digests and keys travel inside a checkpoint.
  assert.equal(/\d\.\d/.test(encoded), false);
});

test('checkpoint schema rejects unsupported keys, foreign owners and bad values', () => {
  const bad: readonly unknown[] = [
    null,
    'nope',
    { ...checkpoint(), extra: 1 },
    (() => { const { leaseToken, ...rest } = checkpoint(); return rest; })(),
    checkpoint({ schemaVersion: 2 as 1 }),
    // Identifier shape only: which owner a checkpoint belongs to is `checkpointMatches`'s job.
    checkpoint({ ownerId: ' ' }),
    checkpoint({ ownerId: 'u\u0000' }),
    checkpoint({ policyIdentity: 'short' }),
    checkpoint({ policyIdentity: sha256('x').toUpperCase() }),
    checkpoint({ consentGeneration: -1 }),
    checkpoint({ consentGeneration: 1.5 }),
    checkpoint({ leaseToken: '' }),
    checkpoint({ leaseToken: 'x'.repeat(129) }),
    checkpoint({ createdAt: -1 }),
    checkpoint({ createdAt: Number.NaN }),
    checkpoint({ entries: 'nope' as never }),
    checkpoint({ entries: [{ embeddingDigest: 'abc', vectorKey: sha256('k') }] }),
    checkpoint({ entries: [{ embeddingDigest: sha256('d'), vectorKey: 'abc' }] }),
    checkpoint({ entries: [{ embeddingDigest: sha256('d'), vectorKey: sha256('k'), extra: 1 } as never] }),
    // Duplicate digests and duplicate keys both reject: neither may shadow the other.
    checkpoint({ entries: [entry('d', 'k1'), entry('d', 'k2')] }),
    checkpoint({ entries: [entry('d1', 'k'), entry('d2', 'k')] }),
  ];
  for (const value of bad) rejectsCheckpoint(value);
  assert.deepEqual(validateCheckpoint(checkpoint({ entries: [] })).entries, []);
  // The lease token is opaque binding data here (path safety is the artifacts layer's check).
  assert.equal(validateCheckpoint(checkpoint({ leaseToken: 'x'.repeat(128) })).leaseToken.length, 128);
});

test('decode fails closed on malformed JSON', () => {
  for (const text of ['', '{', 'null', '[]', JSON.stringify({ ...checkpoint(), schemaVersion: 3 })]) {
    assert.throws(() => decodeCheckpoint(text), (error: unknown) =>
      error instanceof RagFailure && error.code === 'INDEX_NOT_READY');
  }
});

test('checkpointMatches is strict over owner, policy identity and consent generation', () => {
  const value = checkpoint();
  const binding = { ownerId: 'u1', policyIdentity: policyIdentity(), consentGeneration: 1 };
  assert.equal(checkpointMatches(value, binding), true);
  assert.equal(checkpointMatches(value, { ...binding, ownerId: 'u2' }), false);
  assert.equal(checkpointMatches(value, { ...binding, policyIdentity: sha256('other') }), false);
  assert.equal(checkpointMatches(value, { ...binding, consentGeneration: 2 }), false);
  // The account epoch is deliberately not part of the binding; no epoch field exists to match.
  assert.equal('accountEpoch' in value, false);
});

test('vectorKeyFor is the single shared lease-scoped key formula', () => {
  const key = vectorKeyFor('u1', 'n1', 2, 'body-3', 'lease-9', policyIdentity());
  assert.equal(key, sha256(JSON.stringify(['u1', 'n1', 2, 'body-3', 'lease-9', policyIdentity()])));
  assert.match(key, /^[0-9a-f]{64}$/);
  // Any identity, revision or lease move changes the key: a new lease can never address another
  // lease's staged vectors, and a metadata move can never silently reuse a lineage.
  for (const varied of [
    vectorKeyFor('u2', 'n1', 2, 'body-3', 'lease-9', policyIdentity()),
    vectorKeyFor('u1', 'n2', 2, 'body-3', 'lease-9', policyIdentity()),
    vectorKeyFor('u1', 'n1', 3, 'body-3', 'lease-9', policyIdentity()),
    vectorKeyFor('u1', 'n1', 2, 'body-4', 'lease-9', policyIdentity()),
    vectorKeyFor('u1', 'n1', 2, 'body-3', 'lease-10', policyIdentity()),
    vectorKeyFor('u1', 'n1', 2, 'body-3', 'lease-9', sha256('other-policy')),
  ]) {
    assert.notEqual(varied, key);
  }
  assert.equal(vectorKeyFor('u1', 'n1', 2, 'body-3', 'lease-9', policyIdentity()), key);
});

// ---------------------------------------------------------------------------------------------
// Resume merge (resumeFromCheckpoint): EVERY binding-matching checkpoint contributes
// newest-first, deduped by digest; one unfetchable checkpoint never shadows an older sibling.
// The read port mimics production GetVectors: it fails closed when a requested key is missing.
// ---------------------------------------------------------------------------------------------

/** A valid stored vector: right dimensions, finite, non-zero norm. */
const vector = (value: number): readonly number[] => {
  const out = new Array<number>(EMBEDDING_DIMENSIONS).fill(0);
  out[0] = value;
  return out;
};

const readPort = (
  checkpoints: readonly Checkpoint[],
  vectors: ReadonlyMap<string, readonly number[]>,
): Readonly<{
  listCheckpoints: () => Promise<readonly Checkpoint[]>;
  getVectors: (keys: readonly string[], signal: AbortSignal) => Promise<ReadonlyMap<string, readonly number[]>>;
}> => ({
  listCheckpoints: async () => checkpoints,
  getVectors: async (keys) => {
    const found = new Map<string, readonly number[]>();
    for (const key of keys) {
      const stored = vectors.get(key);
      if (stored === undefined) throw new RagFailure('INDEX_NOT_READY');
      found.set(key, stored);
    }
    return found;
  },
});

test('resume merges every binding-matching checkpoint newest-first, deduped by digest', async () => {
  const newer = checkpoint({
    leaseToken: 'lease-new', createdAt: 2_000, entries: [entry('digest-3', 'key-3')],
  });
  const older = checkpoint({
    leaseToken: 'lease-old', createdAt: 1_000,
    entries: [entry('digest-1', 'key-1'), entry('digest-2', 'key-2')],
  });
  const vectors = new Map([
    [sha256('key-3'), vector(3)], [sha256('key-1'), vector(1)], [sha256('key-2'), vector(2)],
  ]);
  const pending = new Set([sha256('digest-1'), sha256('digest-2'), sha256('digest-3')]);
  const resumed = await resumeFromCheckpoint(
    readPort([newer, older], vectors), 'u1', policyIdentity(), 1, pending, new AbortController().signal,
  );
  assert.ok(resumed !== null);
  // Newest-first collection: a thinner newer checkpoint never shadows a richer older sibling.
  assert.deepEqual(resumed.entries.map((item) => item.embeddingDigest),
    [sha256('digest-3'), sha256('digest-1'), sha256('digest-2')]);
  assert.equal(resumed.vectors.size, 3);
  assert.deepEqual(resumed.vectors.get(sha256('digest-3')), vector(3));
  assert.deepEqual(resumed.entries.map((item) => item.vectorKey),
    [sha256('key-3'), sha256('key-1'), sha256('key-2')]);
});

test('a missing vector discards only that checkpoint\'s digests, never an older sibling\'s', async () => {
  // The newest checkpoint names a key the vector index no longer has: its digest is skipped,
  // and the older sibling's digests are still resumed under their own keys.
  const newer = checkpoint({
    leaseToken: 'lease-new', createdAt: 2_000, entries: [entry('digest-3', 'key-gone')],
  });
  const older = checkpoint({
    leaseToken: 'lease-old', createdAt: 1_000,
    entries: [entry('digest-1', 'key-1'), entry('digest-2', 'key-2')],
  });
  const vectors = new Map([[sha256('key-1'), vector(1)], [sha256('key-2'), vector(2)]]);
  const pending = new Set([sha256('digest-1'), sha256('digest-2'), sha256('digest-3')]);
  const resumed = await resumeFromCheckpoint(
    readPort([newer, older], vectors), 'u1', policyIdentity(), 1, pending, new AbortController().signal,
  );
  assert.ok(resumed !== null);
  assert.deepEqual(resumed.entries.map((item) => item.embeddingDigest),
    [sha256('digest-1'), sha256('digest-2')]);
  assert.equal(resumed.vectors.size, 2);
  assert.equal(resumed.vectors.has(sha256('digest-3')), false);
});

test('a non-matching binding contributes nothing to the resume merge', async () => {
  const foreign = checkpoint({ leaseToken: 'lease-x', consentGeneration: 2, createdAt: 3_000 });
  const pending = new Set([sha256('digest-1'), sha256('digest-2')]);
  const vectors = new Map([[sha256('key-1'), vector(1)], [sha256('key-2'), vector(2)]]);
  // Only the non-matching checkpoint exists: nothing is resumable at all.
  assert.equal(await resumeFromCheckpoint(
    readPort([foreign], vectors), 'u1', policyIdentity(), 1, pending, new AbortController().signal,
  ), null);
  // With a matching sibling, only its digests are resumed; the foreign one is ignored.
  const matching = checkpoint({ leaseToken: 'lease-1', createdAt: 1_000 });
  const partial = await resumeFromCheckpoint(
    readPort([foreign, matching], vectors), 'u1', policyIdentity(), 1, pending, new AbortController().signal,
  );
  assert.ok(partial !== null);
  assert.deepEqual(partial.entries.map((item) => item.embeddingDigest),
    [sha256('digest-1'), sha256('digest-2')]);
});

test('a duplicate digest across checkpoints resolves to the newest staged vector', async () => {
  const newer = checkpoint({
    leaseToken: 'lease-new', createdAt: 2_000, entries: [entry('digest-1', 'key-new')],
  });
  const older = checkpoint({
    leaseToken: 'lease-old', createdAt: 1_000, entries: [entry('digest-1', 'key-old')],
  });
  const vectors = new Map([[sha256('key-new'), vector(9)], [sha256('key-old'), vector(4)]]);
  const resumed = await resumeFromCheckpoint(
    readPort([newer, older], vectors), 'u1', policyIdentity(), 1,
    new Set([sha256('digest-1')]), new AbortController().signal,
  );
  assert.ok(resumed !== null);
  assert.equal(resumed.entries.length, 1, 'the older duplicate is never adopted');
  assert.equal(resumed.entries[0]?.vectorKey, sha256('key-new'));
  assert.deepEqual(resumed.vectors.get(sha256('digest-1')), vector(9), 'the newest vector wins');
});
