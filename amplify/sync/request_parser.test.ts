/**
 * Focused pure checks for `amplify/sync/request_parser.ts` (M1.2 slice B).
 *
 * Run with `npx tsx amplify/sync/request_parser.test.ts`. The backend has no
 * test runner and no `@types/node` (see `package.json`), so this file stays a
 * plain script: no imports beyond the module under test, no fixtures, no mocks.
 * A failing check rethrows, which exits the process non-zero.
 *
 * Nothing here touches AWS: the parser is pure, and the only type it borrows
 * from the store is erased at compile time.
 */
import {
  DEFAULT_CHANGE_LIMIT,
  MAX_CHANGE_LIMIT,
  parseChangesQuery,
  parseMutationBody,
} from './request_parser';
import type { MutationProblem } from './request_parser';
import type { SyncMutation } from './dynamo_sync_store';

let passed = 0;

const check = (name: string, run: () => void): void => {
  try {
    run();
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
    throw new Error(label);
  }
};

const assertDeepEqual = (actual: unknown, expected: unknown, label: string): void => {
  const actualJson = JSON.stringify(actual);
  const expectedJson = JSON.stringify(expected);
  if (actualJson !== expectedJson) {
    throw new Error(`${label}: expected ${expectedJson}, got ${actualJson}`);
  }
};

/** Parses a body that must be accepted. */
const mutationOf = (body: string): SyncMutation => {
  const result = parseMutationBody(body);
  if (!result.ok) {
    throw new Error(`expected a parsed mutation, got problem ${result.problem}`);
  }
  return result.mutation;
};

/** Asserts that a body is refused for exactly `problem`. */
const assertProblem = (body: string | null | undefined, problem: MutationProblem, label: string): void => {
  const result = parseMutationBody(body);
  if (result.ok) {
    throw new Error(`${label}: expected problem ${problem}, got an accepted mutation`);
  }
  assertEqual(result.problem, problem, label);
};

const createBody = (overrides: Record<string, unknown> = {}): string =>
  JSON.stringify({
    mutationId: 'mutation-1',
    noteId: 'note-1',
    operation: 'create',
    baseRevision: 0,
    payload: { title: 'Title', content: 'Content' },
    ...overrides,
  });

check('a well-formed create parses into the store mutation shape', () => {
  assertDeepEqual(
    mutationOf(createBody()),
    {
      mutationId: 'mutation-1',
      noteId: 'note-1',
      operation: 'create',
      baseRevision: 0,
      payload: { title: 'Title', content: 'Content' },
    },
    'create',
  );
});

check('update and delete parse, and a delete drops any payload', () => {
  assertDeepEqual(
    mutationOf(createBody({ operation: 'update', baseRevision: 4 })),
    {
      mutationId: 'mutation-1',
      noteId: 'note-1',
      operation: 'update',
      baseRevision: 4,
      payload: { title: 'Title', content: 'Content' },
    },
    'update',
  );

  const deleteMutation = mutationOf(
    createBody({ operation: 'delete', baseRevision: 4, payload: { title: 'x', content: 'y' } }),
  );
  assertEqual(deleteMutation.operation, 'delete', 'operation');
  assertEqual(deleteMutation.payload, undefined, 'payload must be dropped');
});

check('owned route refuses canonical fields and drops unrelated additive fields', () => {
  assertProblem(createBody({ ownerId: 'somebody-else' }), 'PAYLOAD_INVALID', 'shared identity on owned route');
  const mutation = mutationOf(createBody({ extra: true }));
  assertDeepEqual(
    Object.keys(mutation).sort(),
    ['baseRevision', 'mutationId', 'noteId', 'operation', 'payload'],
    'mutation keys',
  );
  assertDeepEqual(Object.keys(mutation.payload ?? {}).sort(), ['content', 'title'], 'payload keys');
});

check('an empty payload object is refused for a missing shape, not silently accepted', () => {
  assertProblem(createBody({ payload: {} }), 'PAYLOAD_INVALID', 'empty payload');
});

