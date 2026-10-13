/**
 * Phase 5.1 canonical RAG consent store (plan 5.1C).
 *
 * One row per verified actor: `{ownerId: 'OWNER#<sub>', noteId: 'RAG#CONSENT'}`, the same
 * canonical partition the indexing store reads. Every read is strongly consistent; the only
 * write is one conditional `UpdateCommand` that compares the grant captured by that read —
 * `accepted`, `version` and `generation` — so a stale writer can never overwrite a newer grant
 * and a whole note is never rewritten. The absence branch is allowed only for
 * `expectedGeneration: 0`, so a row deleted after the read conflicts instead of being recreated.
 * There is no TTL and no delete path: consent is revoked by writing `accepted:false`, which keeps
 * the generation monotonic for in-flight runs.
 *
 * Absence is the default grant `{accepted:false, version:'rag-consent.v1', generation:0}`.
 * A foreign projection, a row carrying a TTL, a key mismatch or any malformed field fails
 * closed as SOURCE_CHANGED: the caller must not act on, or write through, state it cannot read.
 */
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import {
  DynamoDBDocumentClient, GetCommand, TransactWriteCommand, UpdateCommand,
} from '@aws-sdk/lib-dynamodb';
import { CONSENT_VERSION, isValidIdentifier } from '../contract';
import { isSafeInteger, isWellFormed } from '../chunking';
import { CONSENT_SORT_KEY, OWNER_KEY_PREFIX } from '../indexing/jobs';
import { RagFailure } from '../types';

export type ConsentGrant = Readonly<{ accepted: boolean; version: string; generation: number }>;
export type ConsentWrite = Readonly<{ accepted: boolean; version: string; expectedGeneration: number }>;

export type ConsentSendOptions = Readonly<{ abortSignal?: AbortSignal }>;
export type ConsentCommand = GetCommand | UpdateCommand | TransactWriteCommand;
/** The one SDK capability this store needs; a `DynamoDBDocumentClient` satisfies it. */
export interface ConsentPort {
  send(command: ConsentCommand, options?: ConsentSendOptions): Promise<unknown>;
}
/**
 * Optional Phase 5 config guard. When supplied, every read re-validates membership against a
 * fresh config, and every write commits the consent CAS and an exact whole-config
 * `ConditionCheck` in one transaction, so a removed actor or a moved config generation can never
 * ride a stale permit. Omitting it preserves the legacy single-`UpdateCommand` behavior.
 */
export type ConsentGuard = Readonly<{
  /** The state table that holds the exact config row. */
  table: string;
  /** The `CONFIG#PHASE5`/`PILOT` item key the ConditionCheck pins. */
  key: Readonly<{ ownerId: string; noteId: string }>;
  /** The exact config value captured when membership was decided. */
  value: unknown;
  /** Fresh config + membership for this actor; throws a `RagFailure` when no longer permitted. */
  revalidate: (actor: string, signal: AbortSignal) => Promise<void>;
}>;
export type ConsentStore = Readonly<{
  read(actor: string, signal: AbortSignal): Promise<ConsentGrant>;
  write(actor: string, next: ConsentWrite, signal: AbortSignal): Promise<ConsentGrant>;
}>;

export const DEFAULT_CONSENT: ConsentGrant = Object.freeze({
  accepted: false,
  version: CONSENT_VERSION,
  generation: 0,
});

const WRITE_KEYS = ['accepted', 'version', 'expectedGeneration'] as const;
const AWS_REGION = /^[a-z]{2}-[a-z]+-\d$/;
/**
 * The existing-row branch compares the whole grant that the strongly consistent GET captured —
 * `accepted`, `version` and `generation` — and refuses a row carrying a TTL or a foreign
 * `canonicalOwnerId`. Generation alone would let a concurrent rewrite that kept the generation
 * but flipped `accepted` be overwritten. `attribute_exists(#ownerId)` is the canonical existence
 * guard: it states the row must still be there and keeps every supplied `#name` referenced by the
 * expression, because DynamoDB rejects an `ExpressionAttributeNames` entry the condition never
 * uses with a ValidationException before it evaluates anything.
 */
