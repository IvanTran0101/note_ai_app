/**
 * Phase 5 pilot runtime config (plan 5.1D): the one trusted, server-only description of the
 * approved reviewed pilot corpus, stored under `CONFIG#PHASE5`/`PILOT` in the RAG state table.
 *
 * The reader is the authority boundary. It performs one strongly consistent `GetCommand`
 * (retries disabled) and turns the stored row into a deep-frozen `RuntimeConfig`; the caller
 * never sees a mutable copy. A missing row, a foreign key, an unknown/duplicate key, a malformed
 * policy, a corpus owner set that does not exactly equal `policy.owners`, an empty owner list or
 * a non-hex digest all fail closed as `LIVE_POLICY_NOT_CONFIGURED`. `mode`/allowlist decisions
 * are never inferred from a request: this config is the whole permission input.
 *
 * The policy is validated only through the existing `readPilotPolicy`, which requires an already
 * frozen exact shape. Stored data may be unfrozen, so this module deep-copies and deep-freezes
 * the policy before handing it over; that preserves — never weakens — the immutability guard.
 * The digest shape reuses the indexing `SHA256_HEX` regex, so a stored digest and an artifact
 * digest can never drift apart.
 */
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand } from '@aws-sdk/lib-dynamodb';
import { isAwsRegion } from '../indexing/aws_http';
import { SHA256_HEX } from '../indexing/snapshot';
import { isSafeInteger } from '../chunking';
import { isValidIdentifier } from '../contract';
import { RagFailure } from '../types';
import { isCognitoSub, readPilotPolicy } from './pilot_policy';
import type { PilotPolicy } from './pilot_policy';

/** The frozen config row; the same canonical state table the indexing store uses. */
export const RUNTIME_CONFIG_KEY = Object.freeze({ ownerId: 'CONFIG#PHASE5', noteId: 'PILOT' });
export const RUNTIME_CONFIG_VERSION = 'rag-pilot-config.v1';
/**
 * The approved reviewed-pilot kind: five synthetic notes plus the one exact reviewed pilot owner
 * note. It is deliberately not the legacy `synthetic-quality` kind, and there is no fallback to
 * that kind or to any other value.
 */
export const RUNTIME_CORPUS_KIND = 'reviewed-pilot';
/** The one human-reviewed 20-case corpus hash (docs/rag/phase5_gold_review.md). */
export const RUNTIME_CASE_HASH =
  'sha256:0477ea68e177cdeadfd8f61977ffa61fe907557317e0150d3614d8130595f7a3';

const CONFIG_KEYS = ['version', 'generation', 'policy', 'corpus'] as const;
const CORPUS_KEYS = ['kind', 'caseHash', 'owners'] as const;
const CORPUS_NOTE_KEYS = ['noteId', 'inputDigest'] as const;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const hasExactKeys = (value: Record<string, unknown>, required: readonly string[]): boolean =>
  Object.keys(value).length === required.length &&
  required.every((key) => Object.prototype.hasOwnProperty.call(value, key));

/** Every rejection is the same code: a config that cannot be trusted is simply not configured. */
const refuse: () => never = () => {
  throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
};

/** Stored data may be reused by the caller, so parse must never freeze the caller's object. */
const deepCopy = <T>(value: T): T => {
  if (Array.isArray(value)) return value.map((entry) => deepCopy(entry)) as unknown as T;
  if (value !== null && typeof value === 'object') {
    const copy: Record<string, unknown> = {};
    for (const [key, entry] of Object.entries(value as Record<string, unknown>)) {
      copy[key] = deepCopy(entry);
    }
    return copy as unknown as T;
  }
  return value;
};

const deepFreeze = <T>(value: T): T => {
  if (value !== null && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const key of Object.keys(value as Record<string, unknown>)) {
      deepFreeze((value as Record<string, unknown>)[key]);
    }
  }
  return value;
};

export type RuntimeCorpusNote = Readonly<{ noteId: string; inputDigest: string }>;
export type RuntimeConfig = Readonly<{
  version: typeof RUNTIME_CONFIG_VERSION;
  generation: number;
  policy: PilotPolicy;
  corpus: Readonly<{
    kind: typeof RUNTIME_CORPUS_KIND;
    caseHash: typeof RUNTIME_CASE_HASH;
    owners: Readonly<Record<string, readonly RuntimeCorpusNote[]>>;
  }>;
}>;

