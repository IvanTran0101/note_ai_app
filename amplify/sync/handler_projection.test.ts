import assert from 'node:assert/strict';
import {test, mock} from 'node:test';
import {DynamoDBDocumentClient} from '@aws-sdk/lib-dynamodb';
import type {APIGatewayProxyEventV2WithJWTAuthorizer as Event} from 'aws-lambda';
import {TestDynamo} from '../sharing/test_dynamo';

process.env.NOTES_TABLE_NAME = 'synthetic-table';
process.env.NOTES_TABLE_REGION = 'us-east-1';
const {handler} = await import('./handler');
const event = (body: unknown, actor: string | null = 'owner'): Event => ({
  rawPath: '/sync/v2/label-projections', body: typeof body === 'string' ? body : JSON.stringify(body),
  requestContext: {http: {method: 'POST'}, authorizer: {jwt: {claims: actor ? {sub: actor, token_use: 'access'} : {}}}},
}) as Event;
async function invoke(body: unknown, actor: string | null = 'owner') {
  const value = await handler(event(body, actor), {} as never, () => {});
  assert.ok(value && typeof value === 'object');
  return {status: value.statusCode, body: JSON.parse(value.body!)};
}

test('real projection handler maps bad body/schema to nonretryable input errors before reads', async () => {
  let reads = 0;
  const sdk = mock.method(DynamoDBDocumentClient.prototype, 'send', async () => {reads++; throw Error('No external read expected');});
  try {
    for (const body of ['{', {wireVersion: 1, notes: []}, {wireVersion: 2},
      {wireVersion: 2, notes: Array(51).fill({ownerId: 'owner', noteId: 'n'})},
      {wireVersion: 2, notes: [{ownerId: '', noteId: 'n'}]},
      {wireVersion: 2, notes: [{ownerId: 'owner', noteId: 'n', grant: 4}]}]) {
      const r = await invoke(body);
      assert.equal(r.status, 422);
      assert.equal(r.body.code, 'INVALID_MUTATION');
      assert.equal(r.body.retryable, false);
    }
    assert.equal((await invoke('{', null)).status, 401);
    assert.deepEqual(await invoke({wireVersion: 2, notes: []}),
      {status: 200, body: {wireVersion: 2, items: [], hasMore: false}});
    assert.equal(reads, 0);
  } finally {sdk.mock.restore();}
});

test('real projection handler preserves readable owner projection and denies foreign access', async () => {
  const db = new TestDynamo();
  db.put({ownerId: 'OWNER#owner', noteId: 'NOTE#alpha', id: 'alpha', title: 'Synthetic', content: 'Synthetic body',
    revision: 1, deletedAt: null, createdAt: '2026-10-06T00:00:00Z', serverUpdatedAt: '2026-10-06T00:00:00Z'});
  const sdk = mock.method(DynamoDBDocumentClient.prototype, 'send', async (command: any) => db.client.send(command));
  try {
    const own = await invoke({wireVersion: 2, notes: [{ownerId: 'owner', noteId: 'alpha'}]});
    assert.equal(own.status, 200);
    assert.equal(own.body.items[0].note.content, 'Synthetic body');
    const denied = await invoke({wireVersion: 2, notes: [{ownerId: 'other', noteId: 'alpha'}]});
    assert.equal(denied.status, 403);
    assert.ok(!JSON.stringify(denied.body).includes('Synthetic body'));
    db.put({...db.get('owner', 'NOTE#alpha')!, protected: true, protectionRevision: 1});
    db.put({ownerId: 'OWNER#owner', noteId: 'PROTECTION#alpha', canonicalOwnerId: 'owner', targetNoteId: 'alpha', enabled: true, revision: 1, verifier: 'synthetic-verifier'});
    const locked = await invoke({wireVersion: 2, notes: [{ownerId: 'owner', noteId: 'alpha'}]});
    assert.equal(locked.status, 200);
    assert.equal(locked.body.items[0].note.contentAvailable, false);
    assert.ok(!JSON.stringify(locked.body).includes('Synthetic body'));
  } finally {sdk.mock.restore();}
});

test('server/storage JSON errors are not misclassified as malformed request input', async () => {
  const sdk = mock.method(DynamoDBDocumentClient.prototype, 'send', async () => {throw new SyntaxError('PRIVATE_CANARY');});
  try {
    const r = await invoke({wireVersion: 2, notes: [{ownerId: 'owner', noteId: 'alpha'}]});
    assert.equal(r.status, 500);
    assert.equal(r.body.retryable, true);
    assert.ok(!JSON.stringify(r.body).includes('PRIVATE_CANARY'));
  } finally {sdk.mock.restore();}
});

test('typed security storage failure remains retryable 503', async () => {
  let reads = 0;
  const sdk = mock.method(DynamoDBDocumentClient.prototype, 'send', async () => {
    if (++reads === 1) return {Item: {id: 'alpha', title: 'Synthetic', content: 'PRIVATE_CANARY', revision: 1,
      createdAt: '2026-10-06T00:00:00Z', serverUpdatedAt: '2026-10-06T00:00:00Z', deletedAt: null}};
    throw Error('PRIVATE_STORAGE_CANARY');
  });
  try {
    const r = await invoke({wireVersion: 2, notes: [{ownerId: 'owner', noteId: 'alpha'}]});
    assert.equal(r.status, 503);
    assert.equal(r.body.code, 'NOTE_SECURITY_UNAVAILABLE');
    assert.equal(r.body.retryable, true);
    assert.ok(!JSON.stringify(r.body).includes('CANARY'));
  } finally {sdk.mock.restore();}
});
