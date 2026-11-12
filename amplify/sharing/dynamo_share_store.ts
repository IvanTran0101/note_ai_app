import { TransactWriteCommand } from '@aws-sdk/lib-dynamodb';
import type { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import type { NoteSnapshot } from '../sync/sync_store_models';
import type { SecurityAuthorization } from '../protection/protection_store';
import { ActorFeed } from './actor_feed';
import { decodeShare, ShareError } from './share_models';
import type { ShareRecord, ShareStore } from './share_models';
import { shareKey } from './dynamo_note_acl';

export class DynamoShareStore implements ShareStore {
  private readonly feed: ActorFeed;
  constructor(private readonly table: string, private readonly db: DynamoDBDocumentClient) {
    this.feed = new ActorFeed(table, db);
  }
  list(owner: string, id: string) { return this.feed.shares(owner, id); }
  note(owner: string, id: string) { return this.feed.note(owner, id); }
  async read(owner: string, id: string, recipient: string) {
    const row = await this.feed.item(owner, shareKey(owner, id, recipient).noteId);
    if (!row) return null;
    const s = decodeShare(row);
    if (s.ownerId !== owner || s.noteId !== id || s.recipientId !== recipient) throw new ShareError('unavailable');
    return s;
  }
  async receipt(owner: string, requestId: string) {
    const row = await this.feed.item(owner, `SHARECOMMAND#${requestId}`);
    if (!row) return null;
    if (typeof row.fingerprint !== 'string') throw new ShareError('unavailable');
    return { fingerprint: row.fingerprint, share: decodeShare(row) };
  }
  async commit(previous: ShareRecord | null, next: ShareRecord, note: NoteSnapshot,
    a: SecurityAuthorization, requestId: string, fingerprint: string) {
    if (a.actorId !== next.ownerId || a.ownerId !== next.ownerId || a.noteId !== next.noteId || a.operation !== 'manage' ||
        (note.protected ?? false) !== a.enabled || (note.protectionRevision ?? 0) !== a.revision) throw new ShareError('staleAccess');
    const key = (sort: string) => ({ ownerId: `OWNER#${next.ownerId}`, noteId: sort });
    const version = note.sharingRevision ?? 0;
    const writes = [
      { Put: { TableName: this.table, Item: { ...shareKey(next.ownerId, next.noteId, next.recipientId), share: next },
        ConditionExpression: previous ? '#s.accessRevision = :seen AND #s.#status = :status' : 'attribute_not_exists(noteId)',
        ...(previous ? { ExpressionAttributeNames: { '#s': 'share', '#status': 'status' },
          ExpressionAttributeValues: { ':seen': previous.accessRevision, ':status': previous.status } } : {}) } },
      { Update: { TableName: this.table, Key: key(`NOTE#${next.noteId}`),
        UpdateExpression: 'SET sharingRevision = :next',
        ConditionExpression: 'revision = :revision AND attribute_exists(noteId) AND (attribute_not_exists(sharingRevision) OR sharingRevision = :seen)',
        ExpressionAttributeValues: { ':next': version + 1, ':seen': version, ':revision': note.revision } } },
      { ConditionCheck: { TableName: this.table, Key: key(`PROTECTION#${next.noteId}`),
        ConditionExpression: a.revision ? 'revision = :epoch AND enabled = :enabled' : 'attribute_not_exists(noteId)',
        ...(a.revision ? { ExpressionAttributeValues: { ':epoch': a.revision, ':enabled': a.enabled } } : {}) } },
      { Put: { TableName: this.table, Item: { ...key(`SHARECOMMAND#${requestId}`), fingerprint, share: next },
        ConditionExpression: 'attribute_not_exists(noteId)' } },
      ...await this.feed.append(next.ownerId, note),
      ...await this.feed.append(next.recipientId, { ...note, ownerId: next.ownerId, share: next }),
      this.feed.event(next.ownerId, { ...note, sharingRevision: version + 1 }, [next.ownerId, next.recipientId]),
    ];
    if (a.enabled) writes.push({ ConditionCheck: { TableName: this.table, Key: key(`GRANT#${a.grantHash}`),
      ConditionExpression: 'expiresAt > :now AND revision = :epoch AND actorId = :actor AND targetNoteId = :note AND contains(operations, :op)',
      ExpressionAttributeValues: { ':now': Date.now(), ':epoch': a.revision, ':actor': a.actorId, ':note': next.noteId, ':op': 'manage' } } });
    try { await this.db.send(new TransactWriteCommand({ TransactItems: writes })); }
    catch (error) {
      throw new ShareError((error as Error).name === 'TransactionCanceledException' ? 'staleAccess' : 'unavailable');
    }
  }
}
