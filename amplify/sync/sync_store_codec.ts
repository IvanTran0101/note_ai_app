import { parseProtectionChange } from './sync_protection_change';
import { decodeShare } from '../sharing/share_models';
import { TransactionCanceledException } from '@aws-sdk/client-dynamodb';
import type { TransactWriteCommandInput } from '@aws-sdk/lib-dynamodb';
import { stableDigest } from './cursor';
import { SyncInvalidMutationError, SyncStorageError } from './sync_store_models';
import type { NoteSnapshot, InvalidMutationReason, NormalizedMutation, ConflictCheck,
  SyncOperation, MutationPayload, SyncMutation } from './sync_store_models';

export const OWNER_KEY_PREFIX = 'OWNER#';
export const META_SORT_KEY = 'META#SYNC';
export const NOTE_SORT_KEY_PREFIX = 'NOTE#';
export const MUTATION_SORT_KEY_PREFIX = 'MUTATION#';
export const CHANGE_SORT_KEY_PREFIX = 'CHANGE#';

/**
 * The change-feed index name. Repeated as a runtime literal because the Lambda
 * bundle cannot import CDK code; keep it in step with `notes_table.ts`.
 */
export const CHANGES_INDEX_NAME = 'ChangesByOwnerSequence';

/** Contract default for `GET /sync/changes` and the page cap the contract fixes. */
export const DEFAULT_CHANGE_LIMIT = 50;
export const MAX_CHANGE_LIMIT = 100;

/** One initial attempt plus at most three retries: contention, not throughput, is the cause. */
export const MAX_ATTEMPTS = 4;

/** One copy of a snapshot must stay well inside DynamoDB's 400 KB item limit. */
export const MAX_PAYLOAD_BYTES = 300_000;
export const MAX_IDENTIFIER_LENGTH = 128;
export const CONTROL_CHARACTERS = /[\u0000-\u001f\u007f]/;
const UTC_TIMESTAMP = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?Z$/;
const isUtcTimestamp = (value: unknown): value is string => {
  if (typeof value !== 'string') return false;
  const parts = UTC_TIMESTAMP.exec(value);
  if (parts === null) return false;
  const parsed = new Date(value);
  return Number.isFinite(parsed.getTime()) &&
    parsed.getUTCFullYear() === Number(parts[1]) &&
    parsed.getUTCMonth() + 1 === Number(parts[2]) &&
    parsed.getUTCDate() === Number(parts[3]) &&
    parsed.getUTCHours() === Number(parts[4]) &&
    parsed.getUTCMinutes() === Number(parts[5]) &&
    parsed.getUTCSeconds() === Number(parts[6]);
};


export const UTF8 = new TextEncoder();

/** Provider-neutral note state; `deletedAt` set means a tombstone. */
export const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

export const errorNameOf = (error: unknown): string =>
  isRecord(error) && typeof error.name === 'string' ? error.name : 'UnknownError';

/**
 * An SDK error the retry loop cannot fix: a bad request, a missing table, or a
 * denied call would fail identically on a second attempt, and reporting it as
 * retryable would only multiply the load.
 */
export const NON_RETRYABLE_ERRORS = new Set([
  'AccessDeniedException',
  'ConditionalCheckFailedException',
  'ItemCollectionSizeLimitExceededException',
  'ResourceNotFoundException',
  'TransactionCanceledException',
  'ValidationException',
]);

export const toStorageError = (error: unknown): SyncStorageError =>
  new SyncStorageError(`DynamoDB ${errorNameOf(error)} while serving the sync request.`, {
    retryable: !NON_RETRYABLE_ERRORS.has(errorNameOf(error)),
    cause: error,
  });

/** Stored data that this slice cannot read: retrying would fail the same way. */
export const corruptData = (): SyncStorageError =>
  new SyncStorageError('Stored sync data is not readable.', { retryable: false });

export const ownerKeyOf = (ownerId: string): string => {
  if (typeof ownerId !== 'string' || ownerId.trim().length === 0) {
    // Unreachable through the handler, which derives the owner from the JWT.
    throw new SyncStorageError('The sync request has no account owner.', { retryable: false });
  }
  return `${OWNER_KEY_PREFIX}${ownerId}`;
};

export const itemKey = (ownerKey: string, sortKey: string): Record<string, string> => ({
  ownerId: ownerKey,
  noteId: sortKey,
});

export const cleanIdentifier = (
  value: unknown,
  reason: InvalidMutationReason,
  message: string,
): string => {
  if (
    typeof value !== 'string' ||
    value.trim().length === 0 ||
    value.length > MAX_IDENTIFIER_LENGTH ||
    CONTROL_CHARACTERS.test(value)
  ) {
    throw new SyncInvalidMutationError(reason, message);
  }
  return value;
};

