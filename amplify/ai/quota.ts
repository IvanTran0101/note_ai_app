import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, UpdateCommand } from '@aws-sdk/lib-dynamodb';

import { SummaryFailure, type QuotaDecision } from './summary_contract';

/**
 * Per-account minute quota for `POST /ai/summary` (contract section 5: "10 stage
 * requests/phút/account"; direct, section, and merge all count).
 *
 * One DynamoDB item per account per UTC minute:
 *
 * ```text
 * accountWindow = "<sub>#<epochMinute>"   { count, expiresAt }
 * ```
 *
 * `consume` is a single conditional `UpdateItem` - `ADD count :one` guarded by
 * `attribute_not_exists(count) OR count < :limit` - so the counter is atomic:
 * there is no read-then-write window, no lost increment, and no interleaving in
 * which two concurrent requests both pass the check that should refuse one. The
 * first update creates the item with `count = 1`, the tenth succeeds with
 * `count = 10`, and the eleventh fails its condition - a refusal, not an error.
 *
 * The window is a fixed UTC minute derived from epoch arithmetic, so no
 * timezone or calendar state is involved. `expiresAt` (epoch seconds, the start
 * of the next window) is only DynamoDB TTL cleanup: the next minute is a
 * different key, so correctness never waits for the row to disappear. A write
 * delayed past the TTL deletes it recreates the old window with `count = 1`,
 * which is harmless because that key is never read again.
 *
 * `RETRY-AFTER` is derived from the same arithmetic and bounded to 1..60
 * seconds, matching the response header the contract allows.
 *
 * Boundary burst: this is a FIXED window, not a sliding one, so a client can
 * spend 10 in the last millisecond of one minute and 10 in the first
 * millisecond of the next - up to 20 generations around a boundary. That is
 * accepted for the contract's limit. If the burst ever matters, the upgrade is
 * a sliding window (two adjacent rows with a weighted sum), never a
 * read-then-write counter, a reset, or a longer TTL.
 *
 * Fail closed: only `ConditionalCheckFailedException` becomes a quota refusal.
 * Every other failure - throttling, IAM, a missing table, an invalid clock -
 * throws `SummaryFailure('unexpected')`, which the handler answers as 500
 * without calling the provider. The raw SDK error never enters the message, so
 * an account id, key, or table detail cannot leak into a response or a log.
 */

/** Contract limit: 10 stage requests per account per minute. */
const MAX_REQUESTS_PER_WINDOW = 10;

/** One fixed window. A UTC minute is exactly 60_000 epoch milliseconds. */
const WINDOW_MS = 60_000;

/** DynamoDB TTL attribute in epoch seconds; `infrastructure.ts` declares it. */
const EXPIRES_AT_ATTRIBUTE = 'expiresAt';

/** `count` is a DynamoDB reserved word, so the update names it explicitly. */
const COUNT_ATTRIBUTE = 'count';

/** The one SDK error that means "this account is at its limit". */
const CONDITIONAL_CHECK_FAILED = 'ConditionalCheckFailedException';

/** Seconds in one window; the upper bound of a legal `Retry-After`. */
const MAX_RETRY_AFTER_SECONDS = WINDOW_MS / 1000;

export type DynamoSummaryQuotaOptions = Readonly<{
  /** The quota table from `createSummaryInfrastructure`. */
  tableName: string;
  /** Injection seam: a warmer path or a test can supply its own document client. */
  documentClient?: DynamoDBDocumentClient;
}>;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

/** SDK errors carry their type on `name`, so a duplicated SDK copy still matches. */
const errorNameOf = (error: unknown): string =>
  isRecord(error) && typeof error.name === 'string' ? error.name : 'UnknownError';

/** `nowMs` is the handler's clock; a non-time value is a wiring fault, not a request. */
const isClockReading = (value: unknown): value is number =>
  typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;

const windowStartMsOf = (nowMs: number): number => nowMs - (nowMs % WINDOW_MS);

/**
 * One account/minute row key. The last `#` is the separator and the minute is a
 * bare integer, so the decomposition is unique whatever the subject contains:
 * two accounts cannot share a row, and one account gets a fresh row per minute.
 */
const accountWindowOf = (accountId: string, windowStartMs: number): string =>
  `${accountId}#${windowStartMs / WINDOW_MS}`;

/** Seconds until the next window, bounded to the 1..60 the header may carry. */
const retryAfterSecondsOf = (nowMs: number, windowStartMs: number): number =>
  Math.min(
    Math.max(Math.ceil((windowStartMs + WINDOW_MS - nowMs) / 1000), 1),
    MAX_RETRY_AFTER_SECONDS,
  );

export class DynamoSummaryQuota {
  private readonly tableName: string;
  private readonly documentClient: DynamoDBDocumentClient;

  constructor(options: DynamoSummaryQuotaOptions) {
    if (typeof options?.tableName !== 'string' || options.tableName.length === 0) {
      throw new SummaryFailure('unexpected', 'The quota store was created without a table name.');
    }
    this.tableName = options.tableName;
    // maxAttempts 1: a retried throttle could double-count against the account,
    // and a retry cannot turn the condition's refusal into an allowance. Any
    // error reaches the handler, which fails closed.
    this.documentClient =
      options.documentClient ??
      DynamoDBDocumentClient.from(new DynamoDBClient({ maxAttempts: 1 }), {
        marshallOptions: { removeUndefinedValues: true },
      });
  }

  async consume(accountId: string, nowMs: number): Promise<QuotaDecision> {
    if (typeof accountId !== 'string' || accountId.trim().length === 0) {
      throw new SummaryFailure('unexpected', 'The quota check has no account.');
    }
    if (!isClockReading(nowMs)) {
      throw new SummaryFailure('unexpected', 'The quota clock is invalid.');
    }
    const windowStartMs = windowStartMsOf(nowMs);

    try {
      await this.documentClient.send(
        new UpdateCommand({
          TableName: this.tableName,
          Key: { accountWindow: accountWindowOf(accountId, windowStartMs) },
          UpdateExpression: `SET ${EXPIRES_AT_ATTRIBUTE} = :expiresAt ADD #count :one`,
          ConditionExpression: 'attribute_not_exists(#count) OR #count < :limit',
          ExpressionAttributeNames: { '#count': COUNT_ATTRIBUTE },
          ExpressionAttributeValues: {
            ':expiresAt': (windowStartMs + WINDOW_MS) / 1000,
            ':one': 1,
            ':limit': MAX_REQUESTS_PER_WINDOW,
          },
        }),
        { abortSignal: AbortSignal.timeout(4000) },
      );
      return { allowed: true };
    } catch (error) {
      if (errorNameOf(error) === CONDITIONAL_CHECK_FAILED) {
        return { allowed: false, retryAfterSeconds: retryAfterSecondsOf(nowMs, windowStartMs) };
      }
      // Generic on purpose: SDK errors can carry key and table details.
      throw new SummaryFailure('unexpected', 'The quota check failed.');
    }
  }
}
