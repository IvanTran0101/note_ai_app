import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { Context, DynamoDBStreamEvent } from 'aws-lambda';
import { TestDynamo } from '../sharing/test_dynamo';
import { DynamoRelayStore } from './dynamo_relay_store';
import { AppSyncPublisher } from './appsync_publisher';
import { createHandler, type RelayRunner } from './handler';
import { InvocationBudget, type RelayBudget } from './budget';
import { MAX_ATTEMPTS, RevisionRelay, type RelayEvent, type RevisionSignal } from './relay';

const ACTORS = Array.from({ length: 21 }, (_, i) => `a${i}`);
const row = (actors = ACTORS): RelayEvent => ({
  ownerId: 'OWNER#owner', noteId: 'EVENT#event', eventId: 'event', canonicalOwnerId: 'owner',
  targetNoteId: 'alpha', revision: 1, protectionRevision: 0, actors,
  relayStatus: 'pending', relayQueue: 'pending', relayDueAt: 1000, attempts: 0,
} as unknown as RelayEvent);

function fixture(event: RelayEvent = row()) {
  const db = new TestDynamo(); db.put({ ...event, relayStatus: 'pending', relayQueue: 'pending', attempts: 0 });
  const sent: { actor: string; signal: RevisionSignal }[] = [];
  const relay = new RevisionRelay(new DynamoRelayStore('test', db.client),
    { async read() { return 4; } },
    { async publish(actor, signal) { sent.push({ actor, signal }); } },
    () => 1000);
  return { db, relay, sent, key: { ownerId: 'OWNER#owner', noteId: 'EVENT#event' } };
}

const expiry: RelayBudget = { remainingMs: () => 0, expired: () => true,
  workSignal: () => new AbortController().signal,
  bookkeepingSignal: () => new AbortController().signal };
const revisionSignal: RevisionSignal = { version: 1, eventId: 'event', ownerId: 'owner',
  noteId: 'alpha', invalidate: true };

test('invocation budget reserves the final seconds for bookkeeping', () => {
  let now = 1000; const budgets: number[] = [];
  const budget = new InvocationBudget(() => now, () => 60_000, 50_000, 10_000,
    ms => { budgets.push(ms); return new AbortController().signal; });
  assert.equal(budget.remainingMs(), 49_000, 'work stops with bookkeeping and return margin reserved');
  budget.workSignal(8_000); assert.equal(budgets.at(-1), 8_000);
  now = 51_000;
  assert.equal(budget.expired(), true);
  budget.bookkeepingSignal();
  assert.equal(budgets.at(-1), 9_000, 'bookkeeping ends 1s before the Lambda kill boundary');
});

test('already-expired budgets abort instead of scheduling a fresh 1ms attempt', () => {
  const timeouts: number[] = [];
  let now = 1000;
  const budget = new InvocationBudget(() => now, () => 10_500, 50_000, 10_000,
    ms => { timeouts.push(ms); return new AbortController().signal; });
  assert.equal(budget.expired(), true);
  assert.equal(budget.workSignal().aborted, true);
  assert.deepEqual(timeouts, [], 'expired work must not start I/O with a 1ms timer');
  budget.bookkeepingSignal();
  assert.deepEqual(timeouts, [9_500], 'bookkeeping still has the internal deadline');
  now += 9_500;
  assert.equal(budget.bookkeepingSignal().aborted, true);
  assert.deepEqual(timeouts, [9_500], 'expired hard deadline never schedules another attempt');
});

test('stalled complete is bounded before the return margin and retry cannot restart I/O', async () => {
  let now = 1000;
  const timeouts: { ms: number; controller: AbortController }[] = [];
  const budget = new InvocationBudget(() => now, () => 60_000, 50_000, 10_000,
    ms => { const controller = new AbortController(); timeouts.push({ ms, controller }); return controller.signal; });
  const event = { ...row([ACTORS[0]]), leaseId: 'lease' } as RelayEvent;
  const seen: AbortSignal[] = [];
  let completeStarted!: () => void;
  const started = new Promise<void>(resolve => { completeStarted = resolve; });
  const store = {
    async claim() { return event; },
    async complete(_event: RelayEvent, _now: number, signal?: AbortSignal) {
      seen.push(signal!);
      completeStarted();
      await new Promise<never>((_resolve, reject) => {
        signal!.addEventListener('abort', () => reject(new Error('stalled complete')), { once: true });
      });
    },
    async retry(_event: RelayEvent, _due: number, _dead: boolean, signal?: AbortSignal) {
      seen.push(signal!);
    },
    async due() { return []; },
  };
  const relay = new RevisionRelay(store, { async read() { return 4; } },
    { async publish() { now = 51_000; } }, () => now);
  const pending = relay.deliver({ ownerId: 'OWNER#owner', noteId: 'EVENT#event' }, budget);
  await started;
  const completeTimer = timeouts.at(-1)!;
  assert.equal(completeTimer.ms, 9_000, 'complete leaves the final 1s before the Lambda kill');
  now = 60_000;
  completeTimer.controller.abort();
  await pending;
  assert.equal(seen.length, 2);
  assert.equal(seen[1].aborted, true, 'retry sees the already-expired internal deadline');
  assert.equal(timeouts.length, 4, 'expired retry does not schedule a fresh timer');
});

