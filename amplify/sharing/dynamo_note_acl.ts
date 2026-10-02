import { GetCommand } from '@aws-sdk/lib-dynamodb';
import type { DynamoDBDocumentClient, TransactWriteCommandInput } from '@aws-sdk/lib-dynamodb';
import { identifier, NoteSecurityError } from '../protection/protection_store';
import type { NoteAcl, NoteOperation, SecurityAuthorization } from '../protection/protection_store';
import { decodeShare, shareSortKey } from './share_models';
import type { AccessStamp, ShareRecord } from './share_models';

export const shareKey = (owner: string, note: string, recipient: string) =>
  ({ ownerId: `OWNER#${owner}`, noteId: shareSortKey(note, recipient) });

export class DynamoNoteAcl implements NoteAcl {
  constructor(private readonly table: string, private readonly db: DynamoDBDocumentClient) {}
  async read(actor: string, owner: string, noteId: string): Promise<ShareRecord | null> {
    const r = await this.db.send(new GetCommand({ TableName: this.table,
      Key: shareKey(owner, noteId, actor), ConsistentRead: true }));
    const s = r.Item ? decodeShare(r.Item) : null;
    if (s && (s.ownerId !== owner || s.noteId !== noteId || s.recipientId !== actor)) {
      throw new NoteSecurityError('unavailable');
    }
    return s;
  }
  async require(actor: string, owner: string, noteId: string, op: NoteOperation): Promise<AccessStamp | void> {
    identifier(actor); identifier(owner); identifier(noteId);
    if (actor === owner) return;
    const share = await this.read(actor, owner, noteId);
    if (!share || share.status !== 'active' ||
        !(['read', 'summary', 'attachmentRead'].includes(op) || op === 'edit' && share.role === 'editor')) {
      throw new NoteSecurityError('denied');
    }
    return { actorId: actor, ownerId: owner, noteId, role: share.role, accessRevision: share.accessRevision };
  }
}

export function aclCondition(table: string, authority: SecurityAuthorization): NonNullable<TransactWriteCommandInput['TransactItems']> {
  const a = authority.access;
  if (!a) {
    if (authority.actorId !== authority.ownerId) throw new NoteSecurityError('denied');
    return [];
  }
  if (a.actorId !== authority.actorId || a.ownerId !== authority.ownerId || a.noteId !== authority.noteId) {
    throw new NoteSecurityError('denied');
  }
  return [{ ConditionCheck: { TableName: table, Key: shareKey(a.ownerId, a.noteId, a.actorId),
    ConditionExpression: '#s.#status = :active AND #s.accessRevision = :r AND #s.#role = :role AND #s.recipientId = :actor',
    ExpressionAttributeNames: { '#s': 'share', '#status': 'status', '#role': 'role' },
    ExpressionAttributeValues: { ':active': 'active', ':r': a.accessRevision, ':role': a.role, ':actor': a.actorId } } }];
}
