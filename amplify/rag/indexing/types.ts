import jobPolicy from '../../../docs/rag/index_job_policy_v1.json';
import type { Checkpoint } from './checkpoint';
import type { CanonicalNote, Chunk, Counter } from '../types';
export type Job = Readonly<{
  jobVersion: 1; kind: 'RECONCILE_NOTE' | 'RECONCILE_ACCOUNT'; ownerId: string;
  noteId: string | null; sourceRevisionHint: number | null; policyVersion: string; eventId: string;
}>;
export type IndexNote = CanonicalNote & Readonly<{ protectionRevision: number }>;
export type Consent = Readonly<{ accepted: boolean; version: string; generation: number }>;
export type Manifest = Readonly<{
  ownerId: string; generation: number; version: string; fingerprint: string;
  consentGeneration: number; accountEpoch: number; status: 'READY' | 'BLOCKED';
  snapshotKey: string; checksum: string; policyIdentity: string;
}>;
export type IndexState = Readonly<{
  ownerId: string; accountEpoch: number; consent: Consent; notes: readonly IndexNote[];
  manifest: Manifest | null;
}>;
export type Lease = Readonly<{ token: string; expiresAt: number; fingerprint: string }>;
/** One NOTE# row reduced to the fields a fingerprint can move on (see `FreshnessMarkers`). */
export type NoteMarker = Readonly<{ noteId: string; revision: number; deleted: boolean; available: boolean }>;
/** One PROTECTION# row reduced to the fields a fingerprint can move on. */
export type ProtectionMarker = Readonly<{ noteId: string; enabled: boolean; revision: number }>;
/**
 * The light mid-flight freshness view of an account: epoch, consent and per-note
 * revision/deleted/available/protection rows — exactly the transactional marker set that covers
 * every canonical fingerprint input (see `markersOf` for the writer invariant). Notes and
 * protections are sorted by noteId, like `IndexState.notes`.
 */