check('identifiers must be non-blank, bounded, and control-character free', () => {
  const accepted = 'a'.repeat(128);
  assertEqual(mutationOf(createBody({ mutationId: accepted })).mutationId, accepted, '128-char mutationId');
  assertEqual(mutationOf(createBody({ noteId: accepted })).noteId, accepted, '128-char noteId');

  for (const bad of ['', '   ', 7, null, { id: 'x' }]) {
    assertProblem(createBody({ mutationId: bad }), 'MUTATION_ID_INVALID', `mutationId ${JSON.stringify(bad)}`);
    assertProblem(createBody({ noteId: bad }), 'NOTE_ID_INVALID', `noteId ${JSON.stringify(bad)}`);
  }

  assertProblem(createBody({ mutationId: 'a'.repeat(129) }), 'MUTATION_ID_INVALID', '129-char mutationId');
  assertProblem(createBody({ noteId: 'a'.repeat(129) }), 'NOTE_ID_INVALID', '129-char noteId');
  assertProblem(createBody({ noteId: 'note\u0000id' }), 'NOTE_ID_INVALID', 'control character');
  assertProblem(createBody({ noteId: 'note\u007fid' }), 'NOTE_ID_INVALID', 'delete control character');
});

check('a body that is missing or not a JSON object is unreadable', () => {
  for (const body of [undefined, null, '', '   ', 'not json', '[1,2]', 'null', '"create"', '42']) {
    assertProblem(body as string | null | undefined, 'BODY_MALFORMED', `body ${JSON.stringify(body)}`);
  }
});

check('only the three contract operations are accepted', () => {
  for (const bad of ['upsert', 'DELETE', 'Create', '', null, 1]) {
    assertProblem(createBody({ operation: bad }), 'OPERATION_UNSUPPORTED', `operation ${JSON.stringify(bad)}`);
  }
});

check('baseRevision must be a non-negative whole number', () => {
  assertEqual(mutationOf(createBody({ baseRevision: 0 })).baseRevision, 0, 'zero');
  assertEqual(mutationOf(createBody({ baseRevision: 9_007_199_254_740_991 })).baseRevision, 9_007_199_254_740_991, 'max safe');
  for (const bad of [-1, 1.5, '2', null, undefined, 1e999]) {
    assertProblem(
      createBody({ baseRevision: bad }),
      'BASE_REVISION_INVALID',
      `baseRevision ${JSON.stringify(bad)}`,
    );
  }
});

check('create and update require non-blank title and content', () => {
  for (const operation of ['create', 'update']) {
    for (const payload of [undefined, null, 'text', 42, [1]]) {
      assertProblem(createBody({ operation, payload }), 'PAYLOAD_REQUIRED', `${operation} payload ${JSON.stringify(payload)}`);
    }
    assertProblem(createBody({ operation, payload: { title: 1, content: 'c' } }), 'PAYLOAD_INVALID', 'numeric title');
    assertProblem(createBody({ operation, payload: { title: 't' } }), 'PAYLOAD_INVALID', 'missing content');
    assertProblem(createBody({ operation, payload: { title: 't', content: null } }), 'PAYLOAD_INVALID', 'null content');
    assertProblem(createBody({ operation, payload: { title: '  ', content: 'body' } }), 'PAYLOAD_INVALID', 'blank title');
    assertProblem(createBody({ operation, payload: { title: 'title', content: '\n\t' } }), 'PAYLOAD_INVALID', 'blank content');
  }

  // Whitespace around real text is retained rather than normalized.
  assertDeepEqual(
    mutationOf(createBody({ payload: { title: '  Title  ', content: '\nBody\n' } })).payload,
    { title: '  Title  ', content: '\nBody\n' },
    'text formatting',
  );
});

