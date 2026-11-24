import assert from 'node:assert/strict';
import { test } from 'node:test';
import { TransactionCanceledException } from '@aws-sdk/client-dynamodb';
import { GetCommand, TransactWriteCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import { TestDynamo } from '../sharing/test_dynamo';
import { DynamoRelayStore, decodeEvent, LEASE_MS } from './dynamo_relay_store';
import { RevisionRelay, type RelayEvent, type RevisionSignal } from './relay';
import { MAX_NORMALIZE_ACTORS, normalizationPage, shardEventId } from './relay_shards';
import { MAX_EVENT_ACTORS } from '../sharing/actor_feed';

const eventRow = (eventId: string, actors: string[], due = 100, extra: Record<string, unknown> = {}) => ({
  ownerId: 'OWNER#owner', noteId: `EVENT#${eventId}`, eventId, canonicalOwnerId: 'owner',
  targetNoteId: 'alpha', revision: 1, protectionRevision: 0, actors,
  relayStatus: 'pending', relayQueue: 'pending', relayDueAt: due, attempts: 0, ...extra,
});

function fixture(rows: Record<string, unknown>[]) {
  const db = new TestDynamo(); rows.forEach(row => db.put(row));
  let now = 1000; const sent: { actor: string; signal: RevisionSignal }[] = [];
  const relay = new RevisionRelay(new DynamoRelayStore('test', db.client),
    { async read() { return 4; } },
    { async publish(actor, signal) { sent.push({ actor, signal }); } },
    () => now);
  return { db, relay, sent, time: (value: number) => { now = value; } };
}

const eventRows = (db: TestDynamo) =>
  [...db.rows.values()].filter(row => String(row.noteId).startsWith('EVENT#'));

type Expression = {
  ConditionExpression?: string; UpdateExpression?: string; KeyConditionExpression?: string;
  ExpressionAttributeNames?: Record<string, string>;
  ExpressionAttributeValues?: Record<string, unknown>;
};
const placeholders = (text: string | undefined) => {
  const values = new Set<string>(); const names = new Set<string>();
  for (const match of (text ?? '').matchAll(/([:#][A-Za-z0-9_]+)/g)) {
    if (match[0].startsWith(':')) values.add(match[0]); else names.add(match[0]);
  }
  return { values, names };
};
/** Production DynamoDB rejects both missing and unused expression bindings. */
function assertExactBindings(expression: Expression): void {
  const references = [expression.ConditionExpression, expression.UpdateExpression,
    expression.KeyConditionExpression].map(placeholders);
  const values = new Set(references.flatMap(reference => [...reference.values]));
  const names = new Set(references.flatMap(reference => [...reference.names]));
  assert.deepEqual([...values].sort(), Object.keys(expression.ExpressionAttributeValues ?? {}).sort(),
    'expression values must exactly match referenced : placeholders');
  assert.deepEqual([...names].sort(), Object.keys(expression.ExpressionAttributeNames ?? {}).sort(),
    'expression names must exactly match referenced # placeholders');
}
function assertDbBindings(db: TestDynamo): void {
  for (const transaction of db.transactions) {
    for (const item of transaction.input.TransactItems ?? []) {
      if (item.Update) assertExactBindings(item.Update);
    }
  }
  for (const update of db.updates) assertExactBindings(update.input as Expression);
}

test('schema-corrupt poison is fenced-quarantined and the following good key still delivers', async () => {
  const f = fixture([
    eventRow('poison', ['BAD/ACTOR'], 100),
    eventRow('good', ['owner', 'recipient'], 200),
  ]);
  await f.relay.recover();
  assert.equal(f.sent.length, 2);
  const poison = f.db.get('owner', 'EVENT#poison')!;
  assert.equal(poison.relayStatus, 'dead');
  assert.equal(poison.relayQueue, undefined);
  assert.equal(poison.quarantineReason, 'schema-invalid');
  assert.deepEqual(poison.actors, ['BAD/ACTOR'], 'payload is preserved for inspection');
  assert.ok(!JSON.stringify(poison.quarantineReason).includes('BAD/ACTOR'));
});

test('quarantine transport failure leaves poison retryable and never aborts the good key', async () => {
  const f = fixture([
    eventRow('poison', ['BAD/ACTOR'], 100),
    eventRow('good', ['owner', 'recipient'], 200),
  ]);
  f.db.failWhen = command => command instanceof UpdateCommand &&
    String(command.input.UpdateExpression).includes('quarantineReason')
    ? Object.assign(new Error('transport down'), { name: 'DynamoDBServiceException' }) : undefined;
  await f.relay.recover();
  assert.equal(f.sent.length, 2);
  let poison = f.db.get('owner', 'EVENT#poison')!;
  assert.equal(poison.relayStatus, 'pending');
  assert.equal(poison.relayQueue, 'pending');
  assert.equal(poison.quarantineReason, undefined);
  assert.equal(poison.attempts, 1);
  f.db.failWhen = undefined; f.time(1000 + LEASE_MS);
  await f.relay.recover();
  poison = f.db.get('owner', 'EVENT#poison')!;
  assert.equal(poison.relayStatus, 'dead');
  assert.equal(poison.relayQueue, undefined);
});

test('a retry-state write failure on one key does not stop the next key', async () => {
  const db = new TestDynamo();
  db.put(eventRow('bad', ['owner'], 100));
  db.put(eventRow('good', ['owner'], 200));
  const sent: string[] = [];
  const relay = new RevisionRelay(new DynamoRelayStore('test', db.client),
    { async read() { return 4; } },
    { async publish(_actor, signal) {
      if (signal.eventId === 'bad') throw new Error('publish down');
      sent.push(signal.eventId);
    } }, () => 1000);
  db.failWhen = command => command instanceof UpdateCommand &&
    command.input.Key?.noteId === 'EVENT#bad' &&
    String(command.input.UpdateExpression).includes('nextAttemptAt')
    ? Object.assign(new Error('retry write down'), { name: 'DynamoDBServiceException' }) : undefined;
  await relay.recover();
  assert.deepEqual(sent, ['good']);
  assert.equal(db.get('owner', 'EVENT#bad')?.relayStatus, 'pending');
  assert.equal(db.get('owner', 'EVENT#bad')?.relayQueue, 'pending');
  assert.equal(db.get('owner', 'EVENT#good')?.relayStatus, 'done');
});

test('invalid ADD input is raw-read/fenced, while an unexpected transport error stays retryable', async () => {
  const f = fixture([eventRow('bad-add', ['owner'], 100, { attempts: 'not-a-number' })]);
  await f.relay.recover();
  const quarantined = f.db.get('owner', 'EVENT#bad-add')!;
  assert.equal(quarantined.relayStatus, 'dead');
  assert.equal(quarantined.relayQueue, undefined);
  assert.equal(quarantined.attempts, 'not-a-number', 'payload is not rewritten');

  const g = fixture([eventRow('transient', ['owner'], 100), eventRow('good', ['owner'], 200)]);
  g.db.failWhen = command => command instanceof UpdateCommand && command.input.Key?.noteId === 'EVENT#transient'
    ? Object.assign(new Error('network down'), { name: 'TimeoutError' }) : undefined;
  await g.relay.recover();
  assert.equal(g.sent.length, 1);
  assert.equal(g.db.get('owner', 'EVENT#transient')?.relayStatus, 'pending');
  assert.equal(g.db.get('owner', 'EVENT#transient')?.relayQueue, 'pending');
  assert.equal(g.db.get('owner', 'EVENT#transient')?.quarantineReason, undefined);
});

test('a malformed row repaired after the raw read is never dead-lettered', async () => {
  const f = fixture([eventRow('bad-add', ['owner'], 100, { attempts: 'not-a-number' })]);
  f.db.failWhen = command => {
    if (command instanceof UpdateCommand && !String(command.input.UpdateExpression).includes('ADD') &&
        String(command.input.UpdateExpression).startsWith('SET leaseId = :lease, leaseUntil = :until, relayDueAt = :until')) {
      const row = f.db.get('owner', 'EVENT#bad-add')!;
      f.db.put({ ...row, attempts: 0 });
    }
    return undefined;
  };
  await f.relay.recover();
  const row = f.db.get('owner', 'EVENT#bad-add')!;
  assert.equal(row.relayStatus, 'pending');
  assert.equal(row.relayQueue, 'pending');
  assert.equal(row.attempts, 0);
  assert.equal(row.quarantineReason, undefined);
  assert.equal(f.db.updates.filter(update =>
    String(update.input.UpdateExpression).includes('quarantineReason')).length, 0);
});

test('a competing lease acquired after the raw read prevents malformed quarantine', async () => {
  const f = fixture([eventRow('bad-add', ['owner'], 100, { attempts: 'not-a-number' })]);
  f.db.failWhen = command => {
    if (command instanceof UpdateCommand && !String(command.input.UpdateExpression).includes('ADD') &&
        String(command.input.UpdateExpression).startsWith('SET leaseId = :lease, leaseUntil = :until, relayDueAt = :until')) {
      const row = f.db.get('owner', 'EVENT#bad-add')!;
      f.db.put({ ...row, leaseId: 'another-worker', leaseUntil: 5000 });
    }
    return undefined;
  };
  await f.relay.recover();
  const row = f.db.get('owner', 'EVENT#bad-add')!;
  assert.equal(row.relayStatus, 'pending');
  assert.equal(row.relayQueue, 'pending');
  assert.equal(row.leaseId, 'another-worker');
  assert.equal(row.leaseUntil, 5000);
  assert.equal(row.quarantineReason, undefined);
});

test('missing and string attempts are fenced and quarantined on the injected clock', async () => {
  for (const attempts of [undefined, 'not-a-number']) {
    const f = fixture([eventRow('bad-add', ['owner'], 100, { attempts })]);
    const fences: UpdateCommand[] = [];
    f.db.failWhen = command => {
      if (command instanceof UpdateCommand &&
          String(command.input.UpdateExpression).includes('ADD attempts')) {
        return Object.assign(new Error('malformed attempts'), { name: 'ValidationException' });
      }
      if (command instanceof UpdateCommand &&
          String(command.input.UpdateExpression).startsWith('SET leaseId = :lease, leaseUntil = :until, relayDueAt = :until')) {
        fences.push(command);
      }
      return undefined;
    };
    const store = new DynamoRelayStore('test', f.db.client);
    assert.equal(await store.claim({ ownerId: 'OWNER#owner', noteId: 'EVENT#bad-add' }, 5000), null);
    const row = f.db.get('owner', 'EVENT#bad-add')!;
    assert.equal(row.relayStatus, 'dead');
    assert.equal(row.relayQueue, undefined);
    assert.equal(row.attempts, attempts);
    assert.equal(row.quarantineReason, 'schema-invalid');
    assert.match(String(row.leaseId), /^[0-9a-f-]{36}$/);
    assert.equal(row.leaseUntil, undefined, 'the fenced lease is removed by quarantine');
    assert.equal(fences.length, 1);
    assert.equal(fences[0].input.ExpressionAttributeValues![':now'], 5000);
    assert.equal(fences[0].input.ExpressionAttributeValues![':until'], 5000 + LEASE_MS);
    assert.ok(!String(fences[0].input.UpdateExpression).includes('ADD'));
    assertDbBindings(f.db);
  }
});

test('a transport failure while inspecting malformed attempts stays retryable', async () => {
  const f = fixture([eventRow('bad-add', ['owner'], 100, { attempts: 'not-a-number' })]);
  f.db.failWhen = command => {
    if (command instanceof UpdateCommand && String(command.input.UpdateExpression).includes('ADD attempts')) {
      return Object.assign(new Error('malformed attempts'), { name: 'ValidationException' });
    }
    if (command instanceof GetCommand) {
      return Object.assign(new Error('network down'), { name: 'TimeoutError' });
    }
    return undefined;
  };
  const store = new DynamoRelayStore('test', f.db.client);
  await assert.rejects(store.claim({ ownerId: 'OWNER#owner', noteId: 'EVENT#bad-add' }, 1000));
  const row = f.db.get('owner', 'EVENT#bad-add')!;
  assert.equal(row.relayStatus, 'pending');
  assert.equal(row.relayQueue, 'pending');
  assert.equal(row.quarantineReason, undefined);
});

test('well-formed 22 and 43 actor overflow normalizes into disjoint deterministic shards', async () => {
  for (const count of [22, 43]) {
    const actors = Array.from({ length: count }, (_, i) => `a${i}`);
    const f = fixture([eventRow('parent', actors)]);
    await f.relay.recover();
    const parent = f.db.get('owner', 'EVENT#parent')!;
    assert.equal(parent.relayStatus, 'split');
    assert.equal(parent.relayQueue, undefined);
    assert.equal(parent.splitOffset, count);
    const childIds = Array.from({ length: Math.ceil(count / MAX_EVENT_ACTORS) }, (_, i) => shardEventId('parent', i));
    for (const id of childIds) assert.ok(f.db.get('owner', `EVENT#${id}`));
    const union = childIds.flatMap(id => f.db.get('owner', `EVENT#${id}`)!.actors as string[]);
    assert.deepEqual(union, actors);
    assert.equal(new Set(union).size, count);
    assert.ok(childIds.every(id =>
      (f.db.get('owner', `EVENT#${id}`)!.actors as string[]).length <= MAX_EVENT_ACTORS));
    assertDbBindings(f.db);
  }
});

test('2079 and 2080 actors page at the 99-child transaction boundary with no lost actor', async () => {
  for (const count of [MAX_NORMALIZE_ACTORS, MAX_NORMALIZE_ACTORS + 1]) {
    const actors = Array.from({ length: count }, (_, i) => `a${i}`);
    const f = fixture([eventRow('page', actors)]);
    await f.relay.recover();
    const children = eventRows(f.db).filter(row => row.noteId !== 'EVENT#page');
    assert.equal(children.length, Math.ceil(count / MAX_EVENT_ACTORS));
    assert.ok(f.db.transactions.every(tx => tx.input.TransactItems!.length <= 100));
    assert.equal(f.db.transactions[0].input.TransactItems!.length, 100);
    if (count > MAX_NORMALIZE_ACTORS) assert.equal(f.db.transactions.length, 2);
    const parent = f.db.get('owner', 'EVENT#page')!;
    assert.equal(parent.relayStatus, 'split');
    assert.equal(parent.splitOffset, count);
    const union = children.flatMap(row => row.actors as string[]);
    assert.deepEqual(union, actors);
    assert.equal(new Set(union).size, count);
    assertDbBindings(f.db);
  }
});

test('lost normalization ACK leaves one atomic parent split and never recreates children', async () => {
  const actors = Array.from({ length: 22 }, (_, i) => `a${i}`);
  const f = fixture([eventRow('parent', actors)]);
  f.db.afterTransaction = () => { throw new Error('lost ACK'); };
  await f.relay.recover();
  assert.equal(f.db.get('owner', 'EVENT#parent')?.relayStatus, 'split');
  assert.equal(eventRows(f.db).length, 3, 'parent plus two children');
  f.time(1001);
  await f.relay.recover();
  assert.equal(eventRows(f.db).length, 3);
  assert.deepEqual(f.sent.map(x => x.actor), actors);
  assert.equal(new Set(f.sent.map(x => x.signal.eventId)).size, 2);
});

test('an intermediate page lost ACK resumes from the durable offset without duplicate shards', async () => {
  const actors = Array.from({ length: MAX_NORMALIZE_ACTORS + 1 }, (_, i) => `a${i}`);
  const f = fixture([eventRow('page', actors)]);
  f.db.afterTransaction = () => { throw new Error('lost ACK'); };
  await f.relay.recover();
  let parent = f.db.get('owner', 'EVENT#page')!;
  assert.equal(parent.relayStatus, 'pending');
  assert.equal(parent.splitOffset, MAX_NORMALIZE_ACTORS);
  assert.equal(eventRows(f.db).length, 100, 'parent plus the first 99 children');
  f.time(1000 + LEASE_MS);
  await f.relay.recover();
  parent = f.db.get('owner', 'EVENT#page')!;
  assert.equal(parent.relayStatus, 'split');
  assert.equal(parent.splitOffset, actors.length);
  const children = eventRows(f.db).filter(row => row.noteId !== 'EVENT#page');
  assert.equal(children.length, 100);
  const union = children.flatMap(row => row.actors as string[]);
  assert.deepEqual(union, actors);
  assert.equal(new Set(union).size, actors.length);
});

test('an existing deterministic child collision is retryable and is never overwritten', async () => {
  const actors = Array.from({ length: 22 }, (_, i) => `a${i}`);
  const collision = shardEventId('parent', 0);
  const f = fixture([eventRow('parent', actors),
    eventRow(collision, ['sentinel'], 100, { relayQueue: undefined })]);
  await f.relay.recover();
  assert.deepEqual(f.db.get('owner', `EVENT#${collision}`)?.actors, ['sentinel']);
  assert.equal(f.db.get('owner', `EVENT#${shardEventId('parent', 1)}`), undefined);
  const parent = f.db.get('owner', 'EVENT#parent')!;
  assert.equal(parent.relayStatus, 'pending');
  assert.equal(parent.splitOffset, undefined);
  assert.deepEqual(parent.actors, actors);
});

test('a replaced generated lease cannot mutate the parent or create a child', async () => {
  const actors = Array.from({ length: 43 }, (_, i) => `a${i}`);
  const f = fixture([eventRow('parent', actors)]);
  f.db.beforeTransaction = () => {
    const parent = f.db.get('owner', 'EVENT#parent')!;
    f.db.put({ ...parent, leaseId: 'another-worker' });
  };
  await f.relay.recover();
  const parent = f.db.get('owner', 'EVENT#parent')!;
  assert.equal(parent.relayStatus, 'pending');
  assert.equal(parent.leaseId, 'another-worker');
  assert.equal(parent.splitOffset, undefined);
  assert.deepEqual(parent.actors, actors);
  assert.equal(eventRows(f.db).length, 1);
});

test('a typed transaction cancellation from a replaced parent lease returns as stale work', async () => {
  const actors = Array.from({ length: 43 }, (_, i) => `a${i}`);
  const f = fixture([eventRow('parent', actors)]);
  const store = new DynamoRelayStore('test', f.db.client);
  f.db.beforeTransaction = () => {
    const parent = f.db.get('owner', 'EVENT#parent')!;
    f.db.put({ ...parent, leaseId: 'another-worker' });
  };
  assert.equal(await store.claim({ ownerId: 'OWNER#owner', noteId: 'EVENT#parent' }, 1000), null);
  const parent = f.db.get('owner', 'EVENT#parent')!;
  assert.equal(parent.relayStatus, 'pending');
  assert.equal(parent.leaseId, 'another-worker');
  assert.equal(parent.splitOffset, undefined);
  assert.equal(eventRows(f.db).length, 1);
  assert.equal(f.db.transactions.length, 0);
});

test('a typed transaction cancellation from a child collision remains a retryable error', async () => {
  const actors = Array.from({ length: 22 }, (_, i) => `a${i}`);
  const collision = shardEventId('parent', 0);
  const f = fixture([eventRow('parent', actors),
    eventRow(collision, ['sentinel'], 100, { relayQueue: undefined })]);
  const store = new DynamoRelayStore('test', f.db.client);
  await assert.rejects(store.claim({ ownerId: 'OWNER#owner', noteId: 'EVENT#parent' }, 1000));
  assert.deepEqual(f.db.get('owner', `EVENT#${collision}`)?.actors, ['sentinel']);
  assert.equal(f.db.get('owner', `EVENT#${shardEventId('parent', 1)}`), undefined);
  const parent = f.db.get('owner', 'EVENT#parent')!;
  assert.equal(parent.relayStatus, 'pending');
  assert.equal(parent.splitOffset, undefined);
  assert.deepEqual(parent.actors, actors);
  assert.equal(f.db.transactions.length, 0);
});

test('a typed transaction cancellation after an offset advance is a lost ACK', async () => {
  const actors = Array.from({ length: 43 }, (_, i) => `a${i}`);
  const f = fixture([eventRow('parent', actors)]);
  const store = new DynamoRelayStore('test', f.db.client);
  f.db.beforeTransaction = () => {
    const parent = f.db.get('owner', 'EVENT#parent')!;
    f.db.put({ ...parent, splitOffset: MAX_EVENT_ACTORS });
  };
  assert.equal(await store.claim({ ownerId: 'OWNER#owner', noteId: 'EVENT#parent' }, 1000), null);
  const parent = f.db.get('owner', 'EVENT#parent')!;
  assert.equal(parent.relayStatus, 'pending');
  assert.equal(parent.splitOffset, MAX_EVENT_ACTORS);
  assert.equal(eventRows(f.db).length, 1);
  assert.equal(f.db.transactions.length, 0);
});

test('nonconditional transaction cancellations are never swallowed', async () => {
  for (const code of ['TransactionConflict', 'ThrottlingError']) {
    const actors = Array.from({ length: 22 }, (_, i) => `a${i}`);
    const f = fixture([eventRow('parent', actors)]);
    f.db.failWhen = command => command instanceof TransactWriteCommand
      ? new TransactionCanceledException({ message: 'cancelled', $metadata: {},
        CancellationReasons: [{ Code: code }] }) : undefined;
    const store = new DynamoRelayStore('test', f.db.client);
    await assert.rejects(store.claim({ ownerId: 'OWNER#owner', noteId: 'EVENT#parent' }, 1000),
      error => error instanceof TransactionCanceledException);
    const parent = f.db.get('owner', 'EVENT#parent')!;
    assert.equal(parent.relayStatus, 'pending');
    assert.equal(parent.splitOffset, undefined);
  }
});

test('transaction and update expressions bind exactly their referenced placeholders', () => {
  for (const count of [22, MAX_NORMALIZE_ACTORS, MAX_NORMALIZE_ACTORS + 1]) {
    const event = eventRow('page', Array.from({ length: count }, (_, i) => `a${i}`), 100,
      { leaseId: 'lease' }) as unknown as RelayEvent;
    for (let offset = 0; offset < count; offset += MAX_NORMALIZE_ACTORS) {
      const page = normalizationPage('test', event, offset, 1000, LEASE_MS);
      for (const write of page.writes) if (write.Update) assertExactBindings(write.Update);
    }
  }
});

test('strict decode accepts overflow but rejects an invalid durable split offset', () => {
  const base = eventRow('parent', Array.from({ length: 22 }, (_, i) => `a${i}`), 100, { leaseId: 'lease' });
  assert.doesNotThrow(() => decodeEvent(base));
  assert.doesNotThrow(() => decodeEvent({ ...base, splitOffset: 21 }));
  assert.throws(() => decodeEvent({ ...base, splitOffset: 22 }));
  assert.throws(() => decodeEvent({ ...base, actors: ['owner/*'] }));
  const typed = base as unknown as RelayEvent;
  assert.equal(typed.actors.length, 22);
});