/**
 * Validates one stored config value and returns a deep-frozen canonical copy. Every key set is
 * exact, the generation is a positive safe integer, the policy is re-validated by
 * `readPilotPolicy` on a frozen deep copy, the case hash is the pinned reviewed hash, the corpus
 * owner set equals `policy.owners` exactly, every owner list is non-empty and every digest is a
 * lowercase 64-hex value with no duplicate note id inside a list.
 */
export function parseRuntimeConfig(value: unknown): RuntimeConfig {
  if (!isRecord(value) || !hasExactKeys(value, CONFIG_KEYS)) refuse();
  if (value['version'] !== RUNTIME_CONFIG_VERSION) refuse();
  const generation = value['generation'];
  if (!isSafeInteger(generation) || generation < 1) refuse();
  const policy = readPilotPolicy(deepFreeze(deepCopy(value['policy'])));

  const corpus = value['corpus'];
  if (!isRecord(corpus) || !hasExactKeys(corpus, CORPUS_KEYS)) refuse();
  if (corpus['kind'] !== RUNTIME_CORPUS_KIND || corpus['caseHash'] !== RUNTIME_CASE_HASH) refuse();
  const rawOwners = corpus['owners'];
  if (!isRecord(rawOwners)) refuse();
  const ownerKeys = Object.keys(rawOwners);
  // Corpus owners are exactly the pilot owners: no extra, no missing, no prefix fallback.
  if (ownerKeys.length !== policy.owners.length) refuse();

  const owners: Record<string, readonly RuntimeCorpusNote[]> = {};
  for (const owner of ownerKeys) {
    if (!isCognitoSub(owner) || !policy.owners.includes(owner)) refuse();
    const list = rawOwners[owner];
    if (!Array.isArray(list) || list.length === 0) refuse();
    const notes: RuntimeCorpusNote[] = [];
    const seen = new Set<string>();
    for (const entry of list) {
      if (!isRecord(entry) || !hasExactKeys(entry, CORPUS_NOTE_KEYS)) refuse();
      const noteId = entry['noteId'];
      const inputDigest = entry['inputDigest'];
      if (!isValidIdentifier(noteId) || seen.has(noteId)) refuse();
      if (typeof inputDigest !== 'string' || !SHA256_HEX.test(inputDigest)) refuse();
      seen.add(noteId);
      notes.push(Object.freeze({ noteId, inputDigest }));
    }
    owners[owner] = Object.freeze(notes);
  }

  return Object.freeze({
    version: RUNTIME_CONFIG_VERSION,
    generation,
    policy,
    corpus: Object.freeze({
      kind: RUNTIME_CORPUS_KIND,
      caseHash: RUNTIME_CASE_HASH,
      owners: Object.freeze(owners),
    }),
  });
}

const sameOwners = (
  left: RuntimeConfig['corpus']['owners'],
  right: RuntimeConfig['corpus']['owners'],
): boolean => {
  const leftKeys = Object.keys(left);
  if (leftKeys.length !== Object.keys(right).length) return false;
  for (const key of leftKeys) {
    const a = left[key];
    const b = right[key];
    if (a === undefined || b === undefined || a.length !== b.length) return false;
    for (let index = 0; index < a.length; index += 1) {
      if (a[index].noteId !== b[index].noteId || a[index].inputDigest !== b[index].inputDigest) {
        return false;
      }
    }
  }
  return true;
};

/**
 * The whole captured identity must survive unchanged: version, generation, the frozen policy and
 * the complete corpus. Any difference is a source change, never a widened permit.
 */
export const sameRuntimeConfig = (left: RuntimeConfig, right: RuntimeConfig): boolean =>
  left.version === right.version &&
  left.generation === right.generation &&
  left.policy.enabled === right.policy.enabled &&
  left.policy.model === right.policy.model &&
  left.policy.thresholds.answerabilityMin === right.policy.thresholds.answerabilityMin &&
  left.policy.thresholds.conflictMax === right.policy.thresholds.conflictMax &&
  left.policy.owners.length === right.policy.owners.length &&
  left.policy.owners.every((owner, index) => owner === right.policy.owners[index]) &&
  left.corpus.kind === right.corpus.kind &&
  left.corpus.caseHash === right.corpus.caseHash &&
  sameOwners(left.corpus.owners, right.corpus.owners);

