import assert from 'node:assert/strict';
import { test } from 'node:test';
import { GetCommand, PutCommand, TransactWriteCommand,
  type DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import type { APIGatewayProxyEventV2WithJWTAuthorizer } from 'aws-lambda';
import { OwnerNoteAcl } from '../protection/protection_store';
import { ProtectionUseCases } from '../protection/use_cases';
import { TestPasswordHasher, TestProtectionStore } from '../protection/test_support';
import { SummaryFailure, type SummaryRequest } from './summary_contract';
import { createSummaryHandler } from './summary_handler';
import { DynamoSummaryNoteAuthority } from './summary_note_authority';

class RunDatabase {
  rows = new Map<string, Record<string, any>>();
  transactions: TransactWriteCommand[] = [];
  async send(command: GetCommand | PutCommand | TransactWriteCommand) {
    if (command instanceof GetCommand) return { Item: this.rows.get(command.input.Key!.noteId) };
    if (command instanceof PutCommand) {
      const item = command.input.Item!;
      const previous = this.rows.get(item.noteId);
      if (previous && (previous.working || previous.done || previous.version !== item.version)) throw Error('CAS');
      this.rows.set(item.noteId, item);
      return {};
    }
    this.transactions.push(command);
    const put = command.input.TransactItems![0].Put!;
    const previous = this.rows.get(put.Item!.noteId);
    if (previous?.nonce !== put.ExpressionAttributeValues![':nonce'] || !previous?.working) throw Error('CAS');
    this.rows.set(put.Item!.noteId, put.Item!);
    return {};
  }
}

async function fixture() {
  const store = new TestProtectionStore();
  const api = new ProtectionUseCases(store, new TestPasswordHasher(), new OwnerNoteAcl(),
    { async sendCode() {} });
  await api.enable('owner', 'owner', 'alpha', 'synthetic-password', 1);
  const lease = await api.unlock('owner', 'owner', 'alpha', 'synthetic-password', ['summary', 'manage']);
  const db = new RunDatabase();
  const authority = new DynamoSummaryNoteAuthority('test-table', db as unknown as DynamoDBDocumentClient,
    store, api);
  const request: SummaryRequest = { stage: 'direct', inputs: ['secret alpha'],
    note: { ownerId: 'owner', noteId: 'alpha', contentRevision: 1, protectionRevision: 1,
      runId: 'a'.repeat(32), sectionIndex: 0, sourceStart: null, sourceEnd: null } };
  return { store, api, lease, db, authority, request };
}

const changed = (e: unknown) => e instanceof SummaryFailure && e.code === 'noteChanged';
const locked = (e: unknown) => e instanceof SummaryFailure && e.code === 'noteLocked';

test('formatted note Summary validates readable text while retaining authority checks', async () => {
  const { authority, request, lease, store, db } = await fixture();
  const content = 'noteflow:rich:v1\n' + JSON.stringify([
    { insert: 'secret alpha', attributes: { bold: true, color: '#1565C0' } },
    { insert: '\n', attributes: { header: 1 } },
  ]);
  store.notes.set('alpha', { ...store.notes.get('alpha')!, content });
  await assert.rejects(authority.begin(request, 'owner'), locked);
  await assert.rejects(authority.begin({ ...request, inputs: [content] }, 'owner', lease.grant), changed);
  const stage = await authority.begin(request, 'owner', lease.grant);
  await stage.complete('readable result');
  assert.equal(db.transactions.length, 1);
});

test('canonical Summary rejects missing grant, forged source, revision and actor before stage reservation', async () => {
  const { authority, request, lease, db } = await fixture();
  await assert.rejects(authority.begin(request, 'owner'), locked);
  await assert.rejects(authority.begin(request, 'other', lease.grant), locked);
  await assert.rejects(authority.begin({ ...request, inputs: ['unrelated private note'] }, 'owner', lease.grant), changed);
  await assert.rejects(authority.begin({ ...request, note: { ...request.note!, contentRevision: 2 } }, 'owner', lease.grant), changed);
  assert.equal(db.rows.size, 0);
});

test('section lineage is contiguous and merge accepts only ordered approved outputs', async () => {
  const { authority, request, lease, db, store } = await fixture();
  const source = 'First section. Second section.';
  store.notes.set('alpha', { ...store.notes.get('alpha')!, content: source });
  const section = (index: number, start: number, end: number): SummaryRequest =>
    ({ stage: 'section', inputs: [source.slice(start, end).trim()],
      note: { ...request.note!, sectionIndex: index, sourceStart: start, sourceEnd: end } });
  await assert.rejects(authority.begin(section(0, 2, 14), 'owner', lease.grant), changed);
  const first = await authority.begin(section(0, 0, 14), 'owner', lease.grant);
  await first.complete('approved first');
  await assert.rejects(authority.begin(section(0, 0, 14), 'owner', lease.grant), changed);
  const second = await authority.begin(section(1, 15, source.length), 'owner', lease.grant);
  await second.complete('approved second');
  const merge: SummaryRequest = { stage: 'merge', inputs: ['approved first', 'approved second'],
    note: { ...request.note!, sectionIndex: 2 } };
  await assert.rejects(authority.begin({ ...merge, inputs: ['forged output', 'approved second'] }, 'owner', lease.grant), changed);
  const last = await authority.begin(merge, 'owner', lease.grant);
  await last.complete('final output');
  assert.equal(db.transactions.length, 3);
  const conditions = db.transactions[2].input.TransactItems!;
  assert.equal(conditions.length, 4);
  assert.match(conditions[3].ConditionCheck!.ConditionExpression!, /contains\(operations/);
  assert.equal(conditions[3].ConditionCheck!.ExpressionAttributeValues![':op'], 'summary');
  await assert.rejects(authority.begin(merge, 'owner', lease.grant), changed);
});

test('UTF-16 chunks never bisect a surrogate pair', async () => {
  const { authority, request, lease, store } = await fixture();
  store.notes.set('alpha', { ...store.notes.get('alpha')!, content: 'A🧪B' });
  await assert.rejects(authority.begin({ stage: 'section', inputs: ['A\ud83e'],
    note: { ...request.note!, sourceStart: 0, sourceEnd: 2 } }, 'owner', lease.grant), changed);
});

test('late stage output after protection change is discarded without completing run', async () => {
  const { authority, request, lease, store, db } = await fixture();
  const stage = await authority.begin(request, 'owner', lease.grant);
  store.protections.set('alpha', { ...store.protections.get('alpha')!, revision: 2 });
  await assert.rejects(stage.complete('late private output'), locked);
  assert.equal(db.transactions.length, 0);
});

function event(body: unknown, grant?: string): APIGatewayProxyEventV2WithJWTAuthorizer {
  return { rawPath: '/ai/summary', headers: grant ? { 'x-note-unlock-grant': grant } : {},
    body: JSON.stringify(body), requestContext: { http: { method: 'POST' },
      authorizer: { jwt: { claims: { sub: 'owner', token_use: 'access' } } } },
  } as unknown as APIGatewayProxyEventV2WithJWTAuthorizer;
}

test('HTTP Summary gate runs before quota/provider and rejects late result after revocation', async () => {
  const { authority, request, lease, store } = await fixture();
  let quota = 0, provider = 0;
  const handler = createSummaryHandler({ security: authority,
    consumeQuota: async () => { quota++; return { allowed: true }; },
    generate: async () => {
      provider++;
      store.protections.set('alpha', { ...store.protections.get('alpha')!, revision: 2 });
      return { summary: 'private provider result', usage: { inputTokens: 1, outputTokens: 1 } };
    } });
  const body = { ...request, consent: { accepted: true, version: 'summary-cloud-v1' } };
  const refused = await handler(event(body));
  assert.equal(JSON.parse(refused.body!).error.code, 'noteLocked');
  assert.equal(quota, 0);
  assert.equal(provider, 0);
  const late = await handler(event(body, lease.grant));
  assert.equal(provider, 1);
  assert.equal(JSON.parse(late.body!).error.code, 'noteLocked');
  assert.ok(!late.body!.includes('private provider result'));
});
