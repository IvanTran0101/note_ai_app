/**
 * Acceptance matrix for audit finding C1: the `/notes/*` and `/sync/*` data
 * plane must require a Cognito ACCESS token (`token_use === 'access'`), the way
 * `/me/*` already does, and must refuse every other claim shape BEFORE any
 * store or service call.
 *
 * These tests assert the DESIRED contract, so every non-access claim variant is
 * expected to FAIL (red) until the C1 guard lands in `handler.ts`. The
 * access-token controls and the contract-preservation cases must stay green
 * before and after the fix, so the guard cannot over-close the API.
 *
 * Run (from the repository root of the branch under test):
 *
 *   npx tsx --test amplify/sync/token_use_guard.test.ts
 *
 * No network, no AWS credentials, no live table: the DynamoDB document client
 * is double-substituted and the exported handler is invoked directly. The
 * harness is modeled on `amplify/audit/c1_c2_c3_repro.test.ts` and
 * `amplify/sync/handler_projection.test.ts`; body shapes come from
 * `amplify/sync/request_parser.test.ts`.
 */
import assert from 'node:assert/strict';
import {test, mock} from 'node:test';
import {DynamoDBDocumentClient, QueryCommand} from '@aws-sdk/lib-dynamodb';
import type {APIGatewayProxyEventV2WithJWTAuthorizer as Event} from 'aws-lambda';

/**
 * The handler builds its SDK clients and services at module scope, so every
 * variable it reads is pinned before the import. `ATTACHMENT_BUCKET` is set so
 * the attachment service is constructed for the attachment-path control; the
 * 401 cases must be refused before that service is ever consulted.
 */
process.env.NOTES_TABLE_NAME = 'synthetic-table';
process.env.NOTES_TABLE_REGION = 'us-east-1';
process.env.ATTACHMENT_BUCKET = 'synthetic-bucket';

const {handler} = await import('./handler');

/* ------------------------------------------------------------------ helpers */

const CONTENT_CANARY = 'C1_CONTENT_CANARY';

/** One owned, unprotected note under OWNER#owner; the shape toNoteSnapshot accepts. */
const NOTE_ITEM = {
  ownerId: 'OWNER#owner',
  noteId: 'NOTE#alpha',
  id: 'alpha',
  title: 'Synthetic title',
  content: CONTENT_CANARY,
  revision: 1,
  createdAt: '2026-10-02T00:00:00Z',
  serverUpdatedAt: '2026-10-02T00:00:00Z',
  deletedAt: null,
};

type Claims = Record<string, unknown>;

/** The claim variants every route family of the matrix is probed with. */
const ID_TOKEN: Claims = {sub: 'owner', token_use: 'id'};
const MISSING_TOKEN_USE: Claims = {sub: 'owner'};
const MISSING_SUB: Claims = {token_use: 'access'};
const ACCESS_TOKEN: Claims = {sub: 'owner', token_use: 'access'};

const REJECTED_CLAIMS: readonly {name: string; claims: Claims}[] = [
  {name: 'an ID token (token_use "id")', claims: ID_TOKEN},
  {name: 'a token without token_use', claims: MISSING_TOKEN_USE},
  {name: 'a token without sub', claims: MISSING_SUB},
];

const eventOf = (method: string, rawPath: string, claims: Claims, body?: string): Event =>
  ({
    rawPath,
    ...(body === undefined ? {} : {body}),
    headers: {},
    requestContext: {http: {method}, authorizer: {jwt: {claims}}},
  }) as unknown as Event;

type Invocation = Readonly<{status: number; body: unknown; raw: string}>;

const invoke = async (event: Event): Promise<Invocation> => {
  const value = (await handler(event, {} as never, () => {})) as {
    statusCode: number;
    body?: string;
  };
  return {
    status: value.statusCode,
    body: value.body ? JSON.parse(value.body) : null,
    raw: value.body ?? '',
  };
};

/**
 * Serves the owner's note only under its full key (OWNER#owner + NOTE#alpha)
 * and answers every query with an empty page: an account with one unprotected
 * note and an empty feed. Keying on BOTH pk and sk is what the ownership case
 * relies on - a request by another subject must not be handed the owner's row.
 * Every Dynamo call in this file is answered here; a missing branch is a wiring
 * bug in the test, not a passing test.
 */
const stubStore = () =>
  mock.method(DynamoDBDocumentClient.prototype, 'send', async (command: unknown) => {
    if (command instanceof QueryCommand) return {Items: [], Count: 0, ScannedCount: 0};
    const key = (command as {input?: {Key?: {ownerId?: string; noteId?: string}}}).input?.Key;
    if (key?.ownerId === 'OWNER#owner' && key?.noteId === 'NOTE#alpha') return {Item: NOTE_ITEM};
    return {Item: undefined};
  });

