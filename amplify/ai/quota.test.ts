/**
 * Focused checks for the per-account minute quota in `quota.ts`.
 *
 * The injected document client is an in-memory table that applies the same
 * conditional atomic increment the DynamoDB service would, including yielding
 * before each update so concurrent callers interleave the way they would over
 * the network. No AWS call, no network, no credential or provider key.
 *
 * Run with `npx tsx amplify/ai/quota.test.ts` after the staged files are copied
 * into the project, where the SDK dependencies resolve.
 */
import { UpdateCommand, type DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';

import { DynamoSummaryQuota } from './quota';
import { SummaryFailure, type QuotaDecision } from './summary_contract';

/** Test-side copies of the module's public contract, asserted not assumed. */
const LIMIT = 10;
const WINDOW_MS = 60_000;
const CONDITIONAL_CHECK_FAILED = 'ConditionalCheckFailedException';

type StoredRow = { count: number; expiresAt: number; };

let passed = 0;

const check = async (name: string, run: () => Promise<void>): Promise<void> => {
  try {
    await run();
    passed += 1;
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
};

const assertEqual = <T>(actual: T, expected: T, label: string): void => {
  if (actual !== expected) {
    throw new Error(`${label}: expected ${String(expected)}, got ${String(actual)}`);
  }
};

const assertTrue = (value: boolean, label: string): void => {
  if (!value) {
    throw new Error(`${label}: expected true`);
  }
};

const windowKeyOf = (accountId: string, nowMs: number): string =>
  `${accountId}#${Math.floor(nowMs / WINDOW_MS)}`;

const conditionalCheckFailed = (): Error => {
  const error = new Error('The conditional request failed');
  error.name = CONDITIONAL_CHECK_FAILED;
  return error;
};

const namedError = (name: string, message: string): Error => {
  const error = new Error(message);
  error.name = name;
  return error;
};

/**
 * Fails a design guard loudly. `quota.ts` deliberately hides raw errors behind
 * its safe failure, so print the reason here or the diagnosis is lost. The
 * assertion signature also narrows the inspected command in the caller.
 */
type DesignGuard = (holds: boolean, message: string) => asserts holds;

const designGuard: DesignGuard = (holds, message) => {
  if (!holds) {
    console.error(`quota design guard failed: ${message}`);
    throw new Error(message);
  }
};

/**
 * In-memory stand-in for the quota table. It records every command so a test
 * can prove the quota is one conditional increment rather than a read-then-write
 * pair, and it refuses exactly what the real condition refuses.
 */
class FakeQuotaTable {
  readonly rows = new Map<string, StoredRow>();
  readonly commands: string[] = [];
  failWith: Error | undefined;

  async send(command: unknown, options?: { abortSignal?: AbortSignal; }): Promise<unknown> {
    designGuard(options?.abortSignal instanceof AbortSignal, "quota SDK request has abort signal");
    // `instanceof`, not the constructor name: a bundler may rename the class.
    this.commands.push(command instanceof UpdateCommand ? 'UpdateCommand' : 'other');
    // Interleave concurrent callers up to this point; the compare-and-increment
    // below is synchronous, which is the atomicity DynamoDB's condition gives.
    await Promise.resolve();

    if (this.failWith !== undefined) {
      const error = this.failWith;
      this.failWith = undefined;
      throw error;
    }
    designGuard(
      command instanceof UpdateCommand,
      'the quota must use one conditional update, not another command',
    );

    const input = command.input;
    const update = input.UpdateExpression ?? '';
    const condition = input.ConditionExpression ?? '';
    const values = input.ExpressionAttributeValues ?? {};
    // Guard the design, not just the behavior: the counter must be an atomic
    // ADD under a bound-checked condition with the TTL stamped in the same call.
    designGuard(update.includes('SET expiresAt = :expiresAt'), 'expiresAt is set with the update');
    designGuard(update.includes('ADD #count :one'), 'the counter is incremented by ADD');
    designGuard(condition.includes('attribute_not_exists(#count)'), 'a new window starts at one');
    designGuard(condition.includes('#count < :limit'), 'the condition bounds the counter');

    const key = String(input.Key?.accountWindow);
    const limit = Number(values[':limit']);
    const row = this.rows.get(key);
    if (row !== undefined && row.count >= limit) {
      throw conditionalCheckFailed();
    }
    this.rows.set(key, {
      count: (row?.count ?? 0) + 1,
      expiresAt: Number(values[':expiresAt']),
    });
    return {};
  }
}

const quotaWith = (table: FakeQuotaTable): DynamoSummaryQuota =>
  new DynamoSummaryQuota({
    tableName: 'summary-quota',
    documentClient: table as unknown as DynamoDBDocumentClient,
  });

const consumeTimes = async (
  quota: DynamoSummaryQuota,
  accountId: string,
  nowMs: number,
  times: number,
): Promise<QuotaDecision[]> => {
  const decisions: QuotaDecision[] = [];
  for (let index = 0; index < times; index += 1) {
    decisions.push(await quota.consume(accountId, nowMs));
  }
  return decisions;
};

const failureOf = async (run: () => Promise<unknown>): Promise<SummaryFailure> => {
  try {
    await run();
  } catch (error) {
    if (error instanceof SummaryFailure) {
      return error;
    }
    throw error;
  }
  throw new Error('expected the call to fail closed with a SummaryFailure');
};

const main = async (): Promise<void> => {
  const minute = Date.UTC(2026, 0, 1, 0, 0, 0);

  await check('ten requests pass, the eleventh is refused, and one row holds the count', async () => {
    const table = new FakeQuotaTable();
    const quota = quotaWith(table);
    const nowMs = minute + 30_000;

    const decisions = await consumeTimes(quota, 'account-a', nowMs, LIMIT);
    assertTrue(decisions.every((decision) => decision.allowed), 'the first ten are allowed');

    const refused = await quota.consume('account-a', nowMs);
    assertEqual(refused.allowed, false, 'the eleventh is refused');
    if (!refused.allowed) {
      assertEqual(refused.retryAfterSeconds, 30, 'seconds left in the window');
    }

    assertEqual(table.rows.size, 1, 'one account/minute row');
    const row = table.rows.get(windowKeyOf('account-a', nowMs));
    assertEqual(row?.count, LIMIT, 'the counter stops at the limit');
    assertEqual(row?.expiresAt, (minute + WINDOW_MS) / 1000, 'TTL points at the next window');
    assertEqual(table.commands.length, LIMIT + 1, 'one update per consume');
    assertTrue(
      table.commands.every((name) => name === 'UpdateCommand'),
      'no read-then-write or reset command was used',
    );
  });

  await check('concurrent consumption admits exactly ten of twenty', async () => {
    const table = new FakeQuotaTable();
    const quota = quotaWith(table);
    const nowMs = minute + 5 * 60_000;

    const results = await Promise.all(
      Array.from({ length: LIMIT * 2 }, () => quota.consume('account-b', nowMs)),
    );
    const allowed = results.filter((decision) => decision.allowed);
    const refused = results.filter((decision) => !decision.allowed);

    assertEqual(allowed.length, LIMIT, 'allowed requests');
    assertEqual(refused.length, LIMIT, 'refused requests');
    assertTrue(
      refused.every(
        (decision) =>
          !decision.allowed &&
          decision.retryAfterSeconds >= 1 &&
          decision.retryAfterSeconds <= 60,
      ),
      'every refusal carries 1..60 seconds',
    );
    assertEqual(table.rows.get(windowKeyOf('account-b', nowMs))?.count, LIMIT, 'no lost increment');
  });

  await check('accounts and windows stay isolated', async () => {
    const table = new FakeQuotaTable();
    const quota = quotaWith(table);
    const nowMs = minute + 10 * 60_000;

    await consumeTimes(quota, 'account-a', nowMs, LIMIT);
    assertEqual((await quota.consume('account-a', nowMs)).allowed, false, 'account-a is at its limit');
    assertEqual((await quota.consume('account-b', nowMs)).allowed, true, 'account-b is unaffected');
    assertEqual(
      (await quota.consume('account-a', nowMs + WINDOW_MS)).allowed,
      true,
      'the next minute is a fresh window',
    );

    assertEqual(table.rows.size, 3, 'a, b, and a-next-minute rows');
    assertEqual(
      table.rows.get(windowKeyOf('account-a', nowMs))?.count,
      LIMIT,
      'the finished window is not reset',
    );
    assertEqual(table.rows.get(windowKeyOf('account-a', nowMs + WINDOW_MS))?.count, 1, 'new window starts at one');
  });

  await check('the window rolls over exactly at the UTC minute boundary', async () => {
    const table = new FakeQuotaTable();
    const quota = quotaWith(table);
    const boundary = minute + 20 * 60_000;
    const lastMs = boundary - 1;

    await consumeTimes(quota, 'account-c', lastMs, LIMIT);
    const refusedBefore = await quota.consume('account-c', lastMs);
    assertEqual(refusedBefore.allowed, false, 'refused before the boundary');
    if (!refusedBefore.allowed) {
      assertEqual(refusedBefore.retryAfterSeconds, 1, 'one millisecond to the next window');
    }

    const spans = await consumeTimes(quota, 'account-c', boundary, LIMIT);
    assertTrue(spans.every((decision) => decision.allowed), 'the boundary opens a new window');
    const refusedAfter = await quota.consume('account-c', boundary);
    assertEqual(refusedAfter.allowed, false, 'refused after the boundary too');
    if (!refusedAfter.allowed) {
      assertEqual(refusedAfter.retryAfterSeconds, 60, 'a full window remains');
    }
    assertTrue(
      windowKeyOf('account-c', lastMs) !== windowKeyOf('account-c', boundary),
      'the two instants are different rows',
    );
  });

  await check('Retry-After is the ceil of the remaining window, bounded to 1..60', async () => {
    const table = new FakeQuotaTable();
    const quota = quotaWith(table);

    const offsets = [0, 1, 999, 1000, 59_999];
    for (const offset of offsets) {
      const nowMs = minute + 40 * 60_000 + offset;
      const account = `account-offset-${offset}`;
      await consumeTimes(quota, account, nowMs, LIMIT);
      const refused = await quota.consume(account, nowMs);
      assertEqual(refused.allowed, false, `refused at offset ${offset}`);
      if (!refused.allowed) {
        assertEqual(
          refused.retryAfterSeconds,
          Math.ceil((WINDOW_MS - offset) / 1000),
          `seconds left at offset ${offset}`,
        );
        assertTrue(
          refused.retryAfterSeconds >= 1 && refused.retryAfterSeconds <= 60,
          `bounded at offset ${offset}`,
        );
      }
    }
  });

  await check('a storage failure fails closed and no SDK detail leaks', async () => {
    const table = new FakeQuotaTable();
    const quota = quotaWith(table);
    const nowMs = minute + 50 * 60_000;

    table.failWith = namedError(
      'ThrottlingException',
      'Rate exceeded for account-a#41 on table summary-quota',
    );
    const throttled = await failureOf(() => quota.consume('account-a', nowMs));
    assertEqual(throttled.code, 'unexpected', 'throttling is not a refusal');
    assertTrue(!throttled.message.includes('ThrottlingException'), 'no SDK error name in the message');
    assertTrue(!throttled.message.includes('account-a'), 'no account id in the message');
    assertTrue(!throttled.message.includes('summary-quota'), 'no table name in the message');

    table.failWith = namedError('ValidationException', 'Invalid UpdateExpression on summary-quota');
    const validation = await failureOf(() => quota.consume('account-a', nowMs));
    assertEqual(validation.code, 'unexpected', 'a validation error is not a refusal either');
    assertEqual(table.rows.size, 0, 'a failed update stores nothing');
  });

  await check('the SDK quota attempt is aborted below the handler deadline', async () => {
    const originalTimeout = AbortSignal.timeout;
    let requestedMs = 0;
    AbortSignal.timeout = (ms: number) => {
      requestedMs = ms;
      const controller = new AbortController();
      setTimeout(() => controller.abort(), 5);
      return controller.signal;
    };
    try {
      const client = { send: async (_command: unknown, options?: { abortSignal?: AbortSignal }) =>
        await new Promise((_resolve, reject) => {
          if (!options?.abortSignal) return reject(new Error('Abort signal missing'));
          options.abortSignal.addEventListener('abort', () => reject(namedError('AbortError', 'synthetic abort')), { once: true });
        }) } as unknown as DynamoDBDocumentClient;
      const failure = await failureOf(() => new DynamoSummaryQuota({ tableName: 'quota', documentClient: client }).consume('account-a', minute));
      assertEqual(requestedMs, 4000, 'SDK deadline below handler 5000ms');
      assertEqual(failure.code, 'unexpected', 'abort fails closed');
    } finally {
      AbortSignal.timeout = originalTimeout;
    }
  });

  await check('invalid wiring fails closed before any storage call', async () => {
    const missingTable = await failureOf(() => Promise.resolve(new DynamoSummaryQuota({ tableName: '' })));
    assertEqual(missingTable.code, 'unexpected', 'a store without a table name is refused');

    const table = new FakeQuotaTable();
    const quota = quotaWith(table);
    const blankAccount = await failureOf(() => quota.consume('   ', minute));
    assertEqual(blankAccount.code, 'unexpected', 'a blank account is refused');
    const badClock = await failureOf(() => quota.consume('account-a', Number.NaN));
    assertEqual(badClock.code, 'unexpected', 'a non-time clock is refused');
    assertEqual(table.commands.length, 0, 'no request reached the table');
  });
};

main().then(() => console.log(`${passed} DynamoSummaryQuota checks passed`));
