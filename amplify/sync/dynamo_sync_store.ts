import { DynamoDBClient, TransactionCanceledException } from '@aws-sdk/client-dynamodb';
import {
  DynamoDBDocumentClient,
  GetCommand,
  QueryCommand,
  TransactWriteCommand,
  type TransactWriteCommandInput,
} from '@aws-sdk/lib-dynamodb';

import { decodeChangeCursor, encodeChangeCursor, stableDigest } from './cursor';

/**
 * DynamoDB persistence for the NoteFlow sync routes (M1.2 persistence slice A).
 *
 * Storage layout (the table and its index are `amplify/sync/notes_table.ts`):
 *
 * ```text
 * OWNER#<sub> | META#SYNC          { lastSequence }        one per account
 * OWNER#<sub> | NOTE#<noteId>      current snapshot, or its tombstone
 * OWNER#<sub> | MUTATION#<id>      idempotency record of one applied mutation
 * OWNER#<sub> | CHANGE#<sequence>  feed row, snapshot/tombstone + index keys
 * ```
 *
 * `applyMutation` is one `TransactWriteItems` that advances the sequence (under
 * a condition on the value it read, which is what makes a sequence number
 * exclusive), writes the note, writes the feed row, and records the
 * `mutationId` - all or nothing. When a condition fails, nothing is applied and
 * the store re-reads and tries again, at most `MAX_ATTEMPTS` times, because the
 * usual cause is a concurrent writer rather than a bad request. A
 * `baseRevision` that does not match the stored revision is reported as a
 * `conflict` result carrying the remote snapshot, never as an exception: that
 * is a normal sync outcome, not a fault.
 *
 * Rules this slice settles (the HTTP contract leaves them open):
 *
 * - `create` needs `baseRevision` 0 and no stored note. A tombstone counts as
 *   stored: resurrection is not supported here.
 * - `update` and `delete` need a live stored note whose `revision` equals
 *   `baseRevision`. A tombstone, or a note the account never stored, is a
 *   conflict whose `remoteNote` is that snapshot (`null` when there is none).
 * - `delete` writes a payload-free tombstone into both the note item and the
 *   feed row: identity, revision, and timestamps survive, deleted content does
 *   not.
 * - Repeating a `mutationId` with the same request returns the stored original
 *   result; repeating it with a different request throws
 *   `SyncInvalidMutationError` with reason `MUTATION_ID_REUSED`.
 * - Only applied mutations are recorded, so a conflicted `mutationId` can be
 *   retried - with a new `mutationId` as soon as any field changes.
 *
 * `listChanges` reads the `ChangesByOwnerSequence` index for the account in
 * ascending sequence order, above the sequence the caller's cursor covers. Like
 * any GSI that index is eventually consistent: a change can briefly be
 * invisible to a poll, which delays a change but never reorders one. Gap
 * guarantees, retention of `CHANGE#` rows, and TTLs belong to a later slice, as
 * do HTTP shapes (`handler.ts`), a repository over these items, and batches.
 */

export { SyncInvalidCursorError } from './cursor';

/** Sort-key prefixes; `notes_table.ts` documents the item roles they select. */
const OWNER_KEY_PREFIX = 'OWNER#';
const META_SORT_KEY = 'META#SYNC';
const NOTE_SORT_KEY_PREFIX = 'NOTE#';
const MUTATION_SORT_KEY_PREFIX = 'MUTATION#';
const CHANGE_SORT_KEY_PREFIX = 'CHANGE#';

/**
 * The change-feed index name. Repeated as a runtime literal because the Lambda
 * bundle cannot import CDK code; keep it in step with `notes_table.ts`.
 */
const CHANGES_INDEX_NAME = 'ChangesByOwnerSequence';

/** Contract default for `GET /sync/changes` and the page cap the contract fixes. */
const DEFAULT_CHANGE_LIMIT = 50;
const MAX_CHANGE_LIMIT = 100;

/** One initial attempt plus at most three retries: contention, not throughput, is the cause. */
const MAX_ATTEMPTS = 4;

/** One copy of a snapshot must stay well inside DynamoDB's 400 KB item limit. */
const MAX_PAYLOAD_BYTES = 300_000;
const MAX_IDENTIFIER_LENGTH = 128;
const CONTROL_CHARACTERS = /[\u0000-\u001f\u007f]/;
const UTF8 = new TextEncoder();

