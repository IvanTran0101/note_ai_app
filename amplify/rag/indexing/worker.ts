/**
 * Indexing worker: one job becomes one published manifest, or nothing at all.
 *
 * The stream payload is only a hint. The worker loads the owner's canonical state, binds it to
 * a lease taken by canonical fingerprint, and reconciles the *latest* full account: every
 * eligible (own, synced, unprotected, live, available) note is chunked with the injected
 * counter, reused vectors are copied from the previous snapshot under new immutable keys, and
 * only genuinely new embedding inputs are paid for. Before every paid embedding call and
 * before the publish transaction the worker re-reads the store and compares the fingerprint:
 * any consent, epoch, protection or text change aborts with SUPERSEDED and publishes nothing.
 *
 * Failure taxonomy: ports raise `IndexFailure`; retryable failures and an expired deadline are
 * rethrown so the stream replays the batch, terminal failures end as `FAILED(code)`. A failed
 * publish leaves staged artifacts in place and flags them for backfill — it never deletes a
 * prefix that could belong to an active lease.
 */
import { CONSENT_VERSION } from '../contract';
import {
  MAX_EMBEDDING_CHARACTERS, MAX_EMBEDDING_TOKENS, chunkNote, countTokens,
  countUnicodeCharacters, embeddingText,
} from '../chunking';
import { validateVector } from '../retrieval';
import { isEligibleNote } from '../authority';
import { IndexFailure, WORKER_MS } from './types';
import type {
  Document, IndexDeps, IndexState, Job, JobResult, JobStatus, Lease, Manifest, Snapshot,
} from './types';
import type { Chunk } from '../types';
import { bindIndexState, fingerprint, parseJob } from './jobs';
import {
  SNAPSHOT_SCHEMA_VERSION, checksum, embeddingInputDigest, policyIdentity, sha256Hex,
  validateSnapshot,
} from './snapshot';
import { RagFailure } from '../types';

/** Cohere embed accepts at most 96 texts per call; one reservation guards each call. */
export const EMBED_BATCH_LIMIT = 96;

export type IndexWorker = (job: Job, remainingMs?: number) => Promise<JobResult>;

/** Internal control flow: a safe abort that still has to release the lease. */
class Superseded extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = 'Superseded';
  }
}

type Progress = { stagedVersion: string | null };

type Run = Readonly<{
  deps: IndexDeps;
  now: () => number;
  signal: AbortSignal;
  check: () => void;
  job: Job;
  bound: IndexState;
  fp: string;
  lease: Lease;
  progress: Progress;
}>;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const logEvent = (deps: IndexDeps, metadata: Readonly<Record<string, string | number>>): void => {
  try {
    deps.log?.(metadata);
  } catch {
    // Diagnostics never fail a job.
  }
};

/** Bounds one awaited port call with the shared deadline; the port still owns its own I/O. */
const guard = async <T>(
  operation: Promise<T>,
  signal: AbortSignal,
  check: () => void,
): Promise<T> => {
  check();
  let onAbort: () => void = () => {};
  const expired = new Promise<never>((_, reject) => {
    onAbort = () => reject(new IndexFailure('TIMEOUT', true));
    signal.addEventListener('abort', onAbort, { once: true });
  });
  try {
    const value = await Promise.race([operation, expired]);
    check();
    return value;
  } finally {
    signal.removeEventListener('abort', onAbort);
  }
};

const asFailure = (error: unknown, signal: AbortSignal): IndexFailure => {
  if (signal.aborted) return new IndexFailure('TIMEOUT', true);
  if (error instanceof IndexFailure) return error;
  // Phase 2 helpers fail closed with typed codes; only an expired request is worth a replay.
  if (error instanceof RagFailure) return new IndexFailure(error.code, error.code === 'TIMEOUT');
  return new IndexFailure('PORT_FAILURE', true);
};

const consentAccepted = (state: IndexState): boolean =>
  state.consent.accepted === true && state.consent.version === CONSENT_VERSION;

const preflight = (deps: IndexDeps, text: string): void => {
  const tokens = countTokens(deps.embedding.count, text);
  const characters = countUnicodeCharacters(text);
  if (tokens > MAX_EMBEDDING_TOKENS || characters > MAX_EMBEDDING_CHARACTERS) {
    throw new IndexFailure('INPUT_TOO_LONG', false);
  }
};

const requireProducedVector = (vector: unknown): readonly number[] => {
  if (!Array.isArray(vector)) throw new IndexFailure('INVALID_PROVIDER_OUTPUT', false);
  try {
    validateVector(vector);
  } catch {
    throw new IndexFailure('INVALID_PROVIDER_OUTPUT', false);
  }
  return vector;
};