/** One route of the matrix, as a function of the authorizer claims. */
type Route = Readonly<{name: string; eventOf: (claims: Claims) => Event}>;

/**
 * The rejection half of the matrix: every non-access claim variant must draw a
 * 401 with ZERO Dynamo calls - the refusal must happen before any store or
 * service call, or a confused-deputy token would still reach the backend.
 */
const assertGuardRejects = async (routes: readonly Route[]): Promise<void> => {
  const sdk = stubStore();
  try {
    for (const rejected of REJECTED_CLAIMS) {
      for (const route of routes) {
        const callsBefore = sdk.mock.callCount();
        const result = await invoke(route.eventOf(rejected.claims));
        assert.equal(
          result.status,
          401,
          `FINDING C1: ${route.name} accepted ${rejected.name} (status ${result.status}, ` +
            `body ${result.raw}). The gateway audience is the app client id, which both ` +
            'Cognito ID and access tokens satisfy, so this route must require ' +
            'token_use === "access", as /me/ already does.',
        );
        assert.equal(
          sdk.mock.callCount(),
          callsBefore,
          `FINDING C1: ${route.name} touched the store while refusing ${rejected.name}; ` +
            'the rejection must happen before any store or service call.',
        );
      }
    }
  } finally {
    sdk.mock.restore();
  }
};

/**
 * The control half: a valid access token must get PAST the guard, so closing
 * the C1 gap cannot over-close the API. Any non-401 status is sufficient proof
 * the guard passed; `check` may pin the family-specific happy path on top.
 */
const assertControlPassesGuard = async (
  route: Route,
  check?: (result: Invocation) => void,
): Promise<void> => {
  const sdk = stubStore();
  try {
    const result = await invoke(route.eventOf(ACCESS_TOKEN));
    assert.notStrictEqual(
      result.status,
      401,
      `${route.name} refused a valid access token (body ${result.raw}); ` +
        'the token_use guard over-closed the route.',
    );
    check?.(result);
  } finally {
    sdk.mock.restore();
  }
};

/* ------------------------------------------------- 1. POST /sync/*mutations */

/** A create body the parser accepts for the given wire version. */
const noteMutationBody = (wireVersion: 1 | 2 | 3): string =>
  JSON.stringify({
    ...(wireVersion >= 2 ? {wireVersion, entityType: 'note'} : {}),
    ...(wireVersion === 3 ? {documentCapability: 'basicBlocksV1'} : {}),
    mutationId: `mutation-${wireVersion}`,
    noteId: `note-${wireVersion}`,
    operation: 'create',
    baseRevision: 0,
    payload:
      wireVersion === 3
        ? {title: 'Title', content: 'Content', document: null}
        : {title: 'Title', content: 'Content'},
  });

const MUTATION_ROUTES: readonly Route[] = (
  ['/sync/mutations', '/sync/v2/mutations', '/sync/v3/mutations'] as const
).map(
  (path): Route => ({
    name: `POST ${path}`,
    eventOf: (claims) =>
      eventOf('POST', path, claims, noteMutationBody(
        path === '/sync/v3/mutations' ? 3 : path === '/sync/v2/mutations' ? 2 : 1,
      )),
  }),
);

test('mutations routes: only an access token may apply a mutation', async () => {
  await assertGuardRejects(MUTATION_ROUTES);
  for (const route of MUTATION_ROUTES) {
    // Any non-401 (200 applied / 409 conflict / 422 invalid) proves the guard
    // passed; the store path itself is covered by the store's own tests.
    await assertControlPassesGuard(route);
  }
});

/* -------------------------------------------------- 2. GET /sync/*changes */

const CHANGES_ROUTES: readonly Route[] = (
  ['/sync/changes', '/sync/v2/changes', '/sync/v3/changes'] as const
).map(
  (path): Route => ({
    name: `GET ${path}`,
    eventOf: (claims) => eventOf('GET', path, claims),
  }),
);

test('changes routes: only an access token may read the change feed', async () => {
  await assertGuardRejects(CHANGES_ROUTES);
  for (const route of CHANGES_ROUTES) {
    await assertControlPassesGuard(route, (result) => {
      assert.equal(result.status, 200, JSON.stringify(result.body));
      assert.equal((result.body as {items?: readonly unknown[]}).items?.length, 0);
    });
  }
});

/* --------------------------------- 3. POST /sync/v2/label-projections */