/** Provider-neutral note state; `deletedAt` set means a tombstone. */
export type NoteSnapshot = Readonly<{
  id: string;
  title: string;
  content: string;
  revision: number;
  createdAt: string;
  serverUpdatedAt: string;
  deletedAt: string | null;
}>;

export type SyncOperation = 'create' | 'update' | 'delete';

/** `create` and `update` require this; `delete` ignores it. */
export type MutationPayload = Readonly<{ title: string; content: string }>;

/** One client mutation, already stripped of transport concerns. */
export type SyncMutation = Readonly<{
  mutationId: string;
  noteId: string;
  operation: SyncOperation;
  baseRevision: number;
  payload?: MutationPayload;
}>;

export type AppliedMutation = Readonly<{
  status: 'applied';
  mutationId: string;
  note: NoteSnapshot;
  /** True when the stored result of an earlier identical mutation was replayed. */
  replayed: boolean;
}>;

export type ConflictedMutation = Readonly<{
  status: 'conflict';
  mutationId: string;
  /** The stored note at decision time, or `null` when the account has none. */
  remoteNote: NoteSnapshot | null;
}>;

export type ApplyMutationResult = AppliedMutation | ConflictedMutation;

export type ChangesPage = Readonly<{
  items: readonly NoteSnapshot[];
  /** Always minted: the caller stores it and sends it back on the next poll. */
  nextCursor: string;
  hasMore: boolean;
}>;

/** The port `handler.ts` codes against; nothing here knows about HTTP. */
export interface SyncStore {
  /**
   * Applies one mutation for `ownerId` (the verified JWT `sub`).
   *
   * @throws SyncInvalidMutationError when the request cannot be applied as sent.
   * @throws SyncStorageError when storage failed; `retryable` says whether the
   *         same request may be sent again.
   */
  applyMutation(ownerId: string, mutation: SyncMutation): Promise<ApplyMutationResult>;

  /**
   * Lists changes above `cursor` in ascending sequence order. A missing cursor
   * starts from the beginning; `limit` is clamped to 1..100 (default 50).
   *
   * @throws SyncInvalidCursorError when the cursor is not this account's.
   * @throws SyncStorageError when storage failed.
   */
  listChanges(ownerId: string, cursor?: string | null, limit?: number): Promise<ChangesPage>;
}

export type InvalidMutationReason =
  | 'MUTATION_ID_INVALID'
  | 'MUTATION_ID_REUSED'
  | 'NOTE_ID_INVALID'
  | 'OPERATION_UNSUPPORTED'
  | 'BASE_REVISION_INVALID'
  | 'PAYLOAD_REQUIRED'
  | 'PAYLOAD_INVALID'
  | 'PAYLOAD_TOO_LARGE';

/** The request is not applicable as sent; the handler maps this to a client error. */
export class SyncInvalidMutationError extends Error {
  readonly code = 'INVALID_MUTATION';
  readonly reason: InvalidMutationReason;

  constructor(reason: InvalidMutationReason, message: string) {
    super(message);
    this.name = 'SyncInvalidMutationError';
    this.reason = reason;
  }
}

/** Storage failed. `retryable` distinguishes "send it again" from "do not". */
export class SyncStorageError extends Error {
  readonly code = 'STORAGE_FAILURE';
  readonly retryable: boolean;

  /** `cause` carries the provider error for server-side logs only; never serialize it. */
  constructor(message: string, options?: Readonly<{ retryable?: boolean; cause?: unknown }>) {
    super(message, options?.cause === undefined ? undefined : { cause: options.cause });
    this.name = 'SyncStorageError';
    this.retryable = options?.retryable !== false;
  }
}

export type DynamoSyncStoreOptions = Readonly<{
  tableName: string;
  /** Defaults to the client's own chain, which resolves `AWS_REGION` in Lambda. */
  region?: string;
  /** Injection seam: a warmer path or a test can supply its own document client. */
  documentClient?: DynamoDBDocumentClient;
}>;

type NormalizedMutation = Readonly<{
  mutationId: string;
  noteId: string;
  operation: SyncOperation;
  baseRevision: number;
  payload: MutationPayload | null;
  fingerprint: string;
}>;

