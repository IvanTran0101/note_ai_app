/**
 * Phase 5 pilot indexing-worker adapter (plan 5.3B): the only new indexing surface for the
 * bounded synthetic pilot. It adds no job algorithm: it validates one stream batch's trust and
 * pilot scope, then reuses the existing `createStreamHandler`/`runManualJob` over the real
 * `createIndexWorker` and the guarded `createPilotIndexStore`.
 *
 * The stream payload stays a hint, never an authority. Every record must carry the exact
 * configured `eventSourceARN` and `eventSource: 'aws:dynamodb'` before any record field is read;
 * then only the Keys of a listed Cognito owner with an approved `NOTE#`/`PROTECTION#` note id (or
 * the one `RAG#CONSENT` account row) are selected. Original records and SequenceNumbers are
 * forwarded unchanged, so coalescing and earliest-sequence partial failures keep their existing
 * semantics. A non-member or unapproved row is skipped before `store.load`, so it can never reach
 * canonical text, an embedding or a publish; `NewImage` text is never read or logged here.
 *
 * Every invocation reads the trusted `CONFIG#PHASE5`/`PILOT` row again and builds a new guarded
 * store and worker, so a warm invocation can never reuse a previous invocation's captured config,
 * consent or authority. Only the raw SDK clients/tokenizers behind `runtime()` may be cached.
 * Logging is routed through a sanitizer that emits hashed owner/note identities and bounded
 * codes/counts only; the legacy logger is left untouched.
 */
import { isValidIdentifier } from '../contract';
import { createIndexWorker } from '../indexing/worker';
import type { IndexWorker } from '../indexing/worker';
import { createStreamHandler, remainingUntil, runManualJob, WORKER_MARGIN_MS } from '../indexing/stream';
import type { StreamLog } from '../indexing/stream';
import {
  CONSENT_SORT_KEY, NOTE_KEY_PREFIX, OWNER_KEY_PREFIX, PROTECTION_KEY_PREFIX, parseJob,
} from '../indexing/jobs';
import { IndexFailure, WORKER_MS } from '../indexing/types';
import type { IndexDeps, IndexStore } from '../indexing/types';
import { sha256Hex } from '../indexing/snapshot';
import type { DynamoDBStreamEvent } from 'aws-lambda';
import { createPilotIndexStore } from './pilot_index_store';
import type { PilotBudget } from './pilot_budget';
import { isCognitoSub } from './pilot_policy';
import { parseRuntimeConfig } from './runtime_config';
import type { RuntimeConfig } from './runtime_config';

/**
 * Recovery is the existing retirement+orphan sweep. It no longer gets a fresh fixed window: the
 * bounded invocation budget (120s cap less the 10s cutoff margin) supplies the remaining timeout,
 * so a cold config/runtime start is charged to the same deadline. Kept exported for the ordered
 * phase5 slice.
 */
export const PILOT_RECOVER_MS = 110_000;

export type PilotRecover = (
  ownerId: string,
  signal: AbortSignal,
  store: IndexStore,
) => Promise<unknown>;

export type PilotWorkerDeps = Readonly<{
  /** Trusted server-only config reader; one strongly consistent read per invocation. */
  readConfig: (signal: AbortSignal) => Promise<RuntimeConfig>;
  /** Lazily returns the raw SDK/tokenizer index; may safely be a cached factory. */
  runtime: () => IndexDeps;
  /** Pilot budget; only the atomic Cohere admission is reached through the guarded store. */
  budget: Pick<PilotBudget, 'acquireCohere'>;
  /** Existing retirement/orphan helpers, bound to the per-invocation guarded store. */
  recover: PilotRecover;
  /** The one configured stream ARN every record must carry exactly. */
  streamArn: string;
  /** Safe bounded metadata sink; defaults to sanitized `console.log`. */
  log?: (metadata: Readonly<Record<string, string | number>>) => void;
  /** Test seam; forwarded into the worker when supplied. */
  now?: () => number;
}>;

