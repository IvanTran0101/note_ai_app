import { protectionWrite } from './sync_protection_change';
import { labelSnapshot } from '../labels/label_models';
import { projectNoteLabels } from '../labels/note_label_projection';
import { stableDigest } from './cursor';
import { ActorFeed } from '../sharing/actor_feed';
import { aclCondition, DynamoNoteAcl } from '../sharing/dynamo_note_acl';
import { recipientProjection } from '../sharing/feed_projection';
import { DynamoDBClient, TransactionCanceledException } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand, QueryCommand, TransactWriteCommand } from '@aws-sdk/lib-dynamodb';
import { decodeChangeCursor, encodeChangeCursor } from './cursor';
import {boundedChangeRows} from './bounded_change_rows';
import { SyncInvalidMutationError, SyncStorageError } from './sync_store_models';
import type { SyncStore, DynamoSyncStoreOptions, NoteSnapshot, ApplyMutationResult, ChangesPage,
  NormalizedMutation, CommitOutcome, StoredMutation, SyncMutation } from './sync_store_models';
import { MAX_ATTEMPTS, META_SORT_KEY, NOTE_SORT_KEY_PREFIX, MUTATION_SORT_KEY_PREFIX, CHANGES_INDEX_NAME,
  ownerKeyOf, itemKey, normalizeMutation, checkConflict, nextSnapshot, transactItemsFor,
  isRetryableCancellation, toStorageError, toNoteSnapshot, sequenceOf, pageSizeOf, corruptData, isRecord } from './sync_store_codec';
export * from './sync_store_models';
export { SyncInvalidCursorError } from './cursor';
import { NoteSecurityError } from '../protection/protection_store';
import { AttachmentError } from '../attachments/models';
import type { AttachmentAttemptStore } from '../attachments/attempt_store';
import type { NoteSecurityAuthority, ProtectionMetadata, SecurityAuthorization } from '../protection/protection_store';

export class DynamoSyncStore implements SyncStore {
  private readonly tableName: string;
  private readonly documentClient: DynamoDBDocumentClient;
  private readonly security?: NoteSecurityAuthority;
  private readonly feed?: ActorFeed;
  private readonly acl?: DynamoNoteAcl;
  private readonly attachments?: AttachmentAttemptStore;

  constructor(options: DynamoSyncStoreOptions) {
    if (typeof options?.tableName !== 'string' || options.tableName.length === 0) {
      throw new SyncStorageError('The sync store was created without a table name.', { retryable: false });
    }
    this.tableName = options.tableName;
    this.security = options.security;
    this.attachments = options.attachments;
    this.documentClient =
      options.documentClient ??
      DynamoDBDocumentClient.from(
        new DynamoDBClient(options.region === undefined ? {} : { region: options.region }),
        { marshallOptions: { removeUndefinedValues: true } },
      );
    if (options.sharing) {
      this.feed = new ActorFeed(this.tableName, this.documentClient);
      this.acl = new DynamoNoteAcl(this.tableName, this.documentClient);
    }
  }