type StoredMutation = Readonly<{ fingerprint: string; note: NoteSnapshot }>;

type ConflictCheck =
  | Readonly<{ kind: 'apply' }>
  | Readonly<{ kind: 'conflict'; remoteNote: NoteSnapshot | null }>;

type CommitOutcome = Readonly<{ kind: 'committed'; note: NoteSnapshot }> | Readonly<{ kind: 'retry' }>;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const errorNameOf = (error: unknown): string =>
  isRecord(error) && typeof error.name === 'string' ? error.name : 'UnknownError';

/**
 * An SDK error the retry loop cannot fix: a bad request, a missing table, or a
 * denied call would fail identically on a second attempt, and reporting it as
 * retryable would only multiply the load.
 */
const NON_RETRYABLE_ERRORS = new Set([
  'AccessDeniedException',
  'ConditionalCheckFailedException',
  'ItemCollectionSizeLimitExceededException',
  'ResourceNotFoundException',
  'TransactionCanceledException',
  'ValidationException',
]);

const toStorageError = (error: unknown): SyncStorageError =>
  new SyncStorageError(`DynamoDB ${errorNameOf(error)} while serving the sync request.`, {
    retryable: !NON_RETRYABLE_ERRORS.has(errorNameOf(error)),
    cause: error,
  });

/** Stored data that this slice cannot read: retrying would fail the same way. */
const corruptData = (): SyncStorageError =>
  new SyncStorageError('Stored sync data is not readable.', { retryable: false });

const ownerKeyOf = (ownerId: string): string => {
  if (typeof ownerId !== 'string' || ownerId.trim().length === 0) {
    // Unreachable through the handler, which derives the owner from the JWT.
    throw new SyncStorageError('The sync request has no account owner.', { retryable: false });
  }
  return `${OWNER_KEY_PREFIX}${ownerId}`;
};

const itemKey = (ownerKey: string, sortKey: string): Record<string, string> => ({
  ownerId: ownerKey,
  noteId: sortKey,
});

const cleanIdentifier = (
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

const normalizePayload = (operation: SyncOperation, payload: unknown): MutationPayload | null => {
  if (operation === 'delete') {
    return null;
  }
  if (!isRecord(payload)) {
    throw new SyncInvalidMutationError('PAYLOAD_REQUIRED', 'create and update need a title and content payload.');
  }
  const { title, content } = payload;
  if (typeof title !== 'string' || typeof content !== 'string') {
    throw new SyncInvalidMutationError('PAYLOAD_INVALID', 'A payload needs a string title and content.');
  }
  if (UTF8.encode(title).length + UTF8.encode(content).length > MAX_PAYLOAD_BYTES) {
    throw new SyncInvalidMutationError('PAYLOAD_TOO_LARGE', 'The note payload is too large to store.');
  }
  return { title, content };
};

/**
 * Normalizes and validates one mutation. Every field of the request takes part
 * except the `mutationId` itself, so the fingerprint changes the moment the
 * request does - which is how a reused id is caught.
 */
const normalizeMutation = (mutation: SyncMutation): NormalizedMutation => {
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

  return {
    mutationId,
    noteId,
    operation,
    baseRevision,
    payload,
    fingerprint: stableDigest(
      `mutation:${JSON.stringify([
        operation,
        noteId,
        baseRevision,
        payload?.title ?? null,
        payload?.content ?? null,
      ])}`,
    ),
  };
};

/** The shared body of a note item and of the feed row written with it. */
const snapshotAttributes = (snapshot: NoteSnapshot): Record<string, unknown> => ({
  id: snapshot.id,
  title: snapshot.title,
  content: snapshot.content,
  revision: snapshot.revision,
  createdAt: snapshot.createdAt,
  serverUpdatedAt: snapshot.serverUpdatedAt,
  deletedAt: snapshot.deletedAt,
});

const stringFieldOf = (item: Record<string, unknown>, name: string): string => {
  const value = item[name];
  if (typeof value !== 'string') {
    throw corruptData();
  }
  return value;
};

const toNoteSnapshot = (item: Record<string, unknown>): NoteSnapshot => {
  const revision = item.revision;
  const deletedAt = item.deletedAt;
  if (typeof revision !== 'number' || !Number.isSafeInteger(revision) || revision < 1) {
    throw corruptData();
  }
  if (deletedAt !== undefined && deletedAt !== null && typeof deletedAt !== 'string') {
    throw corruptData();
  }
  return {
    id: stringFieldOf(item, 'id'),
    title: stringFieldOf(item, 'title'),
    content: stringFieldOf(item, 'content'),
    revision,
    createdAt: stringFieldOf(item, 'createdAt'),
    serverUpdatedAt: stringFieldOf(item, 'serverUpdatedAt'),
    deletedAt: deletedAt === undefined ? null : deletedAt,
  };
};

const sequenceOf = (item: Record<string, unknown>): number => {
  const sequence = item.changeSequence;
  if (typeof sequence !== 'number' || !Number.isSafeInteger(sequence) || sequence < 1) {
    throw corruptData();
  }
  return sequence;
};

const pageSizeOf = (limit: number | undefined): number => {
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
const checkConflict = (request: NormalizedMutation, remote: NoteSnapshot | null): ConflictCheck => {
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
const isRetryableCancellation = (error: TransactionCanceledException): boolean => {
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
const nextSnapshot = (
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
  deletedAt: request.operation === 'delete' ? now : null,
});

/**
 * The four writes of one applied mutation. Every guard lives here, so this is
 * the only place that decides whether a mutation may land.
 */
const transactItemsFor = (
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
  // Unused expression attribute values are a DynamoDB validation error, so the
  // revision guard only appears when a stored note has a revision to match.
  const noteGuard =
    remote === null
      ? { ConditionExpression: 'attribute_not_exists(noteId)' }
      : {
          ConditionExpression: 'attribute_exists(noteId) AND revision = :revision',
          ExpressionAttributeValues: { ':revision': remote.revision },
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
          ...attributes,
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
          resultNote: attributes,
          serverUpdatedAt: now,
        },
        // A concurrent duplicate of the same mutationId must not overwrite the
        // recorded result; it loses here and replays on the next attempt.
        ConditionExpression: 'attribute_not_exists(noteId)',
      },
    },
  ];
};

