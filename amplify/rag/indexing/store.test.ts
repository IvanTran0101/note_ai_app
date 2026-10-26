/**
 * Indexing store slice tests — canonical pagination, fail-closed namespace/protection reads,
 * torn-snapshot detection, lease/budget CAS and the transactional publish/retirement record.
 *
 * The injected port is a fake DynamoDB document client: it records every command with its
 * abortSignal and inputs, evaluates the condition/update expressions this store emits, and
 * executes Get/Query/Update/TransactWrite against in-memory tables, so the tests assert the
 * wire contract instead of a mock's return values.
 *
 * Runner: node --import tsx --test amplify/rag/indexing/store.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  GetCommand, QueryCommand, TransactWriteCommand, UpdateCommand,
} from '@aws-sdk/lib-dynamodb';
import { CONSENT_VERSION } from '../contract';
import { fingerprint, markersOf, sameMarkers } from './jobs';
import { sha256Hex } from './snapshot';
import { IndexFailure, LEASE_MS, SMOKE_EMBED_LIMIT } from './types';
import type { Consent, IndexState, Manifest } from './types';
import {
  BUDGET_OWNER_KEY, BUDGET_SORT_KEY, LEASE_SORT_KEY, MANIFEST_SORT_KEY, MAX_QUERY_PAGES,
  RETIRE_SORT_KEY_PREFIX, createIndexStore,
} from './store';
import type { StoreCommand, StorePort, StoreSendOptions } from './store';

const OWNER = 'u1';
const NOTES_TABLE = 'notes';
const STATE_TABLE = 'state';
const OWNER_KEY = `OWNER#${OWNER}`;
const META_KEY = 'META#SYNC';
const CONSENT_KEY = 'RAG#CONSENT';

type Row = Record<string, unknown>;
type Call = Readonly<{ name: string; input: any; signal: AbortSignal | undefined }>;

// ---------------------------------------------------------------------------------------------
// In-memory DynamoDB stand-in: conditions and updates are evaluated, not stubbed.
// ---------------------------------------------------------------------------------------------

const rowKey = (key: Row): string => `${String(key['ownerId'])}\u0000${String(key['noteId'])}`;
const clone = <T>(value: T): T => structuredClone(value);

const conditionalFailure = (): Error =>
  Object.assign(new Error('ConditionalCheckFailedException'), { name: 'ConditionalCheckFailedException' });
const transactionCanceled = (reasons: readonly Row[]): Error =>
  Object.assign(new Error('TransactionCanceledException'), {
    name: 'TransactionCanceledException', CancellationReasons: reasons,
  });
const serviceFailure = (name: string, status: number): Error =>
  Object.assign(new Error(name), { name, $metadata: { httpStatusCode: status } });

type ConditionInput = Readonly<{
  ConditionExpression?: string;
  ExpressionAttributeNames?: Record<string, string>;
  ExpressionAttributeValues?: Record<string, unknown>;
}>;

const evalCondition = (
  expression: string, item: Row | undefined,
  names: Record<string, string>, values: Record<string, unknown>,
): boolean => {
  const tokens = expression.match(/\(|\)|<>|<=|>=|=|<|>|,|#?[A-Za-z_][A-Za-z0-9_]*|:[A-Za-z0-9_]+/g);
  if (tokens === null) throw new Error('unparseable condition');
  let index = 0;
  const peek = (): string | undefined => tokens[index];
  const eat = (expected?: string): string => {
    const token = tokens[index];
    if (token === undefined || (expected !== undefined && token !== expected)) {
      throw new Error(`bad condition near ${String(token)}`);
    }
    index += 1;
    return token;
  };
  const attrName = (token: string): string => (token.startsWith('#') ? names[token] ?? token : token);
  const attrValue = (token: string): unknown =>
    (item === undefined ? undefined : item[attrName(token)]);
  const atom = (): unknown => {
    const token = peek();
    if (token === '(') {
      eat('(');
      const value = or();
      eat(')');
      return value;
    }
    if (token !== undefined && token.startsWith(':')) {
      eat();
      return values[token];
    }
    if (token === 'attribute_not_exists' || token === 'attribute_exists') {
      eat();
      eat('(');
      const name = eat();
      eat(')');
      const present = attrValue(name) !== undefined;
      return token === 'attribute_not_exists' ? !present : present;
    }
    eat();
    return attrValue(token as string);
  };
  const comparison = (): boolean => {
    const left = atom();
    const operator = peek();
    if (operator === '=' || operator === '<>' || operator === '<' ||
        operator === '<=' || operator === '>' || operator === '>=') {
      eat();
      const right = atom();
      if (left === undefined || right === undefined) return false;
      if (operator === '=') return left === right;
      if (operator === '<>') return left !== right;
      const a = left as number;
      const b = right as number;
      if (operator === '<') return a < b;
      if (operator === '<=') return a <= b;
      if (operator === '>') return a > b;
      return a >= b;
    }
    return left === true;
  };
  const and = (): boolean => {
    let value = comparison();
    while (peek() === 'AND') {
      eat();
      const next = comparison();
      value = value && next;
    }
    return value;
  };
  const or = (): boolean => {
    let value = and();
    while (peek() === 'OR') {
      eat();
      const next = and();
      value = value || next;
    }
    return value;
  };
  const result = or();
  if (index !== tokens.length) throw new Error('trailing condition tokens');
  return result;
};

type UpdateInput = Readonly<{
  UpdateExpression?: string;
  ExpressionAttributeNames?: Record<string, string>;
  ExpressionAttributeValues?: Record<string, unknown>;
}>;

const applyUpdate = (item: Row, input: UpdateInput): Row => {
  const next = clone(item);
  const names = input.ExpressionAttributeNames ?? {};
  const values = input.ExpressionAttributeValues ?? {};
  const name = (token: string): string => (token.startsWith('#') ? names[token] ?? token : token);
  const clauses = (input.UpdateExpression ?? '').split(/\s+(?=(?:SET|REMOVE|ADD|DELETE)\s)/);
  for (const clause of clauses) {
    const [keyword, ...rest] = clause.trim().split(/\s+/);
    if (keyword === 'SET') {
      for (const assignment of rest.join(' ').split(',')) {
        const [target, value] = assignment.split('=');
        next[name(target.trim())] = values[value.trim()];
      }
    } else if (keyword === 'REMOVE') {
      for (const target of rest) delete next[name(target)];
    } else if (keyword === 'ADD') {
      for (const term of rest.join(' ').split(',')) {
        const [target, value] = term.trim().split(/\s+/);
        const key = name(target);
        next[key] = ((next[key] as number | undefined) ?? 0) + (values[value] as number);
      }
    }
  }
  return next;
};

class FakeDynamo implements StorePort {
  readonly notes = new Map<string, Row>();
  readonly state = new Map<string, Row>();
  readonly calls: Call[] = [];
  pageSize = Number.POSITIVE_INFINITY;
  /** When set, Query answers honor ProjectionExpression like real DynamoDB (marker reads). */
  applyProjection = false;
  cursorMode: 'normal' | 'repeat' | 'runaway' = 'normal';
  failNext: (() => unknown) | null = null;
  beforeQuery: (() => void) | null = null;
  private runaway = 0;

  seed(table: 'notes' | 'state', row: Row): Row {
    this[table].set(rowKey(row), clone(row));
    return row;
  }

  row(table: 'notes' | 'state', sortKey: string, ownerKey = OWNER_KEY): Row | undefined {
    return this[table].get(`${ownerKey}\u0000${sortKey}`);
  }

  private table(input: { TableName?: string }): Map<string, Row> {
    if (input.TableName === NOTES_TABLE) return this.notes;
    if (input.TableName === STATE_TABLE) return this.state;
    throw new Error(`unexpected table ${String(input.TableName)}`);
  }

  private passes(input: ConditionInput, item: Row | undefined): boolean {
    if (input.ConditionExpression === undefined) return true;
    return evalCondition(input.ConditionExpression, item,
      input.ExpressionAttributeNames ?? {}, input.ExpressionAttributeValues ?? {});
  }

  async send(command: StoreCommand, options?: StoreSendOptions): Promise<unknown> {
    this.calls.push({ name: command.constructor.name, input: command.input, signal: options?.abortSignal });
    if (this.failNext !== null) {
      const error = this.failNext();
      this.failNext = null;
      throw error;
    }
    if (command instanceof GetCommand) {
      const item = this.table(command.input).get(rowKey(command.input.Key as Row));
      return item === undefined ? {} : { Item: clone(item) };
    }
    if (command instanceof QueryCommand) {
      this.beforeQuery?.();
      const values = command.input.ExpressionAttributeValues ?? {};
      const sentKey = command.input.ExclusiveStartKey as Row | undefined;
      if (this.cursorMode === 'repeat' && sentKey !== undefined) {
        return { Items: [], LastEvaluatedKey: clone(sentKey) };
      }
      if (this.cursorMode === 'runaway') {
        this.runaway += 1;
        return { Items: [], LastEvaluatedKey: { ownerId: values[':owner'], noteId: `NOTE#p${this.runaway}` } };
      }
      const rows = [...this.table(command.input).values()]
        .filter((row) => row['ownerId'] === values[':owner'] && typeof row['noteId'] === 'string' &&
          row['noteId'].startsWith(String(values[':prefix'])))
        .sort((left, right) => (String(left['noteId']) < String(right['noteId']) ? -1 : 1));
      const startKey = command.input.ExclusiveStartKey as Row | undefined;
      const start = startKey === undefined
        ? 0
        : rows.findIndex((row) => row['noteId'] === startKey['noteId']) + 1;
      const limit = Number.isFinite(this.pageSize) ? this.pageSize : rows.length - start;
      const page = rows.slice(start, start + limit);
      const last = page[page.length - 1];
      // A projected query returns only the listed attributes; an unlisted attribute is absent,
      // exactly like DynamoDB, so a marker read cannot lean on fields it never fetched.
      const project = (item: Row): Row => {
        const expression = command.input.ProjectionExpression;
        if (expression === undefined || !this.applyProjection) return clone(item);
        const names = command.input.ExpressionAttributeNames ?? {};
        const wanted = expression.split(',').map((token) => token.trim())
          .map((token) => (token.startsWith('#') ? names[token] ?? token : token));
        const projected: Row = {};
        for (const attribute of wanted) {
          if (Object.hasOwn(item, attribute)) projected[attribute] = clone(item[attribute]);
        }
        return projected;
      };
      return {
        Items: page.map(project),
        ...(start + page.length < rows.length && last !== undefined
          ? { LastEvaluatedKey: { ownerId: last['ownerId'], noteId: last['noteId'] } }
          : {}),
      };
    }
    if (command instanceof UpdateCommand) {
      const table = this.table(command.input);
      const key = rowKey(command.input.Key as Row);
      const current = table.get(key);
      if (!this.passes(command.input, current)) throw conditionalFailure();
      table.set(key, applyUpdate(current ?? clone(command.input.Key as Row), command.input));
      return {};
    }
    if (command instanceof TransactWriteCommand) {
      const staged = new Map<string, Readonly<{ table: Map<string, Row>; key: string; item: Row | null }>>();
      const reasons: Row[] = [];
      let failed = false;
      for (const entry of command.input.TransactItems ?? []) {
        if (failed) {
          reasons.push({ Code: 'None' });
          continue;
        }
        const target = entry.ConditionCheck ?? entry.Update ?? entry.Delete ?? entry.Put;
        if (target === undefined) throw new Error('empty transaction item');
        const table = this.table(target);
        const key = rowKey((entry.Put?.Item ?? (target as { Key?: Row }).Key) as Row);
        const current = table.get(key);
        if (!this.passes(target, current)) {
          failed = true;
          reasons.push({ Code: 'ConditionalCheckFailed' });
          continue;
        }
        reasons.push({ Code: 'None' });
        if (entry.Put !== undefined) {
          staged.set(key, { table, key, item: clone(entry.Put.Item as Row) });
        } else if (entry.Update !== undefined) {
          staged.set(key, { table, key, item: applyUpdate(current ?? clone(entry.Update.Key as Row), entry.Update) });
        } else if (entry.Delete !== undefined) {
          staged.set(key, { table, key, item: null });
        }
      }
      if (failed) throw transactionCanceled(reasons);
      for (const { table, key, item } of staged.values()) {
        if (item === null) table.delete(key);
        else table.set(key, item);
      }
      return {};
    }
    throw new Error('unsupported command');
  }
}