  async applyMutation(ownerId: string, mutation: SyncMutation,
    authorization?: Readonly<{ actorId: string; grant?: string; inspectOnly?: boolean }>): Promise<ApplyMutationResult> {
    const request = normalizeMutation(mutation);
    if (request.payload?.attachments !== undefined && (!this.attachments || !this.security)) {
      throw new SyncInvalidMutationError('ATTACHMENTS_UNSUPPORTED', 'Verified-object backend required.');
    }
    const ownerKey = ownerKeyOf(ownerId);
    const actor = authorization?.actorId ?? ownerId;
    if (actor !== ownerId && (!this.security || !this.feed || request.ownerId !== ownerId ||
        !request.accessRevision || request.operation !== 'update')) throw new NoteSecurityError('denied');
    if (actor === ownerId && request.ownerId) throw new NoteSecurityError('denied');
    const receiptKey = ownerKeyOf(actor);
    const receiptId = actor === ownerId ? request.mutationId : stableDigest(JSON.stringify([ownerId, request.noteId, request.mutationId]));
    if (authorization?.inspectOnly) return this.inspectPredecessor(ownerId, ownerKey, request, authorization.actorId);
    const authorize = async () => {
      const a = await this.security?.authorize(actor, ownerId, request.noteId,
        request.protectionChange || request.payload && 'pinnedAt' in request.payload
          ? 'manage' : request.operation === 'delete' ? 'delete' : 'edit', authorization?.grant);
      if (request.payload?.attachments !== undefined) {
        await this.security?.authorize(actor, ownerId, request.noteId, 'attachmentWrite', authorization?.grant);
      }
      if (actor !== ownerId && a?.access?.accessRevision !== request.accessRevision) throw new NoteSecurityError('denied');
      return a;
    };
    const project = async (n: NoteSnapshot, a?: ProtectionMetadata) => {
      const projected = actor !== ownerId
        ? await recipientProjection(actor, ownerId, n, this.acl!, this.security!) : this.metadataProjection(n, a);
      if (request.wireVersion !== 2 && request.wireVersion !== 3) return projected;
      const labeled = await projectNoteLabels(this.documentClient, this.tableName, ownerId, projected, actor !== ownerId);
      if (actor !== ownerId) return recipientProjection(actor, ownerId, labeled, this.acl!, this.security!);
      const live = await authorize();
      return this.metadataProjection(labeled, live);
    };

    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
      // A compound replay acknowledges a prior owner write with metadata only.
      // The old grant was invalidated by that very commit; fresh ACL still applies.
      if (request.protectionChange) {
        if (!this.security || (authorization?.actorId ?? ownerId) !== ownerId) throw new NoteSecurityError('denied');
        const recorded = await this.readMutationRecord(ownerKey, request.mutationId);
        if (recorded) {
          const live = await this.security.metadata(authorization?.actorId ?? ownerId, ownerId, request.noteId);
          if (recorded.fingerprint !== request.fingerprint) throw new SyncInvalidMutationError('MUTATION_ID_REUSED', 'Mutation identity reused.');
          return { status: 'applied', mutationId: request.mutationId,
            note: { ...this.metadataProjection(recorded.note, live), title: '', content: '', ...(recorded.note.document !== undefined ? {document: null} : {}), contentAvailable: false }, replayed: true };
        }
      }
      let authority = await authorize();
      if (request.protectionChange && (!authority || authority.enabled !== request.protectionChange.before.enabled ||
          authority.revision !== request.protectionChange.before.revision)) throw new NoteSecurityError('staleRevision');
      const [meta, remote, recorded] = await Promise.all([
        this.readMeta(ownerKey),
        this.readNote(ownerKey, request.noteId),
        this.readMutationRecord(receiptKey, receiptId),
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
          note: await project(recorded.note, authority), replayed: true };
      }

      const check = checkConflict(request, remote);
      if (check.kind === 'conflict') {
        authority = await authorize();
        return { status: 'conflict', mutationId: request.mutationId,
          remoteNote: check.remoteNote ? await project(check.remoteNote, authority) : null };
      }

      authority = await authorize();
      const outcome = await this.commit(ownerKey, request, remote, meta.lastSequence, authority, receiptKey, receiptId);
      if (outcome.kind === 'committed') {
        if (request.protectionChange) {
          const live = await this.security!.metadata(authorization?.actorId ?? ownerId, ownerId, request.noteId);
          return { status: 'applied', mutationId: request.mutationId,
            note: { ...this.metadataProjection(outcome.note, live), title: '', content: '', ...(outcome.note.document !== undefined ? {document: null} : {}), contentAvailable: false }, replayed: false };
        }
        authority = await authorize();
        return { status: 'applied', mutationId: request.mutationId,
          note: await project(outcome.note, authority), replayed: false };
      }
    }

