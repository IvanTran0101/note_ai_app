/**
 * Focused pure checks for `amplify/sync/sync_response.ts` (M1.2 slice B).
 *
 * Run with `npx tsx amplify/sync/sync_response.test.ts`. Like the cursor checks,
 * this is a plain script - no runner, no fixtures, no mocks - and it touches no
 * AWS: the response module only builds `{statusCode, headers, body}` objects
 * from values handed to it.
 */
import type { APIGatewayProxyStructuredResultV2 } from 'aws-lambda';
import type { InvalidCursorReason } from './cursor';
import type { AppliedMutation, ChangesPage, ConflictedMutation, NoteSnapshot } from './dynamo_sync_store';
import type { MutationProblem } from './request_parser';
import {
  appliedMutationResponse,
  changesResponse,
  conflictResponse,
  internalErrorResponse,
  invalidChangesResponse,
  invalidMutationResponse,
  jsonResponse,
  notFoundResponse,
  noteBodyOf,
  storageFailureResponse,
  unauthorizedResponse,
} from './sync_response';

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

const bodyOf = (response: APIGatewayProxyStructuredResultV2): Record<string, unknown> => {
  assertEqual(response.headers?.['content-type'], 'application/json', 'content-type');
  if (typeof response.body !== 'string') {
    throw new Error('a response body must be a JSON string');
  }
  const parsed: unknown = JSON.parse(response.body);
  if (typeof parsed !== 'object' || parsed === null) {
    throw new Error('a response body must be a JSON object');
  }
  return parsed as Record<string, unknown>;
};

const NOTE: NoteSnapshot = {
  id: 'note-1',
  title: 'Title',
  content: 'Content',
  revision: 3,
  createdAt: '2026-09-24T10:00:00.000Z',
  serverUpdatedAt: '2026-09-24T10:00:01.000Z',
  deletedAt: null,
};

const TOMBSTONE: NoteSnapshot = { ...NOTE, deletedAt: '2026-09-24T10:00:02.000Z' };

const NOTE_KEYS = ['content', 'createdAt', 'deletedAt', 'id', 'revision', 'serverUpdatedAt', 'title'];

check('an applied result is a 200 with the note and no store bookkeeping', () => {
  const applied: AppliedMutation = {
    status: 'applied',
    mutationId: 'mutation-1',
    note: NOTE,
    replayed: true,
  };
  const response = appliedMutationResponse(applied);
  assertEqual(response.statusCode, 200, 'status');
  const body = bodyOf(response);
  assertDeepEqual(body, { status: 'applied', mutationId: 'mutation-1', note: NOTE }, 'body');
  assertTrue(!('replayed' in body), 'the store-only replayed flag must not leak');
});

check('the wire note is exactly the snapshot the Application port builds', () => {
  const body = bodyOf(appliedMutationResponse({ status: 'applied', mutationId: 'm', note: NOTE, replayed: false }));
  const note = body.note as Record<string, unknown>;
  assertDeepEqual(Object.keys(note).sort(), NOTE_KEYS, 'note keys');
  assertEqual(note.deletedAt, null, 'a live note has no deletion time');
});

check('a tombstone keeps its deletion time and identity', () => {
  const body = bodyOf(appliedMutationResponse({ status: 'applied', mutationId: 'm', note: TOMBSTONE, replayed: false }));
  assertDeepEqual(body.note, TOMBSTONE, 'tombstone');
});

check('projection drops anything the store keeps beyond the wire shape', () => {
  const stored = { ...NOTE, ownerId: 'OWNER#user-1', changeSequence: 7, fingerprint: 'abc' } as unknown as NoteSnapshot;
  const projected = noteBodyOf(stored);
  assertDeepEqual(Object.keys(projected).sort(), NOTE_KEYS, 'projected keys');
  assertTrue(!('ownerId' in projected) && !('changeSequence' in projected), 'storage keys must not leak');
});

