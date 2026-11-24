/**
 * Durable embedding checkpoint codec + the pure-injected resume/save blocks the worker calls
 * (Patch 5B): what "already paid for" means across worker attempts, plus the one vector-key
 * formula that staging and publishing must agree on.
 *
 * A checkpoint is one lease's progress record: for every embedding input already paid for and
 * staged into the vector index, its digest (policy + title + text) and the immutable key the
 * vector was staged under. Keys are lease-scoped (`vectorKeyFor` folds in the lease token), so
 * entries carried over from an earlier lease of the same binding stay fetchable under exactly
 * the key they were written to; a stale lease can never overwrite a newer lease's staged work.
 *
 * Binding (`checkpointMatches`): a checkpoint is usable only when owner, policy identity and
 * consent generation all match the resuming run exactly. Consent-generation strictness is a
 * deliberate product decision: a consent transition discards embedding progress rather than
 * reusing paid vectors across a consent boundary. The account epoch is deliberately NOT part of
 * the binding — it is bumped by feed appends that cannot change any chunk's content (e.g. share
 * creates), and per-chunk correctness comes from digest matching, so epoch churn must not burn
 * paid work.
 *
 * Honesty about the paid window: an embedding is billable the moment the provider returns it;
 * durability only starts after the vector is staged to the index AND the checkpoint PUT
 * succeeds. A death inside [provider returns] -> [vector staged] -> [checkpoint PUT] re-bills
 * exactly that one chunk. No exactly-once embedding is promised anywhere in this system.
 *
 * Validation follows the snapshot codec idiom (exact shape, frozen result) and throws
 * `RagFailure('INDEX_NOT_READY')` with the code only — this module never imports `./types`
 * (types.ts imports the shapes from here); the artifacts port wraps failures into its own typed
 * codes and the worker treats any unreadable checkpoint as "rebuild", never as a job failure.
 * The port types below are structural: they must stay identical to the optional Artifacts
 * methods in types.ts, and the worker's call sites type-check the bridge.
 */
import { isValidIdentifier } from '../contract';
import { isSafeInteger } from '../chunking';
import { validateVector } from '../retrieval';
import { RagFailure } from '../types';
import { SHA256_HEX, sha256Hex } from './snapshot';

export const CHECKPOINT_SCHEMA_VERSION = 1;

export type CheckpointEntry = Readonly<{ embeddingDigest: string; vectorKey: string }>;

export type Checkpoint = Readonly<{
  schemaVersion: typeof CHECKPOINT_SCHEMA_VERSION;
  ownerId: string;
  policyIdentity: string;
  consentGeneration: number;
  leaseToken: string;
  createdAt: number;
  entries: readonly CheckpointEntry[];
}>;

/** The binding a resume compares against: owner, policy identity and consent generation. */
export type CheckpointBinding = Readonly<{
  ownerId: string; policyIdentity: string; consentGeneration: number;
}>;

/** Structural stageVector port: the exact entry shape the Artifacts method accepts. */
export type StageVectorEntry = Readonly<{
  key: string;
  vector: readonly number[];
  metadata: Readonly<{
    ownerId: string; manifestVersion: string; noteId: string; revision: number; chunkId: string;
  }>;
}>;
export type StageVectorPort = (entry: StageVectorEntry, signal: AbortSignal) => Promise<void>;
export type PutCheckpointPort = (checkpoint: Checkpoint, signal: AbortSignal) => Promise<void>;
export type ListCheckpointsPort = (
  ownerId: string,
  signal: AbortSignal,
) => Promise<readonly Checkpoint[]>;

const ENTRY_KEYS = ['embeddingDigest', 'vectorKey'] as const;
const CHECKPOINT_KEYS = [
  'schemaVersion', 'ownerId', 'policyIdentity', 'consentGeneration', 'leaseToken', 'createdAt',
  'entries',
] as const;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const hasExactKeys = (value: Record<string, unknown>, required: readonly string[]): boolean =>
  Object.keys(value).length === required.length &&
  required.every((key) => Object.prototype.hasOwnProperty.call(value, key));

const broken: () => never = () => {
  throw new RagFailure('INDEX_NOT_READY');
};

const decodeEntry = (value: unknown, digests: Set<string>, keys: Set<string>): CheckpointEntry => {
  if (!isRecord(value) || !hasExactKeys(value, ENTRY_KEYS)) broken();
  const embeddingDigest = value['embeddingDigest'];
  const vectorKey = value['vectorKey'];
  if (typeof embeddingDigest !== 'string' || !SHA256_HEX.test(embeddingDigest)) broken();
  if (typeof vectorKey !== 'string' || !SHA256_HEX.test(vectorKey)) broken();
  // Duplicates would let one digest shadow another's staged vector.
  if (digests.has(embeddingDigest) || keys.has(vectorKey)) broken();
  digests.add(embeddingDigest);
  keys.add(vectorKey);
  return Object.freeze({ embeddingDigest, vectorKey });
};

