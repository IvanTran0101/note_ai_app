/**
 * Phase 5 pilot budget (plan 5.1D + D2): the bounded, server-side quota for the pilot, kept in
 * the existing RAG state table under `BUDGET#PHASE5`/`COUNTER`. Phase 4 counters
 * (`BUDGET#PHASE4`, `BUDGET#SMOKE`) are never read, reset or reused.
 *
 * One atomic `TransactWriteCommand` admits one query attempt: the global attempt counter, the
 * per-account UTC-day counter and the per-account in-flight lease move together or not at all,
 * so a refused admission never debits a counter and never leaves half a lease. Counters include
 * failed calls, are never refunded, and no path deletes or resets a counter item: the ~28s lease
 * only stops a second device from running two queries at once. `release` deletes the lease item,
 * never a counter, and only when the supplied token is still the stored one. Production budget
 * state is monotonic: this module exposes no reset API. The one operator exception is an explicit,
 * audited CAS of TODAY's per-account daily attempts performed outside this module after a deploy.
 *
 * Every admission first reads the counter rows it is about to debit with a strongly consistent
 * `GetCommand` and refuses a row whose present counters are not nonnegative safe integers
 * (missing attribute is 0; `null`, negative, fractional or non-numeric is corruption). The write
 * that follows compares the captured values, so a row that was corrupt all along, or moved
 * between the read and the write, refuses atomically and no counter is debited or repaired.
 * Absence is creatable only for a counter the read captured at 0: a counter captured above 0 must
 * still be present at exactly that value, so a counter row or attribute deleted between the read
 * and the write refuses instead of restarting at 1 and losing the usage already recorded.
 *
 * `acquireEmbedding` wraps the existing global embedding item with the pilot self-hosted counter
 * in a single transaction, so the root replaces `IndexStore.reserveEmbedding` with one call before
 * every embedding attempt (successful or failed). The historical `cohereCalls` stays untouched and
 * the deprecated `acquireCohere` only exists for legacy callers/tests: both embedding paths share
 * one pilot allowance, `cohereCalls + selfHostedEmbeddingCalls <= 5,000`, while the legacy Cohere
 * target is itself capped at 100 and the self-hosted target at 5,000. The same cumulative global
 * cap of 5,012 (12 already used at plan time + 5,000 pilot) is checked in that one transaction. The
 * per-provider JEV/DeepSeek caps are 1,000 each and share one 1,000,000-micros reservation ceiling.
 * No path refunds, resets or deletes a counter. A reset of recorded usage/history is never a
 * runtime behavior: the only exception is the explicit operator-run, audited CAS of TODAY's daily
 * attempts after a deploy, and even that exception repairs no other counter and refunds no spend.
 */
import { randomUUID } from 'node:crypto';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import {
  DynamoDBDocumentClient, DeleteCommand, GetCommand, TransactWriteCommand, UpdateCommand,
} from '@aws-sdk/lib-dynamodb';
import { isSafeInteger } from '../chunking';
import { isValidIdentifier } from '../contract';
import { RagFailure } from '../types';
import { isCognitoSub } from './pilot_policy';

/** Phase 5 quota, separate from the Phase 4 item; `query` is admitted only by `acquireQuery`. */
export const PILOT_BUDGET_KEY = Object.freeze({ ownerId: 'BUDGET#PHASE5', noteId: 'COUNTER' });
export const PILOT_LIMITS = Object.freeze({ query: 1000, jev: 1000, deepseek: 1000, cohere: 100 });
/** One shared pilot embedding allowance for the historical Cohere calls plus the new local ones. */
export const PILOT_EMBEDDING_LIMIT = 5000;
/**
 * Per-account UTC-day demo cap: 100 admitted query attempts. Operator-approved higher demo quota,
 * not a new monetary budget. The runtime never resets a counter; the only reset exception is an
 * explicit operator-run, audited CAS of TODAY's daily attempts after a deploy (outside this
 * module). Normal operation never refunds or erases recorded attempts.
 */
