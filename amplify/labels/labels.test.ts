import test from 'node:test';
import assert from 'node:assert/strict';
import { TestDynamo } from '../sharing/test_dynamo';
import { DynamoLabelStore } from './dynamo_label_store';
import { labelIds, labelName, parseLabelMutation } from './label_models';
import { DynamoSyncStore } from '../sync/dynamo_sync_store';
import { parseMutationBody } from '../sync/request_parser';
import { changesResponse, noteBodyOf } from '../sync/sync_response';
import { decodeChangeCursor } from '../sync/cursor';
import { projectNoteLabels } from './note_label_projection';
import { toNoteSnapshot } from '../sync/sync_store_codec';
import { labelProjectionResponse } from './label_projection_handler';
import { DynamoNoteAcl } from '../sharing/dynamo_note_acl';
import { DynamoShareStore } from '../sharing/dynamo_share_store';
import { ShareUseCases } from '../sharing/share_use_cases';
import { ProtectionUseCases } from '../protection/use_cases';
import { DynamoProtectionStore } from '../protection/dynamo_protection_store';
import { TestPasswordHasher } from '../protection/test_support';

const command = (id = 'same', operation = 'create', revision = 0, name = 'Việt Nam', mutationId = 'label-write') =>
  parseLabelMutation({wireVersion: 2, entityType: 'label', labelId: id,
    mutationId, operation, baseRevision: revision, ...(operation === 'delete' ? {} : {payload: {name}})});
const note = (mutationId = 'note-write', operation: 'create' | 'update' = 'create', baseRevision = 0,
    ids?: readonly string[]) => ({wireVersion: 2 as const, mutationId, noteId: 'same', operation, baseRevision,
      payload: {title: 'Title', content: 'Body', ...(ids ? {labelIds: ids} : {})}});
function setup() {
  const db = new TestDynamo();
  return {db, labels: new DynamoLabelStore('table', db.client), notes: new DynamoSyncStore({tableName: 'table', documentClient: db.client})};
}
test('Dart parity: Unicode64/name and32 unique IDs; duplicate names allowed', () => {
  assert.equal(labelName('  Việt Nam  '), 'Việt Nam');
  assert.equal(labelName('😀'.repeat(64)), '😀'.repeat(64));
  assert.throws(() => labelName('😀'.repeat(65)));
  assert.throws(() => labelName('a\nb'));
  assert.throws(() => labelIds(['a', 'a']));
  assert.throws(() => labelIds(Array.from({length: 33}, (_, i) => String(i))));
  assert.deepEqual(labelIds(['b', 'a']), ['a', 'b']);
});
test('legacy parser refuses label metadata; typed shared editor refuses organize', () => {
  const body = {...note(), entityType: 'note', payload: {title: 'Title', content: 'Body', labelIds: ['same']}};
  assert.equal(parseMutationBody(JSON.stringify(body)).ok, false);
  assert.equal(parseMutationBody(JSON.stringify(body), false, false, 2).ok, true);
  assert.equal(parseMutationBody(JSON.stringify({...body, ownerId: 'owner', accessRevision: 1}), false, true, 2).ok, false);
  assert.throws(() => parseLabelMutation({...command(), ownerId: 'other'}));
});
test('catalog ACK replay immutable; reused mutation ID rejects other name', async () => {
  const {db, labels} = setup(), request = command();
  const first = await labels.apply('owner', request);
  assert.equal(first.status, 'applied');
  const count = db.transactions.length;
  const replay = await labels.apply('owner', request);
  assert.equal(replay.status, 'applied');
  assert.equal(db.transactions.length, count);
  await assert.rejects(labels.apply('owner', command('same', 'create', 0, 'Other')));
  assert.equal(db.get('owner', 'META#SYNC')?.lastSequence, 1);
});
test('same-ID Note and Label do not collide; v1 consumes typed prefix safely', async () => {
  const {labels, notes} = setup();
  await labels.apply('owner', command());
  await notes.applyMutation('owner', note('label-write', 'create', 0, ['same']));
  const old = await notes.listChanges('owner', null, 1);
  assert.equal(old.items.length, 0);
  assert.equal(decodeChangeCursor(old.nextCursor, 'owner'), 1);
  assert.equal(old.hasMore, true);
  const oldSecond = await notes.listChanges('owner', old.nextCursor);
  assert.equal(oldSecond.items.length, 1);
  const typed = await notes.listChanges('owner', null, 50, 2);
  assert.equal(typed.labels?.length, 1);
  assert.equal(typed.items.length, 1);
  assert.equal(decodeChangeCursor(typed.nextCursor, 'owner'), 2);
  assert.equal(typed.items[0].labelProjections?.[0].name, 'Việt Nam');
  const wire = JSON.parse(changesResponse(typed).body!);
  assert.equal(wire.wireVersion, 2);
  assert.deepEqual(new Set(wire.items.map((i: any) => i.entityType)), new Set(['note', 'label']));
});
test('fresh added-label CAS rejects deletion race with no partial Note ACK', async () => {
  const {db, labels, notes} = setup();
  await labels.apply('owner', command());
  db.beforeTransaction = () => db.put({...db.get('owner', 'LABEL#same'), deletedAt: new Date().toISOString(), revision: 2});
  await assert.rejects(notes.applyMutation('owner', note('note-write', 'create', 0, ['same'])));
  assert.equal(db.get('owner', 'NOTE#same'), undefined);
  assert.equal(db.get('owner', 'MUTATION#note-write'), undefined);
});
test('legacy text update preserves membership; deleted Label does not delete Note', async () => {
  const {db, labels, notes} = setup();
  await labels.apply('owner', command());
  await notes.applyMutation('owner', note('n1', 'create', 0, ['same']));
  await labels.apply('owner', command('same', 'delete', 1, '', 'label-delete'));
  await notes.applyMutation('owner', {mutationId: 'legacy', noteId: 'same', operation: 'update', baseRevision: 1,
    payload: {title: 'Changed', content: 'Body'}});
  assert.deepEqual(db.get('owner', 'NOTE#same')?.labelIds, ['same']);
  assert.equal(db.get('owner', 'NOTE#same')?.deletedAt, null);
  const page = await notes.listChanges('owner', null, 50, 2);
  assert.deepEqual(page.items.at(-1)?.labelProjections, []);
});
test('rename changes scoped projections without rewriting Note revision', async () => {
  const {db, labels, notes} = setup();
  await labels.apply('owner', command());
  await notes.applyMutation('owner', note('n1', 'create', 0, ['same']));
  await labels.apply('owner', command('same', 'update', 1, 'Học tập', 'rename'));
  const stored = db.get('owner', 'NOTE#same')!;
  assert.equal(stored.revision, 1);
  const projection = await projectNoteLabels(db.client, 'table', 'owner', toNoteSnapshot(stored));
  assert.deepEqual(projection.labelProjections, [{id: 'same', name: 'Học tập'}]);
});
test('locked/revoked projection and response contain no private label metadata', async () => {
  const {db} = setup();
  const protectedNote = {id: 'same', title: 'Title', content: 'Body', revision: 1,
    createdAt: '2026-10-04T00:00:00Z', serverUpdatedAt: '2026-10-04T00:00:00Z', deletedAt: null,
    protected: true, contentAvailable: false, labelIds: ['secret'], labelProjections: [{id: 'secret', name: 'Private'}]};
  const projected = await projectNoteLabels(db.client, 'table', 'owner', protectedNote, true);
  assert.deepEqual(projected.labelProjections, []);
  assert.deepEqual(projected.labelIds, []);
  assert.ok(!JSON.stringify(noteBodyOf(protectedNote, false, true)).includes('secret'));
});