export const normalizePayload = (operation: SyncOperation, payload: unknown): MutationPayload | null => {
  if (operation === 'delete') {
    return null;
  }
  if (!isRecord(payload)) {
    throw new SyncInvalidMutationError('PAYLOAD_REQUIRED', 'create and update need a title and content payload.');
  }
  const { title, content } = payload;
  if (
    typeof title !== 'string' ||
    typeof content !== 'string' ||
    title.trim().length === 0 ||
    content.trim().length === 0
  ) {
    throw new SyncInvalidMutationError('PAYLOAD_INVALID', 'A payload needs a string title and content.');
  }
  const hasPinnedAt = Object.prototype.hasOwnProperty.call(payload, 'pinnedAt');
  const pinnedAt = payload.pinnedAt;
  if (
    hasPinnedAt &&
    pinnedAt !== null && !isUtcTimestamp(pinnedAt)
  ) {
    throw new SyncInvalidMutationError('PAYLOAD_INVALID', 'A payload needs a valid pinnedAt timestamp or null.');
  }
  if (
    UTF8.encode(title).length +
      UTF8.encode(content).length +
      (typeof pinnedAt === 'string' ? UTF8.encode(pinnedAt).length : 0) >
    MAX_PAYLOAD_BYTES
  ) {
    throw new SyncInvalidMutationError('PAYLOAD_TOO_LARGE', 'The note payload is too large to store.');
  }
  return {
    title,
    content,
    ...(hasPinnedAt ? { pinnedAt: pinnedAt as string | null } : {}),
  };
};

/**
 * Normalizes and validates one mutation. Every field of the request takes part
 * except the `mutationId` itself, so the fingerprint changes the moment the
 * request does - which is how a reused id is caught.
 */
export const normalizeMutation = (mutation: SyncMutation): NormalizedMutation => {
  const mutationId = cleanIdentifier(
    mutation?.mutationId,
    'MUTATION_ID_INVALID',
    'A mutation needs a non-empty mutationId of at most 128 characters.',
  );
  const noteId = cleanIdentifier(
    mutation?.noteId,
    'NOTE_ID_INVALID',
    'A mutation needs a non-empty noteId of at most 128 characters.',
  );
  const operation = mutation?.operation;
  if (operation !== 'create' && operation !== 'update' && operation !== 'delete') {
    throw new SyncInvalidMutationError('OPERATION_UNSUPPORTED', 'The mutation operation is not supported.');
  }
  const baseRevision = mutation?.baseRevision;
  if (typeof baseRevision !== 'number' || !Number.isSafeInteger(baseRevision) || baseRevision < 0) {
    throw new SyncInvalidMutationError('BASE_REVISION_INVALID', 'baseRevision must be a non-negative whole number.');
  }
  const payload = normalizePayload(operation, mutation?.payload);
  const protectionChange = mutation?.protectionChange === undefined ? undefined : parseProtectionChange(mutation.protectionChange);
  if (protectionChange && operation === 'delete') {
    throw new SyncInvalidMutationError('PAYLOAD_INVALID', 'Protection changes require content.');
  }
  const ownerId = mutation.ownerId === undefined ? undefined : cleanIdentifier(mutation.ownerId, 'NOTE_ID_INVALID', 'Invalid canonical owner.');
  const accessRevision = mutation.accessRevision;
  if ((ownerId === undefined) !== (accessRevision === undefined) ||
      (accessRevision !== undefined && (!Number.isSafeInteger(accessRevision) || accessRevision < 1 || operation !== 'update' || protectionChange))) {
    throw new SyncInvalidMutationError('PAYLOAD_INVALID', 'Invalid shared mutation.');
  }

  if (ownerId && payload && Object.hasOwn(payload, 'pinnedAt')) {
    throw new SyncInvalidMutationError('PAYLOAD_INVALID', 'Shared text writes cannot organize notes.');
  }
  return {
    mutationId,
    noteId,
    operation,
    baseRevision,
    payload,
    ...(protectionChange ? { protectionChange } : {}),
    ...(ownerId ? { ownerId, accessRevision } : {}),
    fingerprint: stableDigest(
      `mutation:${JSON.stringify([
        operation,
        noteId,
        baseRevision,
        payload?.title ?? null,
        payload?.content ?? null,
        ...(payload && Object.hasOwn(payload, 'pinnedAt') ? [payload.pinnedAt] : []),
        ...(protectionChange ? [protectionChange] : []),
        ...(ownerId ? [ownerId, accessRevision] : []),
      ])}`,
    ),
  };
};

