import { createHash } from 'node:crypto';
import { NoteSecurityError, identifier } from './protection_store';
import type { NoteAcl, NoteOperation, NoteSecurityAuthority, ProtectionMetadata,
  ProtectionStore, SecurityAuthorization } from './protection_store';

export const securityDigest = (value: string): string =>
  createHash('sha256').update(value, 'utf8').digest('hex');

/** Read-only authority shared by sync, protection and Summary adapters. */
export class ProtectionAuthorizer implements NoteSecurityAuthority {
  constructor(private readonly store: ProtectionStore, private readonly acl: NoteAcl,
    private readonly now: () => number = Date.now) {}

  async metadata(actor: string, owner: string, noteId: string, allowMissing = false): Promise<ProtectionMetadata> {
    await this.acl.require(actor, owner, identifier(noteId), 'read');
    const note = await this.store.readNote(owner, noteId);
    if (!note && !allowMissing) throw new NoteSecurityError('denied');
    const { enabled, revision } = await this.store.readProtection(owner, noteId);
    if (note?.protected && (!enabled || revision < (note.protectionRevision ?? 0))) {
      throw new NoteSecurityError('unavailable');
    }
    return { enabled, revision };
  }

  async authorize(actorId: string, ownerId: string, noteId: string,
    operation: NoteOperation, token?: string): Promise<SecurityAuthorization> {
    const access = await this.acl.require(actorId, ownerId, identifier(noteId), operation);
    if ((operation === 'manage' || operation === 'delete') && actorId !== ownerId) {
      throw new NoteSecurityError('denied');
    }
    const protection = await this.store.readProtection(ownerId, noteId);
    const base = { actorId, ownerId, noteId, operation,
      enabled: protection.enabled, revision: protection.revision, ...(access ? { access } : {}) };
    if (!protection.enabled) return base;
    if (!token || !/^[A-Za-z0-9_-]{43}$/.test(token)) throw new NoteSecurityError('locked');
    const hash = securityDigest(token);
    const grant = await this.store.readGrant(ownerId, hash);
    if (!grant || grant.actorId !== actorId || grant.ownerId !== ownerId ||
        grant.noteId !== noteId || grant.revision !== protection.revision ||
        !grant.operations.includes(operation)) throw new NoteSecurityError('denied');
    if (grant.expiresAt <= this.now()) throw new NoteSecurityError('expired');
    return { ...base, grantHash: hash, expiresAt: grant.expiresAt };
  }
}
