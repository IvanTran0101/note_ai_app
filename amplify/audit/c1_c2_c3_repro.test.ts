/**
 * Reproduction tests for backend audit findings C1, C2 and C3.
 *
 * These tests assert the DESIRED contract, not today's behaviour, so they are
 * expected to FAIL on the current tree and pass once the findings are fixed.
 * Each failure message names the finding and the evidence, so a red run is
 * itself the report.
 *
 *   C1  `/notes/*` and `/sync/*` accept a Cognito ID token, while `/me/*`,
 *       `/ai/summary`, `/rag/query` and consent require `token_use=access`.
 *   C2  Share-by-email can never resolve a recipient: `pre-sign-up` stores
 *       `email_verified=false`, `CognitoRecipientResolver` requires `"true"`.
 *   C3  `pre-sign-up` auto-confirms the account while leaving the mailbox
 *       unproven, so "email" is treated as identity without proof.
 *
 * Run (from the repository root of the branch under test):
 *
 *   npx tsx --test amplify/audit/c1_c2_c3_repro.test.ts
 *
 * No network, no AWS credentials, and no live table: the DynamoDB document
 * client and the Cognito client are both double-substituted. Nothing here is
 * exported and no production file is modified.
 */
import assert from 'node:assert/strict';
import {test, mock} from 'node:test';
import {DynamoDBDocumentClient} from '@aws-sdk/lib-dynamodb';
import type {APIGatewayProxyEventV2WithJWTAuthorizer as Event} from 'aws-lambda';

/** The deployed handler builds its clients at module scope, so env comes first. */
process.env.NOTES_TABLE_NAME = 'synthetic-table';
process.env.NOTES_TABLE_REGION = 'us-east-1';

const {handler: syncHandler} = await import('../sync/handler');
const {handler: preSignUp} = await import('../auth/pre-sign-up/handler');
const {CognitoRecipientResolver} = await import('../sharing/cognito_recipient_resolver');

/* ------------------------------------------------------------------ helpers */

const CONTENT_CANARY = 'C1_CONTENT_CANARY';

/** One owned, unprotected note; the shape `toNoteSnapshot` accepts. */
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

const eventOf = (rawPath: string, claims: Record<string, unknown>): Event =>
  ({
    rawPath,
    headers: {},
    requestContext: {http: {method: 'GET'}, authorizer: {jwt: {claims}}},
  }) as unknown as Event;

const invoke = async (event: Event) => {
  const value = (await syncHandler(event, {} as never, () => {})) as {
    statusCode: number;
    body?: string;
  };
  return {
    status: value.statusCode,
    body: value.body ? JSON.parse(value.body) : null,
  };
};

/**
 * Serves `NOTE#alpha` and reports no protection row, which is exactly what a
 * real unprotected note looks like. Every Dynamo call in this file is answered
 * here; a missing branch is a wiring bug in the test, not a passing test.
 */
const stubNoteStore = () =>
  mock.method(DynamoDBDocumentClient.prototype, 'send', async (command: unknown) => {
    const key = (command as {input?: {Key?: {noteId?: string}}}).input?.Key;
    if (key?.noteId === 'NOTE#alpha') return {Item: NOTE_ITEM};
    return {Item: undefined};
  });

/* ---------------------------------------------------------------------- C1 */

test('C1 control: an access token still reads note content (guards against over-closing)', async () => {
  const sdk = stubNoteStore();
  try {
    const result = await invoke(
      eventOf('/notes/alpha/content', {sub: 'owner', token_use: 'access'}),
    );
    assert.equal(result.status, 200, JSON.stringify(result.body));
    assert.equal(result.body?.content, CONTENT_CANARY);
  } finally {
    sdk.mock.restore();
  }
});

test('C1: an ID token must not be accepted on the note data plane', async () => {
  const sdk = stubNoteStore();
  try {
    const idToken = {sub: 'owner', token_use: 'id'};

    const content = await invoke(eventOf('/notes/alpha/content', idToken));
    assert.equal(
      content.status,
      401,
      `FINDING C1: an ID token read note content (status ${content.status}, ` +
        `body ${JSON.stringify(content.body)}). The gateway audience is the app ` +
        `client id, which both Cognito ID and access tokens satisfy, and the ` +
        '`/notes/*` branch of sync/handler.ts never checks `token_use`.',
    );

    // The same token is already rejected on /me/, which is the inconsistency.
    const profile = await invoke(eventOf('/me/profile', idToken));
    assert.equal(profile.status, 401, JSON.stringify(profile.body));
  } finally {
    sdk.mock.restore();
  }
});

/* ---------------------------------------------------------------------- C2 */

const signupEventOf = (email: string) =>
  ({
    triggerSource: 'PreSignUp_SignUp',
    request: {userAttributes: {email}},
    response: {autoConfirmUser: false, autoVerifyEmail: false},
  }) as never;

/** A Cognito ListUsers answer for one confirmed account with [verified]. */
const cognitoPoolOf = (email: string, verified: string) => ({
  send: async () => ({
    PaginationToken: undefined,
    Users: [
      {
        Enabled: true,
        UserStatus: 'CONFIRMED',
        Attributes: [
          {Name: 'sub', Value: 'recipient-sub'},
          {Name: 'email', Value: email},
          {Name: 'email_verified', Value: verified},
        ],
      },
    ],
  }),
});

test('C2: an account created by this pool must be invitable by email', async () => {
  const email = 'recipient@example.com';
  const signup = (await preSignUp(
    signupEventOf(email),
    {} as never,
    () => {},
  )) as {response: {autoConfirmUser: boolean; autoVerifyEmail: boolean}};

  // This is the attribute value Cognito would persist for a freshly signed-up
  // account, derived from the trigger's own response rather than assumed.
  const storedVerified = signup.response.autoVerifyEmail ? 'true' : 'false';

  const resolver = new CognitoRecipientResolver(
    'synthetic-pool',
    cognitoPoolOf(email, storedVerified) as never,
  );

  let recipient: string | null = null;
  let failure = '';
  try {
    recipient = await resolver.resolve(email);
  } catch (error) {
    failure = String((error as {message?: string})?.message ?? error);
  }

  assert.ok(
    recipient,
    'FINDING C2: share-by-email is unreachable for every account this pool ' +
      `creates. pre-sign-up returns autoVerifyEmail=${signup.response.autoVerifyEmail}, ` +
      `so the stored email_verified is "${storedVerified}", while ` +
      'CognitoRecipientResolver accepts only "true". ' +
      `Resolver answered: ${failure || '(no error, but no recipient)'}.`,
  );
});

/* ---------------------------------------------------------------------- C3 */

test('C3: signup must not confirm an account whose mailbox is unproven', async () => {
  // Deliberately an address the test cannot receive mail at: that is the point.
  const claimedEmail = 'someone-else-controlled@example.com';
  const signup = (await preSignUp(
    signupEventOf(claimedEmail),
    {} as never,
    () => {},
  )) as {response: {autoConfirmUser: boolean; autoVerifyEmail: boolean}};

  const usable = signup.response.autoConfirmUser === true;
  const mailboxProven = signup.response.autoVerifyEmail === true;

  assert.ok(
    !(usable && !mailboxProven),
    'FINDING C3: signup marks the account usable (autoConfirmUser=true) while ' +
      `nobody proved control of "${claimedEmail}" ` +
      `(autoVerifyEmail=${signup.response.autoVerifyEmail}). An unproven address ` +
      'can be squatted, blocking the real owner from registering, and any future ' +
      'feature that trusts email as identity inherits the gap.',
  );
});