test('actor publication starts five workers and waits for all of them to settle', async () => {
  const f = fixture();
  let active = 0, max = 0, calls = 0;
  const settled = new Promise<void>((resolve) => {
    f.relay = new RevisionRelay(new DynamoRelayStore('test', f.db.client),
      { async read() { return 4; } },
      { async publish(actor, signal) {
        calls++; active++; max = Math.max(max, active);
        f.sent.push({ actor, signal });
        try {
          if (calls === 1) { await Promise.resolve(); throw new Error('first failure'); }
          await new Promise(resolve => setTimeout(resolve, 20));
        } finally {
          active--;
          if (calls === 5 && active === 0) resolve();
        }
      } }, () => 1000);
  });
  await f.relay.deliver(f.key);
  await settled;
  assert.equal(active, 0, 'no late publisher remains after retry state is written');
  assert.equal(calls, 5, 'no new actor is started after the first failure');
  assert.equal(max, 5);
  assert.equal(f.db.get('owner', 'EVENT#event')?.relayStatus, 'pending');
});

test('slow fanout exits at the work deadline, then retries with stable event IDs', async () => {
  const f = fixture();
  let now = 1000, advance = true;
  const timeouts: number[] = [];
  const budget = new InvocationBudget(() => now, () => 60_000, 50_000, 10_000,
    ms => { timeouts.push(ms); return new AbortController().signal; });
  f.relay = new RevisionRelay(new DynamoRelayStore('test', f.db.client),
    { async read() { return 4; } },
    { async publish(actor, signal) {
      f.sent.push({ actor, signal });
      if (advance) now = 51_000;
    } }, () => now, () => 0.5);
  await f.relay.deliver(f.key, budget);
  assert.equal(budget.expired(), true);
  assert.ok(f.sent.length > 0 && f.sent.length <= 5);
  assert.equal(f.db.get('owner', 'EVENT#event')?.relayStatus, 'pending');
  assert.equal(timeouts.at(-1), 9_000, 'retry used the bookkeeping signal inside the return margin');

  const firstIds = new Set(f.sent.map(x => x.signal.eventId));
  assert.equal(firstIds.size, 1);
  advance = false; now = f.db.get('owner', 'EVENT#event')!.relayDueAt;
  const retryBudget = new InvocationBudget(() => now, () => 60_000, 50_000, 10_000,
    () => new AbortController().signal);
  await f.relay.deliver(f.key, retryBudget);
  assert.equal(f.db.get('owner', 'EVENT#event')?.relayStatus, 'done');
  assert.deepEqual(new Set(f.sent.map(x => x.actor)), new Set(ACTORS));
  assert.equal(new Set(f.sent.map(x => x.signal.eventId)).size, 1, 'partial publication retries the same event');
});

test('claim/due honor an aborted request signal and leave the row untouched', async () => {
  const f = fixture();
  const store = new DynamoRelayStore('test', f.db.client);
  await assert.rejects(store.claim(f.key, 1000, AbortSignal.abort()));
  assert.equal(f.db.get('owner', 'EVENT#event')?.attempts, 0);
  assert.equal(f.db.get('owner', 'EVENT#event')?.leaseId, undefined);
  await assert.rejects(store.due(1000, 10, AbortSignal.abort()));
});

test('publish cancellation covers signer credentials and response body', async () => {
  const endpoint = 'https://example.appsync-api.us-east-1.amazonaws.com/event';
  let transportCalls = 0;
  const signing = new AppSyncPublisher(endpoint, 'us-east-1',
    (async () => { transportCalls++; return { ok: true, json: async () => ({ failed: [] }) }; }) as unknown as typeof fetch,
    (() => new Promise(() => {})) as () => Promise<{ accessKeyId: string; secretAccessKey: string }>);
  const controller = new AbortController();
  const pending = signing.publish('actor', revisionSignal, controller.signal);
  controller.abort();
  await assert.rejects(pending);
  assert.equal(transportCalls, 0);

  let started!: () => void;
  const bodyStarted = new Promise<void>((resolve) => { started = resolve; });
  const body = new AppSyncPublisher(endpoint, 'us-east-1',
    (async () => ({ ok: true, json: () => { started(); return new Promise(() => {}); } })) as unknown as typeof fetch,
    async () => ({ accessKeyId: 'AKID', secretAccessKey: 'SECRET' }));
  const bodyController = new AbortController();
  const bodyPending = body.publish('actor', revisionSignal, bodyController.signal);
  await bodyStarted;
  bodyController.abort();
  await assert.rejects(bodyPending);
});

test('stream cutoff reports untouched valid records and scheduled recovery claims nothing', async () => {
  let now = 0; const delivered: string[] = [];
  const runner: RelayRunner = {
    async deliver(key) { delivered.push(key.noteId); now = 60_000; },
    async recover() {},
  };
  const handler = createHandler(runner, () => now);
  const event = { Records: [
    { eventName: 'INSERT', dynamodb: { SequenceNumber: '1', Keys: { ownerId: { S: 'OWNER#o' }, noteId: { S: 'EVENT#one' } } } },
    { eventName: 'INSERT', dynamodb: { SequenceNumber: '2', Keys: { ownerId: { S: 'OWNER#o' }, noteId: { S: 'NOTE#ignored' } } } },
    { eventName: 'INSERT', dynamodb: { SequenceNumber: '3', Keys: { ownerId: { S: 'OWNER#o' }, noteId: { S: 'EVENT#two' } } } },
  ] } as unknown as DynamoDBStreamEvent;
  const result = await handler(event, { getRemainingTimeInMillis: () => 60_000 } as Context);
  assert.deepEqual(result.batchItemFailures, [{ itemIdentifier: '3' }]);
  assert.deepEqual(delivered, ['EVENT#one']);

  let due = 0, claims = 0;
  const emptyRelay = new RevisionRelay({
    async claim() { claims++; return null; },
    async complete() {}, async retry() {},
    async due() { due++; return []; },
  }, { async read() { return 4; } }, { async publish() {} }, () => now);
  await emptyRelay.recover(expiry);
  assert.equal(due, 0);
  assert.equal(claims, 0);
  assert.equal(MAX_ATTEMPTS, 20);
});
