import type { NoteSnapshot } from '../sync/sync_store_models';
import type { SecurityAuthorization } from '../protection/protection_store';

export type ShareRole = 'viewer' | 'editor';
export type ShareRecord = Readonly<{
  ownerId: string; noteId: string; recipientId: string; role: ShareRole;
  accessRevision: number; status: 'active' | 'revoked';
  sharedAt: string; updatedAt: string; revokedAt: string | null;
  sharerLabel?: string;
}>;
export type AccessStamp = Readonly<{
  actorId: string; ownerId: string; noteId: string;
  role: ShareRole; accessRevision: number;
}>;
export type ShareCommand = Readonly<{
  requestId: string; action: 'create' | 'role' | 'revoke';
  email?: string; recipientId?: string; role?: ShareRole; expectedAccessRevision: number;
}>;
export interface RecipientResolver { resolve(email: string): Promise<string>; }
export interface ShareStore {
  list(owner: string, noteId: string): Promise<readonly ShareRecord[]>;
  read(owner: string, noteId: string, recipient: string): Promise<ShareRecord | null>;
  note(owner: string, noteId: string): Promise<NoteSnapshot | null>;
  receipt(owner: string, requestId: string): Promise<{ fingerprint: string; share: ShareRecord } | null>;
  commit(previous: ShareRecord | null, next: ShareRecord, note: NoteSnapshot,
    authority: SecurityAuthorization, requestId: string, fingerprint: string): Promise<void>;
}
export type ShareErrorCode = 'recipientUnavailable' | 'duplicate' | 'selfShare' | 'staleAccess' | 'limit' | 'invalidInput' | 'unavailable';
export class ShareError extends Error {
  constructor(readonly code: ShareErrorCode) { super(`ShareError:${code}`); this.name = 'ShareError'; }
}
export const shareSortKey = (note: string, recipient: string) =>
  `SHARE#${encodeURIComponent(note)}#${encodeURIComponent(recipient)}`;
export const sharePrefix = (note: string) => `SHARE#${encodeURIComponent(note)}#`;
export const pairReference = (owner: string, note: string) => JSON.stringify([owner, note]);

export function decodeShare(row: Record<string, unknown>): ShareRecord {
  const s = row.share as ShareRecord | undefined;
  if (!s || typeof s.ownerId !== 'string' || !s.ownerId || typeof s.noteId !== 'string' || !s.noteId ||
      typeof s.recipientId !== 'string' || !s.recipientId || s.recipientId === s.ownerId ||
      (s.role !== 'viewer' && s.role !== 'editor') || (s.status !== 'active' && s.status !== 'revoked') ||
      !Number.isSafeInteger(s.accessRevision) || s.accessRevision < 1 ||
      !Number.isFinite(Date.parse(s.sharedAt)) || !Number.isFinite(Date.parse(s.updatedAt)) ||
      Date.parse(s.updatedAt) < Date.parse(s.sharedAt) ||
      (s.status === 'active' ? s.revokedAt !== null : !s.revokedAt || !Number.isFinite(Date.parse(s.revokedAt)))) {
    throw new ShareError('unavailable');
  }
  return s;
}
