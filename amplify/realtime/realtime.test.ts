import assert from 'node:assert/strict';
import { test } from 'node:test';
import { App, Stack } from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { TestDynamo } from '../sharing/test_dynamo';
import { ActorFeed } from '../sharing/actor_feed';
import { createNotesTable } from '../sync/notes_table';
import { createRealtimeInfrastructure, CHANNEL_HANDLER } from './infrastructure';
import { DynamoRelayStore, decodeEvent, LEASE_MS } from './dynamo_relay_store';
import { RevisionRelay, MAX_ATTEMPTS, retryDelay, type RevisionSignal } from './relay';

function fixture() {
  const db = new TestDynamo(); const store = new DynamoRelayStore('test', db.client);
  const row = { ownerId: 'OWNER#owner', noteId: 'EVENT#event', eventId: 'event',
    canonicalOwnerId: 'owner', targetNoteId: 'alpha', revision: 7, protectionRevision: 3,
    actors: ['owner', 'recipient'], relayStatus: 'pending', relayQueue: 'pending',
    relayDueAt: 1000, attempts: 0 };
  db.put(row); let now = 1000; let access: number | null = 4; let fail = false; let aclFail = false;
  const sent: { actor: string; signal: RevisionSignal }[] = [];
  const relay = new RevisionRelay(store, { async read() { if (aclFail) throw Error('ACL down'); return access; } },
    { async publish(actor, signal) { sent.push({ actor, signal }); if (fail) throw Error('lost ACK'); } },
    () => now, () => 0.5);
  return { db, store, row, sent, relay, key: { ownerId: row.ownerId, noteId: row.noteId },
    time: (t: number) => { now = t; }, access: (a: number | null) => { access = a; },
    fail: (v: boolean) => { fail = v; }, aclFail: () => { aclFail = true; } };
}
test('transactional actor EVENT has sparse recovery index, metadata only and strict decoder', () => {
  const f = fixture(); const feed = new ActorFeed('test', f.db.client);
  const item = feed.event('owner', { id: 'alpha', revision: 1, title: 'SECRET', content: 'PRIVATE',
    createdAt: '', serverUpdatedAt: '', deletedAt: null }, ['owner', 'recipient']).Put!.Item!;
  assert.equal(item.relayQueue, 'pending'); assert.equal(typeof item.relayDueAt, 'number');
  assert.ok(!JSON.stringify(item).includes('PRIVATE')); assert.ok(!JSON.stringify(item).includes('SECRET'));
  assert.throws(() => decodeEvent({ ...f.row, leaseId: 'lease', actors: ['recipient/*'] }));
});
test('conditional lease excludes simultaneous workers and recovers a crashed lease', async () => {
  const f = fixture(); const claims = await Promise.all([f.store.claim(f.key, 1000), f.store.claim(f.key, 1000)]);
  assert.equal(claims.filter(Boolean).length, 1);
  assert.equal(await f.store.claim(f.key, 1000 + LEASE_MS - 1), null);
  const recovered = await f.store.claim(f.key, 1000 + LEASE_MS);
  assert.equal(recovered?.attempts, 2);
  await f.store.complete(claims.find(Boolean)!, 1000);
  assert.equal(f.db.get('owner', 'EVENT#event')?.relayStatus, 'pending');
});
test('success publishes stable metadata to current actors then removes sparse queue', async () => {
  const f = fixture(); await f.relay.deliver(f.key);
  assert.equal(f.sent.length, 2); assert.equal(f.sent[1].signal.accessRevision, 4);
  const row = f.db.get('owner', 'EVENT#event')!;
  assert.equal(row.relayStatus, 'done'); assert.equal(row.relayQueue, undefined);
  assert.ok(row.ttl); await f.relay.deliver(f.key); assert.equal(f.sent.length, 2);
});
test('lost ACK retries same event and rechecks revoked access before metadata fanout', async () => {
  const f = fixture(); f.fail(true); await f.relay.deliver(f.key);
  assert.equal(f.db.get('owner', 'EVENT#event')?.relayStatus, 'pending');
  f.time(f.db.get('owner', 'EVENT#event')!.relayDueAt); f.fail(false); f.access(null);
  await f.relay.recover(); assert.equal(new Set(f.sent.map(x => x.signal.eventId)).size, 1);
  const revoked = f.sent.filter(x => x.actor === 'recipient').at(-1)!.signal;
  assert.deepEqual(Object.keys(revoked).sort(), ['eventId','invalidate','noteId','ownerId','version']);
});
test('ACL unavailable is retried without recipient publication; terminal failures remain durable', async () => {
  const f = fixture(); f.aclFail(); await f.relay.deliver(f.key);
  assert.equal(f.sent.length, 1); assert.equal(f.db.get('owner', 'EVENT#event')?.attempts, 1);
  f.db.put({ ...f.row, attempts: MAX_ATTEMPTS }); await f.relay.deliver(f.key);
  assert.equal(f.db.get('owner', 'EVENT#event')?.relayStatus, 'dead');
  assert.equal(f.db.get('owner', 'EVENT#event')?.relayQueue, undefined);
});
test('bounded recovery queries due index and ignores future/leased/non-event rows', async () => {
  const f = fixture();
  f.db.put({ ...f.row, noteId: 'EVENT#future', eventId: 'future', relayDueAt: 2000 });
  f.db.put({ ...f.row, noteId: 'NOTE#alpha', relayQueue: undefined });
  assert.deepEqual(await f.store.due(1000, 1), [f.key]);
  assert.ok(retryDelay(99, 1) <= 1125000); assert.ok(retryDelay(1, 0) > 0);
});
test('subscribe handler rejects foreign/wildcard/unauthenticated channel', () => {
  const check = new Function('ctx', 'util', CHANNEL_HANDLER.replace(/^import[^\n]+\n/, '').replace('export function onSubscribe', 'function onSubscribe') + '\nreturn onSubscribe(ctx);');
  const util = { unauthorized() { throw Error('unauthorized'); } };
  check({ identity: { sub: 'owner' }, info: { channel: { path: '/notes/owner' } } }, util);
  for (const path of ['/notes/other', '/notes/*', '/notes/owner/*', '/notes/owner/extra']) {
    assert.throws(() => check({ identity: { sub: 'owner' }, info: { channel: { path } } }, util));
  }
  assert.throws(() => check({ identity: {}, info: { channel: { path: '/notes/owner' } } }, util));
});
test('CDK owns-channel Cognito subscribe, IAM-only publish, stream and scheduled recovery', () => {
  const stack = new Stack(new App(), 'RealtimeTest', { env: { account: '123456789012', region: 'us-east-1' } });
  const table = createNotesTable(stack);
  createRealtimeInfrastructure(stack, table, 'us-east-1_test', 'testclient');
  const t = Template.fromStack(stack);
  t.hasResourceProperties('AWS::AppSync::Api', { EventConfig: {
    ConnectionAuthModes: [{ AuthType: 'AMAZON_COGNITO_USER_POOLS' }],
    DefaultPublishAuthModes: [{ AuthType: 'AWS_IAM' }],
    DefaultSubscribeAuthModes: [{ AuthType: 'AMAZON_COGNITO_USER_POOLS' }],
  } });
  t.hasResourceProperties('AWS::AppSync::ChannelNamespace', { Name: 'notes', CodeHandlers: CHANNEL_HANDLER,
    PublishAuthModes: [{ AuthType: 'AWS_IAM' }] });
  t.hasResourceProperties('AWS::DynamoDB::Table', { StreamSpecification: { StreamViewType: 'NEW_IMAGE' } });
  t.resourceCountIs('AWS::Events::Rule', 1); t.resourceCountIs('AWS::Lambda::EventSourceMapping', 1);
});