const requireStoredVector = (vector: unknown): readonly number[] => {
  if (!Array.isArray(vector)) throw new IndexFailure('INDEX_NOT_READY', false);
  try {
    validateVector(vector);
  } catch {
    throw new IndexFailure('INDEX_NOT_READY', false);
  }
  return vector;
};

/** Re-read the store and demand the exact bound fingerprint (epoch and consent generation included). */
const reread = async (run: Run): Promise<void> => {
  run.check();
  const latest = await guard(
    run.deps.store.load(run.job.ownerId, run.signal),
    run.signal,
    run.check,
  );
  if (fingerprint(latest) !== run.fp) throw new Superseded('SOURCE_CHANGED');
};

/** Vector-float reuse from the previous published snapshot: same policy, title, text digest. */
const loadReuse = async (
  run: Run,
  chunks: readonly Chunk[],
  policyId: string,
): Promise<ReadonlyMap<string, readonly number[]>> => {
  const { deps, bound, signal, check } = run;
  const samples = new Map<string, Readonly<{ title: string; text: string }>>();
  for (const chunk of chunks) {
    const digest = embeddingInputDigest(chunk.title, chunk.text);
    if (!samples.has(digest)) samples.set(digest, { title: chunk.title, text: chunk.text });
  }
  const reused = new Map<string, readonly number[]>();
  const previous = bound.manifest;
  if (previous === null || samples.size === 0) return reused;
  let stored: Snapshot;
  try {
    stored = validateSnapshot(await guard(deps.artifacts.read(previous, signal), signal, check));
  } catch (error) {
    if (signal.aborted || (error instanceof IndexFailure && error.retryable)) throw error;
    // A missing/corrupt previous artifact only means "rebuild", never "invent a vector".
    logEvent(deps, { event: 'index.reuse.skipped', ownerId: bound.ownerId, version: previous.version });
    return reused;
  }
  // Policy drift means every score would be stale: rebuild with current embeddings.
  if (stored.policyIdentity !== policyId) return reused;

  const wanted = new Map<string, string>();
  for (const document of stored.documents) {
    const sample = samples.get(document.embeddingDigest);
    if (sample === undefined || wanted.has(document.embeddingDigest)) continue;
    if (document.chunk.title !== sample.title || document.chunk.text !== sample.text) continue;
    wanted.set(document.embeddingDigest, document.vectorKey);
  }
  if (wanted.size === 0) return reused;
  const keys = [...wanted.values()];
  const fetched = await guard(deps.artifacts.getVectors(keys, signal), signal, check);
  for (const [digest, key] of wanted) {
    const vector = fetched.get(key);
    if (vector === undefined) throw new IndexFailure('INDEX_NOT_READY', false);
    reused.set(digest, requireStoredVector(vector));
  }
  return reused;
};

const embedMissing = async (
  run: Run,
  chunks: readonly Chunk[],
  reused: ReadonlyMap<string, readonly number[]>,
): Promise<ReadonlyMap<string, readonly number[]>> => {
  const { deps, signal, check } = run;
  const samples = new Map<string, string>();
  for (const chunk of chunks) {
    const digest = embeddingInputDigest(chunk.title, chunk.text);
    if (!reused.has(digest) && !samples.has(digest)) samples.set(digest, embeddingText(chunk));
  }
  const pending = [...samples.entries()].map(([digest, text]) => ({ digest, text }));
  const embedded = new Map<string, readonly number[]>();
  for (let offset = 0; offset < pending.length; offset += EMBED_BATCH_LIMIT) {
    const batch = pending.slice(offset, offset + EMBED_BATCH_LIMIT);
    for (const entry of batch) preflight(deps, entry.text);
    check();
    await reread(run);
    // Budget is reserved before every paid call; the store decides the shared allowance.
    await guard(deps.store.reserveEmbedding(run.bound.ownerId, signal), signal, check);
    // The reservation is async: re-read the canonical state once more before the paid embed so a
    // consent/epoch/protection/text change that landed during the reservation cannot be embedded.
    await reread(run);
    const produced = await guard(
      deps.embedding.embed(batch.map((entry) => entry.text), 'search_document', signal, () => reread(run)),
      signal,
      check,
    );
    if (!Array.isArray(produced) || produced.length !== batch.length) {
      throw new IndexFailure('INVALID_PROVIDER_OUTPUT', false);
    }
    for (let index = 0; index < batch.length; index += 1) {
      embedded.set(batch[index].digest, requireProducedVector(produced[index]));
    }
  }
  return embedded;
};

