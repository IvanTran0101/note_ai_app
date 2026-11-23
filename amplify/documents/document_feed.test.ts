import test from 'node:test';
import assert from 'node:assert/strict';
import {QueryCommand, type DynamoDBDocumentClient} from '@aws-sdk/lib-dynamodb';
import {boundedChangeRows} from '../sync/bounded_change_rows';
import {DynamoSyncStore} from '../sync/dynamo_sync_store';
import {snapshotAttributes} from '../sync/sync_store_codec';
import {decodeChangeCursor} from '../sync/cursor';
import {parseNoteDocument, projectDocument} from './note_document';

const at = '2026-10-14T00:00:00.000Z';
test('typed feed byte prefix keeps label/note sequence and cursor at last returned row', async () => {
  const document = parseNoteDocument({version: 1, blocks: [{id: 'p', type: 'paragraph',
    runs: [{type: 'text', text: 'x'.repeat(98000)}]}]});
  const rows: (Record<string, unknown> & {changeSequence: number})[] = Array.from({length: 7}, (_, i) => ({...snapshotAttributes({id: `n${i}`, title: 'Title',
    content: projectDocument(document), document, createdAt: at, serverUpdatedAt: at,
    revision: 1, deletedAt: null}), changeSequence: i + 1}));
  rows[1] = {entityType: 'label', canonicalOwnerId: 'owner', id: 'label', name: 'Label',
    createdAt: at, serverUpdatedAt: at, deletedAt: null, revision: 1, changeSequence: 2};
  const db = {async send(command: QueryCommand) {
    assert.ok(command instanceof QueryCommand);
    const after = command.input.ExpressionAttributeValues![':after'];
    return {Items: rows.filter(row => row.changeSequence > after)};
  }} as unknown as DynamoDBDocumentClient;
  const store = new DynamoSyncStore({tableName: 'table', documentClient: db});
  const first = await store.listChanges('owner', null, 7, 3);
  assert.equal(first.hasMore, true);
  assert.equal(first.items.length, 4);
  assert.equal(first.labels!.length, 1);
  assert.equal(decodeChangeCursor(first.nextCursor, 'owner'), 5);
  const second = await store.listChanges('owner', first.nextCursor, 7, 3);
  assert.equal(second.hasMore, false);
  assert.equal(second.items.length, 2);
  assert.equal(decodeChangeCursor(second.nextCursor, 'owner'), 7);
  assert.deepEqual([...first.items, ...second.items].map(n => n.id), ['n0','n2','n3','n4','n5','n6']);
});
test('prefix never skips a large legacy first row or a row after the budget boundary', () => {
  const rows = [{sequence: 1, content: 'x'.repeat(40)}, {sequence: 2, content: 'next'}];
  assert.deepEqual(boundedChangeRows(rows, 2, 10), [rows[0]]);
  assert.deepEqual(boundedChangeRows(rows.slice(1), 2, 10), [rows[1]]);
});
