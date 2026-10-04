import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createHash } from 'node:crypto';
import { TestDynamo } from '../sharing/test_dynamo';
import { DynamoNoteAcl, shareKey } from '../sharing/dynamo_note_acl';
import { DynamoProtectionStore } from '../protection/dynamo_protection_store';
import { ProtectionAuthorizer } from '../protection/authorizer';
import { NoteSecurityError } from '../protection/protection_store';
import { DynamoSyncStore } from '../sync/dynamo_sync_store';
import { normalizeMutation } from '../sync/sync_store_codec';
import { stableDigest } from '../sync/cursor';
import { parseMutationBody } from '../sync/request_parser';
import { noteBodyOf } from '../sync/sync_response';
import { AttachmentAttemptStore } from './attempt_store';
import { AttachmentUseCases, stagingKey } from './use_cases';
import { AttachmentError, CHUNK_BYTES, fileMetadata, manifest } from './models';
import { handleAttachments } from './handler';
import type { FileMetadata, Attempt } from './models';
import type { AttachmentObjectStore } from './object_store';
const hash = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');
const id = 'a'.repeat(64);
class Objects implements AttachmentObjectStore {
  values = new Map<string, Buffer>(); heads = new Map<string, string>(); next = 0;
  onRead?: () => void;
  async uploadUrl(key: string, size: number, sha256: string) { return {url: `https://upload.invalid/${key}`, headers: {size: String(size), checksum: sha256}}; }
  put(key: string, bytes: Buffer) { const version = String(++this.next); this.heads.set(key, version); this.values.set(`${key}@${version}`, Buffer.from(bytes)); }
  async pin(key: string, size: number, sha256: string) {
    const version = this.heads.get(key)!; const b = this.values.get(`${key}@${version}`);
    if (!b || b.length !== size || hash(b) !== sha256) throw new AttachmentError('invalid');
    return {version, sizeBytes: size, sha256};
  }
  async *read(key: string, version: string, start: number, end: number) {
    this.onRead?.(); const b = this.values.get(`${key}@${version}`)!;
    for (let i = start; i < end; i += 4096) yield Uint8Array.from(b.subarray(i, Math.min(i + 4096, end)));
  }
  async finalize(key: string, m: FileMetadata, chunks: AsyncIterable<Uint8Array>) {
    if (this.heads.has(key)) return this.heads.get(key)!;
    const xs: Buffer[] = []; for await (const b of chunks) xs.push(Buffer.from(b));
    const bytes = Buffer.concat(xs); assert.equal(hash(bytes), m.sha256); this.put(key, bytes); return this.heads.get(key)!;
  }
  async removeStaging(prefix: string) { for (const key of this.values.keys()) if (key.startsWith(prefix)) this.values.delete(key); }
}
async function fixture() {
  const db = new TestDynamo(), ps = new DynamoProtectionStore('t', db.client, true);
  const security = new ProtectionAuthorizer(ps, new DynamoNoteAcl('t', db.client));
  const attempts = new AttachmentAttemptStore('t', db.client), objects = new Objects();
  const service = new AttachmentUseCases(attempts, objects, security);
  const sync = new DynamoSyncStore({tableName: 't', documentClient: db.client, security, sharing: true, attachments: attempts});
  await sync.applyMutation('owner', {mutationId: 'create', noteId: 'n', baseRevision: 0, operation: 'create', payload: {title: 'Title', content: 'Body'}});
  const bytes = Buffer.from('safe UTF8 text\n'.repeat(25000));
  const m = {fileName: 'sample.txt', mimeType: 'text/plain', sizeBytes: bytes.length, sha256: hash(bytes), id};
  async function staged(attemptId = id, data = bytes, meta = {...m, id: attemptId}) {
    await service.begin('owner', 'owner', 'n', meta);
    for (let i = 0; i * CHUNK_BYTES < data.length; i++) {
      const b = data.subarray(i * CHUNK_BYTES, (i + 1) * CHUNK_BYTES);
      const a = (await attempts.read('owner', 'n', attemptId))!;
      await service.uploadUrl('owner', 'owner', 'n', attemptId, i, hash(b));
      objects.put(stagingKey(a, i), b);
      await service.confirmChunk('owner', 'owner', 'n', attemptId, i, hash(b));
    }
    return await attempts.read('owner', 'n', attemptId) as Attempt;
  }
  async function linked() {
    await staged(); const status = await service.verify('owner', 'owner', 'n', id); const attachment = status.attachment!;
    const mutation = {wireVersion: 2 as const, mutationId: 'link', noteId: 'n', baseRevision: 1,
      operation: 'update' as const, payload: {title: 'Title', content: 'Body', attachments: [attachment]}};
    await sync.applyMutation('owner', mutation); return {attachment, mutation};
  }
  return {db, ps, security, attempts, objects, service, sync, bytes, m, staged, linked};
}
test('policy validates exact shape, type/size/path/checksum and Note quota', () => {
  const valid = {fileName: 'file.txt', mimeType: 'text/plain', sizeBytes: 1, sha256: '0'.repeat(64)};
  assert.deepEqual(fileMetadata(valid), valid);
  for (const bad of [{fileName: '../x.txt'}, {mimeType: 'application/octet-stream'}, {sizeBytes: 0},
    {sizeBytes: 20 * 1024 * 1024 + 1}, {sha256: 'bad'}]) assert.throws(() => fileMetadata({...valid, ...bad}));
  assert.throws(() => manifest(Array(11).fill(valid)));
});
test('durable stable begin/chunk ACK/verify replay; no mutation before association', async () => {
  const f = await fixture(); await f.staged();
  const a = await f.attempts.read('owner', 'n', id); await f.service.begin('owner', 'owner', 'n', f.m);
  assert.equal((await f.attempts.read('owner', 'n', id))!.generation, a!.generation);
  await f.service.confirmChunk('owner', 'owner', 'n', id, 0, hash(f.bytes.subarray(0, CHUNK_BYTES)));
  const ready = await f.service.verify('owner', 'owner', 'n', id);
  assert.equal(ready.phase, 'verified'); assert.equal(f.db.get('owner', 'NOTE#n')!.revision, 1);
  assert.deepEqual(await f.service.verify('owner', 'owner', 'n', id), ready);
  await assert.rejects(() => f.service.begin('owner', 'owner', 'n', {...f.m, sha256: 'b'.repeat(64)}));
});
test('association is canonical atomic, replay stable, unverified and changed descriptors refused', async () => {
  const f = await fixture(); const {attachment, mutation} = await f.linked();
  assert.equal((await f.service.status('owner', 'owner', 'n', id)).phase, 'linked');
  const replay = await f.sync.applyMutation('owner', mutation); assert.equal(replay.status, 'applied');
  if (replay.status === 'applied') assert.equal(replay.replayed, true);
  await assert.rejects(() => f.sync.applyMutation('owner', {...mutation, mutationId: 'bad', baseRevision: 2,
    payload: {...mutation.payload, attachments: [{...attachment, objectVersion: 'forged'}]}}));
  assert.equal(f.db.get('owner', 'NOTE#n')!.revision, 2);
});
test('legacy text writes preserve manifests, explicit remove ACK transitions unlinked', async () => {
  const f = await fixture(); const {attachment} = await f.linked();
  await f.sync.applyMutation('owner', {mutationId: 'legacy', noteId: 'n', baseRevision: 2, operation: 'update', payload: {title: 'New', content: 'Body2'}});
  assert.deepEqual(f.db.get('owner', 'NOTE#n')!.attachments, [attachment]);
  await f.sync.applyMutation('owner', {wireVersion: 2, mutationId: 'remove', noteId: 'n', baseRevision: 3,
    operation: 'update', payload: {title: 'New', content: 'Body2', attachments: []}});
  assert.equal((await f.attempts.read('owner', 'n', id))!.phase, 'unlinked');
  assert.equal(f.db.get('owner', 'ATTACHMENT_QUOTA#n')!.count, 0);
  await assert.rejects(() => f.service.content('owner', 'owner', 'n', id, attachment.objectVersion, 0, 3));
  assert.ok(f.objects.values.has(`${attachment.storageObjectId}@${attachment.objectVersion}`));
});
test('manifest omission/empty/change participate in fingerprint without altering legacy bytes', async () => {
  const f = await fixture(); const {mutation, attachment} = await f.linked();
  const bare = {...mutation, payload: {title: 'Title', content: 'Body'}};
  assert.notEqual(normalizeMutation(bare).fingerprint, normalizeMutation(mutation).fingerprint);
  assert.notEqual(normalizeMutation({...bare, payload: {...bare.payload, attachments: []}}).fingerprint, normalizeMutation(bare).fingerprint);
  const legacy = {...bare, wireVersion: undefined};
  assert.equal(normalizeMutation(legacy).fingerprint, stableDigest('mutation:["update","n",1,"Title","Body"]'));
  assert.equal(parseMutationBody(JSON.stringify({...mutation, entityType: 'note'}), false, false, 2).ok, true);
  assert.equal(parseMutationBody(JSON.stringify({...mutation, wireVersion: undefined})).ok, false);
  assert.equal(parseMutationBody(JSON.stringify({...mutation, entityType: 'note', payload: {...mutation.payload, attachments: [{...attachment, noteId: 'other'}]}}), false, false, 2).ok, false);
});
test('pinned staging bytes survive PUT reuse/overwrite; final descriptor pins verified bytes', async () => {
  const f = await fixture(); const a = await f.staged();
  f.objects.put(stagingKey(a, 0), Buffer.alloc(CHUNK_BYTES, 0));
  const s = await f.service.verify('owner', 'owner', 'n', id);
  const out: Buffer[] = [];
  for await (const b of f.objects.read(s.attachment!.storageObjectId, s.attachment!.objectVersion, 0, f.bytes.length)) out.push(Buffer.from(b));
  assert.equal(hash(Buffer.concat(out)), f.m.sha256);
});
test('fake file MIME/invalid UTF8 rejected from actual staged bytes and never associated', async () => {
  const f = await fixture(); const bytes = Buffer.from([0xff, 0xfe, 0]);
  await f.staged(id, bytes, {...f.m, sizeBytes: bytes.length, sha256: hash(bytes)});
  await assert.rejects(() => f.service.verify('owner', 'owner', 'n', id), (e: unknown) => e instanceof AttachmentError && e.code === 'invalid');
  assert.equal(f.db.get('owner', 'NOTE#n')!.attachments, undefined);
});
test('cancel is durable/idempotent; late verify/link/cancel-after-linked cannot delete final', async () => {
  const f = await fixture(); await f.staged(); await f.service.cancel('owner', 'owner', 'n', id);
  await f.service.cancel('owner', 'owner', 'n', id);
  await assert.rejects(() => f.service.verify('owner', 'owner', 'n', id));
  assert.equal(f.db.get('owner', 'ATTACHMENT_QUOTA#n')!.count, 0);
  const g = await fixture(); const {attachment} = await g.linked();
  await assert.rejects(() => g.service.cancel('owner', 'owner', 'n', id));
  assert.ok(g.objects.values.has(`${attachment.storageObjectId}@${attachment.objectVersion}`));
});
test('owner/shared read fresh ACL, bounds/version checks and final authorization after read', async () => {
  const f = await fixture(); const {attachment} = await f.linked();
  const now = new Date().toISOString(), share = {ownerId: 'owner', noteId: 'n', recipientId: 'recipient',
    role: 'viewer', accessRevision: 1, status: 'active', sharedAt: now, updatedAt: now, revokedAt: null};
  f.db.put({...shareKey('owner', 'n', 'recipient'), share});
  const r = await f.service.content('recipient', 'owner', 'n', id, attachment.objectVersion, 13, 30);
  assert.deepEqual(r.bytes, f.bytes.subarray(13, 30));
  await assert.rejects(() => f.service.begin('recipient', 'owner', 'n', f.m));
  await assert.rejects(() => f.service.content('stranger', 'owner', 'n', id, attachment.objectVersion, 0, 10));
  await assert.rejects(() => f.service.content('owner', 'owner', 'n', id, attachment.objectVersion, 0, CHUNK_BYTES + 1));
  await assert.rejects(() => f.service.content('owner', 'owner', 'n', id, 'wrong', 0, 1));
  f.objects.onRead = () => f.db.put({...shareKey('owner', 'n', 'recipient'), share: {...share, status: 'revoked', accessRevision: 2, revokedAt: now}});
  await assert.rejects(() => f.service.content('recipient', 'owner', 'n', id, attachment.objectVersion, 0, 10));
});
test('protection grants are operation-specific; lock/expiry metadata hides filenames', async () => {
  const f = await fixture(); const {attachment} = await f.linked();
  f.db.put({ownerId: 'OWNER#owner', noteId: 'PROTECTION#n', canonicalOwnerId: 'owner', targetNoteId: 'n',
    enabled: true, revision: 1, verifier: 'test-verifier'});
  const raw = 'x'.repeat(43), grant = {hash: hash(Buffer.from(raw)), actorId: 'owner', ownerId: 'owner',
    noteId: 'n', revision: 1, operations: ['read'], issuedAt: Date.now(), expiresAt: Date.now() + 60000};
  await f.ps.putGrant(grant as any);
  await assert.rejects(() => f.service.content('owner', 'owner', 'n', id, attachment.objectVersion, 0, 10), NoteSecurityError);
  await assert.rejects(() => f.service.content('owner', 'owner', 'n', id, attachment.objectVersion, 0, 10, raw));
  const binaryRaw = 'y'.repeat(43);
  await f.ps.putGrant({...grant, hash: hash(Buffer.from(binaryRaw)), operations: ['attachmentRead']} as any);
  assert.equal((await f.service.content('owner', 'owner', 'n', id, attachment.objectVersion, 0, 10, binaryRaw)).bytes.length, 10);
  const wire = noteBodyOf({...f.db.get('owner', 'NOTE#n'), id: 'n', protected: true} as any);
  assert.deepEqual(wire.attachments, []); assert.ok(!JSON.stringify(wire).includes('sample.txt'));
});
test('quota reservation and cancellation CAS close concurrent admission races', async () => {
  const f = await fixture();
  for (let i = 0; i < 10; i++) await f.service.begin('owner', 'owner', 'n', {...f.m, id: createHash('sha256').update(String(i)).digest('hex')});
  await assert.rejects(() => f.service.begin('owner', 'owner', 'n', {...f.m, id}), (e: unknown) => e instanceof AttachmentError && e.code === 'quota');
  const g = await fixture(); g.db.beforeTransaction = () => {
    g.db.put({ownerId: 'OWNER#owner', noteId: 'ATTACHMENT_QUOTA#n', generation: 1, count: 10, bytes: 100});
  };
  await assert.rejects(() => g.service.begin('owner', 'owner', 'n', g.m));
  assert.equal(await g.attempts.read('owner', 'n', id), null);
});
test('HTTP binary206/auth/Range/method contract; no signed GET or grant URL', async () => {
  const f = await fixture(); const {attachment} = await f.linked();
  const e = {rawPath: `/notes/n/attachments/${id}/content`, headers: {range: 'bytes=0-9'},
    queryStringParameters: {objectVersion: attachment.objectVersion}, requestContext: {http: {method: 'GET'}}} as any;
  const r = await handleAttachments(e, 'owner', f.service); assert.equal(r.statusCode, 206);
  assert.equal(r.headers!['content-range'], `bytes 0-9/${f.bytes.length}`);
  assert.deepEqual(Buffer.from(r.body!, 'base64'), f.bytes.subarray(0, 10));
  assert.equal((await handleAttachments({...e, headers: {}}, 'owner', f.service)).statusCode, 422);
  assert.equal((await handleAttachments(e, 'stranger', f.service)).statusCode, 403);
  assert.equal((await handleAttachments({...e, requestContext: {http: {method: 'POST'}}, body: '{}'}, 'owner', f.service)).statusCode, 404);
});