/** Staged documents for the whole eligible account; no embedding runs without consent. */
const buildCorpus = async (
  run: Run,
  consentOk: boolean,
): Promise<Readonly<{ documents: readonly Document[]; vectors: ReadonlyMap<string, readonly number[]> }>> => {
  const { deps, bound } = run;
  if (!consentOk) return { documents: Object.freeze([]), vectors: new Map() };
  const chunks: Chunk[] = [];
  for (const note of bound.notes) {
    if (!isEligibleNote(note, bound.ownerId)) continue;
    for (const chunk of chunkNote(note, deps.embedding.count)) chunks.push(chunk);
  }
  const policyId = policyIdentity();
  const reused = await loadReuse(run, chunks, policyId);
  const embedded = await embedMissing(run, chunks, reused);
  const version = run.lease.token;
  const documents: Document[] = [];
  const vectors = new Map<string, readonly number[]>();
  for (const chunk of chunks) {
    const digest = embeddingInputDigest(chunk.title, chunk.text);
    const vector = reused.get(digest) ?? embedded.get(digest);
    if (vector === undefined) throw new IndexFailure('INVALID_STATE', false);
    const vectorKey = sha256Hex(
      JSON.stringify([bound.ownerId, chunk.noteId, chunk.revision, chunk.chunkId, version, policyId]),
    );
    if (vectors.has(vectorKey)) throw new IndexFailure('INVALID_STATE', false);
    vectors.set(vectorKey, vector);
    documents.push(Object.freeze({
      chunk: Object.freeze({ ...chunk }),
      vectorKey,
      embeddingDigest: digest,
    }));
  }
  return { documents: Object.freeze(documents), vectors };
};

/** Store the lease even when the job failed; a lost release is fenced by lease expiry. */
const release = async (
  deps: IndexDeps,
  now: () => number,
  job: Job | null,
  lease: Lease,
  status: JobStatus,
  code: string,
): Promise<void> => {
  if (job === null) return;
  try {
    await deps.store.finish(job.ownerId, lease, status, code, now(), AbortSignal.timeout(2000));
  } catch {
    logEvent(deps, { event: 'index.lease.release.failed', ownerId: job.ownerId, status });
  }
};

const stageAndPublish = async (run: Run): Promise<JobResult> => {
  const { deps, bound, lease, job, progress, signal, check, now } = run;
  const consentOk = consentAccepted(bound);
  const policyId = policyIdentity();
  const { documents, vectors } = await buildCorpus(run, consentOk);
  const version = lease.token;
  const snapshot = validateSnapshot({
    schemaVersion: SNAPSHOT_SCHEMA_VERSION,
    ownerId: bound.ownerId,
    version,
    consentGeneration: bound.consent.generation,
    accountEpoch: bound.accountEpoch,
    policyIdentity: policyId,
    documents,
  });
  const expectedChecksum = checksum(snapshot);

  // Staged snapshot inventories keys for recovery; only the final manifest makes it visible.
  progress.stagedVersion = version;
  const written = await guard(deps.artifacts.put(snapshot, signal), signal, check);
  if (
    !isRecord(written) || typeof written['key'] !== 'string' || written['key'].length === 0 ||
    written['checksum'] !== expectedChecksum
  ) {
    throw new IndexFailure('ARTIFACT_WRITE_FAILED', false);
  }

  await guard(deps.artifacts.putVectors(snapshot, vectors, signal), signal, check);

  const manifest: Manifest = Object.freeze({
    ownerId: bound.ownerId,
    generation: (bound.manifest?.generation ?? 0) + 1,
    version,
    fingerprint: run.fp,
    consentGeneration: bound.consent.generation,
    accountEpoch: bound.accountEpoch,
    status: consentOk ? 'READY' : 'BLOCKED',
    snapshotKey: written['key'],
    checksum: expectedChecksum,
    policyIdentity: policyId,
  });

  await reread(run);
  const published = await guard(
    deps.store.publish(bound, lease, manifest, now(), signal),
    signal,
    check,
  );
  // A rejected CAS means another worker owns the truth; the staged prefix stays for backfill.
  if (published !== true) throw new Superseded('PUBLISH_REJECTED');
  // The staged version is now the current manifest: it must never be treated as an orphan.
  progress.stagedVersion = null;

  // The manifest is current and ready: only the previous generation's namespace is removed.
  if (bound.manifest !== null) {
    try {
      await guard(deps.artifacts.cleanup(bound.manifest, signal), signal, check);
    } catch (error) {
      if (signal.aborted) throw error;
      logEvent(deps, { event: 'index.cleanup.failed', ownerId: job.ownerId, version });
      await release(deps, now, job, lease, 'FAILED', 'CLEANUP_FAILED');
      return { status: 'FAILED', code: 'CLEANUP_FAILED', manifestVersion: version };
    }
  }

  const status: JobStatus = consentOk ? 'SUCCEEDED' : 'BLOCKED';
  const code = consentOk ? 'READY' : 'CONSENT_REQUIRED';
  await guard(deps.store.finish(job.ownerId, lease, status, code, now(), signal), signal, check);
  logEvent(deps, {
    event: 'index.published', ownerId: job.ownerId, status, version,
    documents: snapshot.documents.length,
  });
  return { status: consentOk ? 'SUCCEEDED' : 'BLOCKED', code, manifestVersion: version };
};

