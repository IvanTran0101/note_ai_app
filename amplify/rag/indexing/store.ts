/**
 * Indexing store (Phase 3): the canonical load, the account lease CAS, the transactional
 * publish and the one global embedding budget.
 *
 * Boundaries:
 *  - canonical notes live in the existing notes table under `OWNER#<verified sub>`; this store
 *    reads `NOTE#`/`PROTECTION#` rows with strongly consistent, paginated queries, maps them
 *    through the sync codec (`toNoteSnapshot`) and never trusts a stored flag, a caller text or
 *    an incoming shared projection (`canonicalOwnerId` must be the actor when present).
 *  - a torn snapshot fails closed: META (`lastSequence`) and `RAG#CONSENT` are read around the
 *    paginated load and a moved epoch/generation is `SOURCE_CHANGED` (retryable). Any incoherent
 *    note/protection pair, invalid stored manifest or malformed row is `INVALID_STATE` (terminal).
 *  - the manifest, lease, retirement record and budget counter live in the separate RAG state
 *    table. The notes table only ever receives reads and the publish transaction's
 *    `ConditionCheck`s; `load` performs no write at all.
 *  - publish is one DynamoDB transaction: META epoch, exact consent (absence allowed only for the
 *    default generation 0), the unexpired lease with the exact token/fingerprint, the manifest
 *    guarded by the expected old generation, and a durable `RAG#RETIRE#<old version>` copy of the
 *    replaced manifest (no TTL) so a cleanup can always recover the pointer.
 *  - every SDK call carries the caller's `abortSignal`; failures collapse to a typed
 *    `IndexFailure` whose message is only a code. Only a throttle, a 5xx or a deadline is
 *    retryable. Raw canonical text never reaches an error or a log.
 */
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import {
  DynamoDBDocumentClient, GetCommand, QueryCommand, TransactWriteCommand, UpdateCommand,
  type TransactWriteCommandInput,
} from '@aws-sdk/lib-dynamodb';
import { randomUUID } from 'node:crypto';
import { CONSENT_VERSION, isValidIdentifier } from '../contract';
import { isSafeInteger, isWellFormed } from '../chunking';
import { META_SORT_KEY, toNoteSnapshot } from '../../sync/sync_store_codec';
import type { NoteSnapshot } from '../../sync/sync_store_models';
import {
  CONSENT_SORT_KEY, NOTE_KEY_PREFIX, OWNER_KEY_PREFIX, PROTECTION_KEY_PREFIX, fingerprint,
} from './jobs';
import { SHA256_HEX, validateManifest } from './snapshot';
import { failureForStatus, isAwsRegion } from './aws_http';
import { IndexFailure, LEASE_MS, SMOKE_EMBED_LIMIT } from './types';
import type {
  Consent, IndexNote, IndexState, IndexStore, JobStatus, Lease, Manifest,
} from './types';

export const MANIFEST_SORT_KEY = 'RAG#MANIFEST';
export const LEASE_SORT_KEY = 'RAG#LEASE';
export const RETIRE_SORT_KEY_PREFIX = 'RAG#RETIRE#';
/** The one global budget item: the state table partition is literally `BUDGET#SMOKE`. */
export const BUDGET_OWNER_KEY = 'BUDGET#SMOKE';
export const BUDGET_SORT_KEY = 'COUNTER';
export const LEASE_STATUS_RUNNING = 'RUNNING';
export const LEASE_STATUS_PUBLISHED = 'PUBLISHED';
/** Bounded reads: an account that never ends a page is never indexed half-way. */
export const MAX_QUERY_PAGES = 1_000;
export const MAX_NOTES = 10_000;

/** Attributes a stored row may carry beyond the manifest/retire payload; never part of it. */
const TIMESTAMP_KEYS = ['createdAt', 'updatedAt', 'publishedAt', 'serverUpdatedAt', 'ttl'] as const;
const JOB_STATUSES: ReadonlySet<string> = new Set(['RUNNING', 'SUCCEEDED', 'SUPERSEDED', 'BLOCKED', 'FAILED']);
const THROTTLE_ERRORS: ReadonlySet<string> = new Set([
  'ThrottlingException', 'ProvisionedThroughputExceededException', 'RequestLimitExceeded',
  'TooManyRequestsException',
]);
const TIMEOUT_ERRORS: ReadonlySet<string> = new Set([
  'AbortError', 'TimeoutError', 'RequestTimeout', 'RequestAbortedError', 'TimeoutException',
]);
const DEFAULT_CONSENT: Consent = Object.freeze({
  accepted: false, version: CONSENT_VERSION, generation: 0,
});