/** The shared body of a note item and of the feed row written with it. */
export const snapshotAttributes = (snapshot: NoteSnapshot): Record<string, unknown> => ({
  id: snapshot.id,
  title: snapshot.title,
  content: snapshot.content,
  revision: snapshot.revision,
  createdAt: snapshot.createdAt,
  serverUpdatedAt: snapshot.serverUpdatedAt,
  pinnedAt: snapshot.pinnedAt ?? null,
  deletedAt: snapshot.deletedAt,
  protected: snapshot.protected ?? false,
  protectionRevision: snapshot.protectionRevision ?? 0,
  ...(snapshot.ownerId ? { canonicalOwnerId: snapshot.ownerId } : {}),
  ...(snapshot.share ? { share: snapshot.share } : {}),
  ...(snapshot.sharingRevision !== undefined ? { sharingRevision: snapshot.sharingRevision } : {}),
});

export const stringFieldOf = (item: Record<string, unknown>, name: string): string => {
  const value = item[name];
  if (typeof value !== 'string') {
    throw corruptData();
  }
  return value;
};

export const toNoteSnapshot = (item: Record<string, unknown>): NoteSnapshot => {
  const revision = item.revision;
  const deletedAt = item.deletedAt;
  const pinnedAt = item.pinnedAt;
  if (pinnedAt !== undefined && pinnedAt !== null && !isUtcTimestamp(pinnedAt)) throw corruptData();
  if (typeof revision !== 'number' || !Number.isSafeInteger(revision) || revision < 1) {
    throw corruptData();
  }
  if (deletedAt !== undefined && deletedAt !== null && typeof deletedAt !== 'string') {
    throw corruptData();
  }
  const protectionRevision = item.protectionRevision ?? 0;
  if ((item.protected !== undefined && typeof item.protected !== 'boolean') ||
      typeof protectionRevision !== 'number' || !Number.isSafeInteger(protectionRevision) ||
      protectionRevision < 0 || (item.protected === true && protectionRevision === 0)) throw corruptData();
  return {
    id: stringFieldOf(item, 'id'),
    title: stringFieldOf(item, 'title'),
    content: stringFieldOf(item, 'content'),
    revision,
    createdAt: stringFieldOf(item, 'createdAt'),
    serverUpdatedAt: stringFieldOf(item, 'serverUpdatedAt'),
    pinnedAt: pinnedAt === undefined ? null : pinnedAt,
    deletedAt: deletedAt === undefined ? null : deletedAt,
    protected: item.protected === true,
    protectionRevision,
    contentAvailable: true,
    ...(typeof item.canonicalOwnerId === 'string' ? { ownerId: item.canonicalOwnerId } : {}),
    ...(item.share !== undefined ? { share: decodeShare(item) } : {}),
    ...(item.sharingRevision !== undefined ? { sharingRevision: membershipRevision(item) } : {}),
  };
};

export const sequenceOf = (item: Record<string, unknown>): number => {
  const sequence = item.changeSequence;
  if (typeof sequence !== 'number' || !Number.isSafeInteger(sequence) || sequence < 1) {
    throw corruptData();
  }
  return sequence;
};

export const pageSizeOf = (limit: number | undefined): number => {
  if (typeof limit !== 'number' || !Number.isFinite(limit)) {
    return DEFAULT_CHANGE_LIMIT;
  }
  return Math.min(Math.max(Math.trunc(limit), 1), MAX_CHANGE_LIMIT);
};

/**
 * Whether the request may be applied at all, and if so against which stored
 * note. Shape and state are separate questions on purpose: a client that is
 * merely out of date gets a conflict with the remote snapshot, not an error.
 */
export const checkConflict = (request: NormalizedMutation, remote: NoteSnapshot | null): ConflictCheck => {
  const remoteRevision = remote?.revision ?? 0;
  if (request.baseRevision !== remoteRevision) {
    return { kind: 'conflict', remoteNote: remote };
  }
  if (request.operation === 'create') {
    // A stored note at revision 0 cannot exist, so this is only reachable when
    // the account already has the note - live or as a tombstone.
    return remote === null ? { kind: 'apply' } : { kind: 'conflict', remoteNote: remote };
  }
  if (remote === null || remote.deletedAt !== null) {
    return { kind: 'conflict', remoteNote: remote };
  }
  return { kind: 'apply' };
};

