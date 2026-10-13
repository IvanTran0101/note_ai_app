/**
 * Phase 5 pilot budget tests: one atomic query admission (global attempt + UTC-day attempt +
 * in-flight lease), no partial debit on a refused admission, lease ownership and expiry,
 * provider caps that count failed calls and never refund, the shared 1,000,000-micros ceiling,
 * the atomic global + pilot Cohere admission, key identity with the existing budget item and
 * every input bound. A fake document client evaluates the conditions this budget issues; no
 * AWS, network or provider call is made.
 *
 * The corruption half is deliberate: every counter row is read with a strongly consistent
 * preflight GET, so a stored counter that is `null`, negative, fractional or non-numeric, a
 * foreign key, a corrupt lease or a value another worker moves between the read and the write
 * refuses the admission and debits nothing. A refused admission is the caller's signal that no
 * provider/model call may follow, which `admit()` asserts by never counting one.
 *
 * Runner: node --import tsx --test amplify/rag/phase5/pilot_budget.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DeleteCommand, GetCommand, TransactWriteCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import { BUDGET_OWNER_KEY, BUDGET_SORT_KEY } from '../indexing/store';
import { RagFailure } from '../types';
import {
  GLOBAL_EMBEDDING_KEY, GLOBAL_EMBEDDING_LIMIT, PILOT_BUDGET_KEY, PILOT_DAILY_QUERY_LIMIT, PILOT_LIMITS,
  PILOT_QUERY_LEASE_MS, PILOT_USD_MICROS_LIMIT, createPilotBudget,
} from './pilot_budget';
import type { PilotBudgetPort, PilotCommand, QueryLease } from './pilot_budget';

type Item = Record<string, unknown>;
const SUB = (n: number): string => `0000000${n}-0000-4000-8000-00000000000${n}`;
/** A UUID carrying hex letters, for the case-sensitivity check. */
const LETTERS = 'abcdef01-2345-4678-89ab-cdef01234567';
const START = Date.parse('2026-10-12T10:00:00.000Z');
const DAY = '2026-10-12';
const signal = (): AbortSignal => new AbortController().signal;
const dailyKey = (day: string, actor: string): Item => ({ ownerId: PILOT_BUDGET_KEY.ownerId, noteId: `DAILY#${day}#${actor}` });
const leaseKey = (actor: string): Item => ({ ownerId: PILOT_BUDGET_KEY.ownerId, noteId: `LEASE#${actor}` });
/** Every counter the pilot item owns; a corrupt value in any one of them refuses the debit. */
const COUNTERS = ['queryCalls', 'jevCalls', 'deepseekCalls', 'cohereCalls', 'reservedUsdMicros'] as const;
/** Values a counter must never be read as 0: only a missing attribute is 0. */
const CORRUPT_VALUES: ReadonlyArray<readonly [string, unknown]> = [
  ['negative', -1],
  ['fractional', 1.5],
  ['null', null],
  ['string', '3'],
  ['NaN', Number.NaN],
  ['unsafe', Number.MAX_SAFE_INTEGER + 1],
];

const tokenize = (expression: string): string[] =>
  expression.match(/\(|\)|attribute_not_exists\([^)]*\)|attribute_exists\([^)]*\)|[^\s()]+/g) ?? [];

const compare = (left: unknown, operator: string, right: unknown): boolean => {
  switch (operator) {
    case '=': return left === right;
    case '<': return typeof left === 'number' && typeof right === 'number' && left < right;
    case '<=': return typeof left === 'number' && typeof right === 'number' && left <= right;
    case '>': return typeof left === 'number' && typeof right === 'number' && left > right;
    case '>=': return typeof left === 'number' && typeof right === 'number' && left >= right;
    default: throw new Error(`unsupported operator ${operator}`);
  }
};

/** Evaluates the DynamoDB condition subset this budget writes, so the test never restates it. */
const evaluate = (expression: string, item: Item, names: Record<string, string>, values: Item): boolean => {
  const tokens = tokenize(expression);
  let index = 0;
  const nameOf = (token: string): string => names[token] ?? token;
  const primary = (): boolean => {
    const token = tokens[index++];
    if (token === undefined) throw new Error('unexpected end of condition');
    if (token === '(') {
      const value = or();
      if (tokens[index++] !== ')') throw new Error('unbalanced condition');
      return value;
    }
    const guard = /^(attribute_not_exists|attribute_exists)\((.+)\)$/.exec(token);
    if (guard !== null) {
      const exists = Object.prototype.hasOwnProperty.call(item, nameOf(guard[2] as string));
      return guard[1] === 'attribute_exists' ? exists : !exists;
    }
    const operator = tokens[index++];
    const right = values[tokens[index++] as string];
    return compare(item[nameOf(token)], operator as string, right);
  };
  const and = (): boolean => {
    let value = primary();
    while (tokens[index] === 'AND') {
      index += 1;
      value = primary() && value;
    }
    return value;
  };
  const or = (): boolean => {
    let value = and();
    while (tokens[index] === 'OR') {
      index += 1;
      value = and() || value;
    }
    return value;
  };
  const result = or();
  if (index !== tokens.length) throw new Error(`unparsed condition: ${expression}`);
  return result;
};

type Hook = (command: PilotCommand, items: Map<string, Item>) => void;

type Fake = Readonly<{
  port: PilotBudgetPort;
  items: Map<string, Item>;
  at: (key: Item) => string;
  calls: () => number;
  /** Counter/lease writes actually applied; a refused admission must leave it unchanged. */
  writes: () => number;
  /** Runs once, immediately before the first matching command is evaluated. */
  before: (match: (command: PilotCommand) => boolean, hook: Hook) => void;
}>;

