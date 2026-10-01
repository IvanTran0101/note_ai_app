import { DynamoDBClient, TransactionCanceledException } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand, QueryCommand, TransactWriteCommand } from '@aws-sdk/lib-dynamodb';
import { decodeChangeCursor, encodeChangeCursor } from './cursor';
import { SyncInvalidMutationError, SyncStorageError } from './sync_store_models';
import type { SyncStore, DynamoSyncStoreOptions, NoteSnapshot, ApplyMutationResult, ChangesPage,
  NormalizedMutation, CommitOutcome, StoredMutation, SyncMutation } from './sync_store_models';
import { MAX_ATTEMPTS, META_SORT_KEY, NOTE_SORT_KEY_PREFIX, MUTATION_SORT_KEY_PREFIX, CHANGES_INDEX_NAME,
  ownerKeyOf, itemKey, normalizeMutation, checkConflict, nextSnapshot, transactItemsFor,
  isRetryableCancellation, toStorageError, toNoteSnapshot, sequenceOf, pageSizeOf, corruptData, isRecord } from './sync_store_codec';
export * from './sync_store_models';
export { SyncInvalidCursorError } from './cursor';
import { NoteSecurityError } from '../protection/protection_store';
import type { NoteSecurityAuthority, ProtectionMetadata, SecurityAuthorization } from '../protection/protection_store';

export class DynamoSyncStore implements SyncStore {
  private readonly tableName: string;
  private readonly documentClient: DynamoDBDocumentClient;
  private readonly security?: NoteSecurityAuthority;

  constructor(options: DynamoSyncStoreOptions) {
    if (typeof options?.tableName !== 'string' || options.tableName.length === 0) {
      throw new SyncStorageError('The sync store was created without a table name.', { retryable: false });
    }
    this.tableName = options.tableName;
    this.security = options.security;
    this.documentClient =
      options.documentClient ??
      DynamoDBDocumentClient.from(
        new DynamoDBClient(options.region === undefined ? {} : { region: options.region }),
        { marshallOptions: { removeUndefinedValues: true } },
      );
  }

  async applyMutation(ownerId: string, mutation: SyncMutation,
    authorization?: Readonly<{ actorId: string; grant?: string }>): Promise<ApplyMutationResult> {
    const request = normalizeMutation(mutation);
    const ownerKey = ownerKeyOf(ownerId);
    const authorize = () => this.security?.authorize(authorization?.actorId ?? ownerId,
      ownerId, request.noteId, request.operation === 'delete' ? 'delete' : 'edit', authorization?.grant);

    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
      let authority = await authorize();
      const [meta, remote, recorded] = await Promise.all([
        this.readMeta(ownerKey),
        this.readNote(ownerKey, request.noteId),
        this.readMutationRecord(ownerKey, request.mutationId),
      ]);
      if (remote?.protected && !this.security) throw new NoteSecurityError('locked');
      if (remote?.protected && authority && (!authority.enabled ||
          authority.revision < (remote.protectionRevision ?? 0))) throw new NoteSecurityError('unavailable');

      if (recorded !== null) {
        if (recorded.fingerprint !== request.fingerprint) {
          throw new SyncInvalidMutationError(
            'MUTATION_ID_REUSED',
            `${request.mutationId} was already applied with a different request.`,
          );
        }
        authority = await authorize();
        return { status: 'applied', mutationId: request.mutationId,
          note: this.metadataProjection(recorded.note, authority), replayed: true };
      }

      const check = checkConflict(request, remote);
      if (check.kind === 'conflict') {
        authority = await authorize();
        return { status: 'conflict', mutationId: request.mutationId,
          remoteNote: check.remoteNote ? this.metadataProjection(check.remoteNote, authority) : null };
      }

      authority = await authorize();
      const outcome = await this.commit(ownerKey, request, remote, meta.lastSequence, authority);
      if (outcome.kind === 'committed') {
        authority = await authorize();
        return { status: 'applied', mutationId: request.mutationId,
          note: this.metadataProjection(outcome.note, authority), replayed: false };
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

    // One row beyond the page supports `hasMore`; never advance across a GSI
    // visibility gap, because that sequence may appear in a later poll.
    const response = await this.queryChanges(ownerKey, after, pageSize + 1);
    const rows = response.Items ?? [];
    const contiguousRows: Record<string, unknown>[] = [];
    let expectedSequence = after + 1;
    let foundGap = false;
    for (const row of rows) {
      const sequence = sequenceOf(row);
      if (sequence < expectedSequence) {
        throw corruptData();
      }
      if (sequence > expectedSequence) {
        foundGap = true;
        break;
      }
      contiguousRows.push(row);
      expectedSequence++;
    }
    const hasMore = !foundGap && contiguousRows.length > pageSize;
    const page = contiguousRows.slice(0, pageSize);

    return {
      items: await Promise.all(page.map(async (row) => {
        const snapshot = toNoteSnapshot(row);
        const protection = await this.security?.metadata(ownerId, ownerId, snapshot.id);
        return this.metadataProjection(snapshot, protection);
      })),
      nextCursor: encodeChangeCursor(ownerId, page.length === 0 ? after : sequenceOf(page[page.length - 1])),
      hasMore,
    };
  }

  private async commit(
    ownerKey: string,
    request: NormalizedMutation,
    remote: NoteSnapshot | null,
    lastSequence: number,
    authority?: SecurityAuthorization,
  ): Promise<CommitOutcome> {
    const now = new Date().toISOString();
    const next = nextSnapshot(request, remote, now);
    const note = authority ? { ...next, protected: authority.enabled,
      protectionRevision: authority.revision } : next;
    const transactItems = transactItemsFor(this.tableName, ownerKey, request, remote, note, lastSequence, now);
    if (authority) {
      transactItems?.push({ ConditionCheck: { TableName: this.tableName,
        Key: itemKey(ownerKey, `PROTECTION#${request.noteId}`),
        ConditionExpression: authority.revision === 0 ? 'attribute_not_exists(noteId)' : 'revision = :epoch AND enabled = :enabled',
        ...(authority.revision === 0 ? {} : { ExpressionAttributeValues: {
          ':epoch': authority.revision, ':enabled': authority.enabled } }) } });
      if (authority.enabled) transactItems?.push({ ConditionCheck: {
        TableName: this.tableName, Key: itemKey(ownerKey, `GRANT#${authority.grantHash}`),
        ConditionExpression: 'expiresAt > :now AND revision = :epoch AND actorId = :actor AND targetNoteId = :note AND contains(operations, :operation)',
        ExpressionAttributeValues: { ':now': Date.now(), ':epoch': authority.revision,
          ':actor': authority.actorId, ':note': request.noteId, ':operation': authority.operation } } });
    }

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

  private metadataProjection(note: NoteSnapshot, authority?: ProtectionMetadata): NoteSnapshot {
    const enabled = authority?.enabled ?? note.protected ?? false;
    return { ...note, protected: enabled,
      protectionRevision: authority?.revision ?? note.protectionRevision ?? 0,
      ...(enabled ? { title: '', content: '', contentAvailable: false } : { contentAvailable: true }) };
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
