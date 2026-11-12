import { GetCommand, QueryCommand } from '@aws-sdk/lib-dynamodb';
import type { DynamoDBDocumentClient, TransactWriteCommandInput } from '@aws-sdk/lib-dynamodb';
import { snapshotAttributes, toNoteSnapshot } from '../sync/sync_store_codec';
import type { NoteSnapshot } from '../sync/sync_store_models';
import { decodeShare, ShareError, sharePrefix } from './share_models';
import type { ShareRecord } from './share_models';

type Writes = NonNullable<TransactWriteCommandInput['TransactItems']>;
export const MAX_ACTIVE_RECIPIENTS = 20;
/** One relay event per shard; keeps every transaction write well-formed. */
export const MAX_EVENT_ACTORS = 21;
const key = (actor: string, sort: string) => ({ ownerId: `OWNER#${actor}`, noteId: sort });

/** One counter/feed per actor, shared with existing owned-note sync. */
export class ActorFeed {
  constructor(readonly table: string, readonly db: DynamoDBDocumentClient) {}
  async item(actor: string, sort: string) {
    return (await this.db.send(new GetCommand({ TableName: this.table,
      Key: key(actor, sort), ConsistentRead: true }))).Item ?? null;
  }
  async note(owner: string, id: string): Promise<NoteSnapshot | null> {
    const row = await this.item(owner, `NOTE#${id}`);
    return row ? toNoteSnapshot(row) : null;
  }
  /** Every share row of one note, paginated. Read-only: the active-recipient
   *  cap is enforced on the create path (ShareUseCases.apply), never here -
   *  fanout for note mutations and protection commits depends on this read, and
   *  an over-limit row set must not brick writes or revokes. */
  async shares(owner: string, id: string): Promise<ShareRecord[]> {
    const result: ShareRecord[] = [];
    let start: Record<string, unknown> | undefined;
    do {
      const r = await this.db.send(new QueryCommand({ TableName: this.table,
        KeyConditionExpression: 'ownerId = :owner AND begins_with(noteId, :prefix)',
        ExpressionAttributeValues: { ':owner': `OWNER#${owner}`, ':prefix': sharePrefix(id) },
        ConsistentRead: true, ExclusiveStartKey: start }));
      for (const row of r.Items ?? []) {
        const s = decodeShare(row);
        if (s.ownerId !== owner || s.noteId !== id) throw new ShareError('unavailable');
        result.push(s);
      }
      start = r.LastEvaluatedKey;
    } while (start);
    return result;
  }
  async append(actor: string, snapshot: NoteSnapshot): Promise<Writes> {
    const meta = await this.item(actor, 'META#SYNC');
    const seen = meta?.lastSequence ?? 0;
    if (!Number.isSafeInteger(seen) || seen < 0) throw new ShareError('unavailable');
    const attributes = snapshotAttributes(snapshot);
    const privateContent = snapshot.protected || snapshot.share?.status === 'revoked';
    return [
      { Update: { TableName: this.table, Key: key(actor, 'META#SYNC'),
        UpdateExpression: 'SET lastSequence = :next',
        ConditionExpression: 'attribute_not_exists(lastSequence) OR lastSequence = :seen',
        ExpressionAttributeValues: { ':next': seen + 1, ':seen': seen } } },
      { Put: { TableName: this.table, Item: { ...key(actor, `CHANGE#${seen + 1}`),
        ...attributes, ...(privateContent ? { title: '', content: '', ...(snapshot.document !== undefined ? {document: null} : {}), ...(snapshot.attachments !== undefined ? {attachments: []} : {}) } : {}),
        changeOwnerId: `OWNER#${actor}`, changeSequence: seen + 1 } } },
    ];
  }
  async fanout(owner: string, note: NoteSnapshot): Promise<Writes> {
    const active = (await this.shares(owner, note.id)).filter(s => s.status === 'active');
    const writes = (await Promise.all(active.map(s =>
      this.append(s.recipientId, { ...note, ownerId: owner, share: s })))).flat();
    if (active.length) writes.push(...this.events(owner, note, [owner, ...active.map(s => s.recipientId)]));
    return writes;
  }
  /** Bounded future fanout: every actor appears in exactly one event shard. */
  events(owner: string, note: NoteSnapshot, actors: readonly string[], now = Date.now()): Writes {
    const unique = [...new Set(actors)];
    const writes: Writes = [];
    for (let index = 0; index < unique.length; index += MAX_EVENT_ACTORS) {
      writes.push(this.eventAt(owner, note, unique.slice(index, index + MAX_EVENT_ACTORS), now));
    }
    return writes;
  }
  /** Two-actor create/revoke path. Bulk fanout uses events() above. */
  event(owner: string, note: NoteSnapshot, actors: readonly string[]): Writes[number] {
    return this.eventAt(owner, note, actors, Date.now());
  }
  private eventAt(owner: string, note: NoteSnapshot, actors: readonly string[], now: number): Writes[number] {
    const eventId = crypto.randomUUID();
    // Durable invalidation only. Private content, email and grants never enter events.
    return { Put: { TableName: this.table, Item: { ...key(owner, `EVENT#${eventId}`),
      eventId, canonicalOwnerId: owner, targetNoteId: note.id, revision: note.revision,
      protectionRevision: note.protectionRevision ?? 0, sharingRevision: note.sharingRevision ?? 0,
      actors: [...new Set(actors)], relayStatus: 'pending', attempts: 0,
        nextAttemptAt: now, relayQueue: 'pending', relayDueAt: now,
        createdAt: new Date(now).toISOString() } } };
  }
}