/**
 * One invocation. The optional absolute `deadlineAt` (epoch ms) is injected only by trusted
 * composition from the Lambda context's second argument; an event/body/settings value is never
 * consulted. Without one the handler captures the fixed worker budget itself, so a direct call
 * still charges cold config/runtime to a single bounded invocation window.
 */
export type PilotWorkerHandler = (event: unknown, deadlineAt?: number) => Promise<unknown>;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const hasExactKeys = (value: Record<string, unknown>, required: readonly string[]): boolean =>
  Object.keys(value).length === required.length &&
  required.every((key) => Object.prototype.hasOwnProperty.call(value, key));

const attributeString = (value: unknown): string | null =>
  isRecord(value) && typeof value['S'] === 'string' ? value['S'] : null;

/** Every event name the reused worker/stream path can emit, plus this adapter's own. */
const SAFE_EVENTS = new Set([
  'index.started', 'index.published', 'index.failed', 'index.superseded',
  'index.orphan.staged', 'index.reuse.skipped', 'index.cleanup.failed',
  'index.lease.release.failed', 'index.lease.unavailable',
  'index.stream.rejected', 'index.stream.terminal', 'index.stream.replay',
  'index.stream.unmapped', 'index.manual.failed', 'pilot.stream.selected',
]);
const SAFE_STATUSES = new Set(['RUNNING', 'SUCCEEDED', 'SUPERSEDED', 'BLOCKED', 'FAILED']);
const SAFE_KINDS = new Set(['RECONCILE_NOTE', 'RECONCILE_ACCOUNT']);
const SAFE_CODE = /^[A-Z][A-Z0-9_]{0,63}$/;
const SAFE_TOKEN = /^[A-Za-z0-9_-]{1,128}$/;
const SAFE_SEQUENCE = /^\d{1,64}$/;
const COUNT_KEYS = ['alreadyDone', 'revisionHint', 'documents', 'selected', 'dropped'] as const;

const boundedCount = (value: unknown): number | null =>
  typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 ? value : null;

const hashedIdentity = (value: unknown): string | null =>
  isValidIdentifier(value) ? sha256Hex(value) : null;

/**
 * The one log sanitizer for the pilot path. Only hashed identities, allowlisted event/status/kind
 * values, normalized codes, bounded counters and opaque version/sequence tokens survive; every
 * unknown key (an error message, text, title, token or env value) is dropped. An unsafe code is
 * normalized to `UNKNOWN` rather than echoed.
 */
export function sanitizePilotMetadata(
  metadata: Readonly<Record<string, unknown>>,
): Readonly<Record<string, string | number>> {
  const safe: Record<string, string | number> = {};
  const event = metadata['event'];
  if (typeof event === 'string' && SAFE_EVENTS.has(event)) safe['event'] = event;
  if (metadata['code'] !== undefined) {
    const code = metadata['code'];
    safe['code'] = typeof code === 'string' && SAFE_CODE.test(code) ? code : 'UNKNOWN';
  }
  const status = metadata['status'];
  if (typeof status === 'string' && SAFE_STATUSES.has(status)) safe['status'] = status;
  const kind = metadata['kind'];
  if (typeof kind === 'string' && SAFE_KINDS.has(kind)) safe['kind'] = kind;
  const version = metadata['version'];
  if (typeof version === 'string' && SAFE_TOKEN.test(version)) safe['version'] = version;
  const sequence = metadata['sequenceNumber'];
  if (typeof sequence === 'string' && SAFE_SEQUENCE.test(sequence)) safe['sequenceNumber'] = sequence;
  for (const key of COUNT_KEYS) {
    const count = boundedCount(metadata[key]);
    if (count !== null) safe[key] = count;
  }
  const owner = hashedIdentity(metadata['ownerId']);
  if (owner !== null) safe['owner'] = owner;
  const note = hashedIdentity(metadata['noteId']);
  if (note !== null) safe['note'] = note;
  const eventRef = hashedIdentity(metadata['eventId']);
  if (eventRef !== null) safe['eventRef'] = eventRef;
  return Object.freeze(safe);
}