// ---------------------------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------------------------

const noteRow = (id: string, overrides: Row = {}): Row => ({
  ownerId: OWNER_KEY, noteId: `NOTE#${id}`, id, title: `title-${id}`, content: `body-${id}`,
  revision: 1, createdAt: '2026-10-12T00:00:00.000Z', serverUpdatedAt: '2026-10-12T00:00:01.000Z',
  pinnedAt: null, deletedAt: null, protected: false, protectionRevision: 0, ...overrides,
});
const protectionRow = (id: string, overrides: Row = {}): Row => ({
  ownerId: OWNER_KEY, noteId: `PROTECTION#${id}`, canonicalOwnerId: OWNER, targetNoteId: id,
  enabled: false, revision: 0, verifier: null, ...overrides,
});
const metaRow = (sequence: number): Row => ({ ownerId: OWNER_KEY, noteId: META_KEY, lastSequence: sequence });
const consentRow = (accepted: boolean, generation: number, version = CONSENT_VERSION): Row => ({
  ownerId: OWNER_KEY, noteId: CONSENT_KEY, accepted, version, generation,
});
const budgetRow = (used: number): Row => ({ ownerId: BUDGET_OWNER_KEY, noteId: BUDGET_SORT_KEY, used });

type Fixture = Readonly<{
  fake: FakeDynamo; store: ReturnType<typeof createIndexStore>; controller: AbortController;
  signal: AbortSignal;
}>;