test('cancel before begin is durable/idempotent and blocks late upload without reserving quota', async () => {
  const f = await fixture();
  assert.equal((await f.service.cancel('owner', 'owner', 'n', id)).phase, 'cancelled');
  await f.service.cancel('owner', 'owner', 'n', id);
  await assert.rejects(() => f.service.begin('owner', 'owner', 'n', f.m));
  assert.equal(await f.attempts.read('owner', 'n', id), null);
  assert.equal(f.db.get('owner', 'ATTACHMENT_QUOTA#n'), undefined);
  await assert.rejects(() => f.service.cancel('stranger', 'owner', 'n', id));
});

test('begin wins cancellation race only until fresh cancellation retries and closes the attempt', async () => {
  const f = await fixture();
  f.db.beforeTransaction = () => {
    const attempt = {...f.m, actorId: 'owner', ownerId: 'owner', targetNoteId: 'n',
      protectionRevision: 0, protected: false, phase: 'uploading', generation: 1,
      finalKey: 'final/race', createdAt: new Date().toISOString(), chunks: []};
    f.db.put({ownerId: 'OWNER#owner', noteId: `ATTEMPT#${JSON.stringify(['n', id])}`, generation: 1, attempt});
    f.db.put({ownerId: 'OWNER#owner', noteId: 'ATTACHMENT_QUOTA#n', generation: 1, count: 1, bytes: f.bytes.length});
  };
  await assert.rejects(() => f.service.cancel('owner', 'owner', 'n', id));
  await f.service.cancel('owner', 'owner', 'n', id);
  assert.equal((await f.attempts.read('owner', 'n', id))!.phase, 'cancelled');
  assert.equal(f.db.get('owner', 'ATTACHMENT_QUOTA#n')!.count, 0);
});

