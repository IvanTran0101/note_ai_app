import { randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';
import type { NoteSnapshot } from '../sync/dynamo_sync_store';
import type { PasswordHasher } from './password_hasher';
import { requirePassword } from './argon2id_password_hasher';
import { NoteSecurityError } from './protection_store';
import type { GrantRecord, ProtectionRecord, ProtectionStore, RecoveryChallenge,
  SecurityAuthorization } from './protection_store';

/** Fast test adapter; the production Argon2id adapter has a separate real test. */
export class TestPasswordHasher implements PasswordHasher {
  async hash(password: string) {
    requirePassword(password);
    const salt = randomBytes(16).toString('hex');
    return `${salt}:${scryptSync(password, salt, 32).toString('hex')}`;
  }
  async verify(password: string, encoded: string) {
    requirePassword(password);
    const [salt, hash] = encoded.split(':');
    return timingSafeEqual(scryptSync(password, salt, 32), Buffer.from(hash, 'hex'));
  }
}

export class TestProtectionStore implements ProtectionStore {
  protections = new Map<string, ProtectionRecord>();
  notes = new Map<string, NoteSnapshot>();
  grants = new Map<string, GrantRecord>();
  challenges = new Map<string, RecoveryChallenge>();
  attempts = new Map<string, number[]>();
  constructor() {
    for (const id of ['alpha', 'beta']) {
      this.protections.set(id, { ownerId: 'owner', noteId: id, enabled: false,
        revision: 0, verifier: null });
      this.notes.set(id, { id, title: `private ${id}`, content: `secret ${id}`,
        createdAt: '2026-10-02T00:00:00Z', serverUpdatedAt: '2026-10-02T00:00:00Z',
        revision: 1, deletedAt: null });
    }
  }
  async readProtection(owner: string, id: string) {
    const value = this.protections.get(id);
    if (!value || owner !== value.ownerId) throw new NoteSecurityError('denied');
    return { ...value };
  }
  async readNote(owner: string, id: string) {
    return owner === 'owner' ? this.notes.get(id) ?? null : null;
  }
  async commitProtection(current: ProtectionRecord, next: ProtectionRecord,
    revision: number, _authority?: SecurityAuthorization) {
    if (this.protections.get(current.noteId)?.revision !== current.revision ||
        this.notes.get(current.noteId)?.revision !== revision) {
      throw new NoteSecurityError('staleRevision');
    }
    this.protections.set(current.noteId, next);
    const note = this.notes.get(current.noteId)!;
    this.notes.set(current.noteId, { ...note, protected: next.enabled,
      protectionRevision: next.revision });
  }
  async putGrant(grant: GrantRecord) { this.grants.set(grant.hash, grant); }
  async readGrant(owner: string, hash: string) {
    const g = this.grants.get(hash);
    return g?.ownerId === owner ? g : null;
  }
  async reservePasswordAttempt(owner: string, id: string, actor: string, now: number) {
    const key = `${owner}/${id}/${actor}`;
    const attempts = (this.attempts.get(key) ?? []).filter(t => t > now - 60_000);
    if (attempts.length >= 5) throw new NoteSecurityError('rateLimited');
    this.attempts.set(key, [...attempts, now]);
  }
  async putChallenge(c: RecoveryChallenge) { this.challenges.set(c.id, c); }
  async readChallenge(owner: string, id: string) {
    const c = this.challenges.get(id);
    return c?.ownerId === owner ? { ...c } : null;
  }
  async advanceChallenge(c: RecoveryChallenge, consumed: boolean, now: number) {
    const live = this.challenges.get(c.id);
    if (!live || live.consumed || live.attempts !== c.attempts ||
        live.expiresAt <= now || live.attempts >= 5) {
      throw new NoteSecurityError('invalidChallenge');
    }
    this.challenges.set(c.id, { ...live, attempts: live.attempts + 1, consumed });
  }
}