const makeStore = (notes: readonly Row[] = [], state: readonly Row[] = []): Fixture => {
  const fake = new FakeDynamo();
  for (const row of notes) fake.seed('notes', row);
  for (const row of state) fake.seed('state', row);
  const controller = new AbortController();
  let counter = 0;
  const store = createIndexStore(
    { notesTable: NOTES_TABLE, stateTable: STATE_TABLE, region: 'us-east-1' },
    { client: fake, id: () => `lease-${++counter}` },
  );
  return { fake, store, controller, signal: controller.signal };
};

const manifestFor = (state: IndexState, version: string): Manifest => Object.freeze({
  ownerId: state.ownerId,
  generation: (state.manifest?.generation ?? 0) + 1,
  version,
  fingerprint: fingerprint(state),
  consentGeneration: state.consent.generation,
  accountEpoch: state.accountEpoch,
  status: 'READY',
  snapshotKey: `rag/snapshots/${sha256Hex(state.ownerId)}/${version}.json`,
  checksum: sha256Hex(`checksum-${version}`),
  policyIdentity: sha256Hex('policy'),
});

/** Load then acquire, i.e. exactly what the worker does before a publish. */
const readyStore = async (notes: readonly Row[], state: readonly Row[] = [], now = 1_000) => {
  const fixture = makeStore(notes, state);
  const bound = await fixture.store.load(OWNER, fixture.signal);
  const lease = await fixture.store.acquire(bound, fingerprint(bound), now, fixture.signal);
  assert.ok(lease !== null, 'fixture lease must be acquired');
  return { ...fixture, state: bound, lease, now };
};

const expectFailure = (error: unknown, code: string, retryable: boolean): boolean => {
  assert.ok(error instanceof IndexFailure, `expected IndexFailure, got ${String(error)}`);
  assert.equal(error.code, code);
  assert.equal(error.retryable, retryable);
  return true;
};

const expectLoadFailure = async (
  rows: readonly Row[], code = 'INVALID_STATE', retryable = false,
): Promise<void> => {
  const { store, signal } = makeStore(rows);
  await assert.rejects(store.load(OWNER, signal), (error) => expectFailure(error, code, retryable));
};

const callsOf = (fake: FakeDynamo, name: string): Call[] =>
  fake.calls.filter((call) => call.name === name);

/** Narrows the optional interface member: the production store always exposes the light read. */
const markersReaderOf = (store: ReturnType<typeof createIndexStore>) => {
  assert.ok(store.loadMarkers !== undefined, 'the production store exposes loadMarkers');
  return store.loadMarkers;
};

// ---------------------------------------------------------------------------------------------
// Construction and load
// ---------------------------------------------------------------------------------------------

test('createIndexStore rejects an unusable configuration', () => {
  const client = new FakeDynamo();
  for (const config of [
    { notesTable: '', stateTable: STATE_TABLE, region: 'us-east-1' },
    { notesTable: NOTES_TABLE, stateTable: '', region: 'us-east-1' },
    { notesTable: NOTES_TABLE, stateTable: STATE_TABLE, region: 'not a region' },
  ]) {
    assert.throws(() => createIndexStore(config, { client }),
      (error) => expectFailure(error, 'INVALID_STATE', false));
  }
});