async function sharedFixture() {
  const h = setup();
  await h.labels.apply('owner', command());
  await h.labels.apply('owner', command('private', 'create', 0, 'Unrelated private catalog', 'private'));
  await h.notes.applyMutation('owner', note('n1', 'create', 0, ['same']));
  const acl = new DynamoNoteAcl('table', h.db.client);
  const security = new ProtectionUseCases(new DynamoProtectionStore('table', h.db.client, true),
    new TestPasswordHasher(), acl, {async sendCode() {}});
  const shares = new ShareUseCases(new DynamoShareStore('table', h.db.client),
    {async resolve() {return 'recipient';}}, security);
  await shares.apply('owner', 'owner', 'same', {requestId: 'share', action: 'create',
    email: 'recipient@example.invalid', role: 'editor', expectedAccessRevision: 0});
  const request = {wireVersion: 2, notes: [{ownerId: 'owner', noteId: 'same'}]};
  return {...h, security, shares, request};
}
test('recipient refresh sees renamed labels on this Note only, without a Note revision write', async () => {
  const h = await sharedFixture();
  await h.labels.apply('owner', command('same', 'update', 1, 'Renamed', 'rename'));
  const result = JSON.parse((await labelProjectionResponse('recipient', h.request, 'table', h.db.client, h.security)).body!);
  assert.deepEqual(result.items[0].note.labelProjections, [{id: 'same', name: 'Renamed'}]);
  assert.ok(!JSON.stringify(result).includes('Unrelated private catalog'));
  assert.equal(h.db.get('owner', 'NOTE#same')?.revision, 1);
});
test('revoke immediately masks labels/body from scoped refresh, including previous feed content', async () => {
  const h = await sharedFixture();
  await h.shares.apply('owner', 'owner', 'same', {requestId: 'revoke', action: 'revoke', recipientId: 'recipient', expectedAccessRevision: 1});
  const result = JSON.parse((await labelProjectionResponse('recipient', h.request, 'table', h.db.client, h.security)).body!);
  assert.deepEqual(result.items[0].note.labelIds, []);
  assert.deepEqual(result.items[0].note.labelProjections, []);
  assert.equal(result.items[0].note.contentAvailable, false);
  assert.equal(result.items[0].note.share.status, 'revoked');
});
test('scoped refresh never reads a Note outside fresh ACL or an over-cap batch', async () => {
  const h = await sharedFixture();
  await assert.rejects(labelProjectionResponse('stranger', h.request, 'table', h.db.client, h.security));
  await assert.rejects(labelProjectionResponse('owner', {wireVersion: 2, notes: Array(51).fill(h.request.notes[0])}, 'table', h.db.client, h.security));
});

test('protected shared projection requires its separate read grant and restores only attached labels', async () => {
  const h = await sharedFixture();
  await h.security.enable('owner', 'owner', 'same', 'qa-password', 1);
  const locked = JSON.parse((await labelProjectionResponse('recipient', h.request, 'table', h.db.client, h.security)).body!);
  assert.deepEqual(locked.items[0].note.labelIds, []);
  assert.deepEqual(locked.items[0].note.labelProjections, []);
  const lease = await h.security.unlock('recipient', 'owner', 'same', 'qa-password', ['read']);
  const request = {wireVersion: 2, notes: [{...h.request.notes[0], grant: lease.grant}]};
  const readable = JSON.parse((await labelProjectionResponse('recipient', request, 'table', h.db.client, h.security)).body!);
  assert.deepEqual(readable.items[0].note.labelProjections, [{id: 'same', name: 'Việt Nam'}]);
  assert.ok(!JSON.stringify(readable).includes('Unrelated private catalog'));
});