const fakeDynamo = (): Fake => {
  const items = new Map<string, Item>();
  const hooks: Array<{ match: (command: PilotCommand) => boolean; hook: Hook; used: boolean }> = [];
  let calls = 0;
  let writes = 0;
  const at = (key: Item): string => `${String(key['ownerId'])}\u0000${String(key['noteId'])}`;
  const holds = (expression: unknown, current: Item | undefined, names: unknown, values: unknown): boolean =>
    expression === undefined ||
    evaluate(String(expression), current ?? {}, (names ?? {}) as Record<string, string>, (values ?? {}) as Item);

  const applyUpdate = (input: Item, current: Item | undefined): Item => {
    // A real DynamoDB item always carries its key attributes, so the fake stores them too.
    const next: Item = { ...(input['Key'] as Item), ...(current ?? {}) };
    const names = (input['ExpressionAttributeNames'] ?? {}) as Record<string, string>;
    const values = (input['ExpressionAttributeValues'] ?? {}) as Item;
    const expression = String(input['UpdateExpression'] ?? '');
    for (const match of expression.matchAll(/ADD\s+(#[A-Za-z0-9_]+|[A-Za-z0-9_]+)\s+(:[A-Za-z0-9_]+)/g)) {
      const attribute = names[match[1] as string] ?? (match[1] as string);
      next[attribute] = ((next[attribute] as number | undefined) ?? 0) + (values[match[2] as string] as number);
    }
    for (const match of expression.matchAll(
      /(#[A-Za-z0-9_]+|[A-Za-z0-9_]+)\s*=\s*if_not_exists\((#[A-Za-z0-9_]+|[A-Za-z0-9_]+),\s*(:[A-Za-z0-9_]+)\)\s*\+\s*(:[A-Za-z0-9_]+)/g,
    )) {
      const attribute = names[match[1] as string] ?? (match[1] as string);
      const fallback = values[match[3] as string] as number;
      next[attribute] = ((next[attribute] as number | undefined) ?? fallback) + (values[match[4] as string] as number);
    }
    return next;
  };

  const port: PilotBudgetPort = {
    async send(command): Promise<unknown> {
      calls += 1;
      for (const entry of hooks) {
        if (!entry.used && entry.match(command)) {
          entry.used = true;
          entry.hook(command, items);
          break;
        }
      }
      const input = (command as { input: Item }).input;
      if (command instanceof TransactWriteCommand) {
        const entries = (input['TransactItems'] ?? []) as Item[];
        const allowed = entries.map((entry) => {
          const write = (entry['Put'] ?? entry['Update']) as Item;
          const key = (write['Item'] ?? write['Key']) as Item;
          return holds(write['ConditionExpression'], items.get(at(key)), write['ExpressionAttributeNames'], write['ExpressionAttributeValues']);
        });
        // DynamoDB applies every item or none; a cancelled transaction must debit nothing.
        if (!allowed.every(Boolean)) {
          throw Object.assign(new Error('cancelled'), {
            name: 'TransactionCanceledException',
            CancellationReasons: allowed.map((ok) => (ok ? { Code: 'None' } : { Code: 'ConditionalCheckFailed' })),
          });
        }
        writes += 1;
        for (const entry of entries) {
          if (entry['Put'] !== undefined) {
            const item = (entry['Put'] as Item)['Item'] as Item;
            items.set(at(item), { ...item });
          } else {
            const update = entry['Update'] as Item;
            const key = update['Key'] as Item;
            items.set(at(key), applyUpdate(update, items.get(at(key))));
          }
        }
        return {};
      }
      if (command instanceof UpdateCommand) {
        const key = input['Key'] as Item;
        if (!holds(input['ConditionExpression'], items.get(at(key)), input['ExpressionAttributeNames'], input['ExpressionAttributeValues'])) {
          throw Object.assign(new Error('conditional'), { name: 'ConditionalCheckFailedException' });
        }
        writes += 1;
        const next = applyUpdate(input, items.get(at(key)));
        items.set(at(key), next);
        return { Attributes: next };
      }
      if (command instanceof DeleteCommand) {
        const key = input['Key'] as Item;
        if (!holds(input['ConditionExpression'], items.get(at(key)), input['ExpressionAttributeNames'], input['ExpressionAttributeValues'])) {
          throw Object.assign(new Error('conditional'), { name: 'ConditionalCheckFailedException' });
        }
        writes += 1;
        items.delete(at(key));
        return {};
      }
      if (command instanceof GetCommand) {
        // Every pre-debit counter read must be strongly consistent or the value proves nothing.
        assert.equal(input['ConsistentRead'], true, 'counter reads must be consistent');
        const current = items.get(at(input['Key'] as Item));
        return current === undefined ? {} : { Item: current };
      }
      throw new Error('unexpected command');
    },
  };
  return {
    port, items, at,
    calls: () => calls,
    writes: () => writes,
    before: (match, hook) => { hooks.push({ match, hook, used: false }); },
  };
};

const build = (start: number = START): Readonly<{
  budget: ReturnType<typeof createPilotBudget>;
  fake: Fake;
  advance: (ms: number) => void;
  at: () => number;
}> => {
  const fake = fakeDynamo();
  let now = start;
  let sequence = 0;
  const budget = createPilotBudget('ap-southeast-1', 'rag-state', fake.port, {
    now: () => now,
    id: () => `lease-${(sequence += 1)}`,
  });
  return { budget, fake, advance: (ms: number) => { now += ms; }, at: () => now };
};

const codeOf = async (action: () => Promise<unknown>): Promise<string> => {
  try {
    await action();
    return 'NO_ERROR';
  } catch (error) {
    return error instanceof RagFailure ? error.code : 'NOT_A_RAG_FAILURE';
  }
};

/**
 * Models the caller's only legal sequence: the provider/model invocation happens when — and
 * only when — the budget admitted the work. A refused admission therefore reports 0 calls.
 */
const admit = async (action: () => Promise<unknown>): Promise<Readonly<{ code: string; providerCalls: number }>> => {
  try {
    await action();
    return { code: 'NO_ERROR', providerCalls: 1 };
  } catch (error) {
    return { code: error instanceof RagFailure ? error.code : 'NOT_A_RAG_FAILURE', providerCalls: 0 };
  }
};

const seedPilot = (fake: Fake, patch: Item): Item => {
  const row = { ...PILOT_BUDGET_KEY, ...patch };
  fake.items.set(fake.at(PILOT_BUDGET_KEY), row);
  return row;
};

test('one admission reserves the global attempt, the UTC-day attempt and the lease', async () => {
  const { budget, fake } = build();
  const lease = await budget.acquireQuery(SUB(1), 'req-1', signal());
  assert.deepEqual(lease, { actor: SUB(1), token: 'lease-1', expiresAt: START + PILOT_QUERY_LEASE_MS });
  assert.ok(Object.isFrozen(lease));
  // Two strongly consistent preflight reads (pilot counters + day counter) then one transaction.
  assert.equal(fake.calls(), 3);
  assert.deepEqual(await budget.read(signal()), {
    queryCalls: 1, jevCalls: 0, deepseekCalls: 0, cohereCalls: 0, reservedUsdMicros: 0,
  });
  const daily = fake.items.get(fake.at(dailyKey(DAY, SUB(1)))) as Item;
  const stored = fake.items.get(fake.at(leaseKey(SUB(1)))) as Item;
  assert.equal(daily['attempts'], 1);
  assert.equal(daily['ttl'], undefined);
  assert.deepEqual(
    { token: stored['token'], requestId: stored['requestId'], expiresAt: stored['expiresAt'], acquiredAt: stored['acquiredAt'] },
    { token: 'lease-1', requestId: 'req-1', expiresAt: lease.expiresAt, acquiredAt: START },
  );
  assert.equal(stored['ttl'], undefined);
  // The read above is one more consistent GET; it debits nothing.
  assert.equal(fake.calls(), 4);
});

test('one active query per account: a second device is refused and nothing is debited', async () => {
  const { budget, fake } = build();
  await budget.acquireQuery(SUB(1), 'req-1', signal());
  assert.equal(await codeOf(() => budget.acquireQuery(SUB(1), 'req-2', signal())), 'RATE_LIMITED');
  assert.equal((await budget.read(signal())).queryCalls, 1);
  assert.equal((fake.items.get(fake.at(dailyKey(DAY, SUB(1)))) as Item)['attempts'], 1);
  assert.equal((fake.items.get(fake.at(leaseKey(SUB(1)))) as Item)['token'], 'lease-1');
  // Another account is unaffected.
  assert.equal(await codeOf(() => budget.acquireQuery(SUB(2), 'req-3', signal())), 'NO_ERROR');
  assert.equal((await budget.read(signal())).queryCalls, 2);
});

test('release frees the lease for the owning token and never refunds a counter', async () => {
  const { budget, fake } = build();
  const first = await budget.acquireQuery(SUB(1), 'req-1', signal());
  await budget.release(first, signal());
  assert.equal(fake.items.has(fake.at(leaseKey(SUB(1)))), false);
  const counters = await budget.read(signal());
  assert.equal(counters.queryCalls, 1);
  assert.equal((fake.items.get(fake.at(dailyKey(DAY, SUB(1)))) as Item)['attempts'], 1);
  const second = await budget.acquireQuery(SUB(1), 'req-2', signal());
  assert.equal(second.token, 'lease-2');

  // A stale token cannot release the newer lease.
  const { budget: budget2, fake: fake2, advance } = build();
  const old = await budget2.acquireQuery(SUB(1), 'req-1', signal());
  advance(PILOT_QUERY_LEASE_MS);
  const current = await budget2.acquireQuery(SUB(1), 'req-2', signal());
  await budget2.release(old, signal());
  assert.equal((fake2.items.get(fake2.at(leaseKey(SUB(1)))) as Item)['token'], current.token);
  assert.equal(await codeOf(() => budget2.acquireQuery(SUB(1), 'req-3', signal())), 'RATE_LIMITED');
  await budget2.release(current, signal());
  assert.equal(await codeOf(() => budget2.acquireQuery(SUB(1), 'req-4', signal())), 'NO_ERROR');
  // The lease is not a counter: three admissions stay counted.
  assert.equal((await budget2.read(signal())).queryCalls, 3);
});

test('an unexpired lease refuses and an expired one may be replaced', async () => {
  const { budget, advance } = build();
  await budget.acquireQuery(SUB(1), 'req-1', signal());
  advance(PILOT_QUERY_LEASE_MS - 1);
  assert.equal(await codeOf(() => budget.acquireQuery(SUB(1), 'req-2', signal())), 'RATE_LIMITED');
  advance(1);
  assert.equal(await codeOf(() => budget.acquireQuery(SUB(1), 'req-3', signal())), 'NO_ERROR');
  assert.equal((await budget.read(signal())).queryCalls, 2);
  assert.ok(PILOT_QUERY_LEASE_MS > 26_000);
});

test('the daily cap is ten per account per UTC day and a refusal debits nothing', async () => {
  const { budget, fake } = build();
  for (let i = 0; i < PILOT_DAILY_QUERY_LIMIT; i += 1) {
    const lease = await budget.acquireQuery(SUB(1), `req-${i}`, signal());
    await budget.release(lease, signal());
  }
  const before = await budget.read(signal());
  assert.equal(before.queryCalls, 10);
  assert.equal(await codeOf(() => budget.acquireQuery(SUB(1), 'req-11', signal())), 'RATE_LIMITED');
  assert.deepEqual(await budget.read(signal()), before);
  assert.equal((fake.items.get(fake.at(dailyKey(DAY, SUB(1)))) as Item)['attempts'], 10);
  // A second account has its own daily budget.
  assert.equal(await codeOf(() => budget.acquireQuery(SUB(2), 'req-12', signal())), 'NO_ERROR');
});

test('a new UTC day has its own ten attempts and never resets the old counter', async () => {
  const { budget, fake, advance } = build(Date.parse('2026-10-12T23:00:00.000Z'));
  for (let i = 0; i < PILOT_DAILY_QUERY_LIMIT; i += 1) {
    const lease = await budget.acquireQuery(SUB(1), `req-${i}`, signal());
    await budget.release(lease, signal());
  }
  assert.equal(await codeOf(() => budget.acquireQuery(SUB(1), 'req-11', signal())), 'RATE_LIMITED');
  advance(2 * 60 * 60 * 1000);
  const next = await budget.acquireQuery(SUB(1), 'req-12', signal());
  assert.equal(next.expiresAt, Date.parse('2026-10-13T01:00:00.000Z') + PILOT_QUERY_LEASE_MS);
  assert.equal((fake.items.get(fake.at(dailyKey('2026-10-12', SUB(1)))) as Item)['attempts'], 10);
  assert.equal((fake.items.get(fake.at(dailyKey('2026-10-13', SUB(1)))) as Item)['attempts'], 1);
  assert.equal((await budget.read(signal())).queryCalls, 11);
});

test('the global cap is fifty attempts across accounts and refuses atomically', async () => {
  const { budget, fake } = build();
  for (let n = 1; n <= 5; n += 1) {
    for (let i = 0; i < PILOT_DAILY_QUERY_LIMIT; i += 1) {
      const lease = await budget.acquireQuery(SUB(n), `req-${n}-${i}`, signal());
      await budget.release(lease, signal());
    }
  }
  assert.equal((await budget.read(signal())).queryCalls, PILOT_LIMITS.query);
  assert.equal(await codeOf(() => budget.acquireQuery(SUB(6), 'req-6', signal())), 'RATE_LIMITED');
  assert.equal((await budget.read(signal())).queryCalls, PILOT_LIMITS.query);
  assert.equal(fake.items.has(fake.at(dailyKey(DAY, SUB(6)))), false);
  assert.equal(fake.items.has(fake.at(leaseKey(SUB(6)))), false);
});

test('provider reservations count every call, share one ceiling and never refund', async () => {
  const { budget, fake } = build();
  await budget.reserve('jev', 100_000, signal());
  assert.deepEqual(await budget.read(signal()), {
    queryCalls: 0, jevCalls: 1, deepseekCalls: 0, cohereCalls: 0, reservedUsdMicros: 4200,
  });
  await budget.reserve('deepseek', 10_000, signal());
  const both = await budget.read(signal());
  assert.equal(both.jevCalls, 1);
  assert.equal(both.deepseekCalls, 1);
  assert.equal(both.reservedUsdMicros, 4200 + 4229);
  await budget.reserve('jev', 0, signal());
  assert.equal((await budget.read(signal())).jevCalls, 2);
  // No refund or reset path exists; a failed call stays counted by construction.
  assert.deepEqual(Object.keys(budget).sort(), ['acquireCohere', 'acquireQuery', 'read', 'release', 'reserve']);
  // Each reservation is one consistent preflight read plus one conditional update.
  assert.equal(fake.calls(), 9);
  assert.equal(fake.writes(), 3);
});

test('the per-provider call caps refuse the extra reservation without a second write', async () => {
  const { budget, fake } = build();
  for (let i = 0; i < PILOT_LIMITS.jev; i += 1) await budget.reserve('jev', 0, signal());
  const after = fake.calls();
  const stored = fake.writes();
  assert.equal((await budget.read(signal())).jevCalls, PILOT_LIMITS.jev);
  assert.equal(await codeOf(() => budget.reserve('jev', 0, signal())), 'RATE_LIMITED');
  // The refused reservation reads, then its conditional update is refused: nothing is debited.
  assert.equal(fake.writes(), stored);
  assert.equal((await budget.read(signal())).jevCalls, PILOT_LIMITS.jev);
  assert.equal(fake.calls(), after + 4);
  for (let i = 0; i < PILOT_LIMITS.deepseek; i += 1) await budget.reserve('deepseek', 0, signal());
  assert.equal(await codeOf(() => budget.reserve('deepseek', 0, signal())), 'RATE_LIMITED');
  assert.equal((await budget.read(signal())).deepseekCalls, PILOT_LIMITS.deepseek);
});

test('the shared external ceiling refuses a reservation that would cross it', async () => {
  const { budget, fake } = build();
  await budget.reserve('deepseek', 3_300_000, signal());
  const before = await budget.read(signal());
  assert.equal(before.reservedUsdMicros, 991_229);
  const calls = fake.calls();
  const writes = fake.writes();
  assert.equal(await codeOf(() => budget.reserve('jev', 300_000, signal())), 'RATE_LIMITED');
  assert.deepEqual(await budget.read(signal()), before);
  assert.equal(fake.calls(), calls + 3);
  assert.equal(fake.writes(), writes);
  // A single reservation above the whole ceiling is refused before any write.
  const capped = fake.calls();
  assert.equal(await codeOf(() => budget.reserve('jev', 30_000_000, signal())), 'RATE_LIMITED');
  assert.equal(fake.calls(), capped);
  assert.ok(PILOT_USD_MICROS_LIMIT === 1_000_000);
});

test('Cohere admission wraps the global embedding item and the pilot counter atomically', async () => {
  const { budget, fake } = build();
  fake.items.set(fake.at(GLOBAL_EMBEDDING_KEY), { ownerId: 'BUDGET#SMOKE', noteId: 'COUNTER', used: 12 });
  await budget.acquireCohere(signal());
  assert.equal((fake.items.get(fake.at(GLOBAL_EMBEDDING_KEY)) as Item)['used'], 13);
  assert.equal((await budget.read(signal())).cohereCalls, 1);
  // The cumulative global cap of 112 is shared with the pre-pilot usage.
  fake.items.set(fake.at(GLOBAL_EMBEDDING_KEY), { ownerId: 'BUDGET#SMOKE', noteId: 'COUNTER', used: 111 });
  await budget.acquireCohere(signal());
  assert.equal((fake.items.get(fake.at(GLOBAL_EMBEDDING_KEY)) as Item)['used'], GLOBAL_EMBEDDING_LIMIT);
  assert.equal(await codeOf(() => budget.acquireCohere(signal())), 'RATE_LIMITED');
  assert.equal((fake.items.get(fake.at(GLOBAL_EMBEDDING_KEY)) as Item)['used'], GLOBAL_EMBEDDING_LIMIT);
  assert.equal((await budget.read(signal())).cohereCalls, 2);
});

test('the pilot Cohere cap refuses the hundred-and-first invocation', async () => {
  const { budget, fake } = build();
  for (let i = 0; i < PILOT_LIMITS.cohere; i += 1) await budget.acquireCohere(signal());
  assert.equal((await budget.read(signal())).cohereCalls, PILOT_LIMITS.cohere);
  assert.equal((fake.items.get(fake.at(GLOBAL_EMBEDDING_KEY)) as Item)['used'], PILOT_LIMITS.cohere);
  const calls = fake.calls();
  const writes = fake.writes();
  assert.equal(await codeOf(() => budget.acquireCohere(signal())), 'RATE_LIMITED');
  // Two consistent preflight reads followed by a refused transaction; no debit.
  assert.equal(fake.calls(), calls + 3);
  assert.equal(fake.writes(), writes);
  assert.equal((await budget.read(signal())).cohereCalls, PILOT_LIMITS.cohere);
});

test('a corrupt pilot counter refuses every admission before any debit', async () => {
  for (const name of COUNTERS) {
    for (const [label, value] of CORRUPT_VALUES) {
      const scenario = `${name} ${label}`;
      const { budget, fake } = build();
      const seeded = seedPilot(fake, { [name]: value });
      const io = signal();
      assert.equal(await codeOf(() => budget.read(io)), 'PROVIDER_UNAVAILABLE', `${scenario} (read)`);
      assert.deepEqual(await admit(() => budget.acquireQuery(SUB(1), 'req-1', io)), { code: 'PROVIDER_UNAVAILABLE', providerCalls: 0 }, scenario);
      assert.deepEqual(await admit(() => budget.reserve('jev', 100_000, io)), { code: 'PROVIDER_UNAVAILABLE', providerCalls: 0 }, scenario);
      assert.deepEqual(await admit(() => budget.acquireCohere(io)), { code: 'PROVIDER_UNAVAILABLE', providerCalls: 0 }, scenario);
      // The corrupt row is neither repaired nor debited, and no sibling row was created.
      assert.deepEqual(fake.items.get(fake.at(PILOT_BUDGET_KEY)), seeded, `${scenario} (row untouched)`);
      assert.equal(fake.writes(), 0, `${scenario} (no write)`);
      assert.equal(fake.items.has(fake.at(dailyKey(DAY, SUB(1)))), false, scenario);
      assert.equal(fake.items.has(fake.at(leaseKey(SUB(1)))), false, scenario);
      assert.equal(fake.items.has(fake.at(GLOBAL_EMBEDDING_KEY)), false, scenario);
    }
  }
});

test('a null counter is corruption, while a missing attribute is zero', async () => {
  const { budget, fake } = build();
  seedPilot(fake, { reservedUsdMicros: null });
  assert.equal(await codeOf(() => budget.read(signal())), 'PROVIDER_UNAVAILABLE');
  assert.deepEqual(await admit(() => budget.reserve('deepseek', 1_000, signal())), {
    code: 'PROVIDER_UNAVAILABLE', providerCalls: 0,
  });

  const fresh = build();
  // Only the two key attributes exist: every missing counter is 0, so admission proceeds.
  seedPilot(fresh.fake, {});
  assert.deepEqual(await fresh.budget.read(signal()), {
    queryCalls: 0, jevCalls: 0, deepseekCalls: 0, cohereCalls: 0, reservedUsdMicros: 0,
  });
  assert.equal(await codeOf(() => fresh.budget.acquireQuery(SUB(1), 'req-1', signal())), 'NO_ERROR');

  // The same holds for the reused global item: a missing `used` is 0, not corruption.
  const global = build();
  global.fake.items.set(global.fake.at(GLOBAL_EMBEDDING_KEY), { ...GLOBAL_EMBEDDING_KEY });
  assert.equal(await codeOf(() => global.budget.acquireCohere(signal())), 'NO_ERROR');
  assert.equal((global.fake.items.get(global.fake.at(GLOBAL_EMBEDDING_KEY)) as Item)['used'], 1);
  assert.equal((await global.budget.read(signal())).cohereCalls, 1);
});

test('a corrupt UTC-day or global embedding counter refuses only its own admission', async () => {
  for (const value of [-1, 1.5, null, '3']) {
    const { budget, fake } = build();
    const seeded = { ownerId: PILOT_BUDGET_KEY.ownerId, noteId: `DAILY#${DAY}#${SUB(1)}`, attempts: value };
    fake.items.set(fake.at(dailyKey(DAY, SUB(1))), { ...seeded });
    assert.deepEqual(await admit(() => budget.acquireQuery(SUB(1), 'req-1', signal())), {
      code: 'PROVIDER_UNAVAILABLE', providerCalls: 0,
    }, `day ${String(value)}`);
    assert.equal(fake.writes(), 0, 'no partial debit');
    assert.equal(fake.items.has(fake.at(PILOT_BUDGET_KEY)), false, 'global query counter untouched');
    assert.equal(fake.items.has(fake.at(leaseKey(SUB(1)))), false, 'no lease');
    assert.deepEqual(fake.items.get(fake.at(dailyKey(DAY, SUB(1)))), seeded);
  }
  for (const value of [-1, 2.5, null, '12']) {
    const { budget, fake } = build();
    const seeded = { ...GLOBAL_EMBEDDING_KEY, used: value };
    fake.items.set(fake.at(GLOBAL_EMBEDDING_KEY), { ...seeded });
    assert.deepEqual(await admit(() => budget.acquireCohere(signal())), {
      code: 'PROVIDER_UNAVAILABLE', providerCalls: 0,
    }, `global ${String(value)}`);
    assert.equal(fake.writes(), 0, 'no partial debit');
    assert.equal(fake.items.has(fake.at(PILOT_BUDGET_KEY)), false, 'pilot counters untouched');
    assert.deepEqual(fake.items.get(fake.at(GLOBAL_EMBEDDING_KEY)), seeded);
  }
});

test('a counter row whose key attributes do not match the requested item is refused', async () => {
  const { budget, fake } = build();
  const foreign = { ownerId: 'BUDGET#PHASE4', noteId: 'COUNTER', queryCalls: 3 };
  fake.items.set(fake.at(PILOT_BUDGET_KEY), { ...foreign });
  assert.equal(await codeOf(() => budget.read(signal())), 'PROVIDER_UNAVAILABLE');
  assert.equal((await admit(() => budget.acquireQuery(SUB(1), 'req-1', signal()))).providerCalls, 0);
  assert.equal((await admit(() => budget.reserve('jev', 1_000, signal()))).code, 'PROVIDER_UNAVAILABLE');
  assert.equal(fake.writes(), 0);
  assert.deepEqual(fake.items.get(fake.at(PILOT_BUDGET_KEY)), foreign, 'foreign row never adopted');

  const other = { ownerId: GLOBAL_EMBEDDING_KEY.ownerId, noteId: 'OTHER', used: 1 };
  fake.items.set(fake.at(GLOBAL_EMBEDDING_KEY), { ...other });
  assert.equal((await admit(() => budget.acquireCohere(signal()))).code, 'PROVIDER_UNAVAILABLE');
  assert.equal(fake.writes(), 0);
  assert.deepEqual(fake.items.get(fake.at(GLOBAL_EMBEDDING_KEY)), other);
});

test('a counter that moves between the preflight read and the write is refused, never double-debited', async () => {
  // The global query counter is raised by a concurrent admission after this one read it.
  const global = build();
  global.fake.before((command) => command instanceof TransactWriteCommand, () => {
    seedPilot(global.fake, { queryCalls: 1 });
  });
  assert.deepEqual(await admit(() => global.budget.acquireQuery(SUB(1), 'req-1', signal())), {
    code: 'RATE_LIMITED', providerCalls: 0,
  });
  assert.equal((global.fake.items.get(global.fake.at(PILOT_BUDGET_KEY)) as Item)['queryCalls'], 1, 'only the concurrent debit');
  assert.equal(global.fake.items.has(global.fake.at(dailyKey(DAY, SUB(1)))), false, 'no partial day debit');
  assert.equal(global.fake.items.has(global.fake.at(leaseKey(SUB(1)))), false, 'no partial lease');

  // The UTC-day counter is raised instead: the whole transaction must still cancel.
  const day = build();
  day.fake.before((command) => command instanceof TransactWriteCommand, () => {
    day.fake.items.set(day.fake.at(dailyKey(DAY, SUB(1))), { ...dailyKey(DAY, SUB(1)), attempts: 1 });
  });
  assert.equal(await codeOf(() => day.budget.acquireQuery(SUB(1), 'req-1', signal())), 'RATE_LIMITED');
  assert.equal(day.fake.items.has(day.fake.at(PILOT_BUDGET_KEY)), false, 'no global debit');
  assert.equal(day.fake.items.has(day.fake.at(leaseKey(SUB(1)))), false, 'no lease');
  assert.equal((day.fake.items.get(day.fake.at(dailyKey(DAY, SUB(1)))) as Item)['attempts'], 1, 'concurrent day debit kept');

  // A provider reservation whose counters move between the read and the update is refused too.
  const provider = build();
  provider.fake.before((command) => command instanceof UpdateCommand, () => {
    seedPilot(provider.fake, { jevCalls: 1, reservedUsdMicros: 5 });
  });
  assert.deepEqual(await admit(() => provider.budget.reserve('jev', 100_000, signal())), {
    code: 'RATE_LIMITED', providerCalls: 0,
  });
  const moved = provider.fake.items.get(provider.fake.at(PILOT_BUDGET_KEY)) as Item;
  assert.deepEqual({ jevCalls: moved['jevCalls'], reservedUsdMicros: moved['reservedUsdMicros'] }, { jevCalls: 1, reservedUsdMicros: 5 });

  // The global embedding counter moves before the Cohere transaction: nothing is debited.
  const cohere = build();
  cohere.fake.before((command) => command instanceof TransactWriteCommand, () => {
    cohere.fake.items.set(cohere.fake.at(GLOBAL_EMBEDDING_KEY), { ...GLOBAL_EMBEDDING_KEY, used: 12 });
  });
  assert.deepEqual(await admit(() => cohere.budget.acquireCohere(signal())), {
    code: 'RATE_LIMITED', providerCalls: 0,
  });
  assert.equal(cohere.fake.items.has(cohere.fake.at(PILOT_BUDGET_KEY)), false, 'no pilot debit');
});

test('a provider-call counter captured above zero is not recreated after deletion', async () => {
  const { budget, fake } = build();
  seedPilot(fake, { jevCalls: 5, reservedUsdMicros: 0 });
  const key = fake.at(PILOT_BUDGET_KEY);
  // The consistent read captured five calls; the attribute is gone before the conditional update.
  fake.before((command) => command instanceof UpdateCommand, (_command, items) => {
    delete (items.get(key) as Item)['jevCalls'];
  });
  assert.deepEqual(await admit(() => budget.reserve('jev', 0, signal())), {
    code: 'RATE_LIMITED', providerCalls: 0,
  });
  assert.equal(fake.writes(), 0, 'a lost counter admits nothing');
  const row = fake.items.get(key) as Item;
  assert.equal(row['jevCalls'], undefined, 'the five recorded calls are not restarted at 1');
  assert.equal(row['reservedUsdMicros'], 0);
});

test('a shared USD counter captured above zero is not recreated after deletion', async () => {
  const { budget, fake } = build();
  seedPilot(fake, { jevCalls: 0, reservedUsdMicros: 5_000 });
  const key = fake.at(PILOT_BUDGET_KEY);
  fake.before((command) => command instanceof UpdateCommand, (_command, items) => {
    delete (items.get(key) as Item)['reservedUsdMicros'];
  });
  assert.deepEqual(await admit(() => budget.reserve('jev', 100_000, signal())), {
    code: 'RATE_LIMITED', providerCalls: 0,
  });
  assert.equal(fake.writes(), 0, 'a lost counter admits nothing');
  const row = fake.items.get(key) as Item;
  assert.equal(row['reservedUsdMicros'], undefined, 'the 5000 reserved micros are not restarted at 0');
  assert.equal(row['jevCalls'], 0);
});

test('a global query counter row captured above zero is not recreated after deletion', async () => {
  const { budget, fake } = build();
  seedPilot(fake, { queryCalls: 7, reservedUsdMicros: 0 });
  const key = fake.at(PILOT_BUDGET_KEY);
  fake.before((command) => command instanceof TransactWriteCommand, (_command, items) => {
    items.delete(key);
  });
  assert.deepEqual(await admit(() => budget.acquireQuery(SUB(1), 'req-1', signal())), {
    code: 'RATE_LIMITED', providerCalls: 0,
  });
  assert.equal(fake.writes(), 0, 'a lost counter admits nothing');
  assert.equal(fake.items.has(key), false, 'the counter row is not recreated at 1');
  assert.equal(fake.items.has(fake.at(dailyKey(DAY, SUB(1)))), false, 'no partial day debit');
  assert.equal(fake.items.has(fake.at(leaseKey(SUB(1)))), false, 'no partial lease');
});

test('a query counter attribute captured above zero is not recreated after deletion', async () => {
  const { budget, fake } = build();
  seedPilot(fake, { queryCalls: 7, reservedUsdMicros: 0 });
  const key = fake.at(PILOT_BUDGET_KEY);
  fake.before((command) => command instanceof TransactWriteCommand, (_command, items) => {
    delete (items.get(key) as Item)['queryCalls'];
  });
  assert.deepEqual(await admit(() => budget.acquireQuery(SUB(1), 'req-1', signal())), {
    code: 'RATE_LIMITED', providerCalls: 0,
  });
  assert.equal(fake.writes(), 0, 'a lost counter admits nothing');
  const row = fake.items.get(key) as Item;
  assert.equal(row['queryCalls'], undefined, 'the seven recorded attempts are not restarted at 1');
  assert.equal(row['reservedUsdMicros'], 0, 'the sibling counter is untouched');
  assert.equal(fake.items.has(fake.at(leaseKey(SUB(1)))), false, 'no partial lease');
});

test('a UTC-day counter captured above zero is not recreated after deletion', async () => {
  const { budget, fake } = build();
  const key = fake.at(dailyKey(DAY, SUB(1)));
  fake.items.set(key, { ...dailyKey(DAY, SUB(1)), attempts: 6 });
  fake.before((command) => command instanceof TransactWriteCommand, (_command, items) => {
    items.delete(key);
  });
  assert.deepEqual(await admit(() => budget.acquireQuery(SUB(1), 'req-1', signal())), {
    code: 'RATE_LIMITED', providerCalls: 0,
  });
  assert.equal(fake.writes(), 0, 'a lost counter admits nothing');
  assert.equal(fake.items.has(key), false, 'the day counter is not restarted at 1');
  assert.equal(fake.items.has(fake.at(PILOT_BUDGET_KEY)), false, 'no global debit');
  assert.equal(fake.items.has(fake.at(leaseKey(SUB(1)))), false, 'no partial lease');
});

test('a pilot Cohere counter captured above zero is not recreated after deletion', async () => {
  const { budget, fake } = build();
  seedPilot(fake, { cohereCalls: 30 });
  const key = fake.at(PILOT_BUDGET_KEY);
  fake.before((command) => command instanceof TransactWriteCommand, (_command, items) => {
    delete (items.get(key) as Item)['cohereCalls'];
  });
  assert.deepEqual(await admit(() => budget.acquireCohere(signal())), {
    code: 'RATE_LIMITED', providerCalls: 0,
  });
  assert.equal(fake.writes(), 0, 'a lost counter admits nothing');
  assert.equal(fake.items.has(fake.at(GLOBAL_EMBEDDING_KEY)), false, 'no global embedding debit');
  assert.equal((fake.items.get(key) as Item)['cohereCalls'], undefined, 'the thirty invocations are not restarted at 1');
});

test('a global embedding counter captured above zero is not recreated after deletion', async () => {
  const { budget, fake } = build();
  const key = fake.at(GLOBAL_EMBEDDING_KEY);
  fake.items.set(key, { ...GLOBAL_EMBEDDING_KEY, used: 12 });
  fake.before((command) => command instanceof TransactWriteCommand, (_command, items) => {
    items.delete(key);
  });
  assert.deepEqual(await admit(() => budget.acquireCohere(signal())), {
    code: 'RATE_LIMITED', providerCalls: 0,
  });
  assert.equal(fake.writes(), 0, 'a lost counter admits nothing');
  assert.equal(fake.items.has(key), false, 'the twelve used embeddings are not restarted at 1');
  assert.equal(fake.items.has(fake.at(PILOT_BUDGET_KEY)), false, 'no pilot Cohere debit');
});

test('absence is still creatable when the consistent read captured zero', async () => {
  // The contrast to the test above: with no counter recorded yet, captured 0 keeps the absence
  // branch, so the first debit creates the attribute — and each row/attribute combination that
  // the store newly creates still starts at exactly 1 (or its reservation), never at 0.
  const query = build();
  seedPilot(query.fake, {});
  assert.equal(await codeOf(() => query.budget.acquireQuery(SUB(1), 'req-1', signal())), 'NO_ERROR');
  assert.deepEqual(await query.budget.read(signal()), {
    queryCalls: 1, jevCalls: 0, deepseekCalls: 0, cohereCalls: 0, reservedUsdMicros: 0,
  });
  assert.equal((query.fake.items.get(query.fake.at(dailyKey(DAY, SUB(1)))) as Item)['attempts'], 1);

  const reserve = build();
  seedPilot(reserve.fake, {});
  assert.equal(await codeOf(() => reserve.budget.reserve('jev', 100_000, signal())), 'NO_ERROR');
  assert.deepEqual(await reserve.budget.read(signal()), {
    queryCalls: 0, jevCalls: 1, deepseekCalls: 0, cohereCalls: 0, reservedUsdMicros: 4200,
  });

  // The reused global embedding item with only its key attributes: a missing `used` is 0.
  const cohere = build();
  cohere.fake.items.set(cohere.fake.at(GLOBAL_EMBEDDING_KEY), { ...GLOBAL_EMBEDDING_KEY });
  assert.equal(await codeOf(() => cohere.budget.acquireCohere(signal())), 'NO_ERROR');
  assert.equal((cohere.fake.items.get(cohere.fake.at(GLOBAL_EMBEDDING_KEY)) as Item)['used'], 1);
  assert.equal((await cohere.budget.read(signal())).cohereCalls, 1);
});

test('concurrent workers on one account stay bounded and every debit is accounted', async () => {
  const { budget, fake } = build();
  const io = signal();
  const burst = await Promise.allSettled([
    budget.acquireQuery(SUB(1), 'req-a', io),
    budget.acquireQuery(SUB(1), 'req-b', io),
    budget.acquireQuery(SUB(1), 'req-c', io),
  ]);
  const winners = burst.filter((result) => result.status === 'fulfilled');
  // One in-flight lease per account: the losers are refused, never half-debited.
  assert.equal(winners.length, 1);
  for (const result of burst) {
    if (result.status === 'rejected') {
      assert.ok(result.reason instanceof RagFailure && result.reason.code === 'RATE_LIMITED');
    }
  }
  const first = await budget.read(io);
  assert.equal(first.queryCalls, 1);
  assert.equal((fake.items.get(fake.at(dailyKey(DAY, SUB(1)))) as Item)['attempts'], 1);

  // A second burst while the lease is held admits nothing at all.
  const held = await Promise.allSettled([
    budget.acquireQuery(SUB(1), 'req-d', io),
    budget.acquireQuery(SUB(1), 'req-e', io),
  ]);
  assert.equal(held.filter((result) => result.status === 'fulfilled').length, 0);
  assert.deepEqual(await budget.read(io), first);

  // Two other accounts may both be admitted; the global counter equals the number admitted.
  const others = await Promise.allSettled([
    budget.acquireQuery(SUB(2), 'req-f', io),
    budget.acquireQuery(SUB(3), 'req-g', io),
  ]);
  const admitted = others.filter((result) => result.status === 'fulfilled').length;
  const total = await budget.read(io);
  // No lost or duplicated debit: the global counter is exactly the number of admissions.
  assert.equal(total.queryCalls, 1 + admitted);
  assert.ok(total.queryCalls <= PILOT_LIMITS.query);
  const raced = [SUB(2), SUB(3)];
  for (let index = 0; index < raced.length; index += 1) {
    const row = fake.items.get(fake.at(dailyKey(DAY, raced[index] as string))) as Item | undefined;
    assert.equal(row?.['attempts'], others[index]?.status === 'fulfilled' ? 1 : undefined, `day counter for ${raced[index]}`);
  }
});

test('a corrupt lease row refuses admission without debiting or being replaced', async () => {
  const corrupt: ReadonlyArray<readonly [string, Item]> = [
    ['expiresAt is a string', { token: 'lease-9', requestId: 'req-9', expiresAt: '2026-10-12T09:00:00.000Z', acquiredAt: START }],
    ['expiresAt is negative', { token: 'lease-9', requestId: 'req-9', expiresAt: -1, acquiredAt: START }],
    ['expiresAt is null', { token: 'lease-9', requestId: 'req-9', expiresAt: null, acquiredAt: START }],
    ['expiresAt is missing', { token: 'lease-9', requestId: 'req-9', acquiredAt: START }],
  ];
  for (const [label, lease] of corrupt) {
    const { budget, fake } = build();
    const stored = { ...leaseKey(SUB(1)), ...lease };
    fake.items.set(fake.at(leaseKey(SUB(1))), { ...stored });
    assert.deepEqual(await admit(() => budget.acquireQuery(SUB(1), 'req-1', signal())), {
      code: 'RATE_LIMITED', providerCalls: 0,
    }, label);
    assert.equal(fake.items.has(fake.at(PILOT_BUDGET_KEY)), false, `${label} (no debit)`);
    assert.deepEqual(fake.items.get(fake.at(leaseKey(SUB(1)))), stored, `${label} (lease untouched)`);
  }
});

test('the Phase 5 keys never collide with the Phase 4 or global budget items', () => {
  assert.deepEqual({ ...PILOT_BUDGET_KEY }, { ownerId: 'BUDGET#PHASE5', noteId: 'COUNTER' });
  assert.notEqual(PILOT_BUDGET_KEY.ownerId, BUDGET_OWNER_KEY);
  assert.notEqual(PILOT_BUDGET_KEY.ownerId, 'BUDGET#PHASE4');
  assert.deepEqual({ ...GLOBAL_EMBEDDING_KEY }, { ownerId: BUDGET_OWNER_KEY, noteId: BUDGET_SORT_KEY });
  assert.deepEqual({ ...PILOT_LIMITS }, { query: 50, jev: 60, deepseek: 40, cohere: 100 });
  assert.equal(PILOT_DAILY_QUERY_LIMIT, 10);
  assert.equal(GLOBAL_EMBEDDING_LIMIT, 112);
  assert.equal(PILOT_USD_MICROS_LIMIT, 1_000_000);
});

test('invalid providers, bounds, identities and clocks are refused before any call', async () => {
  const { budget, fake } = build();
  assert.equal(await codeOf(() => budget.reserve('query' as never, 1, signal())), 'LIVE_POLICY_NOT_CONFIGURED');
  assert.equal(await codeOf(() => budget.reserve('cohere' as never, 1, signal())), 'LIVE_POLICY_NOT_CONFIGURED');
  assert.equal(await codeOf(() => budget.reserve('bogus' as never, 1, signal())), 'LIVE_POLICY_NOT_CONFIGURED');
  assert.equal(await codeOf(() => budget.reserve('jev', -1, signal())), 'LIVE_POLICY_NOT_CONFIGURED');
  assert.equal(await codeOf(() => budget.reserve('jev', Number.NaN, signal())), 'LIVE_POLICY_NOT_CONFIGURED');
  assert.equal(await codeOf(() => budget.reserve('jev', 1.5, signal())), 'LIVE_POLICY_NOT_CONFIGURED');
  assert.equal(await codeOf(() => budget.reserve('jev', '10' as unknown as number, signal())), 'LIVE_POLICY_NOT_CONFIGURED');
  assert.equal(await codeOf(() => budget.acquireQuery('actor-a', 'req-1', signal())), 'INVALID_INPUT');
  assert.equal(await codeOf(() => budget.acquireQuery(LETTERS.toUpperCase(), 'req-1', signal())), 'INVALID_INPUT');
  assert.equal(await codeOf(() => budget.acquireQuery(SUB(1), '', signal())), 'INVALID_INPUT');
  assert.equal(await codeOf(() => budget.acquireQuery(SUB(1), 'x'.repeat(129), signal())), 'INVALID_INPUT');
  assert.equal(await codeOf(() => budget.acquireQuery(SUB(1), 'req-1', 'signal' as unknown as AbortSignal)), 'INVALID_INPUT');
  assert.equal(await codeOf(() => budget.acquireQuery(SUB(1), 'req-1', aborted())), 'TIMEOUT');
  assert.equal(await codeOf(() => budget.release(null as unknown as QueryLease, signal())), 'INVALID_INPUT');
  assert.equal(await codeOf(() => budget.release({} as QueryLease, signal())), 'INVALID_INPUT');
  assert.equal(await codeOf(() => budget.release({ ...leaseOf(SUB(1), 'lease-1'), actor: 'actor-a' }, signal())), 'INVALID_INPUT');
  assert.equal(await codeOf(() => budget.release({ ...leaseOf(SUB(1), 'lease-1'), token: ' ' }, signal())), 'INVALID_INPUT');
  assert.equal(await codeOf(() => budget.release({ ...leaseOf(SUB(1), 'lease-1'), expiresAt: -1 }, signal())), 'INVALID_INPUT');
  assert.equal(await codeOf(() => budget.read(aborted())), 'TIMEOUT');
  assert.equal(await codeOf(() => budget.reserve('jev', 1, aborted())), 'TIMEOUT');
  assert.equal(await codeOf(() => budget.acquireCohere(aborted())), 'TIMEOUT');
  assert.equal(fake.calls(), 0);

  const badClock = createPilotBudget('ap-southeast-1', 'rag-state', fake.port, { now: () => Number.NaN });
  assert.equal(await codeOf(() => badClock.acquireQuery(SUB(1), 'req-1', signal())), 'LIVE_POLICY_NOT_CONFIGURED');
  const negativeClock = createPilotBudget('ap-southeast-1', 'rag-state', fake.port, { now: () => -1 });
  assert.equal(await codeOf(() => negativeClock.acquireQuery(SUB(1), 'req-1', signal())), 'LIVE_POLICY_NOT_CONFIGURED');
  const futureClock = createPilotBudget('ap-southeast-1', 'rag-state', fake.port, { now: () => 4_102_444_800_001 });
  assert.equal(await codeOf(() => futureClock.acquireQuery(SUB(1), 'req-1', signal())), 'LIVE_POLICY_NOT_CONFIGURED');
  const badId = createPilotBudget('ap-southeast-1', 'rag-state', fake.port, { id: () => ' ' });
  assert.equal(await codeOf(() => badId.acquireQuery(SUB(1), 'req-1', signal())), 'LIVE_POLICY_NOT_CONFIGURED');
  assert.equal(fake.calls(), 0);
});

test('the factory refuses a bad region, table or options object', () => {
  const { port } = fakeDynamo();
  const refused = (action: () => unknown): boolean => {
    try {
      action();
      return false;
    } catch (error) {
      return error instanceof RagFailure && error.code === 'LIVE_POLICY_NOT_CONFIGURED';
    }
  };
  assert.ok(refused(() => createPilotBudget('southeast-1', 'rag-state')));
  assert.ok(refused(() => createPilotBudget('ap-southeast-1', '')));
  assert.ok(refused(() => createPilotBudget('ap-southeast-1', 'rag-state', undefined, { now: 'clock' } as never)));
  assert.ok(refused(() => createPilotBudget('ap-southeast-1', 'rag-state', undefined, 'options' as never)));
  assert.ok(refused(() => createPilotBudget('ap-southeast-1', 'rag-state', { send: 7 } as never)));
  // The default document client is built with no call; no request is made here.
  assert.doesNotThrow(() => createPilotBudget('ap-southeast-1', 'rag-state', port));
});

test('transport, throttle and non-condition cancellation are distinct outcomes', async () => {
  const failing: PilotBudgetPort = { async send() { throw new Error('socket'); } };
  const failingBudget = createPilotBudget('ap-southeast-1', 'rag-state', failing, { now: () => START });
  assert.equal(await codeOf(() => failingBudget.acquireQuery(SUB(1), 'req-1', signal())), 'PROVIDER_UNAVAILABLE');
  assert.equal(await codeOf(() => failingBudget.reserve('jev', 1, signal())), 'PROVIDER_UNAVAILABLE');
  assert.equal(await codeOf(() => failingBudget.acquireCohere(signal())), 'PROVIDER_UNAVAILABLE');

  const throttled: PilotBudgetPort = {
    async send() { throw Object.assign(new Error('slow'), { name: 'ThrottlingException' }); },
  };
  const throttledBudget = createPilotBudget('ap-southeast-1', 'rag-state', throttled, { now: () => START });
  assert.equal(await codeOf(() => throttledBudget.acquireQuery(SUB(1), 'req-1', signal())), 'RATE_LIMITED');

  const conflicted: PilotBudgetPort = {
    async send() {
      throw Object.assign(new Error('conflict'), {
        name: 'TransactionCanceledException',
        CancellationReasons: [{ Code: 'TransactionConflict' }],
      });
    },
  };
  const conflictBudget = createPilotBudget('ap-southeast-1', 'rag-state', conflicted, { now: () => START });
  assert.equal(await codeOf(() => conflictBudget.acquireQuery(SUB(1), 'req-1', signal())), 'PROVIDER_UNAVAILABLE');

  const { budget, fake } = build();
  for (const value of [-1, 1.5, null, '1']) {
    seedPilot(fake, { queryCalls: value });
    assert.equal(await codeOf(() => budget.read(signal())), 'PROVIDER_UNAVAILABLE', String(value));
  }
  assert.equal(fake.writes(), 0);
});

function aborted(): AbortSignal {
  const controller = new AbortController();
  controller.abort();
  return controller.signal;
}

function leaseOf(actor: string, token: string): QueryLease {
  return { actor, token, expiresAt: START + PILOT_QUERY_LEASE_MS };
}
