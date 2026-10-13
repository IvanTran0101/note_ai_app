import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { APIGatewayProxyEventV2WithJWTAuthorizer as Event } from 'aws-lambda';
import { handleProtection } from './handler';
import { OwnerNoteAcl } from './protection_store';
import { TestPasswordHasher, TestProtectionStore } from './test_support';
import { ProtectionUseCases } from './use_cases';

const event = (wireVersion?: string, grant?: string): Event => ({
  rawPath: '/notes/alpha/content',
  queryStringParameters: wireVersion === undefined ? {} : { wireVersion },
  headers: grant ? { 'x-note-unlock-grant': grant } : {},
  requestContext: { http: { method: 'GET' } },
} as Event);

function fixture() {
  const store = new TestProtectionStore();
  store.notes.set('alpha', { ...store.notes.get('alpha')!, labelIds: ['label-a'], labelProjections: [] });
  const api = new ProtectionUseCases(store, new TestPasswordHasher(), new OwnerNoteAcl(),
    { async sendCode() {} }, () => Date.parse('2026-10-13T00:00:00Z'));
  const read = (wireVersion?: string, grant?: string) =>
    handleProtection(event(wireVersion, grant), 'owner', api, async () => 'qa@example.invalid');
  return { api, read };
}

test('content keeps legacy shape and returns labels only for negotiated V2', async () => {
  const { read } = fixture();
  for (const version of [undefined, '1']) {
    const result = await read(version);
    assert.equal(result.statusCode, 200);
    assert.equal(Object.hasOwn(JSON.parse(result.body!), 'labelIds'), false);
  }
  const result = await read('2');
  assert.equal(result.statusCode, 200);
  assert.deepEqual(JSON.parse(result.body!).labelIds, ['label-a']);
});

test('V2 content labels remain behind the current protected read grant', async () => {
  const { api, read } = fixture();
  await api.enable('owner', 'owner', 'alpha', 'synthetic-password', 1);
  const denied = await read('2');
  assert.equal(denied.statusCode, 423);
  assert.equal(denied.body!.includes('label-a'), false);
  const lease = await api.unlock('owner', 'owner', 'alpha', 'synthetic-password', ['read']);
  const allowed = await read('2', lease.grant);
  assert.equal(allowed.statusCode, 200);
  assert.deepEqual(JSON.parse(allowed.body!).labelIds, ['label-a']);
});

test('unsupported content wire negotiation is rejected explicitly', async () => {
  const { read } = fixture();
  assert.equal((await read('3')).statusCode, 422);
});