export const PILOT_DAILY_QUERY_LIMIT = 100;
/** Longer than the 26s request deadline and the 28s Lambda timeout it guards. */
export const PILOT_QUERY_LEASE_MS = 28_000;
/** One shared external ceiling for JEV + DeepSeek reservations, in USD micros. */
export const PILOT_USD_MICROS_LIMIT = 1_000_000;
/** Existing global embedding item (mirrors indexing/store.ts BUDGET_OWNER_KEY/BUDGET_SORT_KEY). */
export const GLOBAL_EMBEDDING_KEY = Object.freeze({ ownerId: 'BUDGET#SMOKE', noteId: 'COUNTER' });
/** Cumulative global embedding cap: 12 used at plan time + 5,000 pilot, never a runtime reset. */
export const GLOBAL_EMBEDDING_LIMIT = 5012;

export type PilotProvider = 'jev' | 'deepseek';
export type QueryLease = Readonly<{ actor: string; token: string; expiresAt: number }>;
export type PilotBudgetCounters = Readonly<{
  queryCalls: number;
  jevCalls: number;
  deepseekCalls: number;
  cohereCalls: number;
  selfHostedEmbeddingCalls: number;
  reservedUsdMicros: number;
}>;

export type PilotSendOptions = Readonly<{ abortSignal?: AbortSignal }>;
export type PilotCommand = GetCommand | UpdateCommand | DeleteCommand | TransactWriteCommand;
/** The one SDK capability this budget needs; a `DynamoDBDocumentClient` satisfies it. */
export interface PilotBudgetPort {
  send(command: PilotCommand, options?: PilotSendOptions): Promise<unknown>;
}
export type PilotBudget = Readonly<{
  reserve(provider: PilotProvider, inputUpperBound: number, signal: AbortSignal): Promise<void>;
  acquireQuery(actor: string, requestId: string, signal: AbortSignal): Promise<QueryLease>;
  release(lease: QueryLease, signal: AbortSignal): Promise<void>;
  /** Active embedding admission: one atomic debit of the self-hosted + shared global counters. */
  acquireEmbedding(signal: AbortSignal): Promise<void>;
  /** Deprecated legacy Cohere admission, isolated for existing callers/tests; never the active path. */
  acquireCohere(signal: AbortSignal): Promise<void>;
  read(signal: AbortSignal): Promise<PilotBudgetCounters>;
}>;
/** Test seams only: a bounded clock and the lease/table id factory. */
export type PilotBudgetOptions = Readonly<{ now?: () => number; id?: () => string }>;

const AWS_REGION = /^[a-z]{2}-[a-z]+-\d$/;
const COUNTER_NAMES = [
  'queryCalls', 'jevCalls', 'deepseekCalls', 'cohereCalls', 'selfHostedEmbeddingCalls', 'reservedUsdMicros',
] as const;
/** The one counter on the per-account UTC-day item and on the existing global embedding item. */
const DAILY_COUNTER = 'attempts';
const GLOBAL_COUNTER = 'used';
/** 2100-01-01: a bounded clock keeps every lease expiry and UTC-day key well formed. */
const MAX_CLOCK_MS = 4_102_444_800_000;
const TIMEOUT_ERRORS = new Set(['AbortError', 'TimeoutError', 'RequestTimeout', 'RequestAbortedError']);
const THROTTLE_ERRORS = new Set(['ThrottlingException', 'ProvisionedThroughputExceededException', 'RequestLimitExceeded']);

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const errorNameOf = (error: unknown): string =>
  isRecord(error) && typeof error['name'] === 'string' ? error['name'] : '';

const requireSignal = (signal: unknown): AbortSignal => {
  if (!(signal instanceof AbortSignal)) throw new RagFailure('INVALID_INPUT');
  if (signal.aborted) throw new RagFailure('TIMEOUT');
  return signal;
};

/** The pilot identity is a Cognito `sub`; the UUID shape is what makes each composite key unique. */
const requireActor = (actor: unknown): string => {
  if (!isCognitoSub(actor)) throw new RagFailure('INVALID_INPUT');
  return actor;
};

