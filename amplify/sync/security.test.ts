import assert from 'node:assert/strict';
import { test } from 'node:test';
import { GetCommand, QueryCommand, TransactWriteCommand,
  type DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { NoteSecurityError } from '../protection/protection_store';
import type { NoteSecurityAuthority, SecurityAuthorization } from '../protection/protection_store';
import { DynamoSyncStore } from './dynamo_sync_store';
import { normalizeMutation } from './sync_store_codec';
import type { SyncMutation } from './sync_store_models';

const snapshot = { id: 'alpha', title: 'private historical title', content: 'private historical body',
  revision: 7, createdAt: '2026-10-02T00:00:00Z', serverUpdatedAt: '2026-10-02T00:00:00Z',
  deletedAt: null, protected: true, protectionRevision: 1 };
const mutation: SyncMutation = { noteId: 'alpha', mutationId: 'stable-id', operation: 'update',
  baseRevision: 7, payload: { title: 'private updated title', content: 'private updated body' } };
const authorization: SecurityAuthorization = { actorId: 'owner', ownerId: 'owner', noteId: 'alpha',
  enabled: true, revision: 1, operation: 'edit', grantHash: 'digest', expiresAt: Date.now() + 60_000 };
function fixture({ replay = false, conflict = false, failSecond = false } = {}) {
  let checks = 0, reads = 0;
  const writes: TransactWriteCommand[] = [];
  const security: NoteSecurityAuthority = {
    async metadata() { return { enabled: true, revision: 1 }; },
    async authorize(_actor, _owner, _note, operation, grant) {
      checks++;
      if (grant !== 'synthetic-grant' || (failSecond && checks >= 2)) throw new NoteSecurityError('locked');
      return { ...authorization, operation };
    },
  };
  const db = { async send(command: GetCommand | QueryCommand | TransactWriteCommand) {
    reads++;
    if (command instanceof QueryCommand) return { Items: [{ ...snapshot, protected: false, changeSequence: 1 }] };
    if (command instanceof TransactWriteCommand) { writes.push(command); return {}; }
    const key = command.input.Key!.noteId as string;
    if (key === 'META#SYNC') return { Item: { lastSequence: 1 } };
    if (key === 'NOTE#alpha') return { Item: { ...snapshot, revision: conflict ? 8 : 7 } };
    if (key === 'MUTATION#stable-id' && replay) return { Item: {
      fingerprint: normalizeMutation(mutation).fingerprint, resultNote: snapshot } };
    return {};
  } } as unknown as DynamoDBDocumentClient;
  const store = new DynamoSyncStore({ tableName: 'test', documentClient: db, security });
  return { store, writes, reads: () => reads, checks: () => checks };
}

test('currently protected historical feed is always metadata-only', async () => {
  const { store } = fixture();
  const page = await store.listChanges('owner');
  assert.equal(page.items[0].title, '');
  assert.equal(page.items[0].content, '');
  assert.equal(page.items[0].contentAvailable, false);
  assert.equal(page.items[0].protected, true);
  assert.ok(!JSON.stringify(page).includes('private historical'));
});

test('missing grant is refused before reads, conflict or idempotent replay', async () => {
  for (const mode of [{}, { replay: true }, { conflict: true }]) {
    const { store, reads } = fixture(mode);
    await assert.rejects(store.applyMutation('owner', mutation),
      e => e instanceof NoteSecurityError && e.code === 'locked');
    assert.equal(reads(), 0);
  }
});

test('authorized ACK/replay/conflict never include protected body and recheck authority', async () => {
  for (const mode of [{}, { replay: true }, { conflict: true }]) {
    const { store, checks } = fixture(mode);
    const result = await store.applyMutation('owner', mutation,
      { actorId: 'owner', grant: 'synthetic-grant' });
    const note = result.status === 'applied' ? result.note : result.remoteNote!;
    assert.equal(note.contentAvailable, false);
    assert.equal(note.title, '');
    assert.equal(note.content, '');
    assert.ok(checks() >= 2);
  }
});

test('revocation after stored read blocks replay/conflict and commit', async () => {
  for (const mode of [{}, { replay: true }, { conflict: true }]) {
    const { store, writes } = fixture({ ...mode, failSecond: true });
    await assert.rejects(store.applyMutation('owner', mutation,
      { actorId: 'owner', grant: 'synthetic-grant' }), e => e instanceof NoteSecurityError);
    assert.equal(writes.length, 0);
  }
});

test('commit pins protection epoch, live actor/note/operation grant and server time', async () => {
  const { store, writes } = fixture();
  await store.applyMutation('owner', mutation, { actorId: 'owner', grant: 'synthetic-grant' });
  const guards = writes[0].input.TransactItems!.filter(x => x.ConditionCheck).map(x => x.ConditionCheck!);
  assert.equal(guards.length, 2);
  assert.match(guards[0].ConditionExpression!, /revision = :epoch AND enabled/);
  assert.match(guards[1].ConditionExpression!, /expiresAt > :now/);
  const values = guards[1].ExpressionAttributeValues!;
  assert.equal(values[':actor'], 'owner');
  assert.equal(values[':note'], 'alpha');
  assert.equal(values[':operation'], 'edit');
});
