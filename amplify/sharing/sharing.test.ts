import assert from 'node:assert/strict';
import { test } from 'node:test';
import { CognitoRecipientResolver } from './cognito_recipient_resolver';
import { TestDynamo } from './test_dynamo';
import { DynamoNoteAcl } from './dynamo_note_acl';
import { DynamoShareStore } from './dynamo_share_store';
import { ShareUseCases } from './share_use_cases';
import { ShareError, type ShareCommand } from './share_models';
import { ProtectionUseCases } from '../protection/use_cases';
import { DynamoProtectionStore } from '../protection/dynamo_protection_store';
import { TestPasswordHasher } from '../protection/test_support';
import { NoteSecurityError } from '../protection/protection_store';
import { DynamoSyncStore } from '../sync/dynamo_sync_store';
import { parseMutationBody } from '../sync/request_parser';
import { noteBodyOf } from '../sync/sync_response';
import { DynamoSummaryNoteAuthority } from '../ai/summary_note_authority';
import { parseSummaryNoteContext } from '../ai/summary_note_context';

const note = { id: 'alpha', title: 'private title', content: 'private body', revision: 1,
  createdAt: '2026-10-02T00:00:00Z', serverUpdatedAt: '2026-10-02T00:00:00Z', deletedAt: null,
  protected: false, protectionRevision: 0 };
const denied = (e: unknown) => e instanceof NoteSecurityError && ['denied', 'locked', 'staleRevision'].includes(e.code);
const shareError = (code: string) => (e: unknown) => e instanceof ShareError && e.code === code;
function fixture() {
  const db = new TestDynamo(); db.put({ ...note, ownerId: 'OWNER#owner', noteId: 'NOTE#alpha' });
  const acl = new DynamoNoteAcl('test', db.client), p = new DynamoProtectionStore('test', db.client, true);
  const security = new ProtectionUseCases(p, new TestPasswordHasher(), acl, { async sendCode() {} });
  const shares = new ShareUseCases(new DynamoShareStore('test', db.client),
    { async resolve(email) { if (email !== 'recipient@example.invalid') throw new ShareError('recipientUnavailable'); return 'recipient'; } }, security);
  const sync = new DynamoSyncStore({ tableName: 'test', documentClient: db.client, security, sharing: true });
  const create = (id = 'share', role: 'viewer' | 'editor' = 'editor') => shares.apply('owner', 'owner', 'alpha', {
    requestId: id, action: 'create', email: 'recipient@example.invalid', role, expectedAccessRevision: 0 });
  const command = (action: 'role' | 'revoke', epoch: number, role: 'viewer' | 'editor' = 'viewer') => shares.apply('owner', 'owner', 'alpha', {
    requestId: `${action}-${epoch}`, action, recipientId: 'recipient', ...(action === 'role' ? { role } : {}), expectedAccessRevision: epoch });
  const mutation = (id = 'edit', epoch = 1) => ({ ownerId: 'owner', accessRevision: epoch,
    mutationId: id, noteId: 'alpha', operation: 'update' as const, baseRevision: 1, payload: { title: 'edited', content: 'edited body' } });
  return { db, acl, p, security, shares, sync, create, command, mutation };
}

test('registered verified recipient lookup is exact, private and rejects unknown/unverified/ambiguous/disabled', async () => {
  const user = { Enabled: true, UserStatus: 'CONFIRMED', Attributes: [
    { Name: 'sub', Value: 'recipient' }, { Name: 'email', Value: 'recipient@example.invalid' }, { Name: 'email_verified', Value: 'true' }] };
  for (const response of [{ Users: [] }, { Users: [user, user] }, { Users: [{ ...user, Enabled: false }] },
    { Users: [{ ...user, Attributes: user.Attributes.slice(0, 2) }] }, { Users: [user], PaginationToken: 'more' }]) {
    const resolver = new CognitoRecipientResolver('pool', { async send() { return response; } } as any);
    await assert.rejects(resolver.resolve('recipient@example.invalid'), shareError('recipientUnavailable'));
  }
  let filter = '';
  const resolver = new CognitoRecipientResolver('pool', { async send(c: any) { filter = c.input.Filter; return { Users: [user] }; } } as any);
  assert.equal(await resolver.resolve(' Recipient@Example.Invalid '), 'recipient');
  assert.equal(filter, 'email = "recipient@example.invalid"');
  await assert.rejects(resolver.resolve('" OR email = "bad'), shareError('invalidInput'));
});