/** DynamoDB reports which transaction item refused; only a pure condition refusal is a quota loss. */
const cancellationCodes = (error: unknown): string[] => {
  const reasons = isRecord(error) ? error['CancellationReasons'] : undefined;
  if (!Array.isArray(reasons)) return [];
  const codes: string[] = [];
  for (const reason of reasons) {
    if (!isRecord(reason)) continue;
    const code = reason['Code'];
    if (typeof code === 'string' && code !== 'None') codes.push(code);
  }
  return codes;
};

/** USD micros: the same official peak/cache-miss rates the Phase 4 budget uses; usage is separate. */
const microsOf = (provider: PilotProvider, inputUpperBound: number): number =>
  provider === 'jev' ? Math.ceil(inputUpperBound * .042) : Math.ceil(inputUpperBound * .3 + 1024 * 1.2);

const dailyKey = (day: string, actor: string): Readonly<{ ownerId: string; noteId: string }> => ({
  ownerId: PILOT_BUDGET_KEY.ownerId,
  noteId: `DAILY#${day}#${actor}`,
});
const leaseKey = (actor: string): Readonly<{ ownerId: string; noteId: string }> => ({
  ownerId: PILOT_BUDGET_KEY.ownerId,
  noteId: `LEASE#${actor}`,
});

/**
 * The compare-and-set clause for one counter attribute, against the value the preflight read
 * captured. A missing attribute reads as 0, so absence is admitted only when the read captured 0
 * — the initial creation. A counter captured above 0 must still be present at exactly that value,
 * so a counter row or attribute deleted between the consistent read and the write refuses instead
 * of being recreated at 1 and losing the usage already recorded. The lower bound and the
 * exclusive (`< :limit`) or inclusive (`<= :remaining`, the shared USD ceiling) upper bound are
 * unchanged. The clause is fully parenthesised so clauses can be joined with AND.
 */
const counterCas = (
  attribute: string,
  captured: number,
  capturedValue: string,
  bound: string,
  boundInclusive = false,
): string => {
  const matches =
    `${attribute} = ${capturedValue} AND ${attribute} >= :zero AND ` +
    `${attribute} ${boundInclusive ? '<=' : '<'} ${bound}`;
  return captured === 0 ? `(attribute_not_exists(${attribute}) OR (${matches}))` : `(${matches})`;
};

/**
 * The compare-and-set clause for the sibling embedding counter, which must not move between the
 * consistent read and the one transaction: an absent attribute is admitted only when the read
 * captured 0, otherwise its exact captured value is required. Both branches reference
 * `capturedValue`, so the one transaction's `ExpressionAttributeValues` never carries a value the
 * expression does not use: DynamoDB rejects such a request with a ValidationException before it
 * evaluates any condition.
 */
const siblingCas = (attribute: string, captured: number, capturedValue: string): string =>
  captured === 0
    ? `(attribute_not_exists(${attribute}) OR ${attribute} = ${capturedValue})`
    : `${attribute} = ${capturedValue}`;

/**
 * Builds the budget over the existing RAG state table. The default client is a document client
 * with retries disabled (`maxAttempts: 1`): an admitted call is never silently repeated.
 */
