import { GetCommand, PutCommand, TransactWriteCommand, UpdateCommand,
  type TransactWriteCommandInput,
  type DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { toNoteSnapshot } from '../sync/sync_store_codec';
import { ActorFeed } from '../sharing/actor_feed';
import { NOTE_OPERATIONS, NoteSecurityError } from './protection_store';
import type { GrantRecord, ProtectionRecord, ProtectionStore,
  RecoveryChallenge, SecurityAuthorization } from './protection_store';

const key = (owner: string, sort: string) => ({ ownerId: `OWNER#${owner}`, noteId: sort });
const isConditional = (error: unknown) =>
  ['ConditionalCheckFailedException', 'TransactionCanceledException'].includes((error as Error)?.name);
const number = (value: unknown): number => {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) throw new NoteSecurityError('unavailable');
  return value;
};
const text = (value: unknown): string => {
  if (typeof value !== 'string') throw new NoteSecurityError('unavailable');
  return value;
};

/** Provider adapter; epoch/feed cutover is one conditional DynamoDB transaction. */
export class DynamoProtectionStore implements ProtectionStore {
  constructor(private readonly table: string, private readonly db: DynamoDBDocumentClient, private readonly sharing = false) {
    if (!table) throw new NoteSecurityError('unavailable');
  }

  private async get(owner: string, sort: string): Promise<Record<string, unknown> | null> {
    try {
      return (await this.db.send(new GetCommand({ TableName: this.table,
        Key: key(owner, sort), ConsistentRead: true }), { abortSignal: AbortSignal.timeout(2000) })).Item ?? null;
    } catch { throw new NoteSecurityError('unavailable'); }
  }

  async readProtection(ownerId: string, noteId: string): Promise<ProtectionRecord> {
    const item = await this.get(ownerId, `PROTECTION#${noteId}`);
    if (!item) return { ownerId, noteId, enabled: false, revision: 0, verifier: null };
    const revision = number(item.revision);
    if (typeof item.enabled !== 'boolean' || item.canonicalOwnerId !== ownerId ||
        item.targetNoteId !== noteId || (item.enabled && (!revision || typeof item.verifier !== 'string')) ||
        (!item.enabled && item.verifier !== null)) throw new NoteSecurityError('unavailable');
    return { ownerId, noteId, enabled: item.enabled, revision,
      verifier: item.enabled ? text(item.verifier) : null };
  }

  async readNote(ownerId: string, noteId: string) {
    const item = await this.get(ownerId, `NOTE#${noteId}`);
    return item ? toNoteSnapshot(item) : null;
  }

  async commitProtection(current: ProtectionRecord, next: ProtectionRecord,
    expectedContentRevision: number, authority?: SecurityAuthorization): Promise<void> {
    if (next.ownerId !== current.ownerId || next.noteId !== current.noteId ||
        next.revision !== current.revision + 1) throw new NoteSecurityError('invalidInput');
    for (let attempt = 0; attempt < 4; attempt++) {
      const note = await this.readNote(current.ownerId, current.noteId);
      if (!note || note.deletedAt || note.revision !== expectedContentRevision) throw new NoteSecurityError('staleRevision');
      const meta = await this.get(current.ownerId, 'META#SYNC');
      const sequence = number(meta?.lastSequence ?? 0);
      const now = new Date().toISOString();
      try {
        const writes: TransactWriteCommandInput['TransactItems'] = [
          { Put: { TableName: this.table, Item: { ...next,
            ...key(next.ownerId, `PROTECTION#${next.noteId}`),
            canonicalOwnerId: next.ownerId, targetNoteId: next.noteId },
            ConditionExpression: current.revision === 0 ? 'attribute_not_exists(noteId)' : 'revision = :epoch',
            ...(current.revision === 0 ? {} : { ExpressionAttributeValues: { ':epoch': current.revision } }) } },
          { Update: { TableName: this.table, Key: key(next.ownerId, `NOTE#${next.noteId}`),
            UpdateExpression: 'SET #protected = :enabled, protectionRevision = :epoch, serverUpdatedAt = :now',
            ConditionExpression: 'revision = :contentRevision AND attribute_exists(noteId) AND (attribute_not_exists(sharingRevision) OR sharingRevision = :membership)',
            ExpressionAttributeNames: { '#protected': 'protected' },
            ExpressionAttributeValues: { ':enabled': next.enabled, ':epoch': next.revision,
              ':now': now, ':contentRevision': expectedContentRevision, ':membership': note.sharingRevision ?? 0 } } },
          { Update: { TableName: this.table, Key: key(next.ownerId, 'META#SYNC'),
            UpdateExpression: 'SET lastSequence = :next',
            ConditionExpression: 'attribute_not_exists(lastSequence) OR lastSequence = :seen',
            ExpressionAttributeValues: { ':next': sequence + 1, ':seen': sequence } } },
          { Put: { TableName: this.table, Item: { ...note,
            ...key(next.ownerId, `CHANGE#${sequence + 1}`), serverUpdatedAt: now,
            protected: next.enabled, protectionRevision: next.revision,
            ...(next.enabled ? { title: '', content: '', ...(note.document !== undefined ? {document: null} : {}) } : {}),
            changeOwnerId: `OWNER#${next.ownerId}`, changeSequence: sequence + 1 } } },
        ];
        if (this.sharing) writes.push(...await new ActorFeed(this.table, this.db).fanout(next.ownerId,
          { ...note, serverUpdatedAt: now, protected: next.enabled, protectionRevision: next.revision }));
        if (authority) writes.push({ ConditionCheck: { TableName: this.table,
          Key: key(current.ownerId, `GRANT#${authority.grantHash}`),
          ConditionExpression: 'expiresAt > :now AND revision = :epoch AND actorId = :actor AND targetNoteId = :note AND contains(operations, :operation)',
          ExpressionAttributeValues: { ':now': Date.now(), ':epoch': current.revision,
            ':actor': authority.actorId, ':note': current.noteId, ':operation': 'manage' } } });
        await this.db.send(new TransactWriteCommand({ TransactItems: writes }));
        return;
      } catch (error) {
        if (!isConditional(error)) throw new NoteSecurityError('unavailable');
        const live = await this.readProtection(current.ownerId, current.noteId);
        if (live.revision !== current.revision) throw new NoteSecurityError('staleRevision');
      }
    }
    throw new NoteSecurityError('staleRevision');
  }