check('pinnedAt preserves legacy omission and validates explicit values', () => {
  const legacy = mutationOf(createBody());
  assertEqual(Object.prototype.hasOwnProperty.call(legacy.payload ?? {}, 'pinnedAt'), false, 'legacy omission');

  const pinnedAt = '2026-09-25T10:30:00.123Z';
  assertDeepEqual(
    mutationOf(createBody({ payload: { title: 'Title', content: 'Content', pinnedAt } })).payload,
    { title: 'Title', content: 'Content', pinnedAt },
    'pin timestamp',
  );
  assertDeepEqual(
    mutationOf(createBody({ payload: { title: 'Title', content: 'Content', pinnedAt: null } })).payload,
    { title: 'Title', content: 'Content', pinnedAt: null },
    'explicit unpin',
  );

  for (const invalid of [42, '', 'yesterday', '2026-09-25T10:30:00+00:00', '2026-02-30T10:30:00Z']) {
    assertProblem(
      createBody({ payload: { title: 'Title', content: 'Content', pinnedAt: invalid } }),
      'PAYLOAD_INVALID',
      `invalid pinnedAt ${JSON.stringify(invalid)}`,
    );
  }
});

check('the first invalid field decides the problem', () => {
  assertProblem(
    createBody({ mutationId: '', noteId: '', operation: 'upsert', baseRevision: -1, payload: null }),
    'MUTATION_ID_INVALID',
    'mutationId is checked first',
  );
  assertProblem(
    createBody({ noteId: '', operation: 'upsert', baseRevision: -1, payload: null }),
    'NOTE_ID_INVALID',
    'then noteId',
  );
  assertProblem(createBody({ operation: 'upsert', baseRevision: -1, payload: null }), 'OPERATION_UNSUPPORTED', 'then operation');
  assertProblem(createBody({ baseRevision: -1, payload: null }), 'BASE_REVISION_INVALID', 'then baseRevision');
  assertProblem(createBody({ payload: null }), 'PAYLOAD_REQUIRED', 'then payload');
});

check('limit defaults to the contract value and stays inside 1..100', () => {
  assertEqual(DEFAULT_CHANGE_LIMIT, 50, 'default constant');
  assertEqual(MAX_CHANGE_LIMIT, 100, 'cap constant');

  const limitOf = (limit: string | undefined): number | undefined => {
    const result = parseChangesQuery(limit === undefined ? {} : { limit });
    return result.ok ? result.limit : undefined;
  };

  assertEqual(limitOf(undefined), 50, 'absent');
  assertEqual(limitOf(''), 50, 'empty');
  assertEqual(limitOf('1'), 1, 'one');
  assertEqual(limitOf('50'), 50, 'fifty');
  assertEqual(limitOf('100'), 100, 'cap');
  assertEqual(limitOf('007'), 7, 'leading zeros');

  for (const bad of ['0', '101', '1000', 'abc', '1.5', '-5', '+5', ' 50', '5e2', '1,000']) {
    assertEqual(limitOf(bad), undefined, `limit ${JSON.stringify(bad)} must be refused`);
  }
});

check('an unreadable limit is reported as LIMIT_INVALID, not thrown', () => {
  const result = parseChangesQuery({ limit: 'lots' });
  assertTrue(!result.ok, 'must fail');
  if (!result.ok) {
    assertEqual(result.problem, 'LIMIT_INVALID', 'problem');
  }
});

check('a cursor travels through untouched, missing means from the beginning', () => {
  const cursorOf = (cursor: string | undefined): string | undefined => {
    const result = parseChangesQuery(cursor === undefined ? {} : { cursor });
    if (!result.ok) {
      throw new Error('a cursor must not fail the query parse');
    }
    return result.cursor;
  };

  assertEqual(cursorOf(undefined), undefined, 'absent');
  assertEqual(cursorOf(''), undefined, 'empty');

  // The parser does not judge the cursor: only the codec, which knows the
  // caller's account, can. Even a value it will reject is carried through.
  for (const cursor of ['eyJ2IjoxfQ', 'not base64!', 'a'.repeat(200)]) {
    assertEqual(cursorOf(cursor), cursor, `cursor ${cursor.slice(0, 12)}`);
  }
});

check('a missing query map is a valid request with contract defaults', () => {
  for (const query of [undefined, null, {}]) {
    const result = parseChangesQuery(query);
    assertTrue(result.ok, 'must be accepted');
    if (result.ok) {
      assertEqual(result.limit, DEFAULT_CHANGE_LIMIT, 'default limit');
      assertEqual(result.cursor, undefined, 'no cursor');
    }
  }
});

console.log(`${passed} request-parser checks passed`);