check('a conflict is a 409 envelope carrying the remote note', () => {
  const conflict: ConflictedMutation = { status: 'conflict', mutationId: 'mutation-1', remoteNote: NOTE };
  const response = conflictResponse(conflict);
  assertEqual(response.statusCode, 409, 'status');
  const body = bodyOf(response);
  assertDeepEqual(
    body,
    { code: 'REVISION_CONFLICT', retryable: false, mutationId: 'mutation-1', remoteNote: NOTE },
    'body',
  );
  assertTrue(!('status' in body), 'the 409 status is the transport, not a body field');
});

check('a conflict with nothing stored reports remoteNote as null', () => {
  const body = bodyOf(conflictResponse({ status: 'conflict', mutationId: 'mutation-1', remoteNote: null }));
  assertTrue('remoteNote' in body, 'remoteNote must be present');
  assertEqual(body.remoteNote, null, 'remoteNote');
});

check('a change page carries snapshots, hasMore, and only a real cursor', () => {
  const page: ChangesPage = { items: [NOTE, TOMBSTONE], nextCursor: 'opaque-cursor', hasMore: true };
  const response = changesResponse(page);
  assertEqual(response.statusCode, 200, 'status');
  assertDeepEqual(bodyOf(response), { items: [NOTE, TOMBSTONE], hasMore: true, nextCursor: 'opaque-cursor' }, 'body');

  const last: ChangesPage = { items: [NOTE], nextCursor: '', hasMore: false };
  const lastBody = bodyOf(changesResponse(last));
  assertDeepEqual(lastBody, { items: [NOTE], hasMore: false }, 'a cursorless page has no key');
  assertTrue(!('nextCursor' in lastBody), 'an empty cursor must not be serialized');

  // The port types `nextCursor` as optional; a page without one must not invent it.
  const absent = { items: [], hasMore: false } as unknown as ChangesPage;
  assertTrue(!('nextCursor' in bodyOf(changesResponse(absent))), 'an absent cursor must stay absent');
});

check('every mutation problem is a 422 with its own safe message', () => {
  const problems: readonly MutationProblem[] = [
    'BODY_MALFORMED',
    'MUTATION_ID_INVALID',
    'MUTATION_ID_REUSED',
    'NOTE_ID_INVALID',
    'OPERATION_UNSUPPORTED',
    'BASE_REVISION_INVALID',
    'PAYLOAD_REQUIRED',
    'PAYLOAD_INVALID',
    'PAYLOAD_TOO_LARGE',
  ];
  const messages = new Set<string>();
  for (const problem of problems) {
    const response = invalidMutationResponse(problem);
    assertEqual(response.statusCode, 422, `${problem} status`);
    const body = bodyOf(response);
    assertEqual(body.code, 'INVALID_MUTATION', `${problem} code`);
    assertEqual(body.retryable, false, `${problem} retryable`);
    assertTrue(typeof body.message === 'string' && body.message.length > 0, `${problem} message`);
    messages.add(String(body.message));
  }
  assertEqual(messages.size, problems.length, 'each problem explains itself differently');
});

check('a refused query is a 422, split between request shape and cursor', () => {
  const limit = invalidChangesResponse('LIMIT_INVALID');
  assertEqual(limit.statusCode, 422, 'limit status');
  const limitBody = bodyOf(limit);
  assertEqual(limitBody.code, 'INVALID_REQUEST', 'limit code');
  assertEqual(limitBody.retryable, false, 'limit retryable');
  assertTrue(String(limitBody.message).includes('limit'), 'limit message names the field');

  const reasons: readonly InvalidCursorReason[] = ['MALFORMED', 'UNSUPPORTED_VERSION', 'ACCOUNT_MISMATCH'];
  const messages = new Set<string>();
  for (const reason of reasons) {
    const response = invalidChangesResponse(reason);
    assertEqual(response.statusCode, 422, `${reason} status`);
    const body = bodyOf(response);
    assertEqual(body.code, 'INVALID_CURSOR', `${reason} code`);
    assertEqual(body.retryable, false, `${reason} retryable`);
    messages.add(String(body.message));
  }
  assertEqual(messages.size, reasons.length, 'each cursor problem explains itself differently');
});