test('load maps canonical notes, folds protection and paginates with strong reads', async () => {
  const { fake, store, signal } = makeStore([
    metaRow(7), consentRow(true, 3),
    noteRow('a'),
    noteRow('b', { revision: 2, deletedAt: '2026-10-12T01:00:00.000Z', protectionRevision: 3 }),
    protectionRow('b', { enabled: false, revision: 3 }),
  ]);
  fake.pageSize = 1;
  const state = await store.load(OWNER, signal);

  assert.equal(state.ownerId, OWNER);
  assert.equal(state.accountEpoch, 7);
  assert.deepEqual(state.consent, { accepted: true, version: CONSENT_VERSION, generation: 3 });
  assert.equal(state.manifest, null);
  assert.deepEqual(
    state.notes.map((note) => [note.noteId, note.revision, note.deleted, note.protected,
      note.synced, note.available, note.protectionRevision]),
    [['a', 1, false, false, true, true, 0], ['b', 2, true, false, true, true, 3]],
  );
  // No attachment, share or incoming-shared field may leak into a canonical IndexNote.
  assert.deepEqual(Object.keys(state.notes[0]).sort(), [
    'available', 'content', 'deleted', 'noteId', 'ownerId', 'protected',
    'protectionRevision', 'revision', 'synced', 'title',
  ]);

  assert.equal(state.notes[0].title, 'title-a');
  assert.equal(state.notes[0].content, 'body-a');

  const queries = callsOf(fake, 'QueryCommand');
  assert.deepEqual(queries.map((call) => call.input.ExpressionAttributeValues[':prefix']),
    ['NOTE#', 'NOTE#', 'PROTECTION#']);
  assert.ok(queries.every((call) => call.input.ConsistentRead === true));
  assert.deepEqual(queries.map((call) => call.input.ExpressionAttributeValues[':owner']),
    [OWNER_KEY, OWNER_KEY, OWNER_KEY]);
  assert.equal(queries[0].input.ExclusiveStartKey, undefined);
  assert.deepEqual(queries[1].input.ExclusiveStartKey, { ownerId: OWNER_KEY, noteId: 'NOTE#a' });
  const gets = callsOf(fake, 'GetCommand');
  assert.ok(gets.every((call) => call.input.ConsistentRead === true));
  assert.ok(fake.calls.every((call) => call.signal === signal));
  // load is read-only: neither table ever sees a write from a load.
  assert.ok(fake.calls.every((call) => call.name === 'GetCommand' || call.name === 'QueryCommand'));
});

test('load ignores incoming shared projections and keeps foreign rows out of the state', async () => {
  const { store, signal } = makeStore([
    noteRow('own'),
    noteRow('shared', { canonicalOwnerId: 'someone-else', title: 'not canonical' }),
    { ownerId: OWNER_KEY, noteId: 'SHARED#row', text: 'noise' },
    { ownerId: OWNER_KEY, noteId: 'CHANGE#9', text: 'noise' },
  ]);
  const state = await store.load(OWNER, signal);
  assert.deepEqual(state.notes.map((note) => note.noteId), ['own']);
  assert.equal(state.notes[0].synced, true);
  assert.equal(state.notes[0].available, true);
});

test('load fails closed on an inconsistent canonical namespace or protection pair', async () => {
  // The stored key and the snapshot identity must agree.
  await expectLoadFailure([{ ...noteRow('a'), noteId: 'NOTE#b' }]);
  // The sync codec is the only accepted note shape.
  await expectLoadFailure([noteRow('a', { title: 42 })]);
  await expectLoadFailure([noteRow('a', { revision: 0 })]);
  await expectLoadFailure([noteRow('a', { deletedAt: 7 })]);
  // A protection row must belong to the actor, name its note and match the note flags.
  await expectLoadFailure([noteRow('a'), protectionRow('a', { canonicalOwnerId: 'other' })]);
  await expectLoadFailure([noteRow('a'), protectionRow('a', { targetNoteId: 'b' })]);
  await expectLoadFailure([noteRow('a'), protectionRow('a', { enabled: true, revision: 1, verifier: 'opaque-hash' })]);
  await expectLoadFailure([noteRow('a', { protected: true, protectionRevision: 2 })]);
  await expectLoadFailure([noteRow('a', { protected: true, protectionRevision: 1 }),
    protectionRow('a', { enabled: true, revision: 2, verifier: 'opaque-hash' })]);
  await expectLoadFailure([noteRow('a'), protectionRow('a', { canonicalOwnerId: undefined })]);
  await expectLoadFailure([noteRow('a'), protectionRow('a', { verifier: 'unexpected' })]);
  await expectLoadFailure([noteRow('a'), protectionRow('a', { enabled: true, revision: 0 })]);
});

test('load returns the stored manifest and fails closed on an invalid one', async () => {
  const manifest = manifestFor({
    ownerId: OWNER, accountEpoch: 5, consent: { accepted: true, version: CONSENT_VERSION, generation: 1 },
    notes: [], manifest: null,
  }, 'v2');
  const stored = { ...manifest, ownerId: OWNER_KEY, noteId: MANIFEST_SORT_KEY,
    createdAt: 1, updatedAt: 2, publishedAt: 3, ttl: 4 };
  const { store, signal } = makeStore([metaRow(5), consentRow(true, 1)], [stored]);
  const state = await store.load(OWNER, signal);
  assert.deepEqual(state.manifest, manifest);

  const { checksum, ...withoutChecksum } = manifest;
  assert.equal(typeof checksum, 'string');
  const invalid = makeStore([], [{ ...withoutChecksum, ownerId: OWNER_KEY, noteId: MANIFEST_SORT_KEY }]);
  await assert.rejects(invalid.store.load(OWNER, invalid.signal),
    (error) => expectFailure(error, 'INVALID_STATE', false));
  const extra = makeStore([], [{ ...manifest, ownerId: OWNER_KEY, noteId: MANIFEST_SORT_KEY, bogus: 1 }]);
  await assert.rejects(extra.store.load(OWNER, extra.signal),
    (error) => expectFailure(error, 'INVALID_STATE', false));
});

test('load reports SOURCE_CHANGED when the epoch or the consent moves under it', async () => {
  const epoch = makeStore([metaRow(1)]);
  epoch.fake.beforeQuery = () => {
    (epoch.fake.row('notes', META_KEY) as Row)['lastSequence'] = 2;
  };
  await assert.rejects(epoch.store.load(OWNER, epoch.signal),
    (error) => expectFailure(error, 'SOURCE_CHANGED', true));

  const consent = makeStore([consentRow(true, 1)]);
  consent.fake.beforeQuery = () => {
    (consent.fake.row('notes', CONSENT_KEY) as Row)['generation'] = 2;
  };
  await assert.rejects(consent.store.load(OWNER, consent.signal),
    (error) => expectFailure(error, 'SOURCE_CHANGED', true));
});

// ---------------------------------------------------------------------------------------------
// loadMarkers: the light mid-flight freshness read (Patch 5A)
// ---------------------------------------------------------------------------------------------