const settleFailure = async (
  deps: IndexDeps,
  now: () => number,
  signal: AbortSignal,
  job: Job | null,
  lease: Lease | null,
  progress: Progress,
  error: unknown,
): Promise<JobResult> => {
  if (progress.stagedVersion !== null) {
    // Orphans are retained and flagged for backfill; deleting could hit an active prefix.
    logEvent(deps, {
      event: 'index.orphan.staged',
      ownerId: job?.ownerId ?? 'unknown',
      version: progress.stagedVersion,
    });
  }
  if (error instanceof Superseded) {
    if (lease !== null) await release(deps, now, job, lease, 'SUPERSEDED', error.code);
    logEvent(deps, { event: 'index.superseded', code: error.code, ownerId: job?.ownerId ?? 'unknown' });
    return { status: 'SUPERSEDED', code: error.code };
  }
  const failure = asFailure(error, signal);
  if (lease !== null) await release(deps, now, job, lease, 'FAILED', failure.code);
  if (failure.retryable) throw failure;
  logEvent(deps, { event: 'index.failed', code: failure.code, ownerId: job?.ownerId ?? 'unknown' });
  return { status: 'FAILED', code: failure.code };
};

const runJob = async (deps: IndexDeps, now: () => number, value: unknown, remainingMs = WORKER_MS - 10_000): Promise<JobResult> => {
  const controller = new AbortController();
  const signal = controller.signal;
  const budgetMs = Math.min(WORKER_MS - 10_000, remainingMs);
  const end = now() + budgetMs;
  const timer = setTimeout(() => controller.abort(), budgetMs);
  const check = (): void => {
    if (signal.aborted || now() >= end) {
      controller.abort();
      throw new IndexFailure('TIMEOUT', true);
    }
  };
  const progress: Progress = { stagedVersion: null };
  let job: Job | null = null;
  let lease: Lease | null = null;
  try {
    job = parseJob(value);
    logEvent(deps, { event: 'index.started', eventId: job.eventId, ownerId: job.ownerId,
      kind: job.kind, revisionHint: job.sourceRevisionHint ?? 0 });
    check();
    const loaded = await guard(deps.store.load(job.ownerId, signal), signal, check);
    const bound = bindIndexState(loaded, job.ownerId);
    const fp = fingerprint(bound);
    // The published manifest already describes this exact canonical input: nothing to pay for.
    if (bound.manifest !== null && bound.manifest.fingerprint === fp) {
      logEvent(deps, { event: 'index.lease.unavailable', ownerId: job.ownerId, alreadyDone: 1 });
      return { status: 'SUPERSEDED', code: 'ALREADY_DONE' };
    }
    lease = await guard(deps.store.acquire(bound, fp, now(), signal), signal, check);
    if (lease === null) {
      const done = bound.manifest?.fingerprint === fp;
      logEvent(deps, { event: 'index.lease.unavailable', ownerId: job.ownerId, alreadyDone: done ? 1 : 0 });
      return { status: 'SUPERSEDED', code: done ? 'ALREADY_DONE' : 'LEASE_BUSY' };
    }
    return await stageAndPublish({
      deps, now, signal, check, job, bound, fp, lease, progress,
    });
  } catch (error) {
    return await settleFailure(deps, now, signal, job, lease, progress, error);
  } finally {
    clearTimeout(timer);
  }
};

export function createIndexWorker(deps: IndexDeps): IndexWorker {
  if (!isRecord(deps) || !isRecord(deps.store) || !isRecord(deps.artifacts) || !isRecord(deps.embedding)) {
    throw new IndexFailure('INVALID_STATE', false);
  }
  const now = deps.now ?? Date.now;
  return async (job: Job, remainingMs?: number): Promise<JobResult> => runJob(deps, now, job, remainingMs);
}