export class DynamoSyncStore implements SyncStore {
  private readonly tableName: string;
  private readonly documentClient: DynamoDBDocumentClient;

  constructor(options: DynamoSyncStoreOptions) {
    if (typeof options?.tableName !== 'string' || options.tableName.length === 0) {
      throw new SyncStorageError('The sync store was created without a table name.', { retryable: false });
    }
    this.tableName = options.tableName;
    this.documentClient =
      options.documentClient ??
      DynamoDBDocumentClient.from(
        new DynamoDBClient(options.region === undefined ? {} : { region: options.region }),
        { marshallOptions: { removeUndefinedValues: true } },
      );
  }

  async applyMutation(ownerId: string, mutation: SyncMutation): Promise<ApplyMutationResult> {
    const request = normalizeMutation(mutation);
    const ownerKey = ownerKeyOf(ownerId);

    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
      const [meta, remote, recorded] = await Promise.all([
        this.readMeta(ownerKey),
        this.readNote(ownerKey, request.noteId),
        this.readMutationRecord(ownerKey, request.mutationId),
      ]);

      if (recorded !== null) {
        if (recorded.fingerprint !== request.fingerprint) {
          throw new SyncInvalidMutationError(
            'MUTATION_ID_REUSED',
            `${request.mutationId} was already applied with a different request.`,
          );
        }
        return { status: 'applied', mutationId: request.mutationId, note: recorded.note, replayed: true };
      }

      const check = checkConflict(request, remote);
      if (check.kind === 'conflict') {
        return { status: 'conflict', mutationId: request.mutationId, remoteNote: check.remoteNote };
      }

      const outcome = await this.commit(ownerKey, request, remote, meta.lastSequence);
      if (outcome.kind === 'committed') {
        return { status: 'applied', mutationId: request.mutationId, note: outcome.note, replayed: false };
      }
    }

