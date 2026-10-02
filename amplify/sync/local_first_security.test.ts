import assert from 'node:assert/strict';
import { test } from 'node:test';
import { pbkdf2Sync } from 'node:crypto';
import { GetCommand, TransactWriteCommand, type DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { ProtectionAuthorizer, securityDigest } from '../protection/authorizer';
import { DynamoProtectionStore } from '../protection/dynamo_protection_store';
import { Argon2idPasswordHasher } from '../protection/argon2id_password_hasher';
import { NoteSecurityError, OwnerNoteAcl } from '../protection/protection_store';
import { DynamoSyncStore } from './dynamo_sync_store';
import { parseMutationBody } from './request_parser';
import { normalizeMutation } from './sync_store_codec';
import type { ProtectionSyncChange, SyncMutation } from './sync_store_models';

const salt = Buffer.alloc(16, 7);
const password = 'synthetic-local-password';
const verifier = `pbkdf2-sha256-v1$${salt.toString('base64')}$${pbkdf2Sync(password, salt, 600_000, 32, 'sha256').toString('base64')}`;
const change = (before = 0, enabled = true): ProtectionSyncChange => ({
  before: { enabled: before > 0, revision: before },
  after: { enabled, revision: before + 1 }, verifier: enabled ? verifier : null,
});
const request = (id = 'create', epoch = 0, enabled = true): SyncMutation => ({
  mutationId: id, noteId: 'alpha', operation: epoch ? 'update' : 'create',
  baseRevision: epoch, payload: { title: 'private local title', content: 'private local body' },
  protectionChange: change(epoch, enabled),
});

function fixture() {
  const rows = new Map<string, Record<string, unknown>>();
  const writes: TransactWriteCommand[] = [];
  const db = { async send(command: GetCommand | TransactWriteCommand) {
    if (command instanceof GetCommand) return { Item: rows.get(command.input.Key!.noteId as string) };
    assert.ok(command instanceof TransactWriteCommand);
    const items = command.input.TransactItems!;
    // Validate all relevant conditional guards before applying any write.
    for (const item of items) {
      const op = item.Put ?? item.ConditionCheck;
      if (!op) continue;
      const key = item.Put?.Item?.noteId ?? item.ConditionCheck?.Key?.noteId;
      const old = rows.get(key as string), condition = op.ConditionExpression ?? '';
      const v = op.ExpressionAttributeValues ?? {};
      if (condition.includes('attribute_not_exists(noteId)')) assert.equal(old, undefined);
      if (condition.includes('revision = :epoch')) assert.equal(old?.revision, v[':epoch']);
      if (condition.includes('enabled = :enabled')) assert.equal(old?.enabled, v[':enabled']);
      if (condition.includes('expiresAt > :now')) {
        assert.ok(Number(old?.expiresAt) > Number(v[':now']));
        assert.equal(old?.actorId, v[':actor']); assert.equal(old?.targetNoteId, v[':note']);
        assert.ok((old?.operations as string[]).includes(v[':operation'] as string));
      }
      if (condition.includes('revision = :revision')) assert.equal(old?.revision, v[':revision']);
    }
    writes.push(command);
    for (const item of items) {
      if (item.Put) rows.set(item.Put.Item!.noteId as string, { ...item.Put.Item });
      if (item.Update) rows.set(item.Update.Key!.noteId as string,
        { ...item.Update.Key, lastSequence: item.Update.ExpressionAttributeValues![':nextSequence'] });
    }
    return {};
  } } as unknown as DynamoDBDocumentClient;
  const protection = new DynamoProtectionStore('test', db);
  const authority = new ProtectionAuthorizer(protection, new OwnerNoteAcl());
  const store = new DynamoSyncStore({ tableName: 'test', documentClient: db, security: authority });
  const grant = (epoch: number) => {
    const token = 'a'.repeat(43), hash = securityDigest(token);
    rows.set(`GRANT#${hash}`, { hash, canonicalOwnerId: 'owner', targetNoteId: 'alpha',
      actorId: 'owner', revision: epoch, issuedAt: Date.now(), expiresAt: Date.now() + 60_000,
      operations: ['manage', 'edit', 'read', 'delete'] });
    return { actorId: 'owner', grant: token };
  };
  return { store, rows, writes, grant };
}

test('client PBKDF2 verifier verifies correct password; fixed bounds reject malformed and wrong', async () => {
  const hasher = new Argon2idPasswordHasher();
  assert.equal(await hasher.verify(password, verifier), true);
  assert.equal(await hasher.verify('incorrect-password', verifier), false);
  await assert.rejects(hasher.verify(password, 'pbkdf2-sha256-v1$1$2'),
    e => e instanceof NoteSecurityError && e.code === 'unavailable');
});

test('dedicated route requires complete descriptor; normal route refuses it; legacy fingerprints remain stable', () => {
  const body = JSON.stringify(request());
  assert.equal(parseMutationBody(body).ok, false);
  assert.equal(parseMutationBody(body, true).ok, true);
  const legacy = { ...request(), protectionChange: undefined };
  assert.equal(parseMutationBody(JSON.stringify(legacy), true).ok, false);
  assert.equal(parseMutationBody(JSON.stringify(legacy)).ok, true);
  assert.notEqual(normalizeMutation(request()).fingerprint, normalizeMutation(legacy).fingerprint);
  for (const bad of [{ ...change(), verifier: password }, { ...change(), after: { enabled: true, revision: 0 } }]) {
    assert.equal(parseMutationBody(JSON.stringify({ ...request(), protectionChange: bad }), true).ok, false);
  }
});

test('first cloud create commits protection/content/sequence/receipt atomically and never stores protected body in feed', async () => {
  const f = fixture(), result = await f.store.applyMutation('owner', request());
  assert.equal(result.status, 'applied');
  assert.equal(f.writes.length, 1);
  assert.equal(f.rows.get('NOTE#alpha')?.content, 'private local body');
  assert.equal(f.rows.get('NOTE#alpha')?.protected, true);
  assert.equal(f.rows.get('PROTECTION#alpha')?.verifier, verifier);
  assert.equal(f.rows.get('CHANGE#1')?.content, '');
  assert.equal((f.rows.get('MUTATION#create')?.resultNote as Record<string, unknown>).content, '');
  assert.ok(!JSON.stringify(result).includes('private local'));
  assert.ok(!JSON.stringify(result).includes('pbkdf2-sha256'));
});

test('rotation/disable need fresh manage grant and commit pinned epoch; local hash never authorizes a write', async () => {
  const f = fixture();
  await f.store.applyMutation('owner', request());
  for (const enabled of [true, false]) {
    await assert.rejects(f.store.applyMutation('owner', request('change', 1, enabled)),
      e => e instanceof NoteSecurityError && e.code === 'locked');
  }
  assert.equal(f.writes.length, 1);
  await f.store.applyMutation('owner', request('rotate', 1), f.grant(1));
  const guards = f.writes[1].input.TransactItems!.filter(i => i.ConditionCheck);
  assert.equal(guards.length, 1);
  assert.equal(guards[0].ConditionCheck!.ExpressionAttributeValues![':operation'], 'manage');
  await f.store.applyMutation('owner', request('disable', 2, false), f.grant(2));
  assert.equal(f.rows.get('PROTECTION#alpha')?.enabled, false);
  assert.equal(f.rows.get('PROTECTION#alpha')?.verifier, null);
  assert.equal(f.rows.get('NOTE#alpha')?.protectionRevision, 3);
});

test('compound replay after rotation acknowledges metadata without old grant; reused IDs and foreign actors remain refused', async () => {
  const f = fixture();
  await f.store.applyMutation('owner', request());
  await f.store.applyMutation('owner', request('rotate', 1), f.grant(1));
  const replay = await f.store.applyMutation('owner', request('rotate', 1));
  assert.equal(replay.status, 'applied');
  assert.ok(!JSON.stringify(replay).includes('private local'));
  assert.equal(f.writes.length, 2);
  await assert.rejects(f.store.applyMutation('owner', { ...request('rotate', 1), payload: { title: 'other', content: 'other' } }));
  await assert.rejects(f.store.applyMutation('owner', request('rotate', 1), { actorId: 'other' }),
    e => e instanceof NoteSecurityError && e.code === 'denied');
});

test('stale protection descriptor cannot downgrade cloud protection even with a live grant', async () => {
  const f = fixture();
  await f.store.applyMutation('owner', request());
  const stale = { ...request('stale', 1), protectionChange: change(0) };
  await assert.rejects(f.store.applyMutation('owner', stale, f.grant(1)),
    e => e instanceof NoteSecurityError && e.code === 'staleRevision');
  assert.equal(f.writes.length, 1);
});

test('unknown unprotected delivery is inspected without replay/write; absence is a conflict and recorded receipt is metadata only', async () => {
  const f = fixture();
  const legacy = { ...request(), protectionChange: undefined };
  const missing = await f.store.applyMutation('owner', legacy, { actorId: 'owner', inspectOnly: true });
  assert.deepEqual(missing, { status: 'conflict', mutationId: 'create', remoteNote: null });
  assert.equal(f.writes.length, 0);
  await f.store.applyMutation('owner', legacy);
  const seen = await f.store.applyMutation('owner', legacy, { actorId: 'owner', inspectOnly: true });
  assert.equal(seen.status, 'applied');
  assert.ok(!JSON.stringify(seen).includes('private local'));
  assert.equal(f.writes.length, 1);
  await assert.rejects(f.store.applyMutation('owner', legacy, { actorId: 'other', inspectOnly: true }));
  assert.equal(f.writes.length, 1);
});