const LABEL_PROJECTIONS: Route = {
  name: 'POST /sync/v2/label-projections',
  eventOf: (claims) =>
    eventOf('POST', '/sync/v2/label-projections', claims, JSON.stringify({wireVersion: 2, notes: []})),
};

test('label projection route: only an access token may project labels', async () => {
  // This route is special-cased in the handler BEFORE the generic sync
  // dispatch, so it needs its own row in the matrix.
  await assertGuardRejects([LABEL_PROJECTIONS]);
  await assertControlPassesGuard(LABEL_PROJECTIONS, (result) => {
    assert.equal(result.status, 200, JSON.stringify(result.body));
    assert.deepEqual(result.body, {wireVersion: 2, items: [], hasMore: false});
  });
});

/* ------------------------------------------------- 4. GET /notes/:id/content */

const NOTE_CONTENT: Route = {
  name: 'GET /notes/alpha/content',
  eventOf: (claims) => eventOf('GET', '/notes/alpha/content', claims),
};

test('note content route: only an access token may read note content', async () => {
  await assertGuardRejects([NOTE_CONTENT]);
  await assertControlPassesGuard(NOTE_CONTENT, (result) => {
    assert.equal(result.status, 200, JSON.stringify(result.body));
    assert.equal((result.body as {content?: string}).content, CONTENT_CANARY);
  });
});

/* ------------------------------- 5. shares and protection route families */

/**
 * Both controls send an empty body on purpose: input validation then refuses
 * the request before any share/protection store round trip, so no extra
 * environment (Cognito pool, more tables) is needed to prove the guard passed.
 */
const SHARES: Route = {
  name: 'POST /notes/alpha/shares',
  eventOf: (claims) => eventOf('POST', '/notes/alpha/shares', claims, ''),
};

const PROTECTION: Route = {
  name: 'POST /notes/alpha/protection/enable',
  eventOf: (claims) => eventOf('POST', '/notes/alpha/protection/enable', claims, ''),
};

test('sharing and protection routes: only an access token reaches them', async () => {
  await assertGuardRejects([SHARES, PROTECTION]);
  // A non-401 answer (here 422 from input validation) is sufficient proof the
  // guard passed: these services may need more env/tables than the stub serves.
  await assertControlPassesGuard(SHARES);
  await assertControlPassesGuard(PROTECTION);
});

/* ---------------------------------------------------- 6. attachment routes */

const ATTACHMENT_STATUS: Route = {
  name: 'GET /notes/alpha/attachments/<64-hex id>/status',
  eventOf: (claims) =>
    eventOf('GET', `/notes/alpha/attachments/${'a'.repeat(64)}/status`, claims),
};

test('attachment route: only an access token may drive attachments', async () => {
  // The attachment service is only constructed because this file sets
  // ATTACHMENT_BUCKET before the import; the 401 cases must be refused before
  // that service is even consulted.
  await assertGuardRejects([ATTACHMENT_STATUS]);
  await assertControlPassesGuard(ATTACHMENT_STATUS);
});

/* ----------------------------------------------- contract preservation */

test('contract: /sync/health stays reachable without any authorizer claims', async () => {
  const sdk = stubStore();
  try {
    const result = await invoke(eventOf('GET', '/sync/health', {}));
    assert.equal(result.status, 200, JSON.stringify(result.body));
    assert.equal((result.body as {ok?: boolean}).ok, true);
    assert.equal(sdk.mock.callCount(), 0, 'health must not touch the store');
  } finally {
    sdk.mock.restore();
  }
});

test('contract: an unknown path stays 404 even with a valid access token', async () => {
  const sdk = stubStore();
  try {
    const result = await invoke(eventOf('GET', '/sync/nope', ACCESS_TOKEN));
    assert.equal(result.status, 404, JSON.stringify(result.body));
    assert.equal(sdk.mock.callCount(), 0, 'routing must not touch the store');
  } finally {
    sdk.mock.restore();
  }
});

test('ownership: another subject\'s access token must not read the owner note', async () => {
  const sdk = stubStore();
  try {
    // Valid access token, wrong subject: the C1 guard passes, so the existing
    // ACL/protection logic decides - for a subject who owns no such note that
    // is a 403, and the load-bearing property is that the content never leaks.
    const result = await invoke(eventOf('GET', '/notes/alpha/content', {sub: 'other', token_use: 'access'}));
    assert.equal(result.status, 403, JSON.stringify(result.body));
    assert.ok(
      !result.raw.includes(CONTENT_CANARY),
      `the owner's note content leaked to another subject: ${result.raw}`,
    );
  } finally {
    sdk.mock.restore();
  }
});