/** Exact-shape checkpoint guard: no extra key, malformed identity, bad digest or duplicate. */
export function validateCheckpoint(value: unknown): Checkpoint {
  if (!isRecord(value) || !hasExactKeys(value, CHECKPOINT_KEYS)) broken();
  if (value['schemaVersion'] !== CHECKPOINT_SCHEMA_VERSION) broken();
  const ownerId = value['ownerId'];
  if (!isValidIdentifier(ownerId)) broken();
  const policyIdentity = value['policyIdentity'];
  if (typeof policyIdentity !== 'string' || !SHA256_HEX.test(policyIdentity)) broken();
  const consentGeneration = value['consentGeneration'];
  if (!isSafeInteger(consentGeneration) || consentGeneration < 0) broken();
  const leaseToken = value['leaseToken'];
  // Opaque binding data here; the artifacts layer enforces path safety (SAFE_VERSION) before a
  // token ever becomes an S3 key segment.
  if (typeof leaseToken !== 'string' || leaseToken.length === 0 || leaseToken.length > 128) broken();
  const createdAt = value['createdAt'];
  if (!isSafeInteger(createdAt) || createdAt < 0) broken();
  const rawEntries = value['entries'];
  if (!Array.isArray(rawEntries)) broken();
  const digests = new Set<string>();
  const keys = new Set<string>();
  const entries: CheckpointEntry[] = [];
  for (const entry of rawEntries) entries.push(decodeEntry(entry, digests, keys));
  return Object.freeze({
    schemaVersion: CHECKPOINT_SCHEMA_VERSION,
    ownerId,
    policyIdentity,
    consentGeneration,
    leaseToken,
    createdAt,
    entries: Object.freeze(entries),
  });
}

/** Canonical JSON; validation runs first so an invalid checkpoint is never staged. */
export function encodeCheckpoint(checkpoint: Checkpoint): string {
  return JSON.stringify(validateCheckpoint(checkpoint));
}

export function decodeCheckpoint(text: string): Checkpoint {
  if (typeof text !== 'string' || text.length === 0) broken();
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    broken();
  }
  return validateCheckpoint(value);
}

/** Strict binding: any owner, policy or consent-generation mismatch makes a checkpoint unusable. */
export function checkpointMatches(checkpoint: Checkpoint, binding: CheckpointBinding): boolean {
  return checkpoint.ownerId === binding.ownerId &&
    checkpoint.policyIdentity === binding.policyIdentity &&
    checkpoint.consentGeneration === binding.consentGeneration;
}

/**
 * The immutable vector key for one chunk under one lease — the single shared formula for staged
 * vectors (checkpoint resume) and published snapshots (`buildCorpus`), so a staged vector is
 * always fetchable under exactly the key the manifest will name and the two can never drift.
 */
export const vectorKeyFor = (
  ownerId: string,
  noteId: string,
  revision: number,
  chunkId: string,
  leaseToken: string,
  policyIdentity: string,
): string => sha256Hex(JSON.stringify([ownerId, noteId, revision, chunkId, leaseToken, policyIdentity]));

/**
 * Patch 5B resume, pure-injected: MERGE every binding-matching checkpoint.
 *
 * Checkpoints are visited newest-first, but a newer thinner checkpoint (a
 * short-lived attempt, or one whose own resume failed) must never shadow a
 * richer older sibling: entries are collected across ALL matching checkpoints,
 * deduped by embeddingDigest (first — newest — key wins). Each checkpoint's
 * vectors are fetched as a unit; a missing or damaged vector in one checkpoint
 * discards only that checkpoint's unfetchable digests, never another
 * candidate's chances. Returns null when nothing is resumable. The caller
 * decides what a throw means (the worker rebuilds, never fails the job).
 */
export const resumeFromCheckpoint = async (
  read: Readonly<{ listCheckpoints: ListCheckpointsPort; getVectors: (keys: readonly string[], signal: AbortSignal) => Promise<ReadonlyMap<string, readonly number[]>> }>,
  ownerId: string,
  policyIdentity: string,
  consentGeneration: number,
  pending: ReadonlySet<string>,
  signal: AbortSignal,
): Promise<Readonly<{ entries: readonly CheckpointEntry[]; vectors: ReadonlyMap<string, readonly number[]> }> | null> => {
  const checkpoints = await read.listCheckpoints(ownerId, signal);
  const matching = checkpoints.filter((checkpoint) =>
    checkpointMatches(checkpoint, { ownerId, policyIdentity, consentGeneration }));
  const vectors = new Map<string, readonly number[]>();
  const entries: CheckpointEntry[] = [];
  const seen = new Set<string>();
  for (const checkpoint of matching) {
    const usable = checkpoint.entries.filter((entry) =>
      pending.has(entry.embeddingDigest) && !seen.has(entry.embeddingDigest));
    if (usable.length === 0) continue;
    let fetched: ReadonlyMap<string, readonly number[]>;
    try {
      fetched = await read.getVectors(usable.map((entry) => entry.vectorKey), signal);
    } catch {
      // One unreadable checkpoint never poisons the rest of the merge.
      continue;
    }
    for (const entry of usable) {
      const vector = fetched.get(entry.vectorKey);
      if (vector === undefined) continue;
      try {
        validateVector(vector);
      } catch {
        continue;
      }
      seen.add(entry.embeddingDigest);
      vectors.set(entry.embeddingDigest, vector);
      entries.push(entry);
    }
  }
  if (entries.length === 0) return null;
  return Object.freeze({ entries: Object.freeze(entries), vectors });
};

