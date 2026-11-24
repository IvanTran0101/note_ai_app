import type { TransactWriteCommandInput } from '@aws-sdk/lib-dynamodb';
import { isLocalPasswordVerifier } from '../protection/pbkdf2_password_verifier';
import type { SecurityAuthorization } from '../protection/protection_store';
import { NoteSecurityError } from '../protection/protection_store';
import { SyncInvalidMutationError, type ProtectionSyncChange } from './sync_store_models';

const object = (v: unknown): v is Record<string, unknown> =>
  !!v && typeof v === 'object' && !Array.isArray(v);

export const parseProtectionChange = (value: unknown): ProtectionSyncChange => {
  const invalid = (): never => { throw new SyncInvalidMutationError('PAYLOAD_INVALID', 'Invalid protection change.'); };
  if (!object(value) || Object.keys(value).sort().join() !== 'after,before,verifier') return invalid();
  const metadata = (v: unknown) => {
    if (!object(v) || Object.keys(v).sort().join() !== 'enabled,revision' ||
        typeof v.enabled !== 'boolean' || typeof v.revision !== 'number' ||
        !Number.isSafeInteger(v.revision) || v.revision < 0 || v.enabled && v.revision === 0) return invalid();
    return { enabled: v.enabled, revision: v.revision };
  };
  const before = metadata(value.before), after = metadata(value.after);
  if (after.revision <= before.revision ||
      (after.enabled ? !isLocalPasswordVerifier(value.verifier) : value.verifier !== null)) return invalid();
  return { before, after, verifier: value.verifier as string | null };
};

export const protectionWrite = (table: string, ownerKey: string, noteId: string,
  change: ProtectionSyncChange, authority: SecurityAuthorization): NonNullable<TransactWriteCommandInput['TransactItems']>[number] => {
  if (authority.enabled !== change.before.enabled || authority.revision !== change.before.revision ||
      authority.actorId !== authority.ownerId || authority.operation !== 'manage') throw new NoteSecurityError('staleRevision');
  return { Put: { TableName: table, Item: {
    ownerId: ownerKey, noteId: `PROTECTION#${noteId}`,
    canonicalOwnerId: authority.ownerId, targetNoteId: noteId,
    ...change.after, verifier: change.verifier,
  }, ConditionExpression: authority.revision === 0 ? 'attribute_not_exists(noteId)' : 'revision = :epoch AND enabled = :enabled',
  ...(authority.revision === 0 ? {} : { ExpressionAttributeValues: {
    ':epoch': authority.revision, ':enabled': authority.enabled } }) } };
};
