/**
 * DynamoDB Stream -> indexing job normalization and the canonical state fingerprint.
 *
 * The stream is a change *hint*, never an authority. This module reads only the record keys
 * (`ownerId`, `noteId`), the event name, the event id and `NewImage.revision`. Note text,
 * protection flags, projections and any caller-supplied actor are ignored, so a forged
 * payload cannot move ownership or scope. The Lambda event source owns the trusted source
 * ARN check; the records handed here are already trusted to come from the notes table.
 *
 * Relevant rows are `NOTE#<noteId>` and `PROTECTION#<noteId>` (the same note job: either
 * changes the eligible text or its protection status) and `RAG#CONSENT` (one account job).
 * `META#`/`MUTATION#`/`CHANGE#`/`EVENT#`/`SHARED#` and every worker-owned `RAG#` row other
 * than consent are ignored, so the worker cannot re-trigger itself. Duplicate owner/note
 * jobs coalesce, and an account job supersedes the note jobs of the same owner because the
 * worker reconciles the latest canonical account either way.
 */
import type { DynamoDBStreamEvent } from 'aws-lambda';
import { JOB_POLICY_VERSION, IndexFailure } from './types';
import type { IndexNote, IndexState, Job, Manifest } from './types';
import { isValidIdentifier } from '../contract';
import { isSafeInteger, isWellFormed } from '../chunking';
import { embeddingInputDigest, policyIdentity, sha256Hex, validateManifest } from './snapshot';

export const OWNER_KEY_PREFIX = 'OWNER#';
export const NOTE_KEY_PREFIX = 'NOTE#';
export const PROTECTION_KEY_PREFIX = 'PROTECTION#';
export const CONSENT_SORT_KEY = 'RAG#CONSENT';
/** Domain tag so the fingerprint can never be confused with a snapshot/vector digest. */
export const FINGERPRINT_DOMAIN = 'rag-index-fingerprint.v1';

const JOB_KEYS = [
  'jobVersion', 'kind', 'ownerId', 'noteId', 'sourceRevisionHint', 'policyVersion', 'eventId',
] as const;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const hasExactKeys = (value: Record<string, unknown>, required: readonly string[]): boolean =>
  Object.keys(value).length === required.length &&
  required.every((key) => Object.prototype.hasOwnProperty.call(value, key));

const invalidJob: () => never = () => {
  throw new IndexFailure('INVALID_JOB', false);
};

const invalidState: () => never = () => {
  throw new IndexFailure('INVALID_STATE', false);
};

/** Exact job shape, identifier semantics and safe-integer revision hints. */
export function parseJob(value: unknown): Job {
  if (!isRecord(value) || !hasExactKeys(value, JOB_KEYS)) invalidJob();
  if (value['jobVersion'] !== 1) invalidJob();
  const kind = value['kind'];
  if (kind !== 'RECONCILE_NOTE' && kind !== 'RECONCILE_ACCOUNT') invalidJob();
  const ownerId = value['ownerId'];
  if (!isValidIdentifier(ownerId)) invalidJob();
  const noteId = value['noteId'];
  if (kind === 'RECONCILE_NOTE') {
    if (!isValidIdentifier(noteId)) invalidJob();
  } else if (noteId !== null) {
    invalidJob();
  }
  const hint = value['sourceRevisionHint'];
  if (hint !== null && (!isSafeInteger(hint) || hint < 1)) invalidJob();
  if (kind === 'RECONCILE_ACCOUNT' && hint !== null) invalidJob();
  if (value['policyVersion'] !== JOB_POLICY_VERSION) invalidJob();
  const eventId = value['eventId'];
  if (!isValidIdentifier(eventId)) invalidJob();
  return Object.freeze({
    jobVersion: 1,
    kind,
    ownerId,
    noteId: kind === 'RECONCILE_NOTE' ? (noteId as string) : null,
    sourceRevisionHint: hint === null ? null : (hint as number),
    policyVersion: JOB_POLICY_VERSION,
    eventId,
  });
}

export type RecordDisposition =
  | Readonly<{ kind: 'EXCLUDED' }>
  | Readonly<{ kind: 'MALFORMED' }>
  | Readonly<{ kind: 'JOB'; job: Job }>;

const EXCLUDED: RecordDisposition = Object.freeze({ kind: 'EXCLUDED' });
const MALFORMED: RecordDisposition = Object.freeze({ kind: 'MALFORMED' });

const attributeString = (value: unknown): string | null =>
  isRecord(value) && typeof value['S'] === 'string' ? value['S'] : null;

const attributeNumber = (value: unknown): number | null =>
  isRecord(value) && typeof value['N'] === 'string' && value['N'].trim() !== ''
    ? Number(value['N'])
    : null;