  async putGrant(grant: GrantRecord): Promise<void> {
    try {
      await this.db.send(new TransactWriteCommand({ TransactItems: [
        { ConditionCheck: { TableName: this.table,
          Key: key(grant.ownerId, `PROTECTION#${grant.noteId}`),
          ConditionExpression: 'enabled = :enabled AND revision = :epoch',
          ExpressionAttributeValues: { ':enabled': true, ':epoch': grant.revision } } },
        { Put: { TableName: this.table, Item: { ...grant,
          ...key(grant.ownerId, `GRANT#${grant.hash}`), canonicalOwnerId: grant.ownerId,
          targetNoteId: grant.noteId, ttl: Math.floor(grant.expiresAt / 1000) },
          ConditionExpression: 'attribute_not_exists(noteId)' } },
      ] }));
    } catch (error) { throw new NoteSecurityError(isConditional(error) ? 'staleRevision' : 'unavailable'); }
  }

  async readGrant(ownerId: string, hash: string): Promise<GrantRecord | null> {
    const item = await this.get(ownerId, `GRANT#${hash}`);
    if (!item) return null;
    if (item.canonicalOwnerId !== ownerId || item.hash !== hash || !Array.isArray(item.operations) ||
        item.operations.some(op => !NOTE_OPERATIONS.includes(op))) throw new NoteSecurityError('unavailable');
    return { ownerId, hash, actorId: text(item.actorId), noteId: text(item.targetNoteId),
      revision: number(item.revision), operations: item.operations,
      issuedAt: number(item.issuedAt), expiresAt: number(item.expiresAt) };
  }

  async reservePasswordAttempt(owner: string, noteId: string, actor: string, now: number): Promise<void> {
    // Counter belongs to this note/actor, so lockout never blocks another note.
    const sort = `ATTEMPT#${noteId}#${actor}`;
    for (let attempt = 0; attempt < 4; attempt++) {
      const item = await this.get(owner, sort);
      const window = number(item?.window ?? 0);
      const count = number(item?.attempts ?? 0);
      const sameWindow = item !== null && now - window < 60_000;
      if (sameWindow && count >= 5) throw new NoteSecurityError('rateLimited');
      try {
        await this.db.send(new PutCommand({ TableName: this.table,
          Item: { ...key(owner, sort), window: sameWindow ? window : now,
            attempts: sameWindow ? count + 1 : 1, ttl: Math.floor(now / 1000) + 120 },
          ConditionExpression: item ? '#window = :seen AND attempts = :count' : 'attribute_not_exists(noteId)',
          ...(item ? { ExpressionAttributeNames: { '#window': 'window' },
            ExpressionAttributeValues: { ':seen': window, ':count': count } } : {}) }));
        return;
      } catch (error) { if (!isConditional(error)) throw new NoteSecurityError('unavailable'); }
    }
    throw new NoteSecurityError('rateLimited');
  }

  async putChallenge(challenge: RecoveryChallenge): Promise<void> {
    try {
      await this.db.send(new PutCommand({ TableName: this.table, Item: { ...challenge,
        ...key(challenge.ownerId, `CHALLENGE#${challenge.id}`),
        canonicalOwnerId: challenge.ownerId, targetNoteId: challenge.noteId,
        ttl: Math.floor(challenge.expiresAt / 1000) }, ConditionExpression: 'attribute_not_exists(noteId)' }));
    } catch { throw new NoteSecurityError('unavailable'); }
  }

  async readChallenge(ownerId: string, id: string): Promise<RecoveryChallenge | null> {
    const item = await this.get(ownerId, `CHALLENGE#${id}`);
    if (!item) return null;
    if (item.canonicalOwnerId !== ownerId || item.id !== id || typeof item.consumed !== 'boolean') {
      throw new NoteSecurityError('unavailable');
    }
    return { id, ownerId, noteId: text(item.targetNoteId), actorId: text(item.actorId),
      mailboxHash: text(item.mailboxHash), codeHash: text(item.codeHash),
      revision: number(item.revision), expiresAt: number(item.expiresAt),
      attempts: number(item.attempts), consumed: item.consumed };
  }

  async advanceChallenge(challenge: RecoveryChallenge, consumed: boolean, now: number): Promise<void> {
    try {
      await this.db.send(new UpdateCommand({ TableName: this.table,
        Key: key(challenge.ownerId, `CHALLENGE#${challenge.id}`),
        UpdateExpression: 'SET attempts = :next, consumed = :consumed',
        ConditionExpression: 'attempts = :seen AND attempts < :max AND consumed = :unused AND expiresAt > :now',
        ExpressionAttributeValues: { ':next': challenge.attempts + 1, ':consumed': consumed,
          ':seen': challenge.attempts, ':max': 5, ':unused': false, ':now': now } }));
    } catch { throw new NoteSecurityError('invalidChallenge'); }
  }
}