test('share creation atomically seeds actor feeds, receipt, membership and metadata event', async () => {
  const f = fixture(); const s = await f.create();
  assert.equal(s.accessRevision, 1); assert.equal(f.db.transactions.length, 1);
  assert.equal(f.db.get('owner', 'NOTE#alpha')?.sharingRevision, 1);
  const page = await f.sync.listChanges('recipient');
  assert.equal(page.items[0].ownerId, 'owner'); assert.equal(page.items[0].share?.role, 'editor');
  assert.equal(page.items[0].content, 'private body');
  const event = [...f.db.rows.values()].find(r => r.noteId.startsWith('EVENT#'))!;
  assert.ok(!JSON.stringify(event).includes('private')); assert.equal(event.relayStatus, 'pending');
  assert.deepEqual(await f.create(), s); assert.equal(f.db.transactions.length, 1);
});

test('owner admin refuses duplicates, unknown, self, untrusted bodies and stale epoch', async () => {
  const f = fixture(); await f.create();
  await assert.rejects(f.create('duplicate'), shareError('duplicate'));
  const cmd: ShareCommand = { requestId: 'unknown', action: 'create', email: 'unknown@example.invalid', role: 'viewer', expectedAccessRevision: 0 };
  await assert.rejects(f.shares.apply('owner', 'owner', 'alpha', cmd), shareError('recipientUnavailable'));
  await assert.rejects(f.shares.apply('recipient', 'owner', 'alpha', cmd), denied);
  await assert.rejects(f.command('role', 9), shareError('staleAccess'));
  await assert.rejects(f.shares.apply('owner', 'owner', 'alpha', { ...cmd, recipientId: 'spoofed' }), shareError('invalidInput'));
  const self = new ShareUseCases(new DynamoShareStore('test', f.db.client), { async resolve() { return 'owner'; } }, f.security);
  await assert.rejects(self.apply('owner', 'owner', 'alpha', cmd), shareError('selfShare'));
});

test('viewer reads/summary but every write, export, delete and admin are denied by ACL', async () => {
  const f = fixture(); await f.create('share', 'viewer');
  assert.equal((await f.security.content('recipient', 'owner', 'alpha')).content, 'private body');
  await f.acl.require('recipient', 'owner', 'alpha', 'summary');
  for (const op of ['edit', 'manage', 'delete', 'export', 'attachmentWrite'] as const) await assert.rejects(f.acl.require('recipient', 'owner', 'alpha', op), denied);
  await assert.rejects(f.sync.applyMutation('owner', f.mutation(), { actorId: 'recipient' }), denied);
});

test('shared editor writes canonical owner, fanout and actor/pair receipt without changing identity', async () => {
  const f = fixture(); await f.create();
  const result = await f.sync.applyMutation('owner', f.mutation(), { actorId: 'recipient' });
  assert.equal(result.status, 'applied'); assert.equal(f.db.get('owner', 'NOTE#alpha')?.content, 'edited body');
  assert.equal(f.db.get('recipient', 'NOTE#alpha'), undefined);
  assert.equal(f.db.get('owner', 'NOTE#alpha')?.sharingRevision, 1);
  const again = await f.sync.applyMutation('owner', f.mutation(), { actorId: 'recipient' });
  assert.equal(again.status === 'applied' && again.replayed, true);
  assert.equal((await f.sync.listChanges('recipient')).items.at(-1)?.content, 'edited body');
  const guards = f.db.transactions.at(-1)!.input.TransactItems!.filter(x => x.ConditionCheck);
  assert.ok(guards.some(x => x.ConditionCheck?.ConditionExpression?.includes('accessRevision')));
});

test('downgrade/revoke deny stale writes/replay and historical feed removes private data', async () => {
  const f = fixture(); await f.create(); await f.sync.applyMutation('owner', f.mutation(), { actorId: 'recipient' });
  await f.command('role', 1);
  await assert.rejects(f.sync.applyMutation('owner', f.mutation(), { actorId: 'recipient' }), denied);
  await f.command('revoke', 2);
  const page = await f.sync.listChanges('recipient');
  assert.ok(page.items.every(n => n.share?.status === 'revoked' && !n.contentAvailable && !n.title && !n.content));
  assert.equal(f.db.get('owner', 'NOTE#alpha')?.deletedAt, null);
  assert.ok(!JSON.stringify(page.items.map(n => noteBodyOf(n))).includes('private'));
  await assert.rejects(f.security.content('recipient', 'owner', 'alpha'), denied);
});