type Relevance =
  | Readonly<{ kind: 'NOTE'; noteId: string }>
  | Readonly<{ kind: 'ACCOUNT' }>
  | Readonly<{ kind: 'MALFORMED' }>
  | null;

const relevanceOf = (sortKey: string): Relevance => {
  if (sortKey === CONSENT_SORT_KEY) return { kind: 'ACCOUNT' };
  for (const prefix of [NOTE_KEY_PREFIX, PROTECTION_KEY_PREFIX] as const) {
    if (!sortKey.startsWith(prefix)) continue;
    const noteId = sortKey.slice(prefix.length);
    return isValidIdentifier(noteId) ? { kind: 'NOTE', noteId } : { kind: 'MALFORMED' };
  }
  return null;
};

/**
 * Classifies one stream record. Excluded rows are acknowledged silently; a relevant row whose
 * keys/event fields are malformed is a terminal, retry-proof failure the caller must record
 * with typed metadata only.
 */
export function classifyRecord(record: unknown): RecordDisposition {
  if (!isRecord(record)) return EXCLUDED;
  const dynamo = record['dynamodb'];
  if (!isRecord(dynamo)) return EXCLUDED;
  const keys = dynamo['Keys'];
  if (!isRecord(keys)) return EXCLUDED;
  const sortKey = attributeString(keys['noteId']);
  if (sortKey === null) return EXCLUDED;
  const relevance = relevanceOf(sortKey);
  if (relevance === null) return EXCLUDED;
  if (relevance.kind === 'MALFORMED') return MALFORMED;

  const eventName = record['eventName'];
  if (eventName !== 'INSERT' && eventName !== 'MODIFY' && eventName !== 'REMOVE') return MALFORMED;
  const ownerKey = attributeString(keys['ownerId']);
  if (ownerKey === null || !ownerKey.startsWith(OWNER_KEY_PREFIX)) return MALFORMED;
  const ownerId = ownerKey.slice(OWNER_KEY_PREFIX.length);
  if (!isValidIdentifier(ownerId)) return MALFORMED;
  const eventId = record['eventID'];
  if (!isValidIdentifier(eventId)) return MALFORMED;

  if (relevance.kind === 'ACCOUNT') {
    return Object.freeze({
      kind: 'JOB',
      job: parseJob({
        jobVersion: 1, kind: 'RECONCILE_ACCOUNT', ownerId, noteId: null,
        sourceRevisionHint: null, policyVersion: JOB_POLICY_VERSION, eventId,
      }),
    });
  }

  let hint: number | null = null;
  if (eventName !== 'REMOVE') {
    const newImage = dynamo['NewImage'];
    if (isRecord(newImage) && newImage['revision'] !== undefined) {
      const revision = attributeNumber(newImage['revision']);
      if (!isSafeInteger(revision) || revision < 1) return MALFORMED;
      hint = revision;
    }
  }
  return Object.freeze({
    kind: 'JOB',
    job: parseJob({
      jobVersion: 1, kind: 'RECONCILE_NOTE', ownerId, noteId: relevance.noteId,
      sourceRevisionHint: hint, policyVersion: JOB_POLICY_VERSION, eventId,
    }),
  });
}

const jobKey = (job: Job): string => `${job.kind}\u0000${job.ownerId}\u0000${job.noteId ?? ''}`;

/** Coalesced jobs for one stream batch: account jobs supersede the same owner's note jobs. */
export function jobsFromStream(event: DynamoDBStreamEvent): readonly Job[] {
  const records = isRecord(event) && Array.isArray((event as { Records?: unknown }).Records)
    ? ((event as { Records: unknown[] }).Records)
    : [];
  const accounts: Job[] = [];
  const notes: Job[] = [];
  const seen = new Set<string>();
  const accountOwners = new Set<string>();
  for (const record of records) {
    const disposition = classifyRecord(record);
    if (disposition.kind !== 'JOB') continue;
    const job = disposition.job;
    const key = jobKey(job);
    if (seen.has(key)) continue;
    seen.add(key);
    if (job.kind === 'RECONCILE_ACCOUNT') {
      accounts.push(job);
      accountOwners.add(job.ownerId);
    } else {
      notes.push(job);
    }
  }
  return Object.freeze([
    ...accounts,
    ...notes.filter((job) => !accountOwners.has(job.ownerId)),
  ]);
}

const noteIdentity = (note: IndexNote): readonly unknown[] => [
  note.noteId,
  note.revision,
  note.protected === true ? 1 : 0,
  note.protectionRevision,
  note.synced === true ? 1 : 0,
  note.deleted === true ? 1 : 0,
  note.available === true ? 1 : 0,
  note.incomingShared === true ? 1 : 0,
  embeddingInputDigest(note.title, note.content),
];

