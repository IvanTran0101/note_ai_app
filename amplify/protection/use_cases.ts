import { createHash, randomBytes, randomInt, timingSafeEqual } from 'node:crypto';
import type { PasswordHasher } from './password_hasher';
import type { RecoveryMailer } from './recovery_mailer';
import { NOTE_OPERATIONS, NoteSecurityError, identifier } from './protection_store';
import type { GrantRecord, NoteAcl, NoteOperation, NoteSecurityAuthority,
  ProtectionMetadata, ProtectionRecord, ProtectionStore, SecurityAuthorization } from './protection_store';

export const securityDigest = (value: string): string =>
  createHash('sha256').update(value, 'utf8').digest('hex');
const equalDigest = (a: string, b: string): boolean => {
  if (!/^[a-f0-9]{64}$/.test(a) || !/^[a-f0-9]{64}$/.test(b)) return false;
  return timingSafeEqual(Buffer.from(a, 'hex'), Buffer.from(b, 'hex'));
};

export type UnlockResult = ProtectionMetadata & Readonly<{
  grant: string; operations: readonly NoteOperation[]; expiresAt: number;
}>;

export class ProtectionUseCases implements NoteSecurityAuthority {
  private readonly ttlMs: number;
  constructor(readonly store: ProtectionStore, private readonly hasher: PasswordHasher,
    private readonly acl: NoteAcl, private readonly mailer: RecoveryMailer,
    private readonly now: () => number = Date.now, ttlMs = 15 * 60_000) {
    if (!Number.isFinite(ttlMs) || ttlMs < 60_000 || ttlMs > 3_600_000) throw new NoteSecurityError('unavailable');
    this.ttlMs = ttlMs;
  }

  async metadata(actor: string, owner: string, noteId: string): Promise<ProtectionMetadata> {
    await this.acl.require(actor, owner, identifier(noteId), 'read');
    const note = await this.store.readNote(owner, noteId);
    if (!note) throw new NoteSecurityError('denied');
    const { enabled, revision } = await this.store.readProtection(owner, noteId);
    if (note.protected && (!enabled || revision < (note.protectionRevision ?? 0))) {
      throw new NoteSecurityError('unavailable');
    }
    return { enabled, revision };
  }