const EXISTING_ROW_CONDITION =
  'attribute_exists(#ownerId) AND attribute_not_exists(#ttl) AND attribute_not_exists(#canonicalOwnerId) AND ' +
  '#generation = :expected AND #accepted = :capturedAccepted AND #version = :capturedVersion';
/**
 * Absence is the generation-0 creation case only. A row that existed when the caller read it and
 * was deleted before the update must conflict, not be recreated at `expectedGeneration > 0`.
 * Both branches reference `#ownerId`, so the name map below carries no entry DynamoDB would
 * reject as unused.
 */
const ABSENT_ROW_CONDITION = `attribute_not_exists(#ownerId) OR (${EXISTING_ROW_CONDITION})`;

/**
 * The one compare-and-set expression pair shared by the legacy `UpdateCommand` and the guarded
 * `TransactWriteCommand` update item. Both paths must issue byte-identical conditions, so the
 * builder is the single owner of that logic; no second parser or condition copy exists.
 */
type WriteExpressions = Readonly<{
  UpdateExpression: string;
  ConditionExpression: string;
  ExpressionAttributeNames: Record<string, string>;
  ExpressionAttributeValues: Record<string, unknown>;
}>;

const consentWriteExpressions = (
  grant: ConsentWrite,
  captured: ConsentGrant,
  generation: number,
): WriteExpressions =>
  Object.freeze({
    // SET (never Put): the note row keeps every attribute this endpoint does not own.
    UpdateExpression: 'SET #accepted = :accepted, #version = :version, #generation = :generation',
    // The preflight GET refuses a row it cannot read; this condition is the authoritative CAS on
    // the captured grant, so a delete or rewrite between the two calls cannot be adopted,
    // recreated or overwritten.
    ConditionExpression: grant.expectedGeneration === 0 ? ABSENT_ROW_CONDITION : EXISTING_ROW_CONDITION,
    ExpressionAttributeNames: {
      '#ownerId': 'ownerId',
      '#accepted': 'accepted',
      '#version': 'version',
      '#generation': 'generation',
      '#ttl': 'ttl',
      '#canonicalOwnerId': 'canonicalOwnerId',
    },
    ExpressionAttributeValues: {
      ':accepted': grant.accepted,
      ':version': grant.version,
      ':generation': generation,
      ':expected': captured.generation,
      ':capturedAccepted': captured.accepted,
      ':capturedVersion': captured.version,
    },
  });

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const hasExactKeys = (value: Record<string, unknown>, required: readonly string[]): boolean =>
  Object.keys(value).length === required.length &&
  required.every((key) => Object.prototype.hasOwnProperty.call(value, key));

const errorNameOf = (error: unknown): string =>
  isRecord(error) && typeof error['name'] === 'string' ? error['name'] : '';

/** Transaction cancellation reasons that are throttles/timeouts, kept distinct from a CAS loss. */
const CANCELLATION_THROTTLE = new Set([
  'ThrottlingError', 'ThrottlingException', 'ProvisionedThroughputExceeded',
  'ProvisionedThroughputExceededException', 'RequestLimitExceeded',
]);
const CANCELLATION_TIMEOUT = new Set(['RequestTimeout', 'TransactionTimeout']);

/** Only the transaction's own reason codes; a raw reason or item value is never echoed or logged. */
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

/**
 * The only SDK error names this diagnostic will surface verbatim. A name outside the set (or an
 * empty one) is reported as `UNKNOWN`, so a provider- or caller-supplied string never reaches the
 * log as-is. The set is grounded in the failures this store actually maps or can receive.
 */