export type RuntimeConfigReaderOptions = Readonly<{
  region: string;
  stateTable: string;
  client?: RuntimeConfigReaderPort;
}>;
export type RuntimeConfigSendOptions = Readonly<{ abortSignal?: AbortSignal }>;
/** The one SDK capability this reader needs; a `DynamoDBDocumentClient` satisfies it. */
export interface RuntimeConfigReaderPort {
  send(command: GetCommand, options?: RuntimeConfigSendOptions): Promise<unknown>;
}
export type RuntimeConfigReader = Readonly<{ read(signal: AbortSignal): Promise<RuntimeConfig> }>;

const TIMEOUT_ERRORS = new Set(['AbortError', 'TimeoutError', 'RequestTimeout', 'RequestAbortedError']);
const THROTTLE_ERRORS = new Set([
  'ThrottlingException', 'ProvisionedThroughputExceededException', 'RequestLimitExceeded',
  'TooManyRequestsException',
]);

const errorNameOf = (error: unknown): string =>
  isRecord(error) && typeof error['name'] === 'string' ? error['name'] : '';

/** Typed SDK mapping: a deadline, a throttle, a 5xx and a 4xx become distinct safe codes. */
const mapSdk = (error: unknown, signal: AbortSignal): RagFailure => {
  if (signal.aborted) return new RagFailure('TIMEOUT');
  const name = errorNameOf(error);
  if (TIMEOUT_ERRORS.has(name)) return new RagFailure('TIMEOUT');
  if (THROTTLE_ERRORS.has(name)) return new RagFailure('RATE_LIMITED');
  const metadata = isRecord(error) ? error['$metadata'] : undefined;
  const status = isRecord(metadata) ? metadata['httpStatusCode'] : undefined;
  if (typeof status === 'number') {
    if (status === 408) return new RagFailure('TIMEOUT');
    if (status === 429) return new RagFailure('RATE_LIMITED');
    if (status >= 500) return new RagFailure('PROVIDER_UNAVAILABLE');
    return new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
  return new RagFailure('PROVIDER_UNAVAILABLE');
};

const requireSignal = (signal: unknown): AbortSignal => {
  if (!(signal instanceof AbortSignal)) throw new RagFailure('INVALID_INPUT');
  if (signal.aborted) throw new RagFailure('TIMEOUT');
  return signal;
};

/**
 * Builds the reader over the RAG state table. The default client is a document client with
 * retries disabled (`maxAttempts: 1`): a config read is never silently repeated.
 */
export function createRuntimeConfigReader(options: RuntimeConfigReaderOptions): RuntimeConfigReader {
  if (!isRecord(options)) refuse();
  const region = options['region'];
  const stateTable = options['stateTable'];
  const supplied = options['client'];
  if (!isAwsRegion(region) || typeof stateTable !== 'string' || stateTable.length === 0) refuse();
  if (supplied !== undefined && (!isRecord(supplied) || typeof supplied['send'] !== 'function')) refuse();
  const client: RuntimeConfigReaderPort = supplied ??
    (DynamoDBDocumentClient.from(new DynamoDBClient({ region, maxAttempts: 1 })) as unknown as RuntimeConfigReaderPort);

  const send = async (signal: AbortSignal): Promise<unknown> => {
    try {
      return await client.send(
        new GetCommand({ TableName: stateTable, Key: RUNTIME_CONFIG_KEY, ConsistentRead: true }),
        { abortSignal: signal },
      );
    } catch (error) {
      throw mapSdk(error, signal);
    }
  };

  return Object.freeze({
    async read(signal: AbortSignal): Promise<RuntimeConfig> {
      const deadline = requireSignal(signal);
      const output = await send(deadline);
      // A port that resolves late and ignores the abort signal must never turn a cancelled
      // request into a valid permission: re-check the deadline before parsing or admitting.
      requireSignal(deadline);
      if (!isRecord(output)) refuse();
      const item = output['Item'];
      if (!isRecord(item) || !hasExactKeys(item, ['ownerId', 'noteId', 'config'])) refuse();
      if (item['ownerId'] !== RUNTIME_CONFIG_KEY.ownerId || item['noteId'] !== RUNTIME_CONFIG_KEY.noteId) {
        refuse();
      }
      return parseRuntimeConfig(item['config']);
    },
  });
}