test('loadMarkers returns exactly the markers of a full load over identical tables', async () => {
  const { fake, store, signal } = makeStore([
    metaRow(9), consentRow(true, 2),
    // A legacy NOTE row: the canonical writer never stores `contentAvailable`, so the attribute
    // is absent and both readers must derive `available: true` from the codec default.
    noteRow('a'),
    noteRow('b', { revision: 2, deletedAt: '2026-10-12T01:00:00.000Z' }),
    noteRow('c', { protected: true, protectionRevision: 1 }),
    protectionRow('c', { enabled: true, revision: 1, verifier: 'opaque-hash' }),
    noteRow('d', { canonicalOwnerId: 'someone-else', title: 'not canonical' }),
    // A PROTECTION row whose NOTE row was hard-deleted: an orphan on the store side too.
    protectionRow('orphan', { enabled: true, revision: 1, verifier: 'opaque-hash' }),
  ]);
  // Make the fake honor the marker projections, so loadMarkers truly sees projected rows only.
  fake.applyProjection = true;
  const state = await store.load(OWNER, signal);
  const beforeMarkerRead = fake.calls.length;
  const markers = await markersReaderOf(store)(OWNER, signal);

  assert.ok(sameMarkers(markers, markersOf(state)), 'loadMarkers equals markersOf(load(...))');
  assert.deepEqual(markers.notes, [
    { noteId: 'a', revision: 1, deleted: false, available: true },
    { noteId: 'b', revision: 2, deleted: true, available: true },
    { noteId: 'c', revision: 1, deleted: false, available: true },
  ]);
  // The foreign projection and the orphan PROTECTION row are invisible on both sides.
  assert.deepEqual(markers.protections, [{ noteId: 'c', enabled: true, revision: 1 }]);
  assert.equal(markers.ownerId, OWNER);
  assert.equal(markers.accountEpoch, 9);
  assert.deepEqual(markers.consent, { accepted: true, version: CONSENT_VERSION, generation: 2 });

  // The marker queries fetch only marker fields: no title or content ever crosses the wire.
  const markerCalls = fake.calls.slice(beforeMarkerRead);
  assert.ok(markerCalls.every((call) => call.name === 'GetCommand' || call.name === 'QueryCommand'),
    'loadMarkers is read-only');
  const markerQueries = markerCalls.filter((call) => call.name === 'QueryCommand');
  assert.equal(markerQueries.length, 2);
  for (const call of markerQueries) {
    const expression = call.input.ProjectionExpression as string;
    assert.equal(typeof expression, 'string');
    const names = call.input.ExpressionAttributeNames ?? {};
    const resolved = expression.split(',').map((token: string) => token.trim())
      .map((token: string) => (token.startsWith('#') ? names[token] ?? token : token));
    assert.equal(resolved.includes('title'), false);
    assert.equal(resolved.includes('content'), false);
    assert.equal(call.input.ConsistentRead, true);
  }
});

test('loadMarkers reports SOURCE_CHANGED when the epoch or the consent moves under it', async () => {
  const epoch = makeStore([metaRow(1), noteRow('a')]);
  epoch.fake.beforeQuery = () => {
    (epoch.fake.row('notes', META_KEY) as Row)['lastSequence'] = 2;
  };
  await assert.rejects(markersReaderOf(epoch.store)(OWNER, epoch.signal),
    (error) => expectFailure(error, 'SOURCE_CHANGED', true));

  const consent = makeStore([consentRow(true, 1), noteRow('a')]);
  consent.fake.beforeQuery = () => {
    (consent.fake.row('notes', CONSENT_KEY) as Row)['generation'] = 2;
  };
  await assert.rejects(markersReaderOf(consent.store)(OWNER, consent.signal),
    (error) => expectFailure(error, 'SOURCE_CHANGED', true));
});

test('loadMarkers fails closed on a malformed projected row', async () => {
  const malformed: readonly Row[] = [
    noteRow('a', { revision: 0 }),
    noteRow('a', { revision: 2.5 }),
    noteRow('a', { deletedAt: 7 }),
    protectionRow('a', { enabled: 'yes' }),
    protectionRow('a', { revision: -1 }),
    protectionRow('a', { canonicalOwnerId: 'other' }),
  ];
  for (const row of malformed) {
    const fixture = makeStore([row]);
    await assert.rejects(markersReaderOf(fixture.store)(OWNER, fixture.signal),
      (error) => expectFailure(error, 'INVALID_STATE', false));
  }
});

test('load maps transport failures to a typed retryable-only taxonomy', async () => {
  const fixture = makeStore([noteRow('a')]);
  fixture.fake.failNext = () => serviceFailure('ProvisionedThroughputExceededException', 400);
  await assert.rejects(fixture.store.load(OWNER, fixture.signal),
    (error) => expectFailure(error, 'RATE_LIMITED', true));

  fixture.fake.failNext = () => serviceFailure('InternalServerError', 500);
  await assert.rejects(fixture.store.load(OWNER, fixture.signal),
    (error) => expectFailure(error, 'PROVIDER_UNAVAILABLE', true));

  fixture.fake.failNext = () => serviceFailure('ValidationException', 400);
  await assert.rejects(fixture.store.load(OWNER, fixture.signal),
    (error) => expectFailure(error, 'INVALID_INPUT', false));

  // Bounded reads: a repeated cursor and a cursor that never terminates both fail closed.
  const repeated = makeStore([noteRow('a'), noteRow('b')]);
  repeated.fake.pageSize = 1;
  repeated.fake.cursorMode = 'repeat';
  await assert.rejects(repeated.store.load(OWNER, repeated.signal),
    (error) => expectFailure(error, 'INVALID_STATE', false));

  const runaway = makeStore([noteRow('a')]);
  runaway.fake.cursorMode = 'runaway';
  await assert.rejects(runaway.store.load(OWNER, runaway.signal),
    (error) => expectFailure(error, 'INVALID_STATE', false));
  assert.equal(callsOf(runaway.fake, 'QueryCommand').length, MAX_QUERY_PAGES);
});

// ---------------------------------------------------------------------------------------------
// acquire
// ---------------------------------------------------------------------------------------------

