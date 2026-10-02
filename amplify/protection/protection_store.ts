import type { NoteSnapshot } from '../sync/dynamo_sync_store';
import type { AccessStamp } from '../sharing/share_models';

export const NOTE_OPERATIONS = ['read', 'edit', 'delete', 'manage', 'summary',
  'export', 'attachmentRead', 'attachmentWrite'] as const;
export type NoteOperation = typeof NOTE_OPERATIONS[number];
export type ProtectionMetadata = Readonly<{ enabled: boolean; revision: number }>;
export type ProtectionRecord = ProtectionMetadata & Readonly<{
  ownerId: string; noteId: string; verifier: string | null;
}>;
export type GrantRecord = Readonly<{
  hash: string; actorId: string; ownerId: string; noteId: string;
  revision: number; operations: readonly NoteOperation[];
  issuedAt: number; expiresAt: number;
}>;
export type RecoveryChallenge = Readonly<{
  id: string; ownerId: string; noteId: string; actorId: string;
  mailboxHash: string; codeHash: string; revision: number;
  expiresAt: number; attempts: number; consumed: boolean;
}>;
export type SecurityAuthorization = ProtectionMetadata & Readonly<{
  actorId: string; ownerId: string; noteId: string; operation: NoteOperation;
  grantHash?: string; expiresAt?: number;
  access?: AccessStamp;
}>;

export interface ProtectionStore {
  readProtection(ownerId: string, noteId: string): Promise<ProtectionRecord>;
  readNote(ownerId: string, noteId: string): Promise<NoteSnapshot | null>;
  commitProtection(current: ProtectionRecord, next: ProtectionRecord,
    expectedContentRevision: number, authority?: SecurityAuthorization): Promise<void>;
  putGrant(grant: GrantRecord): Promise<void>;
  readGrant(ownerId: string, hash: string): Promise<GrantRecord | null>;
  reservePasswordAttempt(ownerId: string, noteId: string, actorId: string,
    now: number): Promise<void>;
  putChallenge(challenge: RecoveryChallenge): Promise<void>;
  readChallenge(ownerId: string, challengeId: string): Promise<RecoveryChallenge | null>;
  advanceChallenge(challenge: RecoveryChallenge, consumed: boolean, now: number): Promise<void>;
}

export interface NoteAcl {
  require(actorId: string, ownerId: string, noteId: string,
    operation: NoteOperation): Promise<AccessStamp | void>;
}

/// Owner-scoped baseline. A sharing adapter must supply real current ACL evidence.
export class OwnerNoteAcl implements NoteAcl {
  async require(actorId: string, ownerId: string): Promise<void> {
    if (!actorId || actorId !== ownerId) throw new NoteSecurityError('denied');
  }
}

export interface NoteSecurityAuthority {
  authorize(actorId: string, ownerId: string, noteId: string,
    operation: NoteOperation, token?: string): Promise<SecurityAuthorization>;
  metadata(actorId: string, ownerId: string, noteId: string, allowMissing?: boolean): Promise<ProtectionMetadata>;
}

export type NoteSecurityCode = 'locked' | 'invalidPassword' | 'invalidInput' |
  'denied' | 'expired' | 'staleRevision' | 'rateLimited' | 'unavailable' | 'invalidChallenge';

export class NoteSecurityError extends Error {
  constructor(readonly code: NoteSecurityCode) {
    super(`NoteSecurityError:${code}`);
    this.name = 'NoteSecurityError';
  }
}

export const identifier = (value: unknown): string => {
  if (typeof value !== 'string' || !value.trim() || value.length > 128 ||
      /[\u0000-\u001f\u007f]/.test(value)) throw new NoteSecurityError('invalidInput');
  return value;
};