check('an identity-less call is a 401 and an unknown route a 404', () => {
  const unauthorized = unauthorizedResponse();
  assertEqual(unauthorized.statusCode, 401, '401 status');
  assertEqual(bodyOf(unauthorized).code, 'UNAUTHORIZED', '401 code');
  assertEqual(bodyOf(unauthorized).retryable, false, '401 retryable');

  const notFound = notFoundResponse();
  assertEqual(notFound.statusCode, 404, '404 status');
  assertEqual(bodyOf(notFound).code, 'NOT_FOUND', '404 code');
  assertEqual(bodyOf(notFound).retryable, false, '404 retryable');
});

check('storage failures split into retryable 503 and non-retryable 500', () => {
  const throttled = storageFailureResponse(true);
  assertEqual(throttled.statusCode, 503, '503 status');
  const throttledBody = bodyOf(throttled);
  assertEqual(throttledBody.code, 'SERVER_UNAVAILABLE', '503 code');
  assertEqual(throttledBody.retryable, true, '503 retryable');

  const permanent = storageFailureResponse(false);
  assertEqual(permanent.statusCode, 500, '500 status');
  const permanentBody = bodyOf(permanent);
  assertEqual(permanentBody.code, 'INTERNAL_ERROR', '500 code');
  assertEqual(permanentBody.retryable, false, '500 retryable');

  const unexpected = internalErrorResponse();
  assertEqual(unexpected.statusCode, 500, 'unexpected status');
  assertEqual(bodyOf(unexpected).code, 'INTERNAL_ERROR', 'unexpected code');
  assertEqual(bodyOf(unexpected).retryable, true, 'unexpected retryable');
});

check('an error envelope always has a code, a message, and a retryable flag', () => {
  const responses = [
    unauthorizedResponse(),
    notFoundResponse(),
    invalidMutationResponse('PAYLOAD_INVALID'),
    invalidChangesResponse('MALFORMED'),
    invalidChangesResponse('LIMIT_INVALID'),
    storageFailureResponse(true),
    storageFailureResponse(false),
    internalErrorResponse(),
  ];
  for (const response of responses) {
    const body = bodyOf(response);
    assertTrue(typeof body.code === 'string' && body.code.length > 0, 'code');
    assertTrue(typeof body.message === 'string' && body.message.length > 0, 'message');
    assertTrue(typeof body.retryable === 'boolean', 'retryable');
    assertTrue(response.statusCode !== undefined && response.statusCode >= 400, 'error status');
  }
});

check('no response body leaks provider, storage, or exception detail', () => {
  const bodies = [
    jsonResponse(200, { ok: true }),
    appliedMutationResponse({ status: 'applied', mutationId: 'm', note: NOTE, replayed: false }),
    conflictResponse({ status: 'conflict', mutationId: 'm', remoteNote: null }),
    changesResponse({ items: [NOTE], nextCursor: 'cursor', hasMore: true }),
    unauthorizedResponse(),
    notFoundResponse(),
    invalidMutationResponse('MUTATION_ID_REUSED'),
    invalidChangesResponse('ACCOUNT_MISMATCH'),
    storageFailureResponse(true),
    internalErrorResponse(),
  ].map((response) => bodyOf(response));

  for (const body of bodies) {
    const serialized = JSON.stringify(body);
    for (const forbidden of ['Error', 'stack', 'DynamoDB', 'Exception', 'OWNER#', 'jwt', 'token', '\n', '\t']) {
      assertTrue(!serialized.includes(forbidden), `a response body must not contain ${forbidden}`);
    }
  }
});

console.log(`${passed} sync-response checks passed`);