type Row = Record<string, unknown>;

export type IndexStoreConfig = Readonly<{ notesTable: string; stateTable: string; region: string }>;
export type StoreSendOptions = Readonly<{ abortSignal?: AbortSignal }>;
export type StoreCommand = GetCommand | QueryCommand | UpdateCommand | TransactWriteCommand;
/** The one SDK capability this store needs; a `DynamoDBDocumentClient` satisfies it. */
export interface StorePort {
  send(command: StoreCommand, options?: StoreSendOptions): Promise<unknown>;
}
export type IndexStoreOptions = Readonly<{ client?: StorePort; id?: () => string }>;

const isRecord = (value: unknown): value is Row =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

/** Declared as a never-typed binding so control-flow analysis knows the call cannot return. */
const invalidInput: () => never = () => {
  throw new IndexFailure('INVALID_INPUT', false);
};
const invalidState: () => never = () => {
  throw new IndexFailure('INVALID_STATE', false);
};
const errorNameOf = (error: unknown): string =>
  isRecord(error) && typeof error['name'] === 'string' ? error['name'] : '';

/** One failure taxonomy: a deadline, a throttle, a 5xx and an unknown error become codes. */
const mapDynamo = (error: unknown, signal: AbortSignal): IndexFailure => {
  if (signal.aborted) return new IndexFailure('TIMEOUT', true);
  if (error instanceof IndexFailure) return error;
  const name = errorNameOf(error);
  if (TIMEOUT_ERRORS.has(name)) return new IndexFailure('TIMEOUT', true);
  if (THROTTLE_ERRORS.has(name)) return new IndexFailure('RATE_LIMITED', true);
  const metadata = isRecord(error) ? error['$metadata'] : undefined;
  const status = isRecord(metadata) ? metadata['httpStatusCode'] : undefined;
  if (typeof status === 'number') return failureForStatus(status, false);
  return new IndexFailure('PROVIDER_UNAVAILABLE', false);
};

const requireSignal = (signal: unknown): AbortSignal => {
  if (!(signal instanceof AbortSignal)) invalidInput();
  if (signal.aborted) throw new IndexFailure('TIMEOUT', true);
  return signal;
};
const requireOwner = (value: unknown): string => (isValidIdentifier(value) ? value : invalidInput());
const requireNow = (value: unknown): number =>
  (isSafeInteger(value) && value >= 0 ? value : invalidInput());
const ownerKeyOf = (ownerId: string): string => `${OWNER_KEY_PREFIX}${ownerId}`;
const keyOf = (ownerKey: string, sortKey: string): Row => ({ ownerId: ownerKey, noteId: sortKey });

/** A stored `canonicalOwnerId` that is not the actor is an incoming shared copy, never canonical. */
const isForeignProjection = (row: Row, ownerId: string): boolean => {
  const canonical = row['canonicalOwnerId'];
  if (canonical === undefined) return false;
  if (typeof canonical !== 'string') invalidState();
  return canonical !== ownerId;
};

/** DynamoDB reports which transaction item refused; only a pure condition refusal is a CAS loss. */
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

/** Stored note rows come from the sync codec; anything it rejects is terminal corruption. */
const snapshotOf = (row: Row): NoteSnapshot => {
  try {
    return toNoteSnapshot(row);
  } catch {
    invalidState();
  }
};

const manifestOf = (item: Row | null, ownerKey: string, ownerId: string): Manifest | null => {
  if (item === null) return null;
  if (item['ownerId'] !== ownerKey || item['noteId'] !== MANIFEST_SORT_KEY) invalidState();
  // The partition key is `OWNER#<actor>` while the manifest names the actor: a flat row is
  // read back by restoring that one field, and a nested `manifest` attribute is accepted too.
  const nested = item['manifest'];
  let value: unknown = nested;
  if (nested === undefined) {
    const flat: Row = { ...item };
    delete flat['noteId'];
    for (const key of TIMESTAMP_KEYS) delete flat[key];
    flat['ownerId'] = ownerId;
    value = flat;
  }
  try {
    return validateManifest(value, ownerId);
  } catch {
    invalidState();
  }
};