const KNOWN_ERROR_NAMES = new Set([
  'AccessDeniedException',
  'ConditionalCheckFailedException',
  'CredentialsProviderError',
  'InternalServerError',
  'NetworkingError',
  'ProvisionedThroughputExceededException',
  'RequestLimitExceeded',
  'RequestTimeout',
  'ResourceNotFoundException',
  'ServiceUnavailable',
  'ThrottlingException',
  'TimeoutError',
  'TransactionCanceledException',
  'TransactionTimeout',
  'UnrecognizedClientException',
  'ValidationException',
]);
/** Cancellation reasons a diagnostic may echo: the CAS refusal and the transport codes only. */
const KNOWN_CANCELLATION_CODES = new Set([
  'ConditionalCheckFailed',
  ...CANCELLATION_THROTTLE,
  ...CANCELLATION_TIMEOUT,
]);

/** The command being sent, as a fixed trusted label; never a raw constructor or input string. */
const operationOf = (command: ConsentCommand): string => {
  if (command instanceof GetCommand) return 'Get';
  if (command instanceof UpdateCommand) return 'Update';
  if (command instanceof TransactWriteCommand) return 'TransactWrite';
  return 'Unknown';
};

/** The SDK error name, but only when it is on the known whitelist. */
const safeErrorName = (error: unknown): string => {
  const name = errorNameOf(error);
  return KNOWN_ERROR_NAMES.has(name) ? name : 'UNKNOWN';
};

/** A numeric HTTP status only when it is a plausible 100–599 value; otherwise omitted. */
const safeHttpStatus = (error: unknown): number | undefined => {
  if (!isRecord(error)) return undefined;
  const metadata = error['$metadata'];
  if (!isRecord(metadata)) return undefined;
  const status = metadata['httpStatusCode'];
  return isSafeInteger(status) && status >= 100 && status <= 599 ? status : undefined;
};

/**
 * The structured, safe diagnostic for every mapped SDK failure. It carries only the fixed
 * operation label, a whitelisted error name or `UNKNOWN`, a validated numeric HTTP status and
 * known cancellation codes. `error.message`, stacks, command input, returned `Attributes`/`Item`,
 * actor/request identifiers, headers, tokens, config and raw exceptions are never included.
 */
const warnSdkFailure = (command: ConsentCommand, error: unknown): void => {
  console.warn('rag.consent.sdk_failure', {
    operation: operationOf(command),
    errorName: safeErrorName(error),
    httpStatus: safeHttpStatus(error),
    cancellationCodes: cancellationCodes(error).filter((code) => KNOWN_CANCELLATION_CODES.has(code)),
  });
};

const invalidInput: () => never = () => {
  throw new RagFailure('INVALID_INPUT');
};
const invalidState: () => never = () => {
  // No dedicated INVALID_STATE code exists on the wire; an untrustworthy consent row is a
  // conflict the caller must re-read, never a value it may act on or overwrite.
  throw new RagFailure('SOURCE_CHANGED');
};

/** The canonical row key for one actor; the actor is the verified Cognito sub, never a body value. */
export const consentRowKey = (actor: string): Readonly<{ ownerId: string; noteId: string }> => ({
  ownerId: `${OWNER_KEY_PREFIX}${actor}`,
  noteId: CONSENT_SORT_KEY,
});

const requireActor = (actor: unknown): string => (isValidIdentifier(actor) ? actor : invalidInput());

const requireSignal = (signal: unknown): AbortSignal => {
  if (!(signal instanceof AbortSignal)) invalidInput();
  if (signal.aborted) throw new RagFailure('TIMEOUT');
  return signal;
};

/** Exact write shape: no owner, no extra field, an exact version and a safe expected generation. */
const requireWrite = (value: unknown): ConsentWrite => {
  if (!isRecord(value) || !hasExactKeys(value, WRITE_KEYS)) invalidInput();
  const accepted = value['accepted'];
  const version = value['version'];
  const expected = value['expectedGeneration'];
  if (typeof accepted !== 'boolean' || version !== CONSENT_VERSION) invalidInput();
  if (!isSafeInteger(expected) || expected < 0 || expected >= Number.MAX_SAFE_INTEGER) invalidInput();
  return Object.freeze({ accepted, version, expectedGeneration: expected });
};