test('re-share has new epoch; old attempted request cannot replay even with editor restored', async () => {
  const f = fixture(); await f.create(); await f.sync.applyMutation('owner', f.mutation(), { actorId: 'recipient' });
  await f.command('revoke', 1);
  const s = await f.shares.apply('owner', 'owner', 'alpha', { requestId: 'reshare', action: 'create',
    email: 'recipient@example.invalid', role: 'editor', expectedAccessRevision: 2 });
  assert.equal(s.accessRevision, 3);
  await assert.rejects(f.sync.applyMutation('owner', f.mutation(), { actorId: 'recipient' }), denied);
  assert.equal((await f.create()).accessRevision, 3, 'lost ACK returns current ACL, not old ACTIVE epoch');
});

test('revoke race at transaction denies editor and produces no content/partial feed write', async () => {
  const f = fixture(); await f.create();
  f.db.beforeTransaction = () => { const row = f.db.get('owner', 'SHARE#alpha#recipient')!;
    f.db.put({ ...row, share: { ...row.share, status: 'revoked', accessRevision: 2, revokedAt: new Date().toISOString() } }); };
  await assert.rejects(f.sync.applyMutation('owner', f.mutation(), { actorId: 'recipient' }), denied);
  assert.equal(f.db.get('owner', 'NOTE#alpha')?.content, 'private body');
  assert.equal(f.db.get('owner', 'META#SYNC')?.lastSequence, 1);
});

test('protected recipient gets own grant; owner token never transfers and rotation invalidates all', async () => {
  const f = fixture(); await f.create(); await f.security.enable('owner', 'owner', 'alpha', 'test-password-alpha', 1);
  const a = await f.security.unlock('owner', 'owner', 'alpha', 'test-password-alpha', ['read', 'manage']);
  await assert.rejects(f.security.content('recipient', 'owner', 'alpha', a.grant), denied);
  const b = await f.security.unlock('recipient', 'owner', 'alpha', 'test-password-alpha', ['read', 'edit', 'summary']);
  assert.equal((await f.security.content('recipient', 'owner', 'alpha', b.grant)).content, 'private body');
  assert.ok((await f.sync.listChanges('recipient')).items.every(n => !n.contentAvailable));
  await f.security.change('owner', 'owner', 'alpha', 'test-password-alpha', 'next-password-alpha', 1, a.grant);
  await assert.rejects(f.security.content('recipient', 'owner', 'alpha', b.grant), denied);
});

test('dedicated shared route rejects misrouting, deletes, protection actions and missing epochs', () => {
  const f = fixture(), body = JSON.stringify(f.mutation());
  assert.equal(parseMutationBody(body).ok, false); assert.equal(parseMutationBody(body, false, true).ok, true);
  for (const patch of [{ accessRevision: 0 }, { ownerId: undefined }, { operation: 'delete' }, { operation: 'create' }]) {
    assert.equal(parseMutationBody(JSON.stringify({ ...f.mutation(), ...patch }), false, true).ok, false);
  }
});

test('Summary pins actor ACL before input work and at result commit; viewer allowed, revoke denied', async () => {
  const f = fixture(); await f.create('share', 'viewer');
  const authority = new DynamoSummaryNoteAuthority('test', f.db.client, f.p, f.security);
  const context = parseSummaryNoteContext({ ownerId: 'owner', noteId: 'alpha', contentRevision: 1, protectionRevision: 0,
    accessRevision: 1, runId: 'a'.repeat(32), sectionIndex: 0, sourceStart: null, sourceEnd: null });
  const request = { stage: 'direct', inputs: ['private body'], note: context } as any;
  const run = await authority.begin(request, 'recipient'); await run.revalidate();
  await f.command('revoke', 1); await assert.rejects(run.complete('private summary'));
  assert.ok(![...f.db.rows.values()].some(r => r.outputs?.includes('private summary')));
});