  async authorize(actorId: string, ownerId: string, noteId: string,
    operation: NoteOperation, token?: string): Promise<SecurityAuthorization> {
    await this.acl.require(actorId, ownerId, identifier(noteId), operation);
    if ((operation === 'manage' || operation === 'delete') && actorId !== ownerId) throw new NoteSecurityError('denied');
    const protection = await this.store.readProtection(ownerId, noteId);
    const base = { actorId, ownerId, noteId, operation,
      enabled: protection.enabled, revision: protection.revision };
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

  async enable(actor: string, owner: string, noteId: string, password: string,
    expectedContentRevision: number): Promise<ProtectionMetadata> {
    await this.acl.require(actor, owner, identifier(noteId), 'manage');
    const note = await this.requireNote(owner, noteId);
    const current = await this.store.readProtection(owner, noteId);
    if (current.enabled || note.revision !== expectedContentRevision) throw new NoteSecurityError('staleRevision');
    const next = { ...current, enabled: true, revision: current.revision + 1,
      verifier: await this.hasher.hash(password) };
    await this.store.commitProtection(current, next, expectedContentRevision);
    return { enabled: next.enabled, revision: next.revision };
  }

  async unlock(actor: string, owner: string, noteId: string, password: string,
    operations: readonly NoteOperation[]): Promise<UnlockResult> {
    await this.acl.require(actor, owner, identifier(noteId), 'read');
    await this.requireNote(owner, noteId);
    const current = await this.store.readProtection(owner, noteId);
    if (!current.enabled) throw new NoteSecurityError('invalidInput');
    await this.verifyPassword(actor, current, password);
    return this.issueGrant(actor, current, operations);
  }

  async change(actor: string, owner: string, noteId: string, currentPassword: string,
    newPassword: string, expectedEpoch: number, token?: string): Promise<ProtectionMetadata> {
    await this.authorize(actor, owner, noteId, 'manage', token);
    const current = await this.store.readProtection(owner, noteId);
    if (!current.enabled || current.revision !== expectedEpoch) throw new NoteSecurityError('staleRevision');
    await this.verifyPassword(actor, current, currentPassword);
    const note = await this.requireNote(owner, noteId);
    const next = { ...current, revision: current.revision + 1,
      verifier: await this.hasher.hash(newPassword) };
    await this.store.commitProtection(current, next, note.revision,
      await this.authorize(actor, owner, noteId, 'manage', token));
    return { enabled: true, revision: next.revision };
  }

  async disable(actor: string, owner: string, noteId: string, currentPassword: string,
    expectedEpoch: number, token?: string): Promise<ProtectionMetadata> {
    await this.authorize(actor, owner, noteId, 'manage', token);
    const current = await this.store.readProtection(owner, noteId);
    if (!current.enabled || current.revision !== expectedEpoch) throw new NoteSecurityError('staleRevision');
    await this.verifyPassword(actor, current, currentPassword);
    const note = await this.requireNote(owner, noteId);
    const next = { ...current, enabled: false, revision: current.revision + 1, verifier: null };
    await this.store.commitProtection(current, next, note.revision,
      await this.authorize(actor, owner, noteId, 'manage', token));
    return { enabled: false, revision: next.revision };
  }

  async content(actor: string, owner: string, noteId: string, token?: string) {
    const before = await this.authorize(actor, owner, noteId, 'read', token);
    const note = await this.requireNote(owner, noteId);
    const after = await this.authorize(actor, owner, noteId, 'read', token);
    if (before.revision !== after.revision || (note.protected && !after.enabled) ||
        (note.protectionRevision ?? 0) > after.revision) throw new NoteSecurityError('staleRevision');
    return { ...note, protected: after.enabled, protectionRevision: after.revision, contentAvailable: true };
  }

  async requestRecovery(actor: string, owner: string, noteId: string, mailbox: string) {
    await this.acl.require(actor, owner, identifier(noteId), 'manage');
    await this.requireNote(owner, noteId);
    const current = await this.store.readProtection(owner, noteId);
    if (!current.enabled || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(mailbox)) throw new NoteSecurityError('invalidInput');
    await this.store.reservePasswordAttempt(owner, noteId, actor, this.now());
    const id = randomBytes(24).toString('base64url');
    const code = randomInt(0, 1_000_000).toString().padStart(6, '0');
    const expiresAt = this.now() + 5 * 60_000;
    await this.store.putChallenge({ id, ownerId: owner, noteId, actorId: actor,
      mailboxHash: securityDigest(mailbox.toLowerCase()), codeHash: securityDigest(`${id}:${code}`),
      revision: current.revision, expiresAt, attempts: 0, consumed: false });
    await this.mailer.sendCode(mailbox, code);
    return { challengeId: id, expiresAt };
  }

  async confirmRecovery(actor: string, owner: string, noteId: string, mailbox: string,
    challengeId: string, code: string, newPassword: string): Promise<UnlockResult> {
    await this.acl.require(actor, owner, identifier(noteId), 'manage');
    const challenge = await this.store.readChallenge(owner, identifier(challengeId));
    const current = await this.store.readProtection(owner, noteId);
    if (!challenge || challenge.actorId !== actor || challenge.noteId !== noteId ||
        challenge.ownerId !== owner || challenge.revision !== current.revision ||
        challenge.consumed || challenge.expiresAt <= this.now() || challenge.attempts >= 5 ||
        !equalDigest(challenge.mailboxHash, securityDigest(mailbox.toLowerCase()))) {
      throw new NoteSecurityError('invalidChallenge');
    }
    const valid = /^\d{6}$/.test(code) && equalDigest(challenge.codeHash, securityDigest(`${challengeId}:${code}`));
    await this.store.advanceChallenge(challenge, valid, this.now());
    if (!valid) throw new NoteSecurityError('invalidChallenge');
    const note = await this.requireNote(owner, noteId);
    const next = { ...current, enabled: true, revision: current.revision + 1,
      verifier: await this.hasher.hash(newPassword) };
    await this.store.commitProtection(current, next, note.revision);
    return this.issueGrant(actor, next, ['read', 'edit', 'delete', 'manage', 'summary']);
  }

  private async requireNote(owner: string, noteId: string) {
    const note = await this.store.readNote(owner, noteId);
    if (!note || note.deletedAt !== null) throw new NoteSecurityError('denied');
    return note;
  }

  private async verifyPassword(actor: string, record: ProtectionRecord, password: string) {
    await this.acl.require(actor, record.ownerId, record.noteId, 'read');
    await this.store.reservePasswordAttempt(record.ownerId, record.noteId, actor, this.now());
    if (!record.verifier || !await this.hasher.verify(password, record.verifier)) throw new NoteSecurityError('invalidPassword');
  }

  private async issueGrant(actorId: string, record: ProtectionRecord,
    requested: readonly NoteOperation[]): Promise<UnlockResult> {
    if (!requested.length || requested.length > NOTE_OPERATIONS.length ||
        requested.some(op => !NOTE_OPERATIONS.includes(op))) throw new NoteSecurityError('invalidInput');
    const operations = [...new Set(requested)];
    for (const op of operations) await this.acl.require(actorId, record.ownerId, record.noteId, op);
    const live = await this.store.readProtection(record.ownerId, record.noteId);
    if (!live.enabled || live.revision !== record.revision) throw new NoteSecurityError('staleRevision');
    const token = randomBytes(32).toString('base64url');
    const issuedAt = this.now();
    const grant: GrantRecord = { hash: securityDigest(token), actorId,
      ownerId: record.ownerId, noteId: record.noteId, revision: record.revision,
      operations, issuedAt, expiresAt: issuedAt + this.ttlMs };
    await this.store.putGrant(grant);
    return { enabled: true, revision: record.revision, grant: token, operations, expiresAt: grant.expiresAt };
  }
}