export type FreshnessMarkers = Readonly<{
  ownerId: string; accountEpoch: number; consent: Consent;
  notes: readonly NoteMarker[]; protections: readonly ProtectionMarker[];
}>;
export type Document = Readonly<{ chunk: Chunk; vectorKey: string; embeddingDigest: string }>;
export type Snapshot = Readonly<{
  schemaVersion: 1; ownerId: string; version: string; consentGeneration: number;
  accountEpoch: number; policyIdentity: string; documents: readonly Document[];
}>;
export type StageResult = Readonly<{ snapshot: Snapshot; snapshotKey: string; checksum: string }>;
export type JobStatus = 'RUNNING' | 'SUCCEEDED' | 'SUPERSEDED' | 'BLOCKED' | 'FAILED';
export type IndexStore = Readonly<{
  load(ownerId: string, signal: AbortSignal): Promise<IndexState>;
  /**
   * Optional light freshness read for mid-flight revalidation. A store that exposes it lets the
   * worker compare `FreshnessMarkers` instead of re-reading and re-hashing the whole account per
   * chunk; any store (or test fake) without it keeps the exact legacy full-revalidate behavior,
   * so optionality IS the fallback.
   */
  loadMarkers?(ownerId: string, signal: AbortSignal): Promise<FreshnessMarkers>;
  acquire(state: IndexState, fingerprint: string, nowMs: number, signal: AbortSignal): Promise<Lease | null>;
  publish(state: IndexState, lease: Lease, manifest: Manifest, nowMs: number, signal: AbortSignal): Promise<boolean>;
  finish(ownerId: string, lease: Lease, status: JobStatus, code: string, nowMs: number, signal: AbortSignal): Promise<void>;
  reserveEmbedding(ownerId: string, signal: AbortSignal): Promise<void>;
}>;
/** One raw vector hit: the vector key plus its validated cosine distance in [0,2]. */
export type VectorSearchHit = Readonly<{ key: string; distance: number }>;
export type Artifacts = Readonly<{
  read(manifest: Manifest, signal: AbortSignal): Promise<Snapshot>;
  put(snapshot: Snapshot, signal: AbortSignal): Promise<Readonly<{ key: string; checksum: string }>>;
  putVectors(snapshot: Snapshot, vectors: ReadonlyMap<string, readonly number[]>, signal: AbortSignal): Promise<void>;
  getVectors(keys: readonly string[], signal: AbortSignal): Promise<ReadonlyMap<string, readonly number[]>>;
  query(vector: readonly number[], ownerId: string, version: string, noteId: string | null, signal: AbortSignal): Promise<readonly string[]>;
  /**
   * Optional scored variant of `query` with the exact same arguments. Production artifacts
   * implement it; a legacy/injected fake may omit it and `query` remains the fallback (whose
   * callers carry no distance rather than inventing one).
   */
  queryScored?(vector: readonly number[], ownerId: string, version: string, noteId: string | null, signal: AbortSignal): Promise<readonly VectorSearchHit[]>;
  cleanup(manifest: Manifest, signal: AbortSignal): Promise<void>;
  /**
   * Optional staged-key vector delete (checkpoint inventory reaping). Deletes
   * exactly the given keys in bounded batches; absent on fakes that never
   * stage vectors, in which case checkpoint sweeping is simply unavailable.
   */
  deleteStagedVectors?(keys: readonly string[], signal: AbortSignal): Promise<void>;
  /**
   * Patch 5B durable checkpoint ports. All four are optional, exactly like `loadMarkers`: an
   * artifacts object (or test fake) without them keeps the exact legacy worker behavior — no
   * resume, no staging, no checkpoint writes, no stop-margin early exit. Optionality IS the
   * fallback. Production `createArtifacts` implements all four, so real wiring opts in by
   * construction and needs no changes.
   */
  /**
   * Stages one produced vector under its FINAL publish key through the exact PutVectors entry
   * shape and metadata whitelist `putVectors` writes, so a resumed attempt can fetch it by key
   * before any manifest exists. `metadata.manifestVersion` is the staging lease token.
   */
  stageVector?(entry: Readonly<{
    key: string;
    vector: readonly number[];
    metadata: Readonly<{
      ownerId: string; manifestVersion: string; noteId: string; revision: number; chunkId: string;
    }>;
  }>, signal: AbortSignal): Promise<void>;
  /** All checkpoints of one owner, newest-first by `createdAt`; corrupt objects are skipped. */
  listCheckpoints?(ownerId: string, signal: AbortSignal): Promise<readonly Checkpoint[]>;
  /** Durably records one lease's progress under its lease-scoped key; leases never clash. */
  putCheckpoint?(checkpoint: Checkpoint, signal: AbortSignal): Promise<void>;
  /** Deletes exactly the listed leases' checkpoints of one owner; never a prefix delete. */
  deleteCheckpoints?(ownerId: string, signal: AbortSignal, ...tokens: string[]): Promise<void>;
}>;
export type Embedding = Readonly<{
  count: Counter;
  /**
   * `beforeDispatch` is an optional captured revalidation callback. A port that awaits its own
   * reservation or signing window must forward it into the signed transport, which re-runs it
   * immediately before the actual fetch, so a permit/consent/source withdrawal during that
   * window can never reach the provider. Optional so every existing three-argument caller and
   * direct probe keeps its exact behavior.
   */
  embed(
    texts: readonly string[],
    purpose: 'search_document' | 'search_query',
    signal: AbortSignal,
    beforeDispatch?: () => Promise<void>,
  ): Promise<readonly (readonly number[])[]>;
}>;
export type IndexDeps = Readonly<{
  store: IndexStore; artifacts: Artifacts; embedding: Embedding;
  now?: () => number; id?: () => string;
  log?: (metadata: Readonly<Record<string, string | number>>) => void;
}>;
export type JobResult = Readonly<{ status: Exclude<JobStatus, 'RUNNING'>; code: string; manifestVersion?: string }>;
export class IndexFailure extends Error {
  constructor(public readonly code: string, public readonly retryable = false) { super(code); }
}
export const JOB_POLICY_VERSION = jobPolicy.version;
export const LEASE_MS = jobPolicy.leaseMs;
export const WORKER_MS = jobPolicy.workerTimeoutSeconds * 1000;
export const RETENTION_DAYS = jobPolicy.failureRetentionDays;
export const SMOKE_EMBED_LIMIT = jobPolicy.smoke.globalEmbeddingInvocationLimit;
