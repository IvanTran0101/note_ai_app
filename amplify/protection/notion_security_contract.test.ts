import assert from 'node:assert/strict';
import {test} from 'node:test';
import {ProtectionAuthorizer, securityDigest} from './authorizer';
import {OwnerNoteAcl} from './protection_store';
import type {GrantRecord, NoteOperation, ProtectionStore} from './protection_store';

const token = 'a'.repeat(43);
const grant: GrantRecord = {
  hash: securityDigest(token), actorId: 'owner', ownerId: 'owner', noteId: 'note-a',
  revision: 3, operations: ['read'], issuedAt: 100, expiresAt: 200,
};

function authority(record: GrantRecord = grant, now = 150) {
  const store = {
    readProtection: async () => ({ownerId: 'owner', noteId: 'note-a', enabled: true, revision: 3, verifier: 'synthetic'}),
    readGrant: async (_owner: string, hash: string) => hash === record.hash ? record : null,
  } as unknown as ProtectionStore;
  return new ProtectionAuthorizer(store, new OwnerNoteAcl(), () => now);
}

test('SEC-FR-03/08: protected operations reject missing grant; scope is enforced', async () => {
  const auth = authority();
  for (const operation of ['read', 'edit', 'delete', 'manage', 'summary', 'export', 'attachmentRead', 'attachmentWrite'] as NoteOperation[]) {
    await assert.rejects(auth.authorize('owner', 'owner', 'note-a', operation), {code: 'locked'});
  }
  await auth.authorize('owner', 'owner', 'note-a', 'read', token);
  await assert.rejects(auth.authorize('owner', 'owner', 'note-a', 'edit', token), {code: 'denied'});
  await assert.rejects(auth.authorize('owner', 'owner', 'note-b', 'read', token), {code: 'denied'});
  await assert.rejects(auth.authorize('other', 'owner', 'note-a', 'read', token), {code: 'denied'});
});

test('SEC-NFR-05: expired and old-revision grants cannot unlock current note', async () => {
  await assert.rejects(authority(grant, 200).authorize('owner', 'owner', 'note-a', 'read', token), {code: 'expired'});
  await assert.rejects(authority({...grant, revision: 2}).authorize('owner', 'owner', 'note-a', 'read', token), {code: 'denied'});
});