export function createPilotBudget(
  region: string,
  table: string,
  supplied?: PilotBudgetPort,
  options?: PilotBudgetOptions,
): PilotBudget {
  if (typeof region !== 'string' || !AWS_REGION.test(region) || typeof table !== 'string' || table.length === 0) {
    throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
  const rawOptions: unknown = options;
  if (rawOptions !== undefined && !isRecord(rawOptions)) throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  const nowOption = isRecord(rawOptions) ? rawOptions['now'] : undefined;
  const idOption = isRecord(rawOptions) ? rawOptions['id'] : undefined;
  if (nowOption !== undefined && typeof nowOption !== 'function') throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  if (idOption !== undefined && typeof idOption !== 'function') throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  const clock = (nowOption as (() => number) | undefined) ?? Date.now;
  const nextId = (idOption as (() => string) | undefined) ?? (() => randomUUID());

  const client: PilotBudgetPort = supplied ?? DynamoDBDocumentClient.from(new DynamoDBClient({ region, maxAttempts: 1 }));
  if (typeof client.send !== 'function') throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');

  const send = async (command: PilotCommand, signal: AbortSignal): Promise<unknown> => {
    try {
      return await client.send(command, { abortSignal: signal });
    } catch (error) {
      if (signal.aborted) throw new RagFailure('TIMEOUT');
      const name = errorNameOf(error);
      if (name === 'ConditionalCheckFailedException') throw new RagFailure('RATE_LIMITED');
      if (name === 'TransactionCanceledException') {
        const codes = cancellationCodes(error);
        if (codes.length > 0 && codes.every((code) => code === 'ConditionalCheckFailed')) {
          throw new RagFailure('RATE_LIMITED');
        }
      }
      if (THROTTLE_ERRORS.has(name)) throw new RagFailure('RATE_LIMITED');
      if (TIMEOUT_ERRORS.has(name)) throw new RagFailure('TIMEOUT');
      throw new RagFailure('PROVIDER_UNAVAILABLE');
    }
  };

  const nowMs = (): number => {
    const value = clock();
    if (!isSafeInteger(value) || value < 0 || value > MAX_CLOCK_MS) throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
    return value;
  };

  /**
   * One strongly consistent read of a counter row before any debit. A missing attribute is 0;
   * a present counter that is `null`, negative, fractional, non-finite or not a number is
   * corruption, which refuses as PROVIDER_UNAVAILABLE instead of being coerced, debited or
   * repaired. A row whose key attributes do not match the requested item is equally unreadable.
   */
  const readCounters = async (
    key: Readonly<{ ownerId: string; noteId: string }>,
    names: readonly string[],
    signal: AbortSignal,
  ): Promise<Readonly<Record<string, number>>> => {
    const output = await send(new GetCommand({ TableName: table, Key: key, ConsistentRead: true }), signal);
    if (!isRecord(output)) throw new RagFailure('PROVIDER_UNAVAILABLE');
    const item = output['Item'];
    if (item !== undefined && (!isRecord(item) ||
        item['ownerId'] !== key.ownerId || item['noteId'] !== key.noteId)) {
      throw new RagFailure('PROVIDER_UNAVAILABLE');
    }
    const counters: Record<string, number> = {};
    for (const name of names) {
      const value = isRecord(item) ? item[name] : undefined;
      if (value === undefined) {
        counters[name] = 0;
        continue;
      }
      if (!isSafeInteger(value) || value < 0) throw new RagFailure('PROVIDER_UNAVAILABLE');
      counters[name] = value;
    }
    return counters;
  };

  /**
   * One atomic embedding admission: the shared global item plus exactly one pilot counter. The
   * combined pilot allowance is checked against the consistently read pair; the transaction then
   * CASes both the target counter and its unchanged sibling, so two concurrent admissions can
   * never cross the shared 5,000. The target's own bound differs by target: the historical Cohere
   * counter keeps the 100 legacy cap while the active self-hosted counter may use the full 5,000.
   */
  const reserveEmbeddingCall = async (
    target: 'cohereCalls' | 'selfHostedEmbeddingCalls',
    signal: AbortSignal,
  ): Promise<void> => {
    const deadline = requireSignal(signal);
    const global = await readCounters(GLOBAL_EMBEDDING_KEY, [GLOBAL_COUNTER], deadline);
    const pilot = await readCounters(PILOT_BUDGET_KEY, COUNTER_NAMES, deadline);
    const cohere = pilot['cohereCalls'] ?? 0;
    const local = pilot['selfHostedEmbeddingCalls'] ?? 0;
    // Both counters are captured below, so this preflight is exact only if neither moves; the
    // transaction's sibling CAS enforces that and refuses without a debit.
    if (cohere + local >= PILOT_EMBEDDING_LIMIT) throw new RagFailure('RATE_LIMITED');
    const captured = target === 'cohereCalls' ? cohere : local;
    const targetLimit = target === 'cohereCalls' ? PILOT_LIMITS.cohere : PILOT_EMBEDDING_LIMIT;
    const siblingName = target === 'cohereCalls' ? 'selfHostedEmbeddingCalls' : 'cohereCalls';
    const sibling = target === 'cohereCalls' ? local : cohere;
    await send(new TransactWriteCommand({ TransactItems: [
      { Update: {
        TableName: table,
        Key: GLOBAL_EMBEDDING_KEY,
        UpdateExpression: 'ADD used :one',
        ConditionExpression: counterCas('used', global[GLOBAL_COUNTER] ?? 0, ':capturedUsed', ':limit'),
        ExpressionAttributeValues: {
          ':one': 1, ':limit': GLOBAL_EMBEDDING_LIMIT, ':zero': 0,
          ':capturedUsed': global[GLOBAL_COUNTER] ?? 0,
        },
      } },
      { Update: {
        TableName: table,
        Key: PILOT_BUDGET_KEY,
        UpdateExpression: `ADD ${target} :one`,
        ConditionExpression:
          `${counterCas(target, captured, ':capturedTarget', ':targetLimit')} AND ` +
          siblingCas(siblingName, sibling, ':capturedSibling'),
        ExpressionAttributeValues: {
          ':one': 1, ':targetLimit': targetLimit, ':zero': 0,
          ':capturedTarget': captured, ':capturedSibling': sibling,
        },
      } },
    ] }), deadline);
  };

  return Object.freeze({
    async reserve(provider: PilotProvider, inputUpperBound: number, signal: AbortSignal): Promise<void> {
      const deadline = requireSignal(signal);
      if ((provider !== 'jev' && provider !== 'deepseek') ||
          !isSafeInteger(inputUpperBound) || inputUpperBound < 0) {
        throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
      }
      const micros = microsOf(provider, inputUpperBound);
      if (micros > PILOT_USD_MICROS_LIMIT) throw new RagFailure('RATE_LIMITED');
      // Validate and capture every counter before the debit; the update below is the CAS.
      const pilot = await readCounters(PILOT_BUDGET_KEY, COUNTER_NAMES, deadline);
      await send(new UpdateCommand({
        TableName: table,
        Key: PILOT_BUDGET_KEY,
        UpdateExpression: 'SET #calls = if_not_exists(#calls, :zero) + :one, #usd = if_not_exists(#usd, :zero) + :cost',
        // Absence is creatable only for a counter captured at 0; a counter already used must still
        // be present at the captured value and stay in bounds.
        ConditionExpression:
          `${counterCas('#calls', pilot[`${provider}Calls`] ?? 0, ':capturedCalls', ':limit')} AND ` +
          `${counterCas('#usd', pilot['reservedUsdMicros'] ?? 0, ':capturedUsd', ':remaining', true)}`,
        ExpressionAttributeNames: { '#calls': `${provider}Calls`, '#usd': 'reservedUsdMicros' },
        ExpressionAttributeValues: {
          ':zero': 0, ':one': 1, ':limit': PILOT_LIMITS[provider],
          ':cost': micros, ':remaining': PILOT_USD_MICROS_LIMIT - micros,
          ':capturedCalls': pilot[`${provider}Calls`] ?? 0, ':capturedUsd': pilot['reservedUsdMicros'] ?? 0,
        },
      }), deadline);
    },

    async acquireQuery(actor: string, requestId: string, signal: AbortSignal): Promise<QueryLease> {
      const deadline = requireSignal(signal);
      const owner = requireActor(actor);
      if (!isValidIdentifier(requestId)) throw new RagFailure('INVALID_INPUT');
      const now = nowMs();
      const token = nextId();
      if (!isValidIdentifier(token)) throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
      const expiresAt = now + PILOT_QUERY_LEASE_MS;
      const day = new Date(now).toISOString().slice(0, 10);
      // Both counter rows are validated and captured before the one admission transaction.
      const pilot = await readCounters(PILOT_BUDGET_KEY, COUNTER_NAMES, deadline);
      const daily = await readCounters(dailyKey(day, owner), [DAILY_COUNTER], deadline);
      await send(new TransactWriteCommand({
        TransactItems: [
          { Update: {
            TableName: table,
            Key: PILOT_BUDGET_KEY,
            UpdateExpression: 'ADD queryCalls :one',
            ConditionExpression: counterCas('queryCalls', pilot['queryCalls'] ?? 0, ':capturedQuery', ':limit'),
            ExpressionAttributeValues: {
              ':one': 1, ':limit': PILOT_LIMITS.query, ':zero': 0, ':capturedQuery': pilot['queryCalls'] ?? 0,
            },
          } },
          { Update: {
            TableName: table,
            Key: dailyKey(day, owner),
            UpdateExpression: 'ADD attempts :one',
            ConditionExpression: counterCas('attempts', daily[DAILY_COUNTER] ?? 0, ':capturedAttempts', ':limit'),
            ExpressionAttributeValues: {
              ':one': 1, ':limit': PILOT_DAILY_QUERY_LIMIT, ':zero': 0,
              ':capturedAttempts': daily[DAILY_COUNTER] ?? 0,
            },
          } },
          { Put: {
            TableName: table,
            // A lease Put carries its key inside the item; the key must never expire by TTL.
            Item: { ...leaseKey(owner), token, requestId, expiresAt, acquiredAt: now },
            // An unexpired lease held by any device refuses; an expired, well-formed one may be
            // replaced. A lease whose `expiresAt` is missing or not a number fails the comparison
            // too, so a corrupt lease is never silently overwritten and never debits a counter.
            ConditionExpression:
              'attribute_not_exists(noteId) OR ' +
              '(attribute_exists(expiresAt) AND expiresAt >= :zero AND expiresAt <= :now)',
            ExpressionAttributeValues: { ':now': now, ':zero': 0 },
          } },
        ],
      }), deadline);
      return Object.freeze({ actor: owner, token, expiresAt });
    },

    /** Deletes the lease item only, and only while the stored token is still this lease's. */
    async release(lease: QueryLease, signal: AbortSignal): Promise<void> {
      const deadline = requireSignal(signal);
      const actor = isRecord(lease) ? lease['actor'] : undefined;
      const token = isRecord(lease) ? lease['token'] : undefined;
      if (!isCognitoSub(actor) || !isValidIdentifier(token) ||
          !isSafeInteger(lease['expiresAt']) || lease['expiresAt'] < 0) {
        throw new RagFailure('INVALID_INPUT');
      }
      try {
        await client.send(new DeleteCommand({
          TableName: table,
          Key: leaseKey(actor),
          ConditionExpression: '#token = :token',
          ExpressionAttributeNames: { '#token': 'token' },
          ExpressionAttributeValues: { ':token': token },
        }), { abortSignal: deadline });
      } catch (error) {
        if (deadline.aborted) throw new RagFailure('TIMEOUT');
        // A replaced, expired or already released lease is not an error and is never refunded.
        if (errorNameOf(error) === 'ConditionalCheckFailedException') return;
        throw new RagFailure('PROVIDER_UNAVAILABLE');
      }
    },

    /** Active embedding admission: one atomic self-hosted + shared global debit. */
    async acquireEmbedding(signal: AbortSignal): Promise<void> {
      await reserveEmbeddingCall('selfHostedEmbeddingCalls', signal);
    },

    /**
     * Deprecated legacy Cohere admission, kept only for existing callers/tests. It shares the
     * same pilot + global allowance, keeps its own 100 target cap and leaves
     * `selfHostedEmbeddingCalls` untouched.
     */
    async acquireCohere(signal: AbortSignal): Promise<void> {
      await reserveEmbeddingCall('cohereCalls', signal);
    },

    async read(signal: AbortSignal): Promise<PilotBudgetCounters> {
      const deadline = requireSignal(signal);
      const counters = await readCounters(PILOT_BUDGET_KEY, COUNTER_NAMES, deadline);
      return Object.freeze({ ...counters }) as unknown as PilotBudgetCounters;
    },
  });
}
