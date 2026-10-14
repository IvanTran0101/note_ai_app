import test from 'node:test';
import assert from 'node:assert/strict';
import {GetCommand, TransactWriteCommand, type DynamoDBDocumentClient} from '@aws-sdk/lib-dynamodb';
import {parseNoteDocument, projectDocument} from './note_document';
import {parseMutationBody} from '../sync/request_parser';
import {normalizeMutation, nextSnapshot, snapshotAttributes, toNoteSnapshot, transactItemsFor} from '../sync/sync_store_codec';
import {DynamoSyncStore, type NoteSnapshot, type SyncMutation, SyncInvalidMutationError} from '../sync/dynamo_sync_store';
import {noteBodyOf, changesResponse, noteV2MutationResponse, invalidMutationResponse} from '../sync/sync_response';
import {ActorFeed} from '../sharing/actor_feed';

const at = '2026-10-14T00:00:00.000Z';
const doc = (bold = false) => parseNoteDocument({version: 1, blocks: [{id: 'p', type: 'paragraph',
  runs: [{type: 'text', text: 'private rich Việt 📝', ...(bold ? {marks: {bold: true}} : {})}]}]});
const rich = (): NoteSnapshot => ({id: 'n', title: 'Title', content: projectDocument(doc()), document: doc(),
  createdAt: at, serverUpdatedAt: at, revision: 7, deletedAt: null, pinnedAt: at, labelIds: ['label']});
const mutation = (bold = false): SyncMutation => ({wireVersion: 3, mutationId: 'm', noteId: 'n', operation: 'update', baseRevision: 7,
  payload: {title: 'Title', content: projectDocument(doc(bold)), document: doc(bold)}});
const body = (value: SyncMutation) => JSON.stringify({...value, entityType: 'note', documentCapability: 'basicBlocksV1'});

test('V3 parser requires document capability/presence and exact projection', () => {
  assert.equal(parseMutationBody(body(mutation()), false, false, 3).ok, true);
  assert.equal(parseMutationBody(body(mutation()), false, false, 2).ok, false);
  assert.deepEqual(parseMutationBody(JSON.stringify({...mutation(), entityType: 'note'}), false, false, 3),
    {ok: false, problem: 'DOCUMENTS_UNSUPPORTED'});
  assert.equal(parseMutationBody(body({...mutation(), payload: {title: 'Title', content: 'wrong', document: doc()}}), false, false, 3).ok, false);
  const empty = parseNoteDocument({version: 1, blocks: []});
  assert.equal(parseMutationBody(body({...mutation(), payload: {title: 'Title', content: '', document: empty}}), false, false, 3).ok, true);
  assert.equal(parseMutationBody(body({...mutation(), payload: {title: 'Title', content: '', document: null}}), false, false, 3).ok, false);
});

test('format-only change has another fingerprint and all snapshot/transaction copies retain document', () => {
  const first = normalizeMutation(mutation()), formatted = normalizeMutation(mutation(true));
  assert.notEqual(first.fingerprint, formatted.fingerprint);
  const snapshot = nextSnapshot(formatted, rich(), at);
  assert.deepEqual(snapshot.document, doc(true));
  assert.equal(snapshot.content, rich().content);
  assert.equal(snapshot.pinnedAt, at);
  assert.deepEqual(snapshot.labelIds, ['label']);
  assert.deepEqual(toNoteSnapshot(snapshotAttributes(snapshot)).document, doc(true));
  const writes = transactItemsFor('table', 'OWNER#owner', formatted, rich(), snapshot, 7, at)!;
  assert.deepEqual(writes[1].Put!.Item!.document, doc(true));
  assert.deepEqual(writes[2].Put!.Item!.document, doc(true));
  assert.deepEqual(writes[3].Put!.Item!.resultNote.document, doc(true));
});

test('legacy title/metadata update preserves rich structure; plain body replacement refuses', () => {
  const legacy = {...mutation(), wireVersion: undefined, payload: {title: 'Renamed', content: rich().content}};
  assert.deepEqual(nextSnapshot(normalizeMutation(legacy), rich(), at).document, doc());
  assert.throws(() => nextSnapshot(normalizeMutation({...legacy, payload: {title: 'Title', content: 'plain replacement'}}), rich(), at),
    (error: unknown) => error instanceof SyncInvalidMutationError && error.reason === 'DOCUMENTS_UNSUPPORTED');
  assert.throws(() => nextSnapshot(normalizeMutation({...mutation(), payload: {title: 'Title', content: rich().content, document: null}}), rich(), at), SyncInvalidMutationError);
  assert.equal(nextSnapshot(normalizeMutation({...mutation(), operation: 'delete', payload: undefined}), rich(), at).document, null);
});

