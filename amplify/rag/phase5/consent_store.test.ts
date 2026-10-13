/**
 * Phase 5 consent store tests: the canonical key, default-off absence, the generation
 * compare-and-set (including two concurrent writers), fail-closed foreign/ttl/malformed rows,
 * exact write validation and transport mapping. A fake document client evaluates the conditions
 * this store issues; no AWS, network or provider call is made.
 *
 * The condition half is deliberate: the update compares the grant the strongly consistent GET
 * captured (`accepted`, `version`, `generation`, no `ttl`, no foreign projection), and the
 * absence branch exists only for `expectedGeneration: 0`. A row deleted, rewritten or corrupted
 * between the read and the update therefore conflicts and is never recreated or overwritten.
 *
 * Runner: node --import tsx --test amplify/rag/phase5/consent_store.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { GetCommand, TransactWriteCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import { CONSENT_VERSION } from '../contract';
import { CONSENT_SORT_KEY, OWNER_KEY_PREFIX } from '../indexing/jobs';
import { DEFAULT_CONSENT, consentRowKey, createConsentStore } from './consent_store';
import type { ConsentCommand, ConsentPort, ConsentSendOptions, ConsentStore } from './consent_store';
import { RagFailure } from '../types';

const ACTOR = '00000001-0000-4000-8000-000000000001';
const OTHER = '00000002-0000-4000-8000-000000000002';
const ROW = consentRowKey(ACTOR);
const VALID = Object.freeze({ accepted: true, version: CONSENT_VERSION, expectedGeneration: 0 });
/** The same accepted grant one generation later: the existing-row branch of the write. */
const VALID_WITH_GENERATION_1 = Object.freeze({ ...VALID, expectedGeneration: 1 });

type Row = Record<string, unknown>;

const tokenize = (expression: string): string[] =>
  expression.match(/\(|\)|attribute_not_exists\([^)]*\)|attribute_exists\([^)]*\)|[^\s()]+/g) ?? [];

const compare = (left: unknown, operator: string, right: unknown): boolean => {
  switch (operator) {
    case '=':
      // DynamoDB `EQ` compares List/Map values by value; mirror that for the config ConditionCheck.
      if (left !== null && typeof left === 'object' && right !== null && typeof right === 'object') {
        return JSON.stringify(left) === JSON.stringify(right);
      }
      return left === right;
    default: throw new Error(`unsupported operator ${operator}`);
  }
};

