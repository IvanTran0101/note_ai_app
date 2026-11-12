import assert from 'node:assert/strict';
import { test } from 'node:test';
import { TestDynamo } from './test_dynamo';
import { DynamoNoteAcl } from './dynamo_note_acl';
import { DynamoShareStore } from './dynamo_share_store';
import { ShareUseCases } from './share_use_cases';
import { ShareError } from './share_models';
import { ProtectionUseCases } from '../protection/use_cases';
import { DynamoProtectionStore } from '../protection/dynamo_protection_store';
import { TestPasswordHasher } from '../protection/test_support';
import { NoteSecurityError } from '../protection/protection_store';
import { handleShares } from './share_handler';

const note = { id: 'alpha', title: 'title', content: 'body', revision: 1,
  createdAt: '2026-10-02T00:00:00Z', serverUpdatedAt: '2026-10-02T00:00:00Z', deletedAt: null,
  protected: false, protectionRevision: 0 };

function fixture() {
  const db = new TestDynamo();
  db.put({ ...note, ownerId: 'OWNER#owner', noteId: 'NOTE#alpha' });
  const acl = new DynamoNoteAcl('test', db.client);
  const protection = new DynamoProtectionStore('test', db.client, true);
  const security = new ProtectionUseCases(protection, new TestPasswordHasher(), acl, { async sendCode() {} });
  let now = Date.parse('2026-11-01T12:00:00Z');
  const shares = new ShareUseCases(new DynamoShareStore('test', db.client), {
    async resolve(email) {
      if (email !== 'recipient@example.invalid') throw new ShareError('recipientUnavailable');
      return 'recipient';
    },
  }, security, () => now);
  return { db, shares, advanceTime: () => { now += 60_000; } };
}

test('FR sharing admin requires the authenticated owner even when the API names another owner', async () => {
  const f = fixture();
  const response = await handleShares({
    rawPath: '/notes/alpha/shares', body: JSON.stringify({ requestId: 'attacker', action: 'create',
      email: 'recipient@example.invalid', role: 'editor', expectedAccessRevision: 0 }),
    isBase64Encoded: false, queryStringParameters: { ownerId: 'owner' },
    requestContext: { http: { method: 'POST' } },
  } as any, 'recipient', f.shares);

  assert.equal(response.statusCode, 403);
  assert.equal(f.db.get('owner', 'SHARE#alpha#recipient'), undefined);
  assert.equal(f.db.transactions.length, 0);
});

test('FR sharedAt is set on invite and stays stable across role changes and revoke', async () => {
  const f = fixture();
  const invited = await f.shares.apply('owner', 'owner', 'alpha', { requestId: 'invite', action: 'create',
    email: 'recipient@example.invalid', role: 'editor', expectedAccessRevision: 0 });
  assert.equal(invited.sharedAt, '2026-11-01T12:00:00.000Z');

  f.advanceTime();
  const changed = await f.shares.apply('owner', 'owner', 'alpha', { requestId: 'role', action: 'role',
    recipientId: 'recipient', role: 'viewer', expectedAccessRevision: 1 });
  assert.equal(changed.sharedAt, invited.sharedAt);
  assert.equal(changed.updatedAt, '2026-11-01T12:01:00.000Z');

  f.advanceTime();
  const revoked = await f.shares.apply('owner', 'owner', 'alpha', { requestId: 'revoke', action: 'revoke',
    recipientId: 'recipient', expectedAccessRevision: 2 });
  assert.equal(revoked.sharedAt, invited.sharedAt);
  assert.equal(revoked.status, 'revoked');
  assert.equal(revoked.revokedAt, '2026-11-01T12:02:00.000Z');
});

test('FR self, duplicate and unregistered invite attempts do not create shares', async () => {
  const f = fixture();
  const make = (requestId: string, email = 'recipient@example.invalid') => f.shares.apply('owner', 'owner', 'alpha', {
    requestId, action: 'create', email, role: 'viewer', expectedAccessRevision: 0,
  });
  await make('first');
  await assert.rejects(make('duplicate'), (error: unknown) => error instanceof ShareError && error.code === 'duplicate');
  await assert.rejects(make('unregistered', 'missing@example.invalid'),
    (error: unknown) => error instanceof ShareError && error.code === 'recipientUnavailable');
  await assert.rejects(new ShareUseCases(new DynamoShareStore('test', f.db.client), {
    async resolve() { return 'owner'; },
  }, new ProtectionUseCases(new DynamoProtectionStore('test', f.db.client, true), new TestPasswordHasher(),
    new DynamoNoteAcl('test', f.db.client), { async sendCode() {} })).apply('owner', 'owner', 'alpha', {
      requestId: 'self', action: 'create', email: 'owner@example.invalid', role: 'viewer', expectedAccessRevision: 0,
    }), (error: unknown) => error instanceof ShareError && error.code === 'selfShare');
  assert.equal((await f.shares.list('owner', 'owner', 'alpha')).length, 1);
});

test('FR sharing request rejects a non-owner actor at the use-case boundary', async () => {
  const f = fixture();
  await assert.rejects(f.shares.apply('recipient', 'owner', 'alpha', { requestId: 'forged', action: 'create',
    email: 'recipient@example.invalid', role: 'editor', expectedAccessRevision: 0 }),
  (error: unknown) => error instanceof NoteSecurityError && error.code === 'denied');
  assert.equal(f.db.transactions.length, 0);
});