/**
 * A cancelled transaction tells us which item refused. Conditional failures and
 * transaction conflicts mean "the world moved"; throttling means "try again
 * shortly". Everything else - a validation error, a size limit - is permanent.
 */
export const isRetryableCancellation = (error: TransactionCanceledException): boolean => {
  const codes = (error.CancellationReasons ?? [])
    .map((reason) => reason.Code)
    .filter((code): code is string => typeof code === 'string' && code !== 'None');
  if (codes.length === 0) {
    return true;
  }
  return codes.every(
    (code) =>
      code === 'ConditionalCheckFailed' ||
      code === 'TransactionConflict' ||
      code === 'ThrottlingError' ||
      code === 'ProvisionedThroughputExceeded',
  );
};

/** The state transition one applied mutation performs, in one place. */
export const nextSnapshot = (
  request: NormalizedMutation,
  remote: NoteSnapshot | null,
  now: string,
): NoteSnapshot => ({
  id: request.noteId,
  title: request.payload?.title ?? '',
  content: request.payload?.content ?? '',
  revision: request.baseRevision + 1,
  createdAt: remote?.createdAt ?? now,
  serverUpdatedAt: now,
  pinnedAt: request.payload && Object.hasOwn(request.payload, 'pinnedAt')
    ? request.payload.pinnedAt ?? null : remote?.pinnedAt ?? null,
  deletedAt: request.operation === 'delete' ? now : null,
  protected: remote?.protected ?? false,
  protectionRevision: remote?.protectionRevision ?? 0,
  ...(remote?.sharingRevision !== undefined ? { sharingRevision: remote.sharingRevision } : {}),
});

export function membershipRevision(row: Record<string, unknown>): number {
  const n = row.sharingRevision ?? 0;
  if (!Number.isSafeInteger(n) || (n as number) < 0) throw corruptData();
  return n as number;
}

/**
 * The four writes of one applied mutation. Every guard lives here, so this is
 * the only place that decides whether a mutation may land.
 */
export const transactItemsFor = (
  tableName: string,
  ownerKey: string,
  request: NormalizedMutation,
  remote: NoteSnapshot | null,
  note: NoteSnapshot,
  lastSequence: number,
  now: string,
): TransactWriteCommandInput['TransactItems'] => {
  const sequence = lastSequence + 1;
  const attributes = snapshotAttributes(note);
  const metadata = note.protected ? { ...attributes, title: '', content: '' } : attributes;
  // Unused expression attribute values are a DynamoDB validation error, so the
  // revision guard only appears when a stored note has a revision to match.
  const noteGuard =
    remote === null
      ? { ConditionExpression: 'attribute_not_exists(noteId)' }
      : {
          ConditionExpression: 'attribute_exists(noteId) AND revision = :revision AND (attribute_not_exists(sharingRevision) OR sharingRevision = :membership)',
          ExpressionAttributeValues: { ':revision': remote.revision, ':membership': remote.sharingRevision ?? 0 },
        };

  return [
    {
      Update: {
        TableName: tableName,
        Key: itemKey(ownerKey, META_SORT_KEY),
        UpdateExpression: 'SET lastSequence = :nextSequence',
        ConditionExpression: 'attribute_not_exists(lastSequence) OR lastSequence = :sequence',
        ExpressionAttributeValues: { ':nextSequence': sequence, ':sequence': lastSequence },
      },
    },
    {
      Put: {
        TableName: tableName,
        Item: { ownerId: ownerKey, noteId: `${NOTE_SORT_KEY_PREFIX}${note.id}`, ...attributes },
        ...noteGuard,
      },
    },
    {
      Put: {
        TableName: tableName,
        // No condition: the meta guard above already made this sequence
        // exclusive, and only `CHANGE#` rows carry the index keys.
        Item: {
          ownerId: ownerKey,
          noteId: `${CHANGE_SORT_KEY_PREFIX}${sequence}`,
          ...metadata,
          changeOwnerId: ownerKey,
          changeSequence: sequence,
        },
      },
    },
    {
      Put: {
        TableName: tableName,
        Item: {
          ownerId: ownerKey,
          noteId: `${MUTATION_SORT_KEY_PREFIX}${request.mutationId}`,
          mutationId: request.mutationId,
          targetNoteId: request.noteId,
          operation: request.operation,
          fingerprint: request.fingerprint,
          sequence,
          resultNote: metadata,
          serverUpdatedAt: now,
        },
        // A concurrent duplicate of the same mutationId must not overwrite the
        // recorded result; it loses here and replays on the next attempt.
        ConditionExpression: 'attribute_not_exists(noteId)',
      },
    },
  ];
};