    throw new SyncStorageError('The account was updated too frequently for the note to be saved.', {
      retryable: true,
    });
  }

  async listChanges(ownerId: string, cursor?: string | null, limit?: number): Promise<ChangesPage> {
    const after = decodeChangeCursor(cursor, ownerId);
    const pageSize = pageSizeOf(limit);
    const ownerKey = ownerKeyOf(ownerId);

    // One row beyond the page: its presence is what `hasMore` means, and the
    // cursor still stops at the last row actually returned.
    const response = await this.queryChanges(ownerKey, after, pageSize + 1);
    const rows = response.Items ?? [];
    const hasMore = rows.length > pageSize;
    const page = hasMore ? rows.slice(0, pageSize) : rows;

    return {
      items: page.map((row) => toNoteSnapshot(row)),
      nextCursor: encodeChangeCursor(ownerId, page.length === 0 ? after : sequenceOf(page[page.length - 1])),
      hasMore,
    };
  }

  private async commit(
    ownerKey: string,
    request: NormalizedMutation,
    remote: NoteSnapshot | null,
    lastSequence: number,
  ): Promise<CommitOutcome> {
    const now = new Date().toISOString();
    const note = nextSnapshot(request, remote, now);
    const transactItems = transactItemsFor(this.tableName, ownerKey, request, remote, note, lastSequence, now);

    try {
      await this.documentClient.send(new TransactWriteCommand({ TransactItems: transactItems }));
      return { kind: 'committed', note };
    } catch (error) {
      if (error instanceof TransactionCanceledException) {
        if (isRetryableCancellation(error)) {
          return { kind: 'retry' };
        }
        throw new SyncStorageError('The note could not be stored as sent.', { retryable: false, cause: error });
      }
      throw toStorageError(error);
    }
  }

  private async readItem(ownerKey: string, sortKey: string): Promise<Record<string, unknown> | null> {
    try {
      const response = await this.documentClient.send(
        new GetCommand({
          TableName: this.tableName,
          Key: itemKey(ownerKey, sortKey),
          // The conditions in `commit` are the real guard; a consistent read
          // keeps the values they are built from in step with them.
          ConsistentRead: true,
        }),
      );
      return response.Item ?? null;
    } catch (error) {
      throw toStorageError(error);
    }
  }

  private async readMeta(ownerKey: string): Promise<Readonly<{ lastSequence: number }>> {
    const item = await this.readItem(ownerKey, META_SORT_KEY);
    const lastSequence = item?.lastSequence;
    if (lastSequence === undefined) {
      // No applied mutation yet. The transaction's own condition covers the
      // race with an account that creates this item in the meantime.
      return { lastSequence: 0 };
    }
    if (typeof lastSequence !== 'number' || !Number.isSafeInteger(lastSequence) || lastSequence < 0) {
      throw corruptData();
    }
    return { lastSequence };
  }

  private async readNote(ownerKey: string, noteId: string): Promise<NoteSnapshot | null> {
    const item = await this.readItem(ownerKey, `${NOTE_SORT_KEY_PREFIX}${noteId}`);
    return item === null ? null : toNoteSnapshot(item);
  }

  private async readMutationRecord(ownerKey: string, mutationId: string): Promise<StoredMutation | null> {
    const item = await this.readItem(ownerKey, `${MUTATION_SORT_KEY_PREFIX}${mutationId}`);
    if (item === null) {
      return null;
    }
    const { fingerprint, resultNote } = item;
    if (typeof fingerprint !== 'string' || !isRecord(resultNote)) {
      throw corruptData();
    }
    return { fingerprint, note: toNoteSnapshot(resultNote) };
  }

  private async queryChanges(ownerKey: string, after: number, limit: number) {
    try {
      return await this.documentClient.send(
        new QueryCommand({
          TableName: this.tableName,
          IndexName: CHANGES_INDEX_NAME,
          KeyConditionExpression: 'changeOwnerId = :ownerKey AND changeSequence > :after',
          ExpressionAttributeValues: { ':ownerKey': ownerKey, ':after': after },
          ScanIndexForward: true,
          Limit: limit,
        }),
      );
    } catch (error) {
      throw toStorageError(error);
    }
  }
}

/**
 * Smallest wiring the handler needs: one store per container, holding one
 * document client. `tableName` and `region` come from the function's
 * environment (`NOTES_TABLE_NAME`, `NOTES_TABLE_REGION`).
 */
export const createDynamoSyncStore = (options: DynamoSyncStoreOptions): SyncStore =>
  new DynamoSyncStore(options);