const deepFreeze = <T>(value: T): T => {
  if (value !== null && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const key of Object.keys(value)) deepFreeze((value as Record<string, unknown>)[key]);
  }
  return value;
};

const validateNote = (entry: unknown, ownerId: string): IndexNote => {
  if (!isRecord(entry) || entry['ownerId'] !== ownerId) invalidState();
  if (!isValidIdentifier(entry['noteId'])) invalidState();
  if (!isSafeInteger(entry['revision']) || (entry['revision'] as number) < 1) invalidState();
  const protectionRevision = entry['protectionRevision'];
  if (!isSafeInteger(protectionRevision) || (protectionRevision as number) < 0) invalidState();
  for (const flag of ['synced', 'protected', 'deleted', 'available'] as const) {
    if (typeof entry[flag] !== 'boolean') invalidState();
  }
  if (entry['incomingShared'] !== undefined && typeof entry['incomingShared'] !== 'boolean') {
    invalidState();
  }
  if (typeof entry['title'] !== 'string' || !isWellFormed(entry['title'])) invalidState();
  if (typeof entry['content'] !== 'string' || !isWellFormed(entry['content'])) invalidState();
  return Object.freeze({
    ownerId,
    noteId: entry['noteId'] as string,
    revision: entry['revision'] as number,
    title: entry['title'],
    content: entry['content'],
    synced: entry['synced'] === true,
    protected: entry['protected'] === true,
    deleted: entry['deleted'] === true,
    available: entry['available'] === true,
    ...(entry['incomingShared'] === true ? { incomingShared: true } : {}),
    protectionRevision: protectionRevision as number,
  });
};

/**
 * Fail-closed canonical state guard: the returned view is a frozen clone, so nothing that was
 * bound to a lease or hashed into a fingerprint can change underneath the job. A foreign owner,
 * a missing/NaN/negative field, an incoherent flag or a duplicate note is terminal
 * INVALID_STATE — the worker never guesses what the canonical state "probably" was.
 */
export function bindIndexState(value: unknown, ownerId: string): IndexState {
  if (!isRecord(value) || !isValidIdentifier(ownerId) || value['ownerId'] !== ownerId) invalidState();
  const accountEpoch = value['accountEpoch'];
  if (!isSafeInteger(accountEpoch) || (accountEpoch as number) < 0) invalidState();
  const consent = value['consent'];
  if (!isRecord(consent) || typeof consent['accepted'] !== 'boolean') invalidState();
  const consentVersion = consent['version'];
  if (typeof consentVersion !== 'string' || !isWellFormed(consentVersion)) invalidState();
  const consentGeneration = consent['generation'];
  if (!isSafeInteger(consentGeneration) || (consentGeneration as number) < 0) invalidState();
  const rawManifest = value['manifest'];
  let manifest: Manifest | null = null;
  if (rawManifest !== null) {
    try {
      manifest = validateManifest(rawManifest, ownerId);
    } catch {
      invalidState();
    }
  }
  const rawNotes = value['notes'];
  if (!Array.isArray(rawNotes)) invalidState();
  const notes: IndexNote[] = [];
  const seen = new Set<string>();
  for (const entry of rawNotes) {
    const note = validateNote(entry, ownerId);
    if (seen.has(note.noteId)) invalidState();
    seen.add(note.noteId);
    notes.push(note);
  }
  notes.sort((left, right) => (left.noteId < right.noteId ? -1 : left.noteId > right.noteId ? 1 : 0));
  return deepFreeze({
    ownerId,
    accountEpoch: accountEpoch as number,
    consent: {
      accepted: consent['accepted'] === true,
      version: consentVersion,
      generation: consentGeneration as number,
    },
    notes,
    manifest,
  });
}

/**
 * Fingerprint of the canonical input that decides an index rebuild: owner, account epoch,
 * consent state, every note identity/revision/protection/status and its embedding-input
 * digest, plus the full policy identity. Raw text never appears, only digests.
 */
export function fingerprint(state: IndexState): string {
  const raw: unknown = state;
  const ownerId = isRecord(raw) ? raw['ownerId'] : undefined;
  if (!isValidIdentifier(ownerId)) invalidState();
  const bound = bindIndexState(raw, ownerId);
  return sha256Hex(JSON.stringify([
    FINGERPRINT_DOMAIN,
    bound.ownerId,
    bound.accountEpoch,
    bound.consent.accepted === true ? 1 : 0,
    bound.consent.version,
    bound.consent.generation,
    bound.notes.map(noteIdentity),
    policyIdentity(),
  ]));
}
