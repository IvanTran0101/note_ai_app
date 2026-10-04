import type { NoteSnapshot } from '../sync/sync_store_models';
import type { NoteSecurityAuthority } from '../protection/protection_store';
import { NoteSecurityError } from '../protection/protection_store';
import { DynamoNoteAcl } from './dynamo_note_acl';

/** ACL is evaluated now, even for an old feed row or a lost-ACK receipt. */
export async function recipientProjection(actor: string, owner: string, note: NoteSnapshot,
  acl: DynamoNoteAcl, security: NoteSecurityAuthority): Promise<NoteSnapshot> {
  const share = await acl.read(actor, owner, note.id);
  if (!share) throw new NoteSecurityError('denied');
  if (share.status === 'revoked') return { ...note, ownerId: owner, share,
    title: '', content: '', ...(note.attachments !== undefined ? {attachments: []} : {}), labelIds: [], labelProjections: [], contentAvailable: false, deletedAt: null };
  const protection = await security.metadata(actor, owner, note.id);
  const live = await acl.read(actor, owner, note.id);
  if (!live || live.status !== 'active' || live.accessRevision !== share.accessRevision) throw new NoteSecurityError('denied');
  return { ...note, ownerId: owner, share: live, protected: protection.enabled,
    protectionRevision: protection.revision,
    ...(protection.enabled ? { title: '', content: '', ...(note.attachments !== undefined ? {attachments: []} : {}), labelIds: [], labelProjections: [], contentAvailable: false } : { contentAvailable: true }) };
}