    throw new SyncStorageError('The account was updated too frequently for the note to be saved.', {
      retryable: true,
    });
  }

  /** Resolve unknown delivery without replaying an unprotected write. No writes. */
  private async inspectPredecessor(ownerId: string, ownerKey: string,
      request: NormalizedMutation, actor: string): Promise<ApplyMutationResult> {
    if (!this.security || actor !== ownerId || request.protectionChange) throw new NoteSecurityError('denied');
    await this.security.metadata(actor, ownerId, request.noteId, true);
    const recorded = await this.readMutationRecord(ownerKey, request.mutationId);
    const remote = recorded ? recorded.note : await this.readNote(ownerKey, request.noteId);
    const live = await this.security.metadata(actor, ownerId, request.noteId, true);
    const projection = remote ? { ...this.metadataProjection(remote, live),
      title: '', content: '', ...(remote.document !== undefined ? {document: null} : {}), contentAvailable: false } : null;
    if (recorded) {
      if (recorded.fingerprint !== request.fingerprint) throw new SyncInvalidMutationError('MUTATION_ID_REUSED', 'Mutation identity reused.');
      return { status: 'applied', mutationId: request.mutationId, note: projection!, replayed: true };
    }
    return { status: 'conflict', mutationId: request.mutationId, remoteNote: projection };
  }

  async listChanges(ownerId: string, cursor?: string | null, limit?: number, wireVersion: 1 | 2 | 3 = 1): Promise<ChangesPage> {
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
    const page = wireVersion === 3 ? boundedChangeRows(contiguousRows, pageSize)
      : contiguousRows.slice(0, pageSize);
    const hasMore = page.length < Math.min(contiguousRows.length, pageSize) ||
      !foundGap && contiguousRows.length > pageSize;
    const lastVisible = page.length === 0 ? after : sequenceOf(page[page.length - 1]);
    const committed = this.feed && !hasMore ? await this.feed.item(ownerId, META_SORT_KEY) : null;
    if (committed && (!Number.isSafeInteger(committed.lastSequence) || committed.lastSequence < 0)) throw corruptData();
    const catchUpPending = foundGap || Boolean(committed && committed.lastSequence > lastVisible);

    return {
      items: await Promise.all(page.filter(row => row.entityType !== 'label').map(async (row) => {
        const snapshot = toNoteSnapshot(row);
        if (snapshot.ownerId && snapshot.ownerId !== ownerId) {
          if (!this.acl || !this.security) throw new NoteSecurityError('denied');
          const projected = await recipientProjection(ownerId, snapshot.ownerId, snapshot, this.acl, this.security);
          const labeled = wireVersion >= 2 ? await projectNoteLabels(this.documentClient, this.tableName, snapshot.ownerId, projected, true) : projected;
          return recipientProjection(ownerId, snapshot.ownerId, labeled, this.acl, this.security);
        }
        const protection = await this.security?.metadata(ownerId, ownerId, snapshot.id);
        const projected = this.metadataProjection(snapshot, protection);
        return wireVersion >= 2 ? projectNoteLabels(this.documentClient, this.tableName, ownerId, projected) : projected;
      })),
      nextCursor: encodeChangeCursor(ownerId, page.length === 0 ? after : sequenceOf(page[page.length - 1])),
      hasMore,
      ...(catchUpPending ? { catchUpPending: true } : {}),
      ...(wireVersion >= 2 ? {wireVersion: wireVersion as 2 | 3, labels: page.filter(row => row.entityType === 'label').map(row => labelSnapshot(row, ownerId))} : {}),
    };
  }

  private async commit(
    ownerKey: string,
    request: NormalizedMutation,
    remote: NoteSnapshot | null,
    lastSequence: number,
    authority?: SecurityAuthorization,
    receiptKey = ownerKey,
    receiptId = request.mutationId,
  ): Promise<CommitOutcome> {
    const now = new Date().toISOString();
    const next = nextSnapshot(request, remote, now);
    const projection = request.protectionChange?.after ?? authority;
    const note = projection ? { ...next, protected: projection.enabled,
      protectionRevision: projection.revision } : next;
    const transactItems = transactItemsFor(this.tableName, ownerKey, request, remote, note, lastSequence, now);
    if (remote?.attachments?.length || request.payload?.attachments?.length) {
      if (!this.attachments || !authority) throw new SyncInvalidMutationError('ATTACHMENTS_UNSUPPORTED', 'Verified-object backend required.');
      try {
        transactItems?.push(...await this.attachments.associationWrites(ownerKey.slice('OWNER#'.length),
          request.noteId, remote?.attachments ?? [], note.attachments ?? [], authority.revision));
      } catch (e) {
        if (e instanceof AttachmentError) throw new SyncInvalidMutationError('PAYLOAD_INVALID', 'Attachment association refused.');
        throw e;
      }
    }
    const addedLabels = (request.payload?.labelIds ?? []).filter(id => !(remote?.labelIds ?? []).includes(id));
    for (const id of addedLabels) {
      const row = await this.readItem(ownerKey, `LABEL#${id}`);
      if (!row || row.deletedAt !== null) throw new SyncInvalidMutationError('PAYLOAD_INVALID', 'Label is not active.');
      const label = labelSnapshot(row, ownerKey.slice('OWNER#'.length));
      transactItems?.push({ConditionCheck: {TableName: this.tableName,
        Key: itemKey(ownerKey, `LABEL#${id}`),
        ConditionExpression: 'revision = :revision AND deletedAt = :active',
        ExpressionAttributeValues: {':revision': label.revision, ':active': null}}});
    }
    if (receiptKey !== ownerKey && transactItems?.[3]?.Put) {
      transactItems[3].Put.Item = { ...transactItems[3].Put.Item, ...itemKey(receiptKey, `MUTATION#${receiptId}`) };
    }
    if (authority) transactItems?.push(...aclCondition(this.tableName, authority));
    if (this.feed) transactItems?.push(...await this.feed.fanout(ownerKey.slice('OWNER#'.length), note));
    if (authority) {
      if (request.protectionChange) transactItems?.push(protectionWrite(this.tableName, ownerKey, request.noteId, request.protectionChange, authority));
      else transactItems?.push({ ConditionCheck: { TableName: this.tableName,
        Key: itemKey(ownerKey, `PROTECTION#${request.noteId}`),
        ConditionExpression: authority.revision === 0 ? 'attribute_not_exists(noteId)' : 'revision = :epoch AND enabled = :enabled',
        ...(authority.revision === 0 ? {} : { ExpressionAttributeValues: {
          ':epoch': authority.revision, ':enabled': authority.enabled } }) } });
      if (authority.enabled) transactItems?.push({ ConditionCheck: {
        TableName: this.tableName, Key: itemKey(ownerKey, `GRANT#${authority.grantHash}`),
        ConditionExpression: 'expiresAt > :now AND revision = :epoch AND actorId = :actor AND targetNoteId = :note AND contains(operations, :operation)' +
          (request.payload?.attachments !== undefined ? ' AND contains(operations, :attachmentOperation)' : ''),
        ExpressionAttributeValues: { ':now': Date.now(), ':epoch': authority.revision,
          ':actor': authority.actorId, ':note': request.noteId, ':operation': authority.operation,
          ...(request.payload?.attachments !== undefined ? {':attachmentOperation': 'attachmentWrite'} : {}) } } });
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
      ...(enabled ? { title: '', content: '', ...(note.document !== undefined ? {document: null} : {}), ...(note.attachments !== undefined ? {attachments: []} : {}), labelIds: [], labelProjections: [], contentAvailable: false } : { contentAvailable: true }) };
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