test('fresh owner protection epoch continues immutable pending bytes, but old grants cannot', async () => {
  const f = await fixture(); await f.staged();
  const original = (await f.attempts.read('owner', 'n', id))!;
  f.db.put({ownerId: 'OWNER#owner', noteId: 'PROTECTION#n', canonicalOwnerId: 'owner', targetNoteId: 'n',
    enabled: true, revision: 1, verifier: 'test-verifier'});
  const raw = 'z'.repeat(43);
  await f.ps.putGrant({hash: hash(Buffer.from(raw)), actorId: 'owner', ownerId: 'owner', noteId: 'n',
    revision: 1, operations: ['attachmentWrite'], issuedAt: Date.now(), expiresAt: Date.now() + 60000} as any);
  await assert.rejects(() => f.service.verify('owner', 'owner', 'n', id, raw));
  await assert.rejects(() => f.service.begin('owner', 'owner', 'n', f.m));
  await f.service.begin('owner', 'owner', 'n', f.m, raw);
  const renewed = (await f.attempts.read('owner', 'n', id))!;
  assert.deepEqual(renewed.chunks, original.chunks);
  assert.equal(renewed.finalKey, original.finalKey); assert.equal(renewed.protectionRevision, 1);
  assert.equal((await f.service.verify('owner', 'owner', 'n', id, raw)).phase, 'verified');
  f.db.put({ownerId: 'OWNER#owner', noteId: 'PROTECTION#n', canonicalOwnerId: 'owner', targetNoteId: 'n', enabled: true, revision: 2, verifier: 'new-test-verifier'});
  await assert.rejects(() => f.service.cancel('owner', 'owner', 'n', id, raw));
  const fresh = 'w'.repeat(43);
  await f.ps.putGrant({hash: hash(Buffer.from(fresh)), actorId: 'owner', ownerId: 'owner', noteId: 'n',
    revision: 2, operations: ['attachmentWrite'], issuedAt: Date.now(), expiresAt: Date.now() + 60000} as any);
  await f.service.cancel('owner', 'owner', 'n', id, fresh);
  assert.equal((await f.attempts.read('owner', 'n', id))!.phase, 'cancelled');
});