const createSafeLog = (
  sink: ((metadata: Readonly<Record<string, string | number>>) => void) | undefined,
): StreamLog => {
  const target = sink ?? ((metadata: Readonly<Record<string, string | number>>) => console.log(JSON.stringify(metadata)));
  return (metadata: Readonly<Record<string, string | number>>): void => {
    try {
      target(sanitizePilotMetadata(metadata));
    } catch {
      // Diagnostics never fail a job.
    }
  };
};

/** Whole-batch trust check: one bad ARN/eventSource rejects before any record field is read. */
const assertTrustedStream = (records: readonly unknown[], streamArn: string): void => {
  for (const record of records) {
    if (!isRecord(record) || record['eventSourceARN'] !== streamArn || record['eventSource'] !== 'aws:dynamodb') {
      throw new IndexFailure('UNTRUSTED_STREAM', false);
    }
  }
};

const approvedNotes = (config: RuntimeConfig, ownerId: string): ReadonlySet<string> => {
  const list = config.corpus.owners[ownerId];
  const ids = new Set<string>();
  if (list !== undefined) for (const entry of list) ids.add(entry.noteId);
  return ids;
};

/**
 * Keys-only scope filter: a listed owner's approved `NOTE#`/`PROTECTION#` row or their one
 * `RAG#CONSENT` account row. Self-owned `RAG#`/`META#`/`EVENT#`/`CHANGE#`/`MUTATION#`/`SHARED#`
 * rows and every non-member/unapproved row are ignored.
 */
const selectStreamRecord = (config: RuntimeConfig, record: unknown): boolean => {
  if (!isRecord(record)) return false;
  const dynamo = record['dynamodb'];
  if (!isRecord(dynamo)) return false;
  const keys = dynamo['Keys'];
  if (!isRecord(keys)) return false;
  const ownerKey = attributeString(keys['ownerId']);
  const sortKey = attributeString(keys['noteId']);
  if (ownerKey === null || sortKey === null || !ownerKey.startsWith(OWNER_KEY_PREFIX)) return false;
  const ownerId = ownerKey.slice(OWNER_KEY_PREFIX.length);
  if (!isCognitoSub(ownerId) || !Object.prototype.hasOwnProperty.call(config.corpus.owners, ownerId)) {
    return false;
  }
  if (sortKey === CONSENT_SORT_KEY) return true;
  const approved = approvedNotes(config, ownerId);
  for (const prefix of [NOTE_KEY_PREFIX, PROTECTION_KEY_PREFIX] as const) {
    if (sortKey.startsWith(prefix)) return approved.has(sortKey.slice(prefix.length));
  }
  return false;
};

const requireListedOwner = (config: RuntimeConfig, ownerId: unknown): string => {
  if (!isCognitoSub(ownerId) || !Object.prototype.hasOwnProperty.call(config.corpus.owners, ownerId)) {
    throw new IndexFailure('LIVE_POLICY_NOT_CONFIGURED', false);
  }
  return ownerId;
};

const requireApprovedNote = (config: RuntimeConfig, ownerId: string, noteId: unknown): void => {
  if (!isValidIdentifier(noteId) || !approvedNotes(config, ownerId).has(noteId)) {
    throw new IndexFailure('LIVE_POLICY_NOT_CONFIGURED', false);
  }
};

const buildWorker = (
  deps: PilotWorkerDeps,
  config: RuntimeConfig,
  safeLog: StreamLog,
): Readonly<{ store: IndexStore; worker: IndexWorker }> => {
  const raw = deps.runtime();
  if (!isRecord(raw) || !isRecord(raw.store)) throw new IndexFailure('INVALID_STATE', false);
  const store = createPilotIndexStore({
    store: raw.store,
    budget: deps.budget,
    readConfig: deps.readConfig,
    config,
  });
  const worker = createIndexWorker({
    ...raw,
    store,
    log: safeLog,
    ...(deps.now !== undefined ? { now: deps.now } : {}),
  });
  return { store, worker };
};

/**
 * Builds the pilot worker handler over injected ports. The trusted config, guarded store and
 * worker are recreated on every invocation; only the injected `runtime()` may be a cached factory.
 */