test('acquire binds the lease to the recomputed fingerprint and respects expiry', async () => {
  const { fake, store, signal } = makeStore([noteRow('a')]);
  const state = await store.load(OWNER, signal);
  const bound = fingerprint(state);
  const now = 1_000_000;
  const lease = await store.acquire(state, bound, now, signal);
  assert.ok(lease !== null);
  assert.deepEqual({ ...lease }, { token: 'lease-1', expiresAt: now + LEASE_MS, fingerprint: bound });
  assert.deepEqual(fake.row('state', LEASE_SORT_KEY), {
    ownerId: OWNER_KEY, noteId: LEASE_SORT_KEY, token: 'lease-1',
    fingerprint: bound, expiresAt: now + LEASE_MS, status: 'RUNNING',
  });
  const update = callsOf(fake, 'UpdateCommand').at(-1);
  assert.equal(update?.input.Key.ownerId, OWNER_KEY);
  assert.equal(update?.input.TableName, STATE_TABLE);
  assert.equal(update?.input.ConditionExpression,
    'attribute_not_exists(noteId) OR attribute_not_exists(expiresAt) OR expiresAt <= :now');

  // A live lease collides; the same fingerprint at the exact expiry wins again.
  assert.equal(await store.acquire(state, bound, now + 1, signal), null);
  const next = await store.acquire(state, bound, now + LEASE_MS, signal);
  assert.ok(next !== null);
  assert.notEqual(next.token, lease.token);
  assert.equal(fake.row('state', LEASE_SORT_KEY)?.['token'], next.token);
  assert.equal(next.expiresAt, now + LEASE_MS + LEASE_MS);
});

test('acquire treats a released lease as free and refuses a foreign fingerprint', async () => {
  const released: Row = {
    ownerId: OWNER_KEY, noteId: LEASE_SORT_KEY, token: 'old', fingerprint: sha256Hex('old'),
    status: 'SUCCEEDED', code: 'READY', updatedAt: 5,
  };
  const { store, signal } = makeStore([noteRow('a')], [released]);
  const state = await store.load(OWNER, signal);
  const lease = await store.acquire(state, fingerprint(state), 10, signal);
  assert.equal(lease?.token, 'lease-1');

  await assert.rejects(store.acquire(state, sha256Hex('other'), 11, signal),
    (error) => expectFailure(error, 'INVALID_STATE', false));
  const tampered = { ...state, notes: state.notes.map((note) => ({ ...note, title: 'tampered' })) };
  await assert.rejects(store.acquire(tampered, fingerprint(state), 12, signal),
    (error) => expectFailure(error, 'INVALID_STATE', false));
});

test('acquire returns null only for a conditional loss', async () => {
  const { fake, store, signal } = makeStore([noteRow('a')]);
  const state = await store.load(OWNER, signal);
  const bound = fingerprint(state);
  fake.failNext = () => conditionalFailure();
  assert.equal(await store.acquire(state, bound, 1, signal), null);
  fake.failNext = () => serviceFailure('ThrottlingException', 400);
  await assert.rejects(store.acquire(state, bound, 1, signal),
    (error) => expectFailure(error, 'RATE_LIMITED', true));
});

// ---------------------------------------------------------------------------------------------
// publish
// ---------------------------------------------------------------------------------------------

test('publish commits manifest, lease status and a durable retirement record atomically', async () => {
  const first = await readyStore([noteRow('a'), metaRow(4), consentRow(true, 2)]);
  const manifest1 = manifestFor(first.state, 'v1');
  assert.equal(await first.store.publish(first.state, first.lease, manifest1, first.now, first.signal), true);
  assert.deepEqual(first.fake.row('state', MANIFEST_SORT_KEY), {
    ...manifest1, ownerId: OWNER_KEY, noteId: MANIFEST_SORT_KEY,
  });
  assert.equal(first.fake.row('state', LEASE_SORT_KEY)?.['status'], 'PUBLISHED');
  assert.equal(first.fake.row('state', `${RETIRE_SORT_KEY_PREFIX}v1`), undefined);

  const transaction1 = callsOf(first.fake, 'TransactWriteCommand').at(-1);
  const items1 = transaction1?.input.TransactItems as any[];
  assert.equal(items1.length, 4);
  assert.equal(items1[0].ConditionCheck.TableName, NOTES_TABLE);
  assert.equal(items1[0].ConditionCheck.Key.noteId, META_KEY);
  assert.equal(items1[1].ConditionCheck.Key.noteId, CONSENT_KEY);
  assert.equal(items1[2].Update.TableName, STATE_TABLE);
  assert.equal(items1[2].Update.ConditionExpression,
    '#token = :token AND fingerprint = :fingerprint AND expiresAt > :now');
  assert.equal(items1[3].Put.ConditionExpression, 'attribute_not_exists(noteId)');
  // No two operations in one transaction may target the same item.
  const targets = items1.map((entry: any) => {
    const target = entry.ConditionCheck ?? entry.Update ?? entry.Delete ?? entry.Put;
    const key = entry.Put?.Item ?? target.Key;
    return `${target.TableName}/${String(key.noteId)}`;
  });
  assert.equal(new Set(targets).size, targets.length);

  // The worker releases the published lease before the next generation starts.
  await first.store.finish(OWNER, first.lease, 'SUCCEEDED', 'READY', 1_500, first.signal);
  const state2 = await first.store.load(OWNER, first.signal);
  assert.deepEqual(state2.manifest, manifest1);
  const lease2 = await first.store.acquire(state2, fingerprint(state2), 2_000, first.signal);
  assert.ok(lease2 !== null);
  const manifest2 = manifestFor(state2, 'v2');
  assert.equal(await first.store.publish(state2, lease2, manifest2, 2_000, first.signal), true);

  const retired = first.fake.row('state', `${RETIRE_SORT_KEY_PREFIX}v1`);
  assert.deepEqual(retired?.['manifest'], manifest1);
  assert.equal(typeof retired?.['createdAt'], 'number');
  assert.equal(Object.hasOwn(retired as Row, 'ttl'), false);
  const items2 = callsOf(first.fake, 'TransactWriteCommand').at(-1)?.input.TransactItems as any[];
  assert.equal(items2.length, 5);
  assert.equal(items2[3].Put.ConditionExpression, 'generation = :oldGeneration');
  assert.equal(items2[3].Put.ExpressionAttributeValues[':oldGeneration'], 1);
});