/** Absence is the default grant; every stored value must be coherent and canonical. */
const grantOf = (item: unknown, actor: string): ConsentGrant => {
  if (item === undefined || item === null) return DEFAULT_CONSENT;
  if (!isRecord(item)) invalidState();
  const key = consentRowKey(actor);
  if (item['ownerId'] !== key.ownerId || item['noteId'] !== key.noteId) invalidState();
  const canonical = item['canonicalOwnerId'];
  // This key is never written as a share projection; any such row is foreign and unreadable.
  if (canonical !== undefined) invalidState();
  if (Object.prototype.hasOwnProperty.call(item, 'ttl')) invalidState();
  const accepted = item['accepted'];
  const version = item['version'];
  const generation = item['generation'];
  if (typeof accepted !== 'boolean') invalidState();
  if (version !== CONSENT_VERSION || !isWellFormed(version)) invalidState();
  if (!isSafeInteger(generation) || generation < 0) invalidState();
  return Object.freeze({ accepted, version, generation });
};

/**
 * Builds the store over one existing notes table. The default client is a document client with
 * retries disabled (`maxAttempts: 1`): a consent write is never silently repeated. When a
 * `ConsentGuard` is supplied, reads re-validate the fresh config after the canonical read and
 * writes commit the consent CAS plus an exact whole-config `ConditionCheck` in one transaction.
 */