export function createPilotWorkerHandler(deps: PilotWorkerDeps): PilotWorkerHandler {
  if (
    !isRecord(deps) ||
    typeof deps['readConfig'] !== 'function' ||
    typeof deps['runtime'] !== 'function' ||
    !isRecord(deps['budget']) ||
    typeof deps['budget']['acquireCohere'] !== 'function' ||
    typeof deps['recover'] !== 'function' ||
    typeof deps['streamArn'] !== 'string' || deps['streamArn'].length === 0 ||
    (deps['log'] !== undefined && typeof deps['log'] !== 'function') ||
    (deps['now'] !== undefined && typeof deps['now'] !== 'function')
  ) {
    throw new IndexFailure('INVALID_STATE', false);
  }
  const safeLog = createSafeLog(deps['log']);

  return async function handle(event: unknown, deadlineAt?: number): Promise<unknown> {
    // Trust first: an untrusted batch is rejected before the config read, so a forged stream can
    // never influence which config or body is loaded.
    const records = isRecord(event) && Array.isArray(event['Records'])
      ? (event['Records'] as readonly unknown[])
      : null;
    if (records !== null) assertTrustedStream(records, deps.streamArn);

    // One absolute invocation deadline for the whole invocation; a missing trusted deadline keeps
    // the fixed 110s worker budget (the 120s cap less the 10s cutoff margin), so cold
    // setup/config time is never reset into a fresh per-stage window. The margin is subtracted
    // exactly once, here at capture; an already-bounded absolute deadline is used as-is.
    const invocationDeadline = deadlineAt ?? Date.now() + WORKER_MS - WORKER_MARGIN_MS;
    const remaining = (): number => remainingUntil(invocationDeadline);
    // Expired already: never read config or dispatch any port at a zero deadline.
    if (remaining() <= 0) throw new IndexFailure('TIMEOUT', true);
    const signal = AbortSignal.timeout(remaining());
    // One shared deadline for config parsing, worker construction and recovery: an aborted
    // timeout signal or a clock that has reached the deadline both mean the step is too late.
    const liveBudget = (): number => {
      const budget = remainingUntil(invocationDeadline);
      if (signal.aborted || budget <= 0) throw new IndexFailure('TIMEOUT', true);
      return budget;
    };

    liveBudget();
    const config = parseRuntimeConfig(await deps.readConfig(signal));
    liveBudget();
    const { store, worker } = buildWorker(deps, config, safeLog);
    liveBudget();

    if (records !== null) {
      const selected = records.filter((record) => selectStreamRecord(config, record));
      safeLog({ event: 'pilot.stream.selected', selected: selected.length, dropped: records.length - selected.length });
      const stream = createStreamHandler(worker, safeLog);
      const original = event as Record<string, unknown>;
      return stream(
        Object.freeze({ ...original, Records: Object.freeze(selected) }) as unknown as DynamoDBStreamEvent,
        invocationDeadline,
      );
    }

    if (!isRecord(event)) throw new IndexFailure('INVALID_JOB', false);
    if (event['operation'] === 'reconcile' && hasExactKeys(event, ['operation', 'job'])) {
      const job = parseJob(event['job']);
      requireListedOwner(config, job.ownerId);
      if (job.kind === 'RECONCILE_NOTE') requireApprovedNote(config, job.ownerId, job.noteId);
      return runManualJob(worker, job, safeLog, invocationDeadline);
    }
    if (event['operation'] === 'recover' && hasExactKeys(event, ['operation', 'ownerId'])) {
      const ownerId = requireListedOwner(config, event['ownerId']);
      // Never dispatch recovery at an expired/zero deadline, and never return its raw value once
      // the deadline is gone: a port that ignores its abort cannot turn a late sweep into success.
      const recoverSignal = AbortSignal.timeout(liveBudget());
      const result = await deps.recover(ownerId, recoverSignal, store);
      if (recoverSignal.aborted) throw new IndexFailure('TIMEOUT', true);
      liveBudget();
      return result;
    }
    throw new IndexFailure('INVALID_JOB', false);
  };
}