test('publish returns false for each conditional loss: token, expiry, epoch, consent, generation', async () => {
  const cases: readonly string[] = ['token', 'expiry', 'epoch', 'consent', 'generation'];
  for (const scenario of cases) {
    const fixture = await readyStore([noteRow('a'), metaRow(2), consentRow(true, 1)]);
    const manifest = manifestFor(fixture.state, 'v1');
    let now = fixture.now;
    if (scenario === 'token') {
      (fixture.fake.row('state', LEASE_SORT_KEY) as Row)['token'] = 'newer-lease';
    } else if (scenario === 'expiry') {
      now = fixture.lease.expiresAt;
    } else if (scenario === 'epoch') {
      (fixture.fake.row('notes', META_KEY) as Row)['lastSequence'] = 3;
    } else if (scenario === 'consent') {
      (fixture.fake.row('notes', CONSENT_KEY) as Row)['generation'] = 2;
    } else {
      assert.equal(await fixture.store.publish(fixture.state, fixture.lease, manifest, now, fixture.signal), true);
      await fixture.store.finish(OWNER, fixture.lease, 'SUCCEEDED', 'READY', 1_500, fixture.signal);
      const state2 = await fixture.store.load(OWNER, fixture.signal);
      const lease2 = await fixture.store.acquire(state2, fingerprint(state2), 2_000, fixture.signal);
      assert.ok(lease2 !== null);
      (fixture.fake.row('state', MANIFEST_SORT_KEY) as Row)['generation'] = 9;
      assert.equal(await fixture.store.publish(state2, lease2, manifestFor(state2, 'v2'), 2_000, fixture.signal), false);
      continue;
    }
    assert.equal(await fixture.store.publish(fixture.state, fixture.lease, manifest, now, fixture.signal), false,
      `scenario ${scenario} must be a CAS loss`);
  }
});

test('publish condition-checks the default consent by absence or exact value', async () => {
  const absent = await readyStore([noteRow('a')]);
  assert.equal(absent.state.consent.accepted, false);
  assert.equal(await absent.store.publish(absent.state, absent.lease, manifestFor(absent.state, 'v1'),
    absent.now, absent.signal), true);

  const exact = await readyStore([noteRow('a'), consentRow(false, 0)]);
  assert.equal(await exact.store.publish(exact.state, exact.lease, manifestFor(exact.state, 'v1'),
    exact.now, exact.signal), true);
  const exactTransaction = callsOf(exact.fake, 'TransactWriteCommand').at(-1);
  assert.equal(exactTransaction?.input.TransactItems[1].ConditionCheck.ConditionExpression,
    'attribute_not_exists(noteId) OR (accepted = :accepted AND #version = :version AND generation = :generation)');

  // A row that grants consent where the bound state saw the default must lose the CAS.
  const moved = await readyStore([noteRow('a')]);
  moved.fake.seed('notes', consentRow(true, 0));
  assert.equal(await moved.store.publish(moved.state, moved.lease, manifestFor(moved.state, 'v1'),
    moved.now, moved.signal), false);
});

test('publish accepts an absent META for epoch 0 and rejects a moved sequence', async () => {
  const empty = await readyStore([noteRow('a')]);
  assert.equal(empty.state.accountEpoch, 0);
  assert.equal(await empty.store.publish(empty.state, empty.lease, manifestFor(empty.state, 'v1'),
    empty.now, empty.signal), true);

  const zero = await readyStore([noteRow('a'), { ownerId: OWNER_KEY, noteId: META_KEY, lastSequence: 0 }]);
  assert.equal(await zero.store.publish(zero.state, zero.lease, manifestFor(zero.state, 'v1'),
    zero.now, zero.signal), true);

  const moved = await readyStore([noteRow('a'), metaRow(1)]);
  (moved.fake.row('notes', META_KEY) as Row)['lastSequence'] = 2;
  assert.equal(await moved.store.publish(moved.state, moved.lease, manifestFor(moved.state, 'v1'),
    moved.now, moved.signal), false);
});

test('publish fails closed on an incoherent lease, state or manifest before touching DynamoDB', async () => {
  const fixture = await readyStore([noteRow('a'), metaRow(2), consentRow(true, 1)]);
  const good = manifestFor(fixture.state, 'v1');
  const cases: readonly Readonly<{ lease: typeof fixture.lease; manifest: Manifest }>[] = [
    { lease: fixture.lease, manifest: { ...good, checksum: 'not-a-digest' } },
    { lease: { ...fixture.lease, fingerprint: sha256Hex('other') }, manifest: good },
    { lease: fixture.lease, manifest: { ...good, generation: 7 } },
    { lease: fixture.lease, manifest: { ...good, accountEpoch: 3 } },
    { lease: fixture.lease, manifest: { ...good, consentGeneration: 4 } },
    { lease: fixture.lease, manifest: { ...good, ownerId: 'other' } },
  ];
  for (const entry of cases) {
    await assert.rejects(
      fixture.store.publish(fixture.state, entry.lease, entry.manifest, fixture.now, fixture.signal),
      (error) => expectFailure(error, 'INVALID_STATE', false),
    );
  }
  assert.equal(callsOf(fixture.fake, 'TransactWriteCommand').length, 0);
});

test('publish replays an unknown transaction cancellation instead of reporting a CAS loss', async () => {
  const fixture = await readyStore([noteRow('a')]);
  const manifest = manifestFor(fixture.state, 'v1');
  fixture.fake.failNext = () => transactionCanceled([{ Code: 'ConditionalCheckFailed' }]);
  assert.equal(await fixture.store.publish(fixture.state, fixture.lease, manifest,
    fixture.now, fixture.signal), false);

  fixture.fake.failNext = () => transactionCanceled([{ Code: 'ThrottlingError' }]);
  await assert.rejects(
    fixture.store.publish(fixture.state, fixture.lease, manifest, fixture.now, fixture.signal),
    (error) => expectFailure(error, 'PROVIDER_UNAVAILABLE', true));

  fixture.fake.failNext = () => transactionCanceled([]);
  await assert.rejects(
    fixture.store.publish(fixture.state, fixture.lease, manifest, fixture.now, fixture.signal),
    (error) => expectFailure(error, 'PROVIDER_UNAVAILABLE', true));

  fixture.fake.failNext = () => serviceFailure('InternalServerError', 500);
  await assert.rejects(
    fixture.store.publish(fixture.state, fixture.lease, manifest, fixture.now, fixture.signal),
    (error) => expectFailure(error, 'PROVIDER_UNAVAILABLE', true));
});