/** Sweep ports: exactly the optional Artifacts surface the sweeper needs. */
export type SweepPorts = Readonly<{
  listCheckpoints: ListCheckpointsPort;
  deleteStagedVectors: (keys: readonly string[], signal: AbortSignal) => Promise<void>;
  deleteCheckpoints: (ownerId: string, signal: AbortSignal, ...tokens: string[]) => Promise<void>;
}>;

/**
 * Reaps stale checkpoints: their staged vectors first, the inventory JSON last
 * (inventory-before-delete, so an interruption between the two leaves the map
 * readable for a rerun — the sweep is idempotent and tolerates late writes by
 * a dead lease reappearing after a sweep).
 *
 * Ownership fences, per the checkpoint contract:
 *  - the checkpoint of the LIVE manifest's own lease is skipped: its staged
 *    keys ARE the published vectors (keys fold the lease token, so no other
 *    checkpoint can name them);
 *  - anything younger than [minAgeMs] is skipped: its lease may still be live
 *    (the default mirrors the orphan recovery precedent — a full day past the
 *    lease window, whichever is larger).
 */
export const sweepStaleCheckpoints = async (
  ports: SweepPorts,
  ownerId: string,
  liveVersion: string | null,
  nowMs: number,
  minAgeMs: number,
  signal: AbortSignal,
): Promise<Readonly<{ swept: number }>> => {
  const checkpoints = await ports.listCheckpoints(ownerId, signal);
  let swept = 0;
  for (const checkpoint of checkpoints) {
    if (checkpoint.leaseToken === liveVersion) continue;
    if (nowMs - checkpoint.createdAt < minAgeMs) continue;
    if (checkpoint.entries.length > 0) {
      await ports.deleteStagedVectors(
        checkpoint.entries.map((entry) => entry.vectorKey), signal,
      );
    }
    await ports.deleteCheckpoints(ownerId, signal, checkpoint.leaseToken);
    swept += 1;
  }
  return Object.freeze({ swept });
};

/**
 * One run's incremental checkpoint writer (pure-injected ports; the worker owns the deadline).
 * `adopt` seeds the saved list with resumed entries (keys staged under earlier leases stay
 * valid — keys are immutable and lease-scoped); `record` stages one freshly paid vector under
 * its FINAL publish key and then durably rewrites the whole progress list. A write failure
 * propagates: that is the documented re-bill window. The entries list is written whole each
 * time (~140 bytes per entry) — correctness before byte economy: no truncation that could
 * silently drop paid work.
 */
export const createCheckpointWriter = (
  stageVector: StageVectorPort,
  putCheckpoint: PutCheckpointPort,
  ownerId: string,
  policyIdentity: string,
  consentGeneration: number,
  leaseToken: string,
  now: () => number,
  signal: AbortSignal,
): Readonly<{ adopt(entries: readonly CheckpointEntry[]): void; recordCount(): number; record(
  digest: string,
  vector: readonly number[],
  chunk: Readonly<{ noteId: string; revision: number; chunkId: string }>,
): Promise<void> }> => {
  const saved: CheckpointEntry[] = [];
  return {
    adopt: (entries) => {
      saved.push(...entries);
    },
    recordCount: () => saved.length,
    record: async (digest, vector, chunk) => {
      const vectorKey = vectorKeyFor(
        ownerId, chunk.noteId, chunk.revision, chunk.chunkId, leaseToken, policyIdentity,
      );
      await stageVector({
        key: vectorKey,
        vector,
        metadata: {
          ownerId,
          manifestVersion: leaseToken,
          noteId: chunk.noteId,
          revision: chunk.revision,
          chunkId: chunk.chunkId,
        },
      }, signal);
      saved.push(Object.freeze({ embeddingDigest: digest, vectorKey }));
      await putCheckpoint({
        schemaVersion: CHECKPOINT_SCHEMA_VERSION,
        ownerId,
        policyIdentity,
        consentGeneration,
        leaseToken,
        createdAt: now(),
        entries: Object.freeze([...saved]),
      }, signal);
    },
  };
};
