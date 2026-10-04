import type { DynamoDBDocumentClient, TransactWriteCommandInput } from '@aws-sdk/lib-dynamodb';
import { GetCommand, QueryCommand, TransactWriteCommand } from '@aws-sdk/lib-dynamodb';
import type { SecurityAuthorization } from '../protection/protection_store';
import { aclCondition } from '../sharing/dynamo_note_acl';
import { ActorFeed } from '../sharing/actor_feed';
import { AttachmentError, sameDescriptor } from './models';
import type { Attempt, AttachmentDescriptor } from './models';
type Writes = NonNullable<TransactWriteCommandInput['TransactItems']>;
export const attemptKey = (owner: string, note: string, id: string) =>
  ({ownerId: `OWNER#${owner}`, noteId: `ATTEMPT#${JSON.stringify([note, id])}`});
const cancellationKey = (owner: string, note: string, id: string) =>
  ({ownerId: `OWNER#${owner}`, noteId: `ATTACHMENT_CANCEL#${JSON.stringify([note, id])}`});

/** Same table and conditional Note authority as M02/M05/M06. No second Note writer. */
export class AttachmentAttemptStore {
  readonly feed: ActorFeed;
  constructor(readonly table: string, readonly db: DynamoDBDocumentClient) {
    this.feed = new ActorFeed(table, db);
  }
  async read(owner: string, note: string, id: string): Promise<Attempt | null> {
    const row = (await this.db.send(new GetCommand({TableName: this.table,
      Key: attemptKey(owner, note, id), ConsistentRead: true}))).Item;
    return row ? row.attempt as Attempt : null;
  }
  async forNote(owner: string, note: string): Promise<Attempt[]> {
    const result: Attempt[] = []; let start: Record<string, unknown> | undefined;
    do {
      const r = await this.db.send(new QueryCommand({TableName: this.table,
        KeyConditionExpression: 'ownerId = :owner AND begins_with(noteId, :prefix)',
        ExpressionAttributeValues: {':owner': `OWNER#${owner}`, ':prefix': `ATTEMPT#${JSON.stringify([note]).slice(0, -1)},`},
        ConsistentRead: true, ExclusiveStartKey: start}));
      result.push(...(r.Items ?? []).map(x => x.attempt as Attempt)); start = r.LastEvaluatedKey;
    } while (start);
    return result;
  }
  guards(a: SecurityAuthorization): Writes {
    return [...aclCondition(this.table, a), {ConditionCheck: {TableName: this.table,
      Key: {ownerId: `OWNER#${a.ownerId}`, noteId: `PROTECTION#${a.noteId}`},
      ConditionExpression: a.revision === 0 ? 'attribute_not_exists(noteId)' : 'revision = :epoch AND enabled = :enabled',
      ...(a.revision === 0 ? {} : {ExpressionAttributeValues: {':epoch': a.revision, ':enabled': a.enabled}})}},
      ...(a.enabled ? [{ConditionCheck: {TableName: this.table,
        Key: {ownerId: `OWNER#${a.ownerId}`, noteId: `GRANT#${a.grantHash}`},
        ConditionExpression: 'expiresAt > :now AND revision = :epoch AND actorId = :actor AND targetNoteId = :note AND contains(operations, :op)',
        ExpressionAttributeValues: {':now': Date.now(), ':epoch': a.revision, ':actor': a.actorId,
          ':note': a.noteId, ':op': a.operation}}}] : [])];
  }
  async save(before: Attempt | null, after: Attempt, authority: SecurityAuthorization, noteRevision: number) {
    const writes: Writes = [{Put: {TableName: this.table,
      Item: {...attemptKey(after.ownerId, after.targetNoteId, after.id), generation: after.generation, attempt: after},
      ConditionExpression: before ? 'generation = :generation' : 'attribute_not_exists(noteId)',
      ...(before ? {ExpressionAttributeValues: {':generation': before.generation}} : {})}},
      {ConditionCheck: {TableName: this.table,
        Key: {ownerId: `OWNER#${after.ownerId}`, noteId: `NOTE#${after.targetNoteId}`},
        ConditionExpression: 'revision = :revision AND deletedAt = :active',
      ExpressionAttributeValues: {':revision': noteRevision, ':active': null}}}, ...this.guards(authority)];
    if (!before) writes.push({ConditionCheck: {TableName: this.table,
      Key: cancellationKey(after.ownerId, after.targetNoteId, after.id),
      ConditionExpression: 'attribute_not_exists(noteId)'}});
    if (!before || before.phase !== 'cancelled' && after.phase === 'cancelled') {
      writes.push(await this.quotaWrite(after.ownerId, after.targetNoteId,
        before ? -1 : 1, before ? -after.sizeBytes : after.sizeBytes));
    }
    try { await this.db.send(new TransactWriteCommand({TransactItems: writes})); }
    catch (e) {
      if ((e as Error).name === 'TransactionCanceledException') throw new AttachmentError('stale');
      throw new AttachmentError('unavailable');
    }
  }
  /** A cancel ACK before begin must also prevent a late begin from admitting bytes. */
  async cancelMissing(owner: string, note: string, id: string, authority: SecurityAuthorization, noteRevision: number) {
    const writes: Writes = [{Put: {TableName: this.table,
      Item: {...cancellationKey(owner, note, id), cancelled: true}}},
      {ConditionCheck: {TableName: this.table, Key: attemptKey(owner, note, id),
        ConditionExpression: 'attribute_not_exists(noteId)'}},
      {ConditionCheck: {TableName: this.table,
        Key: {ownerId: `OWNER#${owner}`, noteId: `NOTE#${note}`},
        ConditionExpression: 'revision = :revision AND deletedAt = :active',
        ExpressionAttributeValues: {':revision': noteRevision, ':active': null}}}, ...this.guards(authority)];
    try { await this.db.send(new TransactWriteCommand({TransactItems: writes})); }
    catch (e) {
      if ((e as Error).name === 'TransactionCanceledException') throw new AttachmentError('stale');
      throw new AttachmentError('unavailable');
    }
  }
  /** Called inside the canonical Note commit; server ACK is the only Ready transition. */
  async associationWrites(owner: string, noteId: string, previous: readonly AttachmentDescriptor[],
    next: readonly AttachmentDescriptor[], protectionRevision: number): Promise<Writes> {
    const writes: Writes = [];
    for (const a of next) {
      const old = previous.find(x => x.id === a.id);
      if (old) { if (!sameDescriptor(old, a)) throw new AttachmentError('invalid'); continue; }
      const attempt = await this.read(owner, noteId, a.id);
      if (!attempt || attempt.actorId !== owner || attempt.phase !== 'verified' ||
          attempt.protectionRevision !== protectionRevision ||
          !attempt.descriptor || !sameDescriptor(attempt.descriptor, a)) throw new AttachmentError('denied');
      writes.push(this.transitionWrite(attempt, 'linked'));
    }
    const removed = previous.filter(x => !next.some(n => n.id === x.id));
    for (const old of removed) {
      const attempt = await this.read(owner, noteId, old.id);
      if (!attempt || attempt.phase !== 'linked' || !attempt.descriptor ||
          !sameDescriptor(old, attempt.descriptor)) throw new AttachmentError('unavailable');
      writes.push(this.transitionWrite(attempt, 'unlinked'));
    }
    if (removed.length) writes.push(await this.quotaWrite(owner, noteId,
      -removed.length, -removed.reduce((n, a) => n + a.sizeBytes, 0)));
    return writes;
  }
  private async quotaWrite(owner: string, note: string, countDelta: number, bytesDelta: number): Promise<Writes[number]> {
    const sort = `ATTACHMENT_QUOTA#${note}`;
    const old = await this.feed.item(owner, sort);
    const count = (old?.count ?? 0) + countDelta, bytes = (old?.bytes ?? 0) + bytesDelta;
    if (!Number.isSafeInteger(count) || !Number.isSafeInteger(bytes) || count < 0 || bytes < 0 ||
        count > 10 || bytes > 100 * 1024 * 1024) throw new AttachmentError('quota');
    return {Put: {TableName: this.table, Item: {ownerId: `OWNER#${owner}`, noteId: sort,
      generation: (old?.generation ?? 0) + 1, count, bytes},
      ConditionExpression: old ? 'generation = :generation' : 'attribute_not_exists(noteId)',
      ...(old ? {ExpressionAttributeValues: {':generation': old.generation}} : {})}};
  }
  private transitionWrite(a: Attempt, phase: Attempt['phase']): Writes[number] {
    return {Put: {TableName: this.table,
      Item: {...attemptKey(a.ownerId, a.targetNoteId, a.id), generation: a.generation + 1,
        attempt: {...a, phase, generation: a.generation + 1}},
      ConditionExpression: 'generation = :generation', ExpressionAttributeValues: {':generation': a.generation}}};
  }
}