// ---------------------------------------------------------------------------------------------
// finish and the global budget
// ---------------------------------------------------------------------------------------------

test('finish releases the lease by token, keeps the token and never touches canonical notes', async () => {
  const fixture = await readyStore([noteRow('a')]);
  await fixture.store.finish(OWNER, fixture.lease, 'SUCCEEDED', 'READY', 2_000, fixture.signal);
  const released = fixture.fake.row('state', LEASE_SORT_KEY) as Row;
  assert.equal(released['status'], 'SUCCEEDED');
  assert.equal(released['code'], 'READY');
  assert.equal(released['updatedAt'], 2_000);
  assert.equal(released['token'], fixture.lease.token);
  assert.equal(Object.hasOwn(released, 'expiresAt'), false);

  const next = await fixture.store.acquire(fixture.state, fingerprint(fixture.state), 2_001, fixture.signal);
  assert.equal(next?.token, 'lease-2');
  // An old worker's release must not clear the newer lease.
  await fixture.store.finish(OWNER, fixture.lease, 'FAILED', 'TIMEOUT', 2_002, fixture.signal);
  const stillLive = fixture.fake.row('state', LEASE_SORT_KEY) as Row;
  assert.equal(stillLive['token'], 'lease-2');
  assert.equal(stillLive['status'], 'RUNNING');
  assert.ok(callsOf(fixture.fake, 'UpdateCommand').every((call) => call.input.TableName === STATE_TABLE));
  assert.equal(callsOf(fixture.fake, 'TransactWriteCommand').length, 0);
});

test('reserveEmbedding enforces one global 20-call budget across owners', async () => {
  const { fake, store, signal } = makeStore();
  for (let index = 0; index < SMOKE_EMBED_LIMIT; index += 1) {
    await store.reserveEmbedding(index % 2 === 0 ? 'u1' : 'u2', signal);
  }
  const counter = fake.row('state', BUDGET_SORT_KEY, BUDGET_OWNER_KEY) as Row;
  assert.equal(counter['used'], SMOKE_EMBED_LIMIT);
  assert.equal(Object.hasOwn(counter, 'ttl'), false);
  assert.ok(callsOf(fake, 'UpdateCommand').every((call) =>
    call.input.Key.ownerId === BUDGET_OWNER_KEY && call.input.Key.noteId === BUDGET_SORT_KEY));
  assert.equal(callsOf(fake, 'UpdateCommand').at(-1)?.input.UpdateExpression, 'ADD used :one');

  await assert.rejects(store.reserveEmbedding('u3', signal),
    (error) => expectFailure(error, 'BUDGET_EXHAUSTED', false));
  await assert.rejects(store.reserveEmbedding('u1', signal),
    (error) => expectFailure(error, 'BUDGET_EXHAUSTED', false));
  // Terminal: the counter is never reset or overridden by a user request.
  assert.equal((fake.row('state', BUDGET_SORT_KEY, BUDGET_OWNER_KEY) as Row)['used'], SMOKE_EMBED_LIMIT);
});

// ---------------------------------------------------------------------------------------------
// Cross-cutting: deadline and signal propagation
// ---------------------------------------------------------------------------------------------

test('every port call carries the caller signal and an aborted deadline never reaches DynamoDB', async () => {
  const fixture = await readyStore([noteRow('a')]);
  await fixture.store.publish(fixture.state, fixture.lease, manifestFor(fixture.state, 'v1'),
    fixture.now, fixture.signal);
  await fixture.store.finish(OWNER, fixture.lease, 'SUCCEEDED', 'READY', 1_001, fixture.signal);
  await fixture.store.reserveEmbedding(OWNER, fixture.signal);
  assert.ok(fixture.fake.calls.length > 0);
  assert.ok(fixture.fake.calls.every((call) => call.signal === fixture.signal));

  const aborted = new AbortController();
  aborted.abort();
  const before = fixture.fake.calls.length;
  const signal = aborted.signal;
  await assert.rejects(fixture.store.load(OWNER, signal),
    (error) => expectFailure(error, 'TIMEOUT', true));
  await assert.rejects(fixture.store.acquire(fixture.state, fingerprint(fixture.state), 1, signal),
    (error) => expectFailure(error, 'TIMEOUT', true));
  await assert.rejects(fixture.store.publish(fixture.state, fixture.lease, manifestFor(fixture.state, 'v1'), 1, signal),
    (error) => expectFailure(error, 'TIMEOUT', true));
  await assert.rejects(fixture.store.finish(OWNER, fixture.lease, 'FAILED', 'TIMEOUT', 1, signal),
    (error) => expectFailure(error, 'TIMEOUT', true));
  await assert.rejects(fixture.store.reserveEmbedding(OWNER, signal),
    (error) => expectFailure(error, 'TIMEOUT', true));
  assert.equal(fixture.fake.calls.length, before);
  await assert.rejects(fixture.store.load(OWNER, undefined as unknown as AbortSignal),
    (error) => expectFailure(error, 'INVALID_INPUT', false));
});

test('deleting an established META after the last read rejects publication',async()=>{
  const r=await readyStore([noteRow('a'),metaRow(1)]);
  r.fake.notes.delete(rowKey(metaRow(1)));
  assert.equal(await r.store.publish(r.state,r.lease,manifestFor(r.state,'v1'),r.now,r.signal),false);
});
test('hard-deleted note with a leftover protection row contributes no document',async()=>{
  const fake=new FakeDynamo();
  fake.seed('notes',protectionRow('a'));
  const store=createIndexStore({notesTable:'notes',stateTable:'state',region:'ap-southeast-1'},{client:fake});
  assert.deepEqual((await store.load(OWNER,new AbortController().signal)).notes,[]);
});