test('lost-ACK legacy replay happens before rich current-state guard', async () => {
  const legacy: SyncMutation = {mutationId: 'legacy', noteId: 'n', operation: 'update', baseRevision: 1,
    payload: {title: 'Old', content: 'Old body'}};
  const normalized = normalizeMutation(legacy);
  let commits = 0;
  const previous = {...rich(), document: undefined, title: 'Old', content: 'Old body', revision: 2};
  const db = {async send(command: unknown) {
    if (command instanceof TransactWriteCommand) { commits++; throw new Error('Replay cannot commit'); }
    const id = (command as GetCommand).input.Key!.noteId;
    if (id === 'MUTATION#legacy') return {Item: {fingerprint: normalized.fingerprint, resultNote: snapshotAttributes(previous)}};
    if (id === 'NOTE#n') return {Item: snapshotAttributes(rich())};
    return {Item: {lastSequence: 7}};
  }} as unknown as DynamoDBDocumentClient;
  const result = await new DynamoSyncStore({tableName: 'table', documentClient: db}).applyMutation('owner', legacy);
  assert.equal(result.status, 'applied');
  if (result.status === 'applied') { assert.equal(result.replayed, true); assert.equal(result.note.content, 'Old body'); }
  assert.equal(commits, 0);
});

test('V3 body/response preserves document; legacy output and protected/revoked metadata never leak it', async () => {
  assert.deepEqual(noteBodyOf(rich(), false, true, true).document, doc());
  assert.equal(Object.hasOwn(noteBodyOf(rich()), 'document'), false);
  const protectedNote = {...rich(), protected: true, protectionRevision: 1};
  assert.equal(noteBodyOf(protectedNote, false, true, true).document, null);
  assert.deepEqual(noteBodyOf(protectedNote, true, true, true).document, doc());
  assert.equal(noteBodyOf({...rich(), title: '', content: '', document: null, contentAvailable: false}, false, true, true).document, null);
  const revoked = noteBodyOf({...rich(), title: '', content: '', document: null, contentAvailable: false}, false, true, true);
  assert.equal(revoked.protected, false);
  assert.equal(revoked.protectionRevision, 0);
  assert.equal(revoked.contentAvailable, false);
  const result = {status: 'applied' as const, mutationId: 'm', note: rich(), replayed: false};
  const response = JSON.parse(noteV2MutationResponse(result, 3).body!);
  assert.equal(response.documentCapability, 'basicBlocksV1');
  assert.deepEqual(response.note.document, doc());
  const page = JSON.parse(changesResponse({wireVersion: 3, items: [rich()], nextCursor: 'cursor', hasMore: false}).body!);
  assert.deepEqual(page.items[0].note.document, doc());
  assert.equal(JSON.parse(invalidMutationResponse('DOCUMENTS_UNSUPPORTED').body!).code, 'DOCUMENT_REQUIRES_UPGRADE');
  const writes = transactItemsFor('table', 'OWNER#owner', normalizeMutation(mutation()), rich(), protectedNote, 7, at)!;
  assert.equal(writes[2].Put!.Item!.document, null);
  assert.deepEqual(writes[1].Put!.Item!.document, doc());
  const db = {async send() { return {Item: {lastSequence: 7}}; }} as unknown as DynamoDBDocumentClient;
  const feed = new ActorFeed('table', db);
  assert.equal((await feed.append('actor', protectedNote))[1].Put!.Item!.document, null);
  assert.equal(Object.hasOwn(feed.event('owner', rich(), ['owner']).Put!.Item!, 'document'), false);
});

test('corrupt stored document/projection and oversize whole rich snapshot refuse', () => {
  assert.throws(() => toNoteSnapshot({...snapshotAttributes(rich()), content: 'wrong'}));
  assert.throws(() => toNoteSnapshot({...snapshotAttributes(rich()), document: {version: 2, blocks: []}}));
  const large = parseNoteDocument({version: 1, blocks: [{id: 'p', type: 'paragraph', runs: [{type: 'text', text: 'x'.repeat(80000)}]}]});
  const request = normalizeMutation({...mutation(), payload: {title: 't'.repeat(200000), content: projectDocument(large), document: large}});
  assert.throws(() => nextSnapshot(request, null, at), (error: unknown) => error instanceof SyncInvalidMutationError && error.reason === 'PAYLOAD_TOO_LARGE');
});