/** Evaluates the DynamoDB condition subset this store writes, so the test never restates it. */
const evaluate = (expression: string, item: Row, names: Record<string, string>, values: Row): boolean => {
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

/**
 * Real DynamoDB rejects any request whose `ExpressionAttributeNames`/`Values` carries an entry
 * the condition or update expression never references (`ValidationException`), so a supplied
 * substitution must be used and a referenced one must be supplied. The check reads the command
 * that was actually issued; it never restates which alias this store is expected to use.
 */
const unusedSubstitutions = (input: Row): string[] => {
  const expression = `${String(input['UpdateExpression'] ?? '')} ${String(input['ConditionExpression'] ?? '')}`;
  const usedNames = new Set(expression.match(/#[A-Za-z0-9_]+/g) ?? []);
  const usedValues = new Set(expression.match(/:[A-Za-z0-9_]+/g) ?? []);
  const suppliedNames = Object.keys((input['ExpressionAttributeNames'] ?? {}) as Row);
  const suppliedValues = Object.keys((input['ExpressionAttributeValues'] ?? {}) as Row);
  const violations: string[] = [];
  for (const name of suppliedNames) if (!usedNames.has(name)) violations.push(`${name} is supplied but unused`);
  for (const value of suppliedValues) if (!usedValues.has(value)) violations.push(`${value} is supplied but unused`);
  for (const name of usedNames) if (!suppliedNames.includes(name)) violations.push(`${name} is used but unsupplied`);
  for (const value of usedValues) if (!suppliedValues.includes(value)) violations.push(`${value} is used but unsupplied`);
  return violations;
};

const assertSubstitutionsUsed = (input: Row): void => {
  const violations = unusedSubstitutions(input);
  if (violations.length > 0) assert.fail(violations.join('; '));
};

const fake = (): Readonly<{
  port: ConsentPort;
  items: Map<string, Row>;
  at: (key: Row) => string;
  calls: () => number;
}> => {
  const items = new Map<string, Row>();
  let calls = 0;
  const at = (key: Row): string => `${String(key['ownerId'])}\u0000${String(key['noteId'])}`;
  const port: ConsentPort = {
    async send(command: ConsentCommand): Promise<unknown> {
      calls += 1;
      if (command instanceof GetCommand) {
        // The contract requires one strongly consistent read of the canonical row per GET.
        assert.equal(command.input.ConsistentRead, true);
        assert.equal((command.input.Key as Row)['noteId'], CONSENT_SORT_KEY);
        assert.ok(String((command.input.Key as Row)['ownerId']).startsWith(OWNER_KEY_PREFIX));
        const item = items.get(at(command.input.Key as Row));
        return item === undefined ? {} : { Item: item };
      }
      assert.ok(command instanceof UpdateCommand, 'only a conditional update may write consent');
      const input = (command as UpdateCommand).input;
      assert.equal(String(input.UpdateExpression), 'SET #accepted = :accepted, #version = :version, #generation = :generation');
      assert.equal(typeof input.ConditionExpression, 'string', 'every consent write is conditional');
      const key = input.Key as Row;
      const current = items.get(at(key));
      const names = (input.ExpressionAttributeNames ?? {}) as Record<string, string>;
      const values = (input.ExpressionAttributeValues ?? {}) as Row;
      // The issued condition is evaluated as written; the test never mirrors its logic.
      if (!evaluate(String(input.ConditionExpression), current ?? {}, names, values)) {
        throw Object.assign(new Error('conditional'), { name: 'ConditionalCheckFailedException' });
      }
      const next: Row = {
        ...(current ?? {}),
        ownerId: key['ownerId'],
        noteId: key['noteId'],
        accepted: values[':accepted'],
        version: values[':version'],
        generation: values[':generation'],
      };
      items.set(at(key), next);
      return { Attributes: next };
    },
  };
  return { port, items, at, calls: () => calls };
};

/** Runs `hook` after the first GET of the write path returns, before any update is issued. */
const afterFirstGet = (base: ConsentPort, hook: () => void): ConsentPort => {
  let fired = false;
  return {
    async send(command: ConsentCommand, options?: ConsentSendOptions): Promise<unknown> {
      const result = await base.send(command, options);
      if (!fired && command instanceof GetCommand) {
        fired = true;
        hook();
      }
      return result;
    },
  };
};

/** Records every `UpdateCommand` input the store issues, for expression-level assertions. */
const recordUpdates = (base: ConsentPort): Readonly<{ port: ConsentPort; inputs: () => Row[] }> => {
  const inputs: Row[] = [];
  return {
    port: {
      async send(command: ConsentCommand, options?: ConsentSendOptions): Promise<unknown> {
        if (command instanceof UpdateCommand) inputs.push(command.input as unknown as Row);
        return base.send(command, options);
      },
    },
    inputs: () => inputs,
  };
};

const storeOf = (port: ConsentPort): ConsentStore => createConsentStore('ap-southeast-1', 'notes', port);

const codeOf = async (action: () => Promise<unknown>): Promise<string> => {
  try {
    await action();
    return 'NO_ERROR';
  } catch (error) {
    return error instanceof RagFailure ? error.code : 'NOT_A_RAG_FAILURE';
  }
};

const signal = (): AbortSignal => new AbortController().signal;

test('absent consent is the default grant read with a strongly consistent GET', async () => {
  const { port, calls } = fake();
  const store = storeOf(port);
  const grant = await store.read(ACTOR, signal());
  assert.deepEqual(grant, { accepted: false, version: CONSENT_VERSION, generation: 0 });
  assert.equal(grant.version, 'rag-consent.v1');
  assert.ok(Object.isFrozen(DEFAULT_CONSENT));
  assert.equal(calls(), 1);
  assert.equal(ROW.ownerId, `${OWNER_KEY_PREFIX}${ACTOR}`);
  assert.equal(ROW.noteId, CONSENT_SORT_KEY);
});

test('the canonical key is injective: no valid actor can alias another account row', async () => {
  const { port, items, at, calls } = fake();
  const store = storeOf(port);
  const odd = `${ACTOR}#x`;
  assert.notDeepEqual(consentRowKey(odd), ROW);
  await store.write(odd, VALID, signal());
  assert.equal(items.has(at(ROW)), false);
  assert.deepEqual(await store.read(ACTOR, signal()), DEFAULT_CONSENT);
  assert.equal(items.get(at(consentRowKey(odd) as Row))?.['generation'], 1);
  // One guarded read + one conditional write for `odd`, then one read of the real account row.
  assert.equal(calls(), 3);
});

test('a generation-0 compare-and-set creates the first grant and increments the generation', async () => {
  const { port, items, at } = fake();
  const store = storeOf(port);
  const created = await store.write(ACTOR, VALID, signal());
  assert.deepEqual(created, { accepted: true, version: CONSENT_VERSION, generation: 1 });
  assert.deepEqual(await store.read(ACTOR, signal()), created);
  assert.deepEqual(items.get(at(ROW)), { ...ROW, accepted: true, version: CONSENT_VERSION, generation: 1 });
  // A second accepted write with the correct expectation moves the generation again.
  const again = await store.write(ACTOR, { ...VALID, expectedGeneration: 1 }, signal());
  assert.equal(again.generation, 2);
});

test('revoke is a normal CAS write and keeps the generation monotonic', async () => {
  const { port, items, at } = fake();
  const store = storeOf(port);
  await store.write(ACTOR, VALID, signal());
  const revoked = await store.write(
    ACTOR,
    { accepted: false, version: CONSENT_VERSION, expectedGeneration: 1 },
    signal(),
  );
  assert.deepEqual(revoked, { accepted: false, version: CONSENT_VERSION, generation: 2 });
  assert.equal(items.get(at(ROW))?.['generation'], 2);
  assert.equal(items.get(at(ROW))?.['ttl'], undefined);
});

test('a stale expectedGeneration is refused and the stored grant is untouched', async () => {
  const { port, items, at } = fake();
  const store = storeOf(port);
  await store.write(ACTOR, VALID, signal());
  const before = { ...items.get(at(ROW)) };
  const code = await codeOf(() => store.write(
    ACTOR,
    { accepted: false, version: CONSENT_VERSION, expectedGeneration: 0 },
    signal(),
  ));
  assert.equal(code, 'SOURCE_CHANGED');
  assert.deepEqual(items.get(at(ROW)), before);
});

test('two concurrent writers with the same generation: exactly one wins', async () => {
  const { port, items, at } = fake();
  const store = storeOf(port);
  const io = signal();
  const results = await Promise.allSettled([
    store.write(ACTOR, { accepted: true, version: CONSENT_VERSION, expectedGeneration: 0 }, io),
    store.write(ACTOR, { accepted: false, version: CONSENT_VERSION, expectedGeneration: 0 }, io),
  ]);
  const fulfilled = results.filter((result) => result.status === 'fulfilled');
  const rejected = results.filter((result) => result.status === 'rejected');
  assert.equal(fulfilled.length, 1);
  assert.equal(rejected.length, 1);
  assert.ok(rejected[0]?.status === 'rejected' && rejected[0].reason instanceof RagFailure);
  assert.equal((rejected[0] as PromiseRejectedResult).reason.code, 'SOURCE_CHANGED');
  assert.equal(items.get(at(ROW))?.['generation'], 1);
  assert.equal(
    items.get(at(ROW))?.['accepted'],
    (fulfilled[0] as PromiseFulfilledResult<{ accepted: boolean }>).value.accepted,
  );
});

test('a row deleted between the read and the update conflicts instead of being recreated', async () => {
  const { port, items, at } = fake();
  const seeded = { ...ROW, accepted: true, version: CONSENT_VERSION, generation: 2 };
  items.set(at(ROW), { ...seeded });
  const deleting = afterFirstGet(port, () => items.delete(at(ROW)));
  const code = await codeOf(() => storeOf(deleting).write(
    ACTOR,
    { accepted: false, version: CONSENT_VERSION, expectedGeneration: 2 },
    signal(),
  ));
  assert.equal(code, 'SOURCE_CHANGED');
  assert.equal(items.has(at(ROW)), false, 'the deleted row is not recreated');

  // Generation 0 is the one absence case that may still create: the default grant is unchanged.
  const second = fake();
  const absent = afterFirstGet(second.port, () => second.items.delete(second.at(ROW)));
  const created = await storeOf(absent).write(ACTOR, VALID, signal());
  assert.deepEqual(created, { accepted: true, version: CONSENT_VERSION, generation: 1 });
});

test('a grant rewritten between the read and the update is refused, never overwritten', async () => {
  const races: ReadonlyArray<readonly [string, Row]> = [
    ['accepted flipped at the same generation', { accepted: false }],
    ['version rewritten', { version: 'rag-consent.v2' }],
    ['generation moved', { generation: 3 }],
    ['ttl added', { ttl: 1 }],
    ['foreign projection added', { canonicalOwnerId: OTHER }],
  ];
  for (const [label, patch] of races) {
    const { port, items, at } = fake();
    const seeded = { ...ROW, accepted: true, version: CONSENT_VERSION, generation: 2 };
    items.set(at(ROW), { ...seeded });
    const racing = afterFirstGet(port, () => { items.set(at(ROW), { ...seeded, ...patch }); });
    const code = await codeOf(() => storeOf(racing).write(
      ACTOR,
      { accepted: false, version: CONSENT_VERSION, expectedGeneration: 2 },
      signal(),
    ));
    assert.equal(code, 'SOURCE_CHANGED', label);
    assert.deepEqual(items.get(at(ROW)), { ...seeded, ...patch }, `${label} (row untouched)`);
  }
});

test('an existing generation-0 row is still written by the existing-row branch', async () => {
  const { port, items, at } = fake();
  const seeded = { ...ROW, accepted: false, version: CONSENT_VERSION, generation: 0 };
  items.set(at(ROW), { ...seeded });
  const stored = await storeOf(port).write(ACTOR, VALID, signal());
  assert.deepEqual(stored, { accepted: true, version: CONSENT_VERSION, generation: 1 });
  assert.deepEqual(items.get(at(ROW)), { ...ROW, accepted: true, version: CONSENT_VERSION, generation: 1 });
});

test('every supplied substitution is used, on absent creation and on both existing-row writes', async () => {
  /** Whether the issued condition admits the same write against a missing row. */
  const admitsAbsence = (input: Row): boolean =>
    evaluate(
      String(input['ConditionExpression']),
      {},
      (input['ExpressionAttributeNames'] ?? {}) as Record<string, string>,
      (input['ExpressionAttributeValues'] ?? {}) as Row,
    );

  // Absent-row creation: expectedGeneration 0 is the only write whose condition may create the row.
  const creating = fake();
  const createRecorder = recordUpdates(creating.port);
  const created = await storeOf(createRecorder.port).write(ACTOR, VALID, signal());
  assert.deepEqual(created, { accepted: true, version: CONSENT_VERSION, generation: 1 });

  // Revoke at generation 1: an existing row, written by the existing-row branch.
  const revoking = fake();
  const revokeRecorder = recordUpdates(revoking.port);
  const revokeStore = storeOf(revokeRecorder.port);
  await revokeStore.write(ACTOR, VALID, signal());
  assert.deepEqual(
    await revokeStore.write(ACTOR, { accepted: false, version: CONSENT_VERSION, expectedGeneration: 1 }, signal()),
    { accepted: false, version: CONSENT_VERSION, generation: 2 },
  );

  // Second grant at generation 1: the same branch with accepted true.
  const regranting = fake();
  const regrantRecorder = recordUpdates(regranting.port);
  const regrantStore = storeOf(regrantRecorder.port);
  await regrantStore.write(ACTOR, VALID, signal());
  assert.deepEqual(
    await regrantStore.write(ACTOR, VALID_WITH_GENERATION_1, signal()),
    { accepted: true, version: CONSENT_VERSION, generation: 2 },
  );

  const creation = createRecorder.inputs();
  const revoke = revokeRecorder.inputs();
  const regrant = regrantRecorder.inputs();
  assert.equal(creation.length, 1);
  assert.equal(revoke.length, 2);
  assert.equal(regrant.length, 2);
  // An unused name or value is a real-DynamoDB ValidationException, so none may be supplied.
  for (const input of [...creation, ...revoke, ...regrant]) assertSubstitutionsUsed(input);
  // Only the generation-0 creation write may recreate a row that is absent at write time.
  assert.equal(admitsAbsence(creation[0] as Row), true, 'generation 0 creates the first grant');
  assert.equal(admitsAbsence(revoke[1] as Row), false, 'revoke may not recreate a deleted row');
  assert.equal(admitsAbsence(regrant[1] as Row), false, 'a second grant may not recreate a deleted row');
});

test('the maximum generation is readable but can never be written past', async () => {
  const { port, items, at, calls } = fake();
  const top = { ...ROW, accepted: true, version: CONSENT_VERSION, generation: Number.MAX_SAFE_INTEGER };
  items.set(at(ROW), { ...top });
  const store = storeOf(port);
  assert.deepEqual(await store.read(ACTOR, signal()), {
    accepted: true, version: CONSENT_VERSION, generation: Number.MAX_SAFE_INTEGER,
  });
  const before = calls();
  assert.equal(await codeOf(() => store.write(
    ACTOR,
    { accepted: false, version: CONSENT_VERSION, expectedGeneration: Number.MAX_SAFE_INTEGER },
    signal(),
  )), 'INVALID_INPUT');
  assert.equal(calls(), before, 'refused before any DynamoDB call');
  assert.equal(await codeOf(() => store.write(
    ACTOR,
    { accepted: false, version: CONSENT_VERSION, expectedGeneration: Number.MAX_SAFE_INTEGER - 1 },
    signal(),
  )), 'SOURCE_CHANGED');
  assert.deepEqual(items.get(at(ROW)), top, 'the top-generation row is untouched');
});

test('foreign, ttl-carrying, key-mismatched and malformed rows fail closed', async () => {
  const corrupt: ReadonlyArray<readonly [string, Row]> = [
    ['accepted is not boolean', { ...ROW, accepted: 'true', version: CONSENT_VERSION, generation: 0 }],
    ['version drift', { ...ROW, accepted: true, version: 'rag-consent.v2', generation: 0 }],
    ['version is not a string', { ...ROW, accepted: true, version: 7, generation: 0 }],
    ['generation is NaN', { ...ROW, accepted: true, version: CONSENT_VERSION, generation: Number.NaN }],
    ['generation is negative', { ...ROW, accepted: true, version: CONSENT_VERSION, generation: -1 }],
    ['generation is fractional', { ...ROW, accepted: true, version: CONSENT_VERSION, generation: 1.5 }],
    ['generation is a string', { ...ROW, accepted: true, version: CONSENT_VERSION, generation: '1' }],
    ['row carries a ttl', { ...ROW, accepted: true, version: CONSENT_VERSION, generation: 0, ttl: 1 }],
    ['foreign projection', { ...ROW, accepted: true, version: CONSENT_VERSION, generation: 0, canonicalOwnerId: OTHER }],
    ['key mismatch', { ownerId: `${OWNER_KEY_PREFIX}${OTHER}`, noteId: CONSENT_SORT_KEY, accepted: true, version: CONSENT_VERSION, generation: 0 }],
  ];
  for (const [label, row] of corrupt) {
    const { port, items, at } = fake();
    items.set(at(ROW), { ...row });
    const store = storeOf(port);
    const io = signal();
    assert.equal(await codeOf(() => store.read(ACTOR, io)), 'SOURCE_CHANGED', label);
    assert.equal(
      await codeOf(() => store.write(ACTOR, VALID, io)),
      'SOURCE_CHANGED',
      `${label} (write)`,
    );
    assert.deepEqual(items.get(at(ROW)), { ...row }, `${label} (unchanged)`);
  }
});

test('invalid arguments are refused before any DynamoDB call', async () => {
  const { port, calls } = fake();
  const store = storeOf(port);
  const io = signal();
  const aborted = new AbortController();
  aborted.abort();
  assert.equal(await codeOf(() => store.read('', io)), 'INVALID_INPUT');
  assert.equal(await codeOf(() => store.read(` ${ACTOR}`, io)), 'INVALID_INPUT');
  assert.equal(await codeOf(() => store.read(7 as unknown as string, io)), 'INVALID_INPUT');
  assert.equal(await codeOf(() => store.read(ACTOR, 'signal' as unknown as AbortSignal)), 'INVALID_INPUT');
  assert.equal(await codeOf(() => store.read(ACTOR, aborted.signal)), 'TIMEOUT');
  assert.equal(await codeOf(() => store.write(ACTOR, { ...VALID, version: 'rag-consent.v2' }, io)), 'INVALID_INPUT');
  assert.equal(await codeOf(() => store.write(ACTOR, { ...VALID, ownerId: ACTOR } as never, io)), 'INVALID_INPUT');
  assert.equal(await codeOf(() => store.write(ACTOR, { accepted: true } as never, io)), 'INVALID_INPUT');
  assert.equal(await codeOf(() => store.write(ACTOR, { ...VALID, accepted: 'true' } as never, io)), 'INVALID_INPUT');
  assert.equal(await codeOf(() => store.write(ACTOR, { ...VALID, expectedGeneration: Number.NaN }, io)), 'INVALID_INPUT');
  assert.equal(await codeOf(() => store.write(ACTOR, { ...VALID, expectedGeneration: -1 }, io)), 'INVALID_INPUT');
  assert.equal(await codeOf(() => store.write(ACTOR, { ...VALID, expectedGeneration: 1.5 }, io)), 'INVALID_INPUT');
  assert.equal(await codeOf(() => store.write(ACTOR, { ...VALID, expectedGeneration: Number.MAX_SAFE_INTEGER }, io)), 'INVALID_INPUT');
  assert.equal(await codeOf(() => store.write(ACTOR, VALID, aborted.signal)), 'TIMEOUT');
  assert.equal(calls(), 0);
});

test('transport failures map to PROVIDER_UNAVAILABLE and an in-flight deadline to TIMEOUT', async () => {
  const failing: ConsentPort = { async send() { throw new Error('socket'); } };
  assert.equal(await codeOf(() => storeOf(failing).read(ACTOR, signal())), 'PROVIDER_UNAVAILABLE');
  const throttled: ConsentPort = {
    async send() { throw Object.assign(new Error('slow down'), { name: 'ThrottlingException' }); },
  };
  assert.equal(await codeOf(() => storeOf(throttled).write(ACTOR, VALID, signal())), 'PROVIDER_UNAVAILABLE');
  const controller = new AbortController();
  const abortedMidCall: ConsentPort = {
    async send() { controller.abort(); throw new Error('aborted'); },
  };
  assert.equal(await codeOf(() => storeOf(abortedMidCall).read(ACTOR, controller.signal)), 'TIMEOUT');
});

test('an SDK failure warns with the known name only, never the message, note or row data', async () => {
  const SECRET = 'arn:aws:iam::123456789012:role/secret-role';
  const NOTE = 'private note body that must never be logged';
  const warnings: unknown[][] = [];
  const original = console.warn;
  console.warn = (...args: unknown[]) => { warnings.push(args); };
  try {
    const failing: ConsentPort = {
      async send() {
        throw Object.assign(new Error(`request failed for ${SECRET} ${NOTE}`), {
          name: 'ValidationException',
          $metadata: { httpStatusCode: 400 },
          // Row/response data a provider may attach: none of it may be echoed by the diagnostic.
          Attributes: { ownerId: `${OWNER_KEY_PREFIX}${ACTOR}`, noteId: CONSENT_SORT_KEY, note: NOTE },
          Item: { note: NOTE, canonicalOwnerId: OTHER },
        });
      },
    };
    assert.equal(await codeOf(() => storeOf(failing).read(ACTOR, signal())), 'PROVIDER_UNAVAILABLE');
  } finally {
    console.warn = original;
  }
  assert.equal(warnings.length, 1, 'exactly one structured warning per mapped failure');
  assert.equal(warnings[0]?.[0], 'rag.consent.sdk_failure');
  const detail = warnings[0]?.[1] as Record<string, unknown>;
  assert.equal(detail['operation'], 'Get');
  assert.equal(detail['errorName'], 'ValidationException');
  assert.equal(detail['httpStatus'], 400);
  // The whole rendered payload, not just the fields read above, must be free of raw data.
  const rendered = JSON.stringify(warnings);
  assert.equal(rendered.includes(SECRET), false, 'the injected secret never appears');
  assert.equal(rendered.includes(NOTE), false, 'the note body never appears');
  assert.equal(rendered.includes('request failed'), false, 'error.message never appears');
  assert.equal(rendered.includes(ACTOR), false, 'the actor never appears');
  assert.equal(rendered.includes('RAG#CONSENT'), false, 'the row key never appears');
  assert.equal(rendered.includes(OTHER), false, 'other identifiers never appear');
});

test('the store refuses an invalid configuration and never writes a whole note', () => {
  assert.throws(() => createConsentStore('ap-southeast-1', ''), (error: unknown) =>
    error instanceof RagFailure && error.code === 'LIVE_POLICY_NOT_CONFIGURED');
  assert.throws(() => createConsentStore('southeast-1', 'notes'), (error: unknown) =>
    error instanceof RagFailure && error.code === 'LIVE_POLICY_NOT_CONFIGURED');
  // The default client is built without any call; no request is made here.
  assert.doesNotThrow(() => createConsentStore('ap-southeast-1', 'notes'));
});

/* ------------------------------------------------------------------ *
 * Group 4: the pilot config guard. Every read re-validates membership
 * against a fresh config; every write pins the exact captured config
 * row and the consent CAS in one transaction.
 * ------------------------------------------------------------------ */

const CONFIG_KEY = { ownerId: 'CONFIG#PHASE5', noteId: 'PILOT' } as const;
const CONFIG_V1 = {
  version: 'rag-pilot-config.v1',
  generation: 1,
  policy: { enabled: true, owners: [ACTOR] },
  corpus: { kind: 'reviewed-pilot', caseHash: 'sha256:x', owners: { [ACTOR]: [{ noteId: 'n-a', inputDigest: 'a'.repeat(64) }] } },
} as const;

type Guarded = Readonly<{
  port: ConsentPort;
  items: Map<string, Row>;
  at: (key: Row) => string;
  transactions: Row[];
  setConfig: (next: Record<string, unknown> | undefined) => void;
  setFresh: (next: Record<string, unknown> | undefined) => void;
}>;

/**
 * A document-client fake that evaluates the whole transaction atomically: the config
 * ConditionCheck is compared by value first, and only then is the consent CAS update applied.
 * A failed check cancels the transaction and leaves the notes row untouched.
 */
const guarded = (initial: Record<string, unknown> | undefined): Guarded => {
  const items = new Map<string, Row>();
  const transactions: Row[] = [];
  let config = initial;
  let fresh = initial;
  const at = (key: Row): string => `${String(key['ownerId'])}\u0000${String(key['noteId'])}`;
  const configItem = (): Row => (config === undefined ? {} : { ...CONFIG_KEY, config });
  const cancelled = () => Object.assign(new Error('cancelled'), {
    name: 'TransactionCanceledException',
    CancellationReasons: [{ Code: 'ConditionalCheckFailed' }],
  });
  const port: ConsentPort = {
    async send(command: ConsentCommand): Promise<unknown> {
      if (command instanceof GetCommand) {
        if (command.input.TableName === 'state') {
          return fresh === undefined ? {} : { Item: { ...CONFIG_KEY, config: fresh } };
        }
        const item = items.get(at(command.input.Key as Row));
        return item === undefined ? {} : { Item: item };
      }
      assert.ok(command instanceof TransactWriteCommand, 'a guarded write is one transaction');
      const transact = command.input.TransactItems as unknown as Row[];
      transactions.push({ TransactItems: transact } as unknown as Row);
      const check = transact.find((entry) => entry['ConditionCheck'] !== undefined)?.['ConditionCheck'] as Row;
      const update = transact.find((entry) => entry['Update'] !== undefined)?.['Update'] as Row;
      assert.ok(check !== undefined && update !== undefined, 'the transaction has a ConditionCheck and an Update');
      if (!evaluate(
        String(check['ConditionExpression']),
        configItem(),
        (check['ExpressionAttributeNames'] ?? {}) as Record<string, string>,
        (check['ExpressionAttributeValues'] ?? {}) as Row,
      )) {
        throw cancelled();
      }
      const key = update['Key'] as Row;
      const current = items.get(at(key));
      const values = (update['ExpressionAttributeValues'] ?? {}) as Row;
      if (!evaluate(
        String(update['ConditionExpression']),
        current ?? {},
        (update['ExpressionAttributeNames'] ?? {}) as Record<string, string>,
        values,
      )) {
        throw cancelled();
      }
      items.set(at(key), {
        ...(current ?? {}), ownerId: key['ownerId'], noteId: key['noteId'],
        accepted: values[':accepted'], version: values[':version'], generation: values[':generation'],
      });
      return {};
    },
  };
  return {
    port, items, at, transactions,
    setConfig: (next) => { config = next; },
    setFresh: (next) => { fresh = next; },
  };
};

const guardOf = (value: Record<string, unknown>, fresh: () => Record<string, unknown> | undefined) =>
  Object.freeze({
    table: 'state',
    key: CONFIG_KEY,
    value,
    revalidate: async (actor: string) => {
      const current = fresh();
      const policy = current?.['policy'] as { owners?: readonly string[] } | undefined;
      if (policy?.owners?.includes(actor) !== true) throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
    },
  });

const guardedStore = (fake: Guarded, value: Record<string, unknown> = CONFIG_V1): ConsentStore =>
  createConsentStore('ap-southeast-1', 'notes', fake.port, guardOf(value, () => value));

test('a guarded write pins the exact config row and the consent CAS in one transaction', async () => {
  const fake = guarded(CONFIG_V1);
  const store = createConsentStore('ap-southeast-1', 'notes', fake.port, guardOf(CONFIG_V1, () => CONFIG_V1));
  const stored = await store.write(ACTOR, VALID, signal());
  assert.deepEqual(stored, { accepted: true, version: CONSENT_VERSION, generation: 1 });
  assert.equal(fake.transactions.length, 1, 'exactly one write transaction');
  const transact = fake.transactions[0]?.['TransactItems'] as Row[];
  assert.equal(transact.length, 2);
  const check = transact[0]?.['ConditionCheck'] as Row;
  const update = transact[1]?.['Update'] as Row;
  assert.equal(check['TableName'], 'state');
  assert.deepEqual(check['Key'], CONFIG_KEY);
  assert.equal(check['ConditionExpression'], '#config = :capturedConfig');
  assert.deepEqual(check['ExpressionAttributeValues'], { ':capturedConfig': CONFIG_V1 });
  assert.equal(update['TableName'], 'notes');
  assert.deepEqual(update['Key'], ROW);
  assert.equal(update['ReturnValues'], undefined, 'a transaction never returns ALL_NEW');
  // A bounded strong GET then confirms the committed row before the wire success.
  assert.deepEqual(fake.items.get(fake.at(ROW)), { ...ROW, accepted: true, version: CONSENT_VERSION, generation: 1 });
});

test('a config generation move during the write cancels the transaction and writes no consent', async () => {
  const fake = guarded(CONFIG_V1);
  let fired = false;
  const racing: ConsentPort = {
    async send(command, options) {
      const result = await fake.port.send(command, options);
      if (!fired && command instanceof GetCommand && command.input.TableName === 'notes') {
        fired = true;
        fake.setConfig({ ...CONFIG_V1, generation: 2 });
      }
      return result;
    },
  };
  const store = createConsentStore('ap-southeast-1', 'notes', racing, guardOf(CONFIG_V1, () => CONFIG_V1));
  assert.equal(await codeOf(() => store.write(ACTOR, VALID, signal())), 'SOURCE_CHANGED');
  assert.equal(fake.items.has(fake.at(ROW)), false, 'the stale permit never wrote a consent row');
});

test('a committed write is reported SOURCE_CHANGED when the config moves after commit', async () => {
  const fake = guarded(CONFIG_V1);
  let fresh: Record<string, unknown> | undefined = CONFIG_V1;
  const moving: ConsentPort = {
    async send(command, options) {
      const result = await fake.port.send(command, options);
      if (command instanceof TransactWriteCommand) {
        // The permit is withdrawn after the atomic commit: the change is reported, never rolled back.
        fresh = { ...CONFIG_V1, generation: 2, policy: { enabled: false, owners: [] } };
      }
      return result;
    },
  };
  const store = createConsentStore('ap-southeast-1', 'notes', moving, guardOf(CONFIG_V1, () => fresh));
  assert.equal(await codeOf(() => store.write(ACTOR, VALID, signal())), 'LIVE_POLICY_NOT_CONFIGURED');
  assert.deepEqual(fake.items.get(fake.at(ROW)), { ...ROW, accepted: true, version: CONSENT_VERSION, generation: 1 });
});

test('a read refuses to release a grant after the actor is removed mid-read', async () => {
  const fake = guarded(CONFIG_V1);
  fake.items.set(fake.at(ROW), { ...ROW, accepted: true, version: CONSENT_VERSION, generation: 4 });
  let fresh: Record<string, unknown> | undefined = CONFIG_V1;
  const removing: ConsentPort = {
    async send(command, options) {
      const result = await fake.port.send(command, options);
      if (command instanceof GetCommand && command.input.TableName === 'notes') {
        fresh = { ...CONFIG_V1, policy: { enabled: false, owners: [] } };
      }
      return result;
    },
  };
  const store = createConsentStore('ap-southeast-1', 'notes', removing, guardOf(CONFIG_V1, () => fresh));
  assert.equal(await codeOf(() => store.read(ACTOR, signal())), 'LIVE_POLICY_NOT_CONFIGURED');
});

test('a disabled-but-listed owner can still read and revoke through the guard', async () => {
  const disabled = { ...CONFIG_V1, policy: { enabled: false, owners: [ACTOR] } };
  const fake = guarded(disabled);
  const store = guardedStore(fake, disabled);
  assert.deepEqual(await store.read(ACTOR, signal()), DEFAULT_CONSENT);
  const revoked = await store.write(ACTOR, { ...VALID, accepted: false }, signal());
  assert.deepEqual(revoked, { accepted: false, version: CONSENT_VERSION, generation: 1 });
});

test('transaction cancellation reasons map to distinct safe codes without echoing them', async () => {
  const guard = guardOf(CONFIG_V1, () => CONFIG_V1);
  const failing = (reason: string): ConsentStore => createConsentStore('ap-southeast-1', 'notes', {
    async send(command): Promise<unknown> {
      if (command instanceof TransactWriteCommand) {
        throw Object.assign(new Error('raw detail must never surface'), {
          name: 'TransactionCanceledException',
          CancellationReasons: [{ Code: reason }],
        });
      }
      return {};
    },
  }, guard);
  assert.equal(await codeOf(() => failing('ConditionalCheckFailed').write(ACTOR, VALID, signal())), 'SOURCE_CHANGED');
  assert.equal(await codeOf(() => failing('ThrottlingError').write(ACTOR, VALID, signal())), 'RATE_LIMITED');
  assert.equal(await codeOf(() => failing('RequestTimeout').write(ACTOR, VALID, signal())), 'TIMEOUT');
  assert.equal(await codeOf(() => failing('ValidationError').write(ACTOR, VALID, signal())), 'PROVIDER_UNAVAILABLE');
});

test('the guard rejects a store without a valid config identity', () => {
  assert.throws(
    () => createConsentStore('ap-southeast-1', 'notes', undefined, { table: 'state' } as never),
    (error: unknown) => error instanceof RagFailure && error.code === 'LIVE_POLICY_NOT_CONFIGURED',
  );
});