export function createConsentStore(
  region: string,
  table: string,
  supplied?: ConsentPort,
  guard?: ConsentGuard,
): ConsentStore {
  if (typeof region !== 'string' || !AWS_REGION.test(region) || typeof table !== 'string' || table.length === 0) {
    throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
  if (guard !== undefined && (
    !isRecord(guard) ||
    typeof guard['table'] !== 'string' || guard['table'].length === 0 ||
    !isRecord(guard['key']) ||
    typeof guard['key']['ownerId'] !== 'string' || guard['key']['ownerId'].length === 0 ||
    typeof guard['key']['noteId'] !== 'string' || guard['key']['noteId'].length === 0 ||
    !Object.prototype.hasOwnProperty.call(guard, 'value') ||
    typeof guard['revalidate'] !== 'function'
  )) {
    throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
  const client: ConsentPort = supplied ?? DynamoDBDocumentClient.from(new DynamoDBClient({ region, maxAttempts: 1 }));

  const send = async (command: ConsentCommand, signal: AbortSignal): Promise<unknown> => {
    try {
      return await client.send(command, { abortSignal: signal });
    } catch (error) {
      if (signal.aborted) throw new RagFailure('TIMEOUT');
      // Diagnostic only: the privacy-safe structured warning never changes the mapping below.
      warnSdkFailure(command, error);
      const name = errorNameOf(error);
      // A refused condition is a compare-and-set loss, never a transport failure.
      if (name === 'ConditionalCheckFailedException') throw new RagFailure('SOURCE_CHANGED');
      // A transaction cancels for several reasons; only a pure condition refusal is a CAS loss.
      // A throttle or a timeout stays distinct (and is never echoed with its raw reasons).
      if (name === 'TransactionCanceledException') {
        const codes = cancellationCodes(error);
        if (codes.length > 0 && codes.every((code) => code === 'ConditionalCheckFailed')) {
          throw new RagFailure('SOURCE_CHANGED');
        }
        if (codes.some((code) => CANCELLATION_THROTTLE.has(code))) throw new RagFailure('RATE_LIMITED');
        if (codes.some((code) => CANCELLATION_TIMEOUT.has(code))) throw new RagFailure('TIMEOUT');
      }
      throw new RagFailure('PROVIDER_UNAVAILABLE');
    }
  };

  const readRow = async (owner: string, deadline: AbortSignal): Promise<ConsentGrant> => {
    const output = await send(
      new GetCommand({ TableName: table, Key: consentRowKey(owner), ConsistentRead: true }),
      deadline,
    );
    if (!isRecord(output)) invalidState();
    return grantOf(output['Item'], owner);
  };

  /** Post-commit truth: a bounded strongly consistent GET that must reproduce the admitted write. */
  const requireStored = async (
    owner: string,
    grant: ConsentWrite,
    generation: number,
    deadline: AbortSignal,
  ): Promise<ConsentGrant> => {
    const stored = await readRow(owner, deadline);
    if (
      stored.accepted !== grant.accepted ||
      stored.version !== grant.version ||
      stored.generation !== generation
    ) {
      invalidState();
    }
    return stored;
  };

  return Object.freeze({
    async read(actor: string, signal: AbortSignal): Promise<ConsentGrant> {
      const owner = requireActor(actor);
      const deadline = requireSignal(signal);
      const grant = await readRow(owner, deadline);
      // The canonical read happened first; membership is then re-checked against the fresh
      // immutable config before the grant is returned, so a removed actor never receives a grant.
      if (guard !== undefined) await guard.revalidate(owner, deadline);
      return grant;
    },

    async write(actor: string, next: ConsentWrite, signal: AbortSignal): Promise<ConsentGrant> {
      const owner = requireActor(actor);
      const grant = requireWrite(next);
      const deadline = requireSignal(signal);
      // Fail closed before writing: a row this store cannot read (foreign, TTL-carrying or
      // malformed) is never adopted or repaired, and a generation the caller did not observe
      // is refused before the conditional write. The captured grant then rides into the
      // condition below, which stays the authoritative CAS.
      const captured = await readRow(owner, deadline);
      if (captured.generation !== grant.expectedGeneration) throw new RagFailure('SOURCE_CHANGED');
      const generation = grant.expectedGeneration + 1;
      const expressions = consentWriteExpressions(grant, captured, generation);
      const key = consentRowKey(owner);
      if (guard === undefined) {
        // Legacy single-item path: the conditional update returns the stored row, so no extra
        // read is issued and the existing call-for-call behavior is preserved.
        const output = await send(
          new UpdateCommand({ TableName: table, Key: key, ...expressions, ReturnValues: 'ALL_NEW' }),
          deadline,
        );
        if (!isRecord(output)) invalidState();
        const stored = grantOf(output['Attributes'], owner);
        if (
          stored.accepted !== grant.accepted ||
          stored.version !== grant.version ||
          stored.generation !== generation
        ) {
          invalidState();
        }
        return stored;
      }
      // One transaction: the exact captured config row must still be present and byte-equal
      // (`#config = :capturedConfig` covers nested generation/version/policy/corpus), and the
      // notes consent row moves under the existing CAS. Either both apply or neither does, so a
      // config removed or moved during the write can never commit a stale admin permit.
      await send(
        new TransactWriteCommand({
          TransactItems: [
            { ConditionCheck: {
              TableName: guard.table,
              Key: guard.key,
              ConditionExpression: '#config = :capturedConfig',
              ExpressionAttributeNames: { '#config': 'config' },
              ExpressionAttributeValues: { ':capturedConfig': guard.value },
            } },
            { Update: {
              TableName: table,
              Key: key,
              ...expressions,
            } },
          ],
        }),
        deadline,
      );
      // No ReturnValues on a transaction: the success is only confirmed by a bounded strong GET
      // plus a fresh config/membership re-read. A change after the commit is reported, never
      // rolled back and never a counter refund.
      const stored = await requireStored(owner, grant, generation, deadline);
      await guard.revalidate(owner, deadline);
      return stored;
    },
  });
}