export function createIndexStore(config: IndexStoreConfig, options?: IndexStoreOptions): IndexStore {
  const rawConfig: unknown = config;
  if (!isRecord(rawConfig)) invalidState();
  const notesTable = rawConfig['notesTable'];
  const stateTable = rawConfig['stateTable'];
  const region = rawConfig['region'];
  if (typeof notesTable !== 'string' || notesTable.length === 0 ||
      typeof stateTable !== 'string' || stateTable.length === 0 || !isAwsRegion(region)) {
    invalidState();
  }
  const rawOptions: unknown = options;
  if (rawOptions !== undefined && !isRecord(rawOptions)) invalidState();
  const optionClient = isRecord(rawOptions) ? rawOptions['client'] : undefined;
  const optionId = isRecord(rawOptions) ? rawOptions['id'] : undefined;
  if (optionClient !== undefined && !isRecord(optionClient)) invalidState();
  if (optionId !== undefined && typeof optionId !== 'function') invalidState();
  const client: StorePort = (optionClient as StorePort | undefined) ??
    DynamoDBDocumentClient.from(new DynamoDBClient({ region, maxAttempts: 1 }));
  if (typeof client.send !== 'function') invalidState();
  const nextId: () => string = (optionId as (() => string) | undefined) ?? (() => randomUUID());

  const send = async (command: StoreCommand, signal: AbortSignal): Promise<Row> => {
    let output: unknown;
    try {
      output = await client.send(command, { abortSignal: signal });
    } catch (error) {
      throw mapDynamo(error, signal);
    }
    if (!isRecord(output)) invalidState();
    return output;
  };

  const getItem = async (table: string, key: Row, signal: AbortSignal): Promise<Row | null> => {
    const output = await send(new GetCommand({ TableName: table, Key: key, ConsistentRead: true }), signal);
    const item = output['Item'];
    if (item === undefined || item === null) return null;
    if (!isRecord(item)) invalidState();
    return item;
  };

  const epochOf = (item: Row | null): number => {
    if (item === null) return 0;
    const sequence = item['lastSequence'];
    if (sequence === undefined) return 0;
    if (!isSafeInteger(sequence) || sequence < 0) invalidState();
    return sequence;
  };

  const consentOf = (item: Row | null, ownerId: string): Consent => {
    if (item === null || isForeignProjection(item, ownerId)) return DEFAULT_CONSENT;
    if (Object.hasOwn(item, 'ttl')) invalidState();
    const accepted = item['accepted'];
    const version = item['version'];
    const generation = item['generation'];
    if (typeof accepted !== 'boolean' || typeof version !== 'string' || !isWellFormed(version) ||
        !isSafeInteger(generation) || generation < 0) {
      invalidState();
    }
    return Object.freeze({ accepted, version, generation });
  };

  /** One prefix, strongly consistent, fully paginated; a repeated cursor is corruption. */
  const queryRows = async (ownerKey: string, prefix: string, signal: AbortSignal): Promise<Row[]> => {
    const rows: Row[] = [];
    let cursor: Row | undefined;
    let sent: string | null = null;
    for (let page = 0; ; page += 1) {
      if (page >= MAX_QUERY_PAGES) invalidState();
      const output = await send(new QueryCommand({
        TableName: notesTable,
        ConsistentRead: true,
        KeyConditionExpression: 'ownerId = :owner AND begins_with(noteId, :prefix)',
        ExpressionAttributeValues: { ':owner': ownerKey, ':prefix': prefix },
        ...(cursor === undefined ? {} : { ExclusiveStartKey: cursor }),
      }), signal);
      const items = output['Items'];
      if (items !== undefined) {
        if (!Array.isArray(items)) invalidState();
        for (const item of items) {
          if (!isRecord(item)) invalidState();
          rows.push(item);
        }
      }
      if (rows.length > MAX_NOTES) invalidState();
      const next = output['LastEvaluatedKey'];
      if (next === undefined || next === null) return rows;
      if (!isRecord(next)) invalidState();
      const encoded = JSON.stringify(next);
      if (encoded === sent) invalidState();
      sent = encoded;
      cursor = next;
    }
  };

  const load = async (ownerId: string, signal: AbortSignal): Promise<IndexState> => {
    const owner = requireOwner(ownerId);
    const deadline = requireSignal(signal);
    const ownerKey = ownerKeyOf(owner);
    const epochBefore = epochOf(await getItem(notesTable, keyOf(ownerKey, META_SORT_KEY), deadline));
    const consentBefore = consentOf(await getItem(notesTable, keyOf(ownerKey, CONSENT_SORT_KEY), deadline), owner);
    const noteRows = await queryRows(ownerKey, NOTE_KEY_PREFIX, deadline);
    const protectionRows = await queryRows(ownerKey, PROTECTION_KEY_PREFIX, deadline);
    const epochAfter = epochOf(await getItem(notesTable, keyOf(ownerKey, META_SORT_KEY), deadline));
    const consentAfter = consentOf(await getItem(notesTable, keyOf(ownerKey, CONSENT_SORT_KEY), deadline), owner);
    if (epochAfter !== epochBefore || consentAfter.accepted !== consentBefore.accepted ||
        consentAfter.version !== consentBefore.version || consentAfter.generation !== consentBefore.generation) {
      throw new IndexFailure('SOURCE_CHANGED', true);
    }
    const manifest = manifestOf(await getItem(stateTable, keyOf(ownerKey, MANIFEST_SORT_KEY), deadline), ownerKey, owner);

    const protections = new Map<string, Readonly<{ enabled: boolean; revision: number }>>();
    for (const row of protectionRows) {
      if (row['ownerId'] !== ownerKey) invalidState();
      const sortKey = row['noteId'];
      if (typeof sortKey !== 'string' || !sortKey.startsWith(PROTECTION_KEY_PREFIX)) invalidState();
      const noteId = sortKey.slice(PROTECTION_KEY_PREFIX.length);
      if (!isValidIdentifier(noteId) || protections.has(noteId)) invalidState();
      // A protection row can never be a shared projection, and must name its own note.
      if (row['canonicalOwnerId'] !== owner || row['targetNoteId'] !== noteId) invalidState();
      const enabled = row['enabled'];
      const revision = row['revision'];
      if (typeof enabled !== 'boolean' || !isSafeInteger(revision) || revision < 0 ||
          (enabled && (revision < 1 || typeof row['verifier'] !== 'string')) ||
          (!enabled && row['verifier'] !== null)) {
        invalidState();
      }
      protections.set(noteId, Object.freeze({ enabled, revision }));
    }

    const seenKeys = new Set<string>();
    const notes: IndexNote[] = [];
    for (const row of noteRows) {
      if (row['ownerId'] !== ownerKey) invalidState();
      const sortKey = row['noteId'];
      if (typeof sortKey !== 'string' || !sortKey.startsWith(NOTE_KEY_PREFIX)) invalidState();
      const noteId = sortKey.slice(NOTE_KEY_PREFIX.length);
      if (!isValidIdentifier(noteId) || seenKeys.has(noteId)) invalidState();
      seenKeys.add(noteId);
      if (isForeignProjection(row, owner)) continue;
      const snapshot = snapshotOf(row);
      if (snapshot.id !== noteId || (snapshot.ownerId !== undefined && snapshot.ownerId !== owner)) invalidState();
      const protection = protections.get(noteId);
      const enabled = protection?.enabled === true;
      const revision = protection?.revision ?? 0;
      if (snapshot.protected !== enabled || snapshot.protectionRevision !== revision) invalidState();
      notes.push(Object.freeze({
        ownerId: owner,
        noteId,
        revision: snapshot.revision,
        title: snapshot.title,
        content: snapshot.content,
        synced: true,
        protected: enabled,
        deleted: snapshot.deletedAt !== null,
        available: snapshot.contentAvailable === true,
        protectionRevision: revision,
      }));
    }
    // Orphan protection rows after a hard delete are not an eligible document.
    notes.sort((left, right) => (left.noteId < right.noteId ? -1 : left.noteId > right.noteId ? 1 : 0));
    return Object.freeze({
      ownerId: owner,
      accountEpoch: epochBefore,
      consent: consentBefore,
      notes: Object.freeze(notes),
      manifest,
    });
  };

  const acquire = async (
    state: IndexState, requested: string, nowMs: number, signal: AbortSignal,
  ): Promise<Lease | null> => {
    const deadline = requireSignal(signal);
    const now = requireNow(nowMs);
    if (!isRecord(state)) invalidInput();
    const owner = requireOwner(state.ownerId);
    if (typeof requested !== 'string' || !SHA256_HEX.test(requested)) invalidInput();
    // The lease is bound to the recomputed canonical fingerprint, never to the caller's word.
    const expected = fingerprint(state);
    if (expected !== requested) invalidState();
    const token = nextId();
    if (!isValidIdentifier(token)) invalidState();
    const expiresAt = now + LEASE_MS;
    try {
      await client.send(new UpdateCommand({
        TableName: stateTable,
        Key: keyOf(ownerKeyOf(owner), LEASE_SORT_KEY),
        UpdateExpression: 'SET #token = :token, fingerprint = :fingerprint, expiresAt = :expiresAt, #status = :status',
        // Released leases have no `expiresAt`; a live one must be expired before it can be replaced.
        ConditionExpression: 'attribute_not_exists(noteId) OR attribute_not_exists(expiresAt) OR expiresAt <= :now',
        ExpressionAttributeNames: { '#token': 'token', '#status': 'status' },
        ExpressionAttributeValues: {
          ':token': token, ':fingerprint': expected, ':expiresAt': expiresAt,
          ':status': LEASE_STATUS_RUNNING, ':now': now,
        },
      }), { abortSignal: deadline });
    } catch (error) {
      if (errorNameOf(error) === 'ConditionalCheckFailedException') return null;
      throw mapDynamo(error, deadline);
    }
    return Object.freeze({ token, expiresAt, fingerprint: expected });
  };

  const publish = async (
    state: IndexState, lease: Lease, manifest: Manifest, nowMs: number, signal: AbortSignal,
  ): Promise<boolean> => {
    const deadline = requireSignal(signal);
    const now = requireNow(nowMs);
    if (!isRecord(state) || !isRecord(lease) || !isRecord(manifest)) invalidInput();
    const owner = requireOwner(state.ownerId);
    if (typeof lease.token !== 'string' || !isValidIdentifier(lease.token) ||
        !isSafeInteger(lease.expiresAt) || typeof lease.fingerprint !== 'string' ||
        !SHA256_HEX.test(lease.fingerprint)) {
      invalidInput();
    }
    let bound: Manifest;
    try {
      bound = validateManifest(manifest, owner);
    } catch {
      invalidState();
    }
    const expected = fingerprint(state);
    const oldGeneration = state.manifest?.generation ?? 0;
    if (expected !== lease.fingerprint || bound.fingerprint !== lease.fingerprint ||
        bound.accountEpoch !== state.accountEpoch ||
        bound.consentGeneration !== state.consent.generation ||
        bound.generation !== oldGeneration + 1) {
      invalidState();
    }
    const ownerKey = ownerKeyOf(owner);
    const consent = state.consent;
    const exactConsent = 'accepted = :accepted AND #version = :version AND generation = :generation';
    const defaultConsent = consent.accepted === false &&
      consent.version === CONSENT_VERSION && consent.generation === 0;
    const items: NonNullable<TransactWriteCommandInput['TransactItems']> = [
      { ConditionCheck: {
        TableName: notesTable,
        Key: keyOf(ownerKey, META_SORT_KEY),
        // Epoch 0 is the absent META (a stored 0 means the same thing); anything else is exact.
        ConditionExpression: state.accountEpoch === 0
          ? 'attribute_not_exists(noteId) OR lastSequence = :epoch'
          : 'lastSequence = :epoch',
        ExpressionAttributeValues: { ':epoch': state.accountEpoch },
      } },
      { ConditionCheck: {
        TableName: notesTable,
        Key: keyOf(ownerKey, CONSENT_SORT_KEY),
        ConditionExpression: defaultConsent
          ? `attribute_not_exists(noteId) OR (${exactConsent})`
          : exactConsent,
        ExpressionAttributeNames: { '#version': 'version' },
        ExpressionAttributeValues: {
          ':accepted': consent.accepted, ':version': consent.version, ':generation': consent.generation,
        },
      } },
      { Update: {
        TableName: stateTable,
        Key: keyOf(ownerKey, LEASE_SORT_KEY),
        UpdateExpression: 'SET #status = :published',
        ConditionExpression: '#token = :token AND fingerprint = :fingerprint AND expiresAt > :now',
        ExpressionAttributeNames: { '#status': 'status', '#token': 'token' },
        ExpressionAttributeValues: {
          ':published': LEASE_STATUS_PUBLISHED, ':token': lease.token,
          ':fingerprint': lease.fingerprint, ':now': now,
        },
      } },
      { Put: {
        TableName: stateTable,
        Item: { ...bound, ownerId: ownerKey, noteId: MANIFEST_SORT_KEY },
        ConditionExpression: state.manifest === null
          ? 'attribute_not_exists(noteId)'
          : 'generation = :oldGeneration',
        ...(state.manifest === null ? {} : { ExpressionAttributeValues: { ':oldGeneration': oldGeneration } }),
      } },
    ];
    if (state.manifest !== null) {
      // Durable recovery pointer for the replaced generation; no TTL, so cleanup never loses it.
      items.push({ Put: {
        TableName: stateTable,
        Item: {
          ownerId: ownerKey,
          noteId: `${RETIRE_SORT_KEY_PREFIX}${state.manifest.version}`,
          manifest: state.manifest,
          createdAt: now,
        },
      } });
    }
    // No two operations may target the same item inside one transaction.
    const targets = new Set<string>();
    for (const entry of items) {
      const table = entry.ConditionCheck?.TableName ?? entry.Update?.TableName ??
        entry.Delete?.TableName ?? entry.Put?.TableName;
      const key = entry.ConditionCheck?.Key ?? entry.Update?.Key ?? entry.Delete?.Key ?? entry.Put?.Item;
      if (table === undefined || key === undefined) invalidState();
      const target = `${table}\u0000${String(key['ownerId'])}\u0000${String(key['noteId'])}`;
      if (targets.has(target)) invalidState();
      targets.add(target);
    }
    try {
      await client.send(new TransactWriteCommand({ TransactItems: items }), { abortSignal: deadline });
      return true;
    } catch (error) {
      if (errorNameOf(error) === 'ConditionalCheckFailedException') return false;
      if (errorNameOf(error) === 'TransactionCanceledException') {
        const codes = cancellationCodes(error);
        // Only a pure condition refusal is a CAS loss; a conflict/throttle must be replayed.
        if (codes.length > 0 && codes.every((code) => code === 'ConditionalCheckFailed')) return false;
        throw new IndexFailure('PROVIDER_UNAVAILABLE', true);
      }
      throw mapDynamo(error, deadline);
    }
  };

  const finish = async (
    ownerId: string, lease: Lease, status: JobStatus, code: string, nowMs: number, signal: AbortSignal,
  ): Promise<void> => {
    const deadline = requireSignal(signal);
    const now = requireNow(nowMs);
    const owner = requireOwner(ownerId);
    if (!isRecord(lease) || typeof lease.token !== 'string' || !isValidIdentifier(lease.token)) invalidInput();
    if (!JOB_STATUSES.has(status) || typeof code !== 'string' || !isValidIdentifier(code)) invalidInput();
    try {
      await client.send(new UpdateCommand({
        TableName: stateTable,
        Key: keyOf(ownerKeyOf(owner), LEASE_SORT_KEY),
        // The token stays behind, so a stale worker can never release a newer lease.
        UpdateExpression: 'SET #status = :status, #code = :code, updatedAt = :now REMOVE expiresAt',
        ConditionExpression: '#token = :token',
        ExpressionAttributeNames: { '#status': 'status', '#code': 'code', '#token': 'token' },
        ExpressionAttributeValues: { ':status': status, ':code': code, ':now': now, ':token': lease.token },
      }), { abortSignal: deadline });
    } catch (error) {
      // A replaced/expired lease already moved on: releasing it again is harmless.
      if (errorNameOf(error) === 'ConditionalCheckFailedException') return;
      throw mapDynamo(error, deadline);
    }
  };

  const reserveEmbedding = async (ownerId: string, signal: AbortSignal): Promise<void> => {
    const deadline = requireSignal(signal);
    requireOwner(ownerId);
    try {
      await client.send(new UpdateCommand({
        TableName: stateTable,
        // One global item across every owner; no TTL and no reset path.
        Key: { ownerId: BUDGET_OWNER_KEY, noteId: BUDGET_SORT_KEY },
        UpdateExpression: 'ADD used :one',
        ConditionExpression: 'attribute_not_exists(noteId) OR used < :limit',
        ExpressionAttributeValues: { ':one': 1, ':limit': SMOKE_EMBED_LIMIT },
      }), { abortSignal: deadline });
    } catch (error) {
      if (errorNameOf(error) === 'ConditionalCheckFailedException') {
        throw new IndexFailure('BUDGET_EXHAUSTED', false);
      }
      throw mapDynamo(error, deadline);
    }
  };

  return Object.freeze({ load, acquire, publish, finish, reserveEmbedding });
}
