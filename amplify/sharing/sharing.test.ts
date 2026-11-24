import assert from 'node:assert/strict';
import { test } from 'node:test';
import { CognitoRecipientResolver } from './cognito_recipient_resolver';
import { TestDynamo } from './test_dynamo';
import { DynamoNoteAcl, shareKey } from './dynamo_note_acl';
import { DynamoShareStore } from './dynamo_share_store';
import { ShareUseCases } from './share_use_cases';
import { ActorFeed, MAX_ACTIVE_RECIPIENTS, MAX_EVENT_ACTORS } from './actor_feed';
import { ShareError, type ShareCommand, type ShareStore } from './share_models';
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
/** Notes already at/past the active-share cap. Seeded directly because the
 *  fixed create path can no longer produce an over-limit row set. */
function crowdedFixture(active = MAX_ACTIVE_RECIPIENTS + 1) {
  const db = new TestDynamo(); db.put({ ...note, ownerId: 'OWNER#owner', noteId: 'NOTE#alpha' });
  for (let i = 1; i <= active; i++) {
    db.put({ ...shareKey('owner', 'alpha', `r${i}`), share: { ownerId: 'owner', noteId: 'alpha',
      recipientId: `r${i}`, role: 'viewer', accessRevision: 1, status: 'active',
      sharedAt: '2026-10-02T00:00:00Z', updatedAt: '2026-10-02T00:00:00Z', revokedAt: null } });
  }
  const acl = new DynamoNoteAcl('test', db.client), p = new DynamoProtectionStore('test', db.client, true);
  const security = new ProtectionUseCases(p, new TestPasswordHasher(), acl, { async sendCode() {} });
  const shares = new ShareUseCases(new DynamoShareStore('test', db.client),
    { async resolve(email: string) { return email.split('@')[0]; } }, security);
  const sync = new DynamoSyncStore({ tableName: 'test', documentClient: db.client, security, sharing: true });
  const create = (rid: string, request = `create-${rid}`) => shares.apply('owner', 'owner', 'alpha', {
    requestId: request, action: 'create', email: `${rid}@example.invalid`, role: 'editor', expectedAccessRevision: 0 });
  const revoke = (rid: string) => shares.apply('owner', 'owner', 'alpha', {
    requestId: `revoke-${rid}`, action: 'revoke', recipientId: rid, expectedAccessRevision: 1 });
  const ownerEdit = (id = 'edit') => ({ mutationId: id, noteId: 'alpha', operation: 'update' as const,
    baseRevision: 1, payload: { title: 'edited', content: 'edited body' } });
  return { db, acl, p, security, shares, sync, create, revoke, ownerEdit };
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

test('two concurrent creates at 19 active admit one recipient; the loser is refused and the cap holds', async () => {
  const f = crowdedFixture(MAX_ACTIVE_RECIPIENTS - 1);
  const outcomes = await Promise.allSettled([f.create('r20'), f.create('r21')]);
  assert.equal(outcomes.filter(o => o.status === 'fulfilled').length, 1);
  for (const o of outcomes.filter(o => o.status === 'rejected')) {
    assert.ok(o.reason instanceof ShareError && ['staleAccess', 'limit'].includes(o.reason.code),
      `unexpected rejection: ${String(o.reason)}`);
  }
  const active = (await f.shares.list('owner', 'owner', 'alpha')).filter(s => s.status === 'active').length;
  assert.ok(active <= MAX_ACTIVE_RECIPIENTS, `active count ${active} exceeded the cap`);
});

test('apply completes the note read before the share-list read, closing the stale-count/newer-revision interleaving', async () => {
  const f = fixture();
  const events: string[] = [];
  const inner = new DynamoShareStore('test', f.db.client);
  const timed: ShareStore = {
    async note(owner: string, id: string) { events.push('note:start'); const n = await inner.note(owner, id); events.push('note:end'); return n; },
    async read(owner: string, id: string, recipient: string) { events.push('read:start'); const r = await inner.read(owner, id, recipient); events.push('read:end'); return r; },
    async list(owner: string, id: string) { events.push('list:start'); const rows = await inner.list(owner, id); events.push('list:end'); return rows; },
    receipt: (...args: Parameters<ShareStore['receipt']>) => inner.receipt(...args),
    commit: (...args: Parameters<ShareStore['commit']>) => inner.commit(...args),
  };
  await new ShareUseCases(timed, { async resolve() { return 'recipient'; } }, f.security)
    .apply('owner', 'owner', 'alpha', { requestId: 'order', action: 'create',
      email: 'recipient@example.invalid', role: 'editor', expectedAccessRevision: 0 });
  assert.ok(events.indexOf('note:end') < events.indexOf('list:start'),
    'the list snapshot must never be older than the sharingRevision the commit CAS pins');
});

test('a note at 21 active is not bricked: list reads every row, revoke recovers, create stays refused', async () => {
  const f = crowdedFixture();
  assert.equal((await f.shares.list('owner', 'owner', 'alpha')).length, MAX_ACTIVE_RECIPIENTS + 1);
  await assert.rejects(f.create('r22'), shareError('limit'));
  await f.revoke('r1');
  assert.ok(f.db.transactions.at(-1)!.input.TransactItems!.length <= 100);
  const active = (await f.shares.list('owner', 'owner', 'alpha')).filter(s => s.status === 'active');
  assert.equal(active.length, MAX_ACTIVE_RECIPIENTS);
  await assert.rejects(f.create('r22'), shareError('limit'));
});

test('owner edits and protection commits fan out on a 21-active note as bounded event shards', async () => {
  const f = crowdedFixture();
  const applied = await f.sync.applyMutation('owner', f.ownerEdit(), { actorId: 'owner' });
  assert.equal(applied.status, 'applied');
  assert.equal(f.db.get('owner', 'NOTE#alpha')?.content, 'edited body');
  assert.equal(f.db.get('r1', 'CHANGE#1')?.content, 'edited body');
  assert.equal(f.db.get(`r${MAX_ACTIVE_RECIPIENTS + 1}`, 'CHANGE#1')?.content, 'edited body');
  const expected = ['owner', ...Array.from({ length: MAX_ACTIVE_RECIPIENTS + 1 }, (_, i) => `r${i + 1}`)];
  const events = [...f.db.rows.values()].filter(r => r.noteId.startsWith('EVENT#'));
  assert.ok(events.length >= 2);
  assert.ok(events.every(e => e.actors.length <= MAX_EVENT_ACTORS));
  const union = events.flatMap(e => e.actors);
  assert.equal(union.length, new Set(union).size, 'event shards must be disjoint');
  assert.deepEqual([...union].sort(), expected.sort(), 'every actor is represented exactly once');
  assert.ok(f.db.transactions.at(-1)!.input.TransactItems!.length <= 100);
  await f.security.enable('owner', 'owner', 'alpha', 'test-password-alpha', 2);
  assert.equal(f.db.get('owner', 'PROTECTION#alpha')?.enabled, true);
  assert.equal(f.db.get('r2', 'CHANGE#2')?.title, '');
});

test('event sharding is bounded and lossless at 22 and 43 actors', () => {
  const db = new TestDynamo(); const feed = new ActorFeed('test', db.client);
  const note = { ...noteFixture(), id: 'alpha', revision: 3, protectionRevision: 1 };
  for (const count of [22, 43]) {
    const actors = Array.from({ length: count }, (_, i) => `a${i}`);
    const events = feed.events('owner', note, actors, 1000);
    const emitted = events.flatMap(w => w.Put!.Item!.actors as string[]);
    assert.equal(events.length, Math.ceil(count / MAX_EVENT_ACTORS));
    assert.ok(events.every(w => (w.Put!.Item!.actors as string[]).length <= MAX_EVENT_ACTORS));
    assert.equal(emitted.length, new Set(emitted).size);
    assert.deepEqual([...emitted].sort(), actors.sort());
    assert.ok(events.every(w => w.Put!.Item!.relayQueue === 'pending'));
  }
});

function noteFixture() {
  return { id: 'alpha', title: '', content: '', revision: 1, createdAt: '2026-10-02T00:00:00Z',
    serverUpdatedAt: '2026-10-02T00:00:00Z', deletedAt: null, protected: false, protectionRevision: 0 };
}

test('lost-ACK replay after revoke returns the revoked record and never resurrects access', async () => {
  const f = fixture(); await f.create();
  await f.command('revoke', 1);
  const replay = await f.create();
  assert.equal(replay.status, 'revoked');
  assert.equal(replay.accessRevision, 2);
  await assert.rejects(f.security.content('recipient', 'owner', 'alpha'), denied);
  await assert.rejects(f.sync.applyMutation('owner', f.mutation(), { actorId: 'recipient' }), denied);
});
