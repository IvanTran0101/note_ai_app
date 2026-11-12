import { identifier, NoteSecurityError } from '../protection/protection_store';
import type { NoteSecurityAuthority } from '../protection/protection_store';
import { stableDigest } from '../sync/cursor';
import { normalizedEmail } from './cognito_recipient_resolver';
import { MAX_ACTIVE_RECIPIENTS } from './actor_feed';
import { ShareError } from './share_models';
import type { ShareCommand, ShareRecord, ShareStore, RecipientResolver } from './share_models';

export class ShareUseCases {
  constructor(private readonly store: ShareStore, private readonly resolver: RecipientResolver,
    private readonly security: NoteSecurityAuthority, private readonly now = Date.now) {}
  async list(actor: string, owner: string, id: string, grant?: string) {
    await this.security.authorize(actor, owner, id, 'manage', grant);
    const rows = await this.store.list(owner, id);
    await this.security.authorize(actor, owner, id, 'manage', grant);
    return rows;
  }
  async apply(actor: string, owner: string, id: string, cmd: ShareCommand, grant?: string): Promise<ShareRecord> {
    identifier(actor); identifier(owner); identifier(id); identifier(cmd.requestId);
    if (actor !== owner) throw new NoteSecurityError('denied');
    await this.security.authorize(actor, owner, id, 'manage', grant);
    if (!['create', 'role', 'revoke'].includes(cmd.action) || !Number.isSafeInteger(cmd.expectedAccessRevision) ||
        cmd.expectedAccessRevision < 0 || (cmd.action !== 'revoke' && !['viewer', 'editor'].includes(cmd.role ?? ''))) {
      throw new ShareError('invalidInput');
    }
    const email = cmd.action === 'create' && typeof cmd.email === 'string' ? normalizedEmail(cmd.email) : undefined;
    if (cmd.action === 'create' ? !email || cmd.recipientId !== undefined : !cmd.recipientId || cmd.email !== undefined) {
      throw new ShareError('invalidInput');
    }
    const fingerprint = stableDigest(JSON.stringify([owner, id, cmd.action, email ?? null,
      cmd.recipientId ?? null, cmd.role ?? null, cmd.expectedAccessRevision]));
    const receipt = await this.store.receipt(owner, cmd.requestId);
    if (receipt) {
      if (receipt.fingerprint !== fingerprint) throw new ShareError('invalidInput');
      await this.security.authorize(actor, owner, id, 'manage', grant);
      // Re-read current ACL so a lost-ACK replay never resurrects revoked access.
      const current = await this.store.read(owner, id, receipt.share.recipientId);
      if (!current) throw new ShareError('unavailable');
      return current;
    }
    const recipient = email ? await this.resolver.resolve(email) : identifier(cmd.recipientId);
    if (recipient === owner) throw new ShareError('selfShare');
    // The note is read FIRST because it pins the sharingRevision the commit CAS
    // binds to; the share list is read AFTER it, so its count reflects at least
    // the pinned revision. Any concurrent share write that lands after the pin
    // bumps sharingRevision and cancels the CAS below. Reading these in
    // Promise.all instead could pair an older list snapshot with a newer note
    // revision and admit one share beyond the cap.
    const note = await this.store.note(owner, id);
    const previous = await this.store.read(owner, id, recipient);
    const shares = await this.store.list(owner, id);
    if (!note || note.deletedAt) throw new NoteSecurityError('denied');
    if (cmd.action === 'create' && previous?.status === 'active') throw new ShareError('duplicate');
    if ((previous?.accessRevision ?? 0) !== cmd.expectedAccessRevision ||
        (cmd.action !== 'create' && previous?.status !== 'active')) throw new ShareError('staleAccess');
    if (cmd.action === 'create' && shares.filter(s => s.status === 'active').length >= MAX_ACTIVE_RECIPIENTS) {
      throw new ShareError('limit');
    }
    const timestamp = new Date(this.now()).toISOString();
    const next: ShareRecord = { ownerId: owner, noteId: id, recipientId: recipient,
      role: cmd.role ?? previous!.role, accessRevision: (previous?.accessRevision ?? 0) + 1,
      status: cmd.action === 'revoke' ? 'revoked' : 'active',
      sharedAt: cmd.action === 'create' ? timestamp : previous!.sharedAt, updatedAt: timestamp,
      revokedAt: cmd.action === 'revoke' ? timestamp : null };
    const authority = await this.security.authorize(actor, owner, id, 'manage', grant);
    await this.store.commit(previous, next, note, authority, cmd.requestId, fingerprint);
    await this.security.authorize(actor, owner, id, 'manage', grant);
    return next;
  }
}
