import assert from 'node:assert/strict';
import {test, mock} from 'node:test';
import {DynamoDBDocumentClient, UpdateCommand} from '@aws-sdk/lib-dynamodb';
import {TestDynamo} from '../sharing/test_dynamo';
import {handler} from './lambda';
import {eventFor, requestBody, providerPayload} from './test_support';

test('real Lambda composition fails closed for missing secrets and uses current rotated key with canonical note', async () => {
  const keys = ['DEEPSEEK_API_KEY', 'SUMMARY_QUOTA_TABLE_NAME', 'NOTES_TABLE_NAME'];
  const before = keys.map(k => process.env[k]);
  const db = new TestDynamo();
  db.put({ownerId: 'OWNER#account-test', noteId: 'NOTE#synthetic-note', id: 'synthetic-note',
    title: 'Synthetic', content: 'synthetic note', revision: 1, protected: false, protectionRevision: 0,
    deletedAt: null, createdAt: '2026-10-06T00:00:00Z', serverUpdatedAt: '2026-10-06T00:00:00Z'});
  let quota = 0, requests = 0, run = 0;
  const tokens: string[] = [], logs: unknown[] = [];
  const sdk = mock.method(DynamoDBDocumentClient.prototype, 'send', async (c: any) => {
    if (c instanceof UpdateCommand && c.input.TableName === 'synthetic-quota') {quota++; return {};}
    return db.client.send(c);
  });
  const network = mock.method(globalThis, 'fetch', async (_url: unknown, init?: RequestInit) => {
    requests++; tokens.push(new Headers(init?.headers).get('authorization')!);
    return new Response(JSON.stringify(providerPayload('direct')), {headers: {'content-type': 'application/json'}});
  });
  const info = mock.method(console, 'info', (...args: unknown[]) => {logs.push(args);});
  const error = mock.method(console, 'error', (...args: unknown[]) => {logs.push(args);});
  async function invoke() {
    const body = requestBody('direct', ['synthetic note']);
    body.note.runId = String.fromCharCode(97 + run++).repeat(32);
    const r = await handler(eventFor({claims: {sub: 'account-test', token_use: 'access'}, body: JSON.stringify(body)}),
      {getRemainingTimeInMillis: () => 28000} as never, () => {});
    assert.ok(r && typeof r === 'object'); return r;
  }
  try {
    process.env.SUMMARY_QUOTA_TABLE_NAME = 'synthetic-quota';
    process.env.NOTES_TABLE_NAME = 'synthetic-notes';
    delete process.env.DEEPSEEK_API_KEY;
    assert.equal((await invoke()).statusCode, 500);
    process.env.DEEPSEEK_API_KEY = '<value will be resolved during runtime>';
    assert.equal((await invoke()).statusCode, 500);
    assert.equal(quota, 0); assert.equal(requests, 0);
    for (const key of ['synthetic-key-A', 'synthetic-key-B']) {
      process.env.DEEPSEEK_API_KEY = key;
      assert.equal((await invoke()).statusCode, 200);
    }
    assert.deepEqual(tokens, ['Bearer synthetic-key-A', 'Bearer synthetic-key-B']);
    assert.equal(quota, 2);
    delete process.env.DEEPSEEK_API_KEY;
    assert.equal((await invoke()).statusCode, 500);
    assert.equal(requests, 2);
    for (const key of ['synthetic-key-A', 'synthetic-key-B', 'synthetic note']) assert.ok(!JSON.stringify(logs).includes(key));
  } finally {
    keys.forEach((k,i) => {if (before[i] === undefined) delete process.env[k]; else process.env[k] = before[i];});
    sdk.mock.restore(); network.mock.restore(); info.mock.restore(); error.mock.restore();
  }
});
