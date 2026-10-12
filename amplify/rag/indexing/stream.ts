/**
 * DynamoDB Stream entry point for the indexing worker.
 *
 * The handler never acknowledges a whole batch opaquely and never invents work: each record is
 * classified (relevant job, ignored row, or a relevant but malformed row), identical owner/job
 * pairs coalesce, and an account job absorbs the note records of the same owner. A retryable
 * failure is reported as `batchItemFailures` under the *earliest* SequenceNumber of every
 * original record that fed that job, because AWS replays from that point and may replay already
 * successful records — the worker's lease/fingerprint idempotency makes that replay safe.
 *
 * Terminal outcomes (worker `FAILED`, malformed relevant records, non-retryable port errors)
 * are acknowledged and recorded as typed metadata only: no raw content, keys or payloads.
 * Excluded rows are acknowledged silently, which is what keeps the worker's own `RAG#` rows
 * from re-triggering it. A manual/backfill invocation funnels the same raw value through the
 * same worker path, which parses it; the parent Lambda owns the trusted IAM source.
 */
import type { DynamoDBStreamEvent } from 'aws-lambda';
import { WORKER_MS, IndexFailure } from './types';
import type { Job, JobResult } from './types';
import { classifyRecord } from './jobs';
import type { IndexWorker } from './worker';

export type StreamLog = (metadata: Readonly<Record<string, string | number>>) => void;
export type BatchItemFailure = Readonly<{ itemIdentifier: string }>;
export type StreamResult = Readonly<{ batchItemFailures: readonly BatchItemFailure[] }>;

type Group = { job: Job; sequences: string[] };

const jobGroupKey = (job: Job): string => `${job.kind}\u0000${job.ownerId}\u0000${job.noteId ?? ''}`;

const sequenceOf = (record: unknown): string | null => {
  if (record === null || typeof record !== 'object') return null;
  const dynamo = (record as { dynamodb?: unknown }).dynamodb;
  if (dynamo === null || typeof dynamo !== 'object') return null;
  const sequence = (dynamo as { SequenceNumber?: unknown }).SequenceNumber;
  return typeof sequence === 'string' && sequence.length > 0 ? sequence : null;
};

/** Earliest sequence number in numeric order; DynamoDB sequence numbers exceed 2^53. */
const earliestSequence = (sequences: readonly string[]): string | null => {
  let earliest: string | null = null;
  for (const sequence of sequences) {
    if (earliest === null) {
      earliest = sequence;
      continue;
    }
    try {
      if (BigInt(sequence) < BigInt(earliest)) earliest = sequence;
    } catch {
      if (sequence < earliest) earliest = sequence;
    }
  }
  return earliest;
};

const emit = (log: StreamLog | undefined, metadata: Readonly<Record<string, string | number>>): void => {
  try {
    log?.(metadata);
  } catch {
    // Diagnostics never fail the batch.
  }
};

/** Runs one job and reports whether the batch must replay it, plus the typed failure code. */
const outcomeOf = (result: JobResult | null, thrown: unknown): Readonly<{ replay: boolean; code: string }> => {
  if (thrown !== null) {
    if (thrown instanceof IndexFailure && !thrown.retryable) return { replay: false, code: thrown.code };
    if (thrown instanceof IndexFailure) return { replay: true, code: thrown.code };
    return { replay: true, code: 'PORT_FAILURE' };
  }
  if (result?.code === 'LEASE_BUSY') return { replay: true, code: result.code };
  if (result !== null && result.status === 'FAILED') return { replay: false, code: result.code };
  return { replay: false, code: '' };
};

export function createStreamHandler(
  worker: IndexWorker,
  log?: StreamLog,
): (event: DynamoDBStreamEvent) => Promise<StreamResult> {
  if (typeof worker !== 'function') throw new TypeError('index worker is required');
  return async (event: DynamoDBStreamEvent): Promise<StreamResult> => {
    const deadline = Date.now() + WORKER_MS - 10_000;
    const records = event !== null && typeof event === 'object' && Array.isArray(event.Records)
      ? (event.Records as readonly unknown[])
      : [];
    const groups = new Map<string, Group>();
    const order: Group[] = [];
    for (const record of records) {
      const disposition = classifyRecord(record);
      if (disposition.kind === 'EXCLUDED') continue;
      const sequence = sequenceOf(record);
      if (disposition.kind === 'MALFORMED') {
        // Retrying cannot repair a malformed row: acknowledge it and keep typed evidence.
        emit(log, {
          event: 'index.stream.rejected',
          code: 'INVALID_JOB',
          ...(sequence === null ? {} : { sequenceNumber: sequence }),
        });
        continue;
      }
      const key = jobGroupKey(disposition.job);
      let group = groups.get(key);
      if (group === undefined) {
        group = { job: disposition.job, sequences: [] };
        groups.set(key, group);
        order.push(group);
      }
      if (sequence !== null) group.sequences.push(sequence);
    }

    // An account job reconciles the whole owner, so the note records of that owner fold in.
    const accounts = new Map<string, Group>();
    for (const group of order) {
      if (group.job.kind === 'RECONCILE_ACCOUNT') accounts.set(group.job.ownerId, group);
    }
    const active: Group[] = [];
    for (const group of order) {
      if (group.job.kind === 'RECONCILE_ACCOUNT') {
        active.push(group);
        continue;
      }
      const account = accounts.get(group.job.ownerId);
      if (account !== undefined) {
        account.sequences.push(...group.sequences);
        continue;
      }
      active.push(group);
    }

    const failures: BatchItemFailure[] = [];
    for (const group of active) {
      let result: JobResult | null = null;
      let thrown: unknown = null;
      try {
        const remainingMs = deadline - Date.now();
        if (remainingMs <= 0) throw new IndexFailure('TIMEOUT', true);
        result = await worker(group.job, remainingMs);
      } catch (error) {
        thrown = error;
      }
      const outcome = outcomeOf(result, thrown);
      if (!outcome.replay) {
        if (outcome.code !== '') {
          emit(log, {
            event: 'index.stream.terminal',
            code: outcome.code,
            ownerId: group.job.ownerId,
            ...(group.job.noteId === null ? {} : { noteId: group.job.noteId }),
          });
        }
        continue;
      }
      const earliest = earliestSequence(group.sequences);
      if (earliest === null) {
        // A failing job with no usable sequence number cannot be addressed for replay.
        emit(log, { event: 'index.stream.unmapped', code: outcome.code, ownerId: group.job.ownerId });
        continue;
      }
      emit(log, {
        event: 'index.stream.replay',
        code: outcome.code,
        ownerId: group.job.ownerId,
        sequenceNumber: earliest,
      });
      failures.push(Object.freeze({ itemIdentifier: earliest }));
    }
    return Object.freeze({ batchItemFailures: Object.freeze(failures) });
  };
}

/**
 * Manual/backfill invocation: the raw value goes through the same worker path, so `parseJob`
 * validates the identifier and safe-integer semantics before anything is loaded. Retryable
 * failures are rethrown to the caller, which owns the retry decision for a manual run.
 */
export async function runManualJob(
  worker: IndexWorker,
  value: unknown,
  log?: StreamLog,
): Promise<JobResult> {
  try {
    return await worker(value as Job);
  } catch (error) {
    const failure = error instanceof IndexFailure ? error : new IndexFailure('PORT_FAILURE', true);
    emit(log, {
      event: 'index.manual.failed',
      code: failure.code,
      retryable: failure.retryable ? 1 : 0,
    });
    throw failure;
  }
}
