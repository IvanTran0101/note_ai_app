/**
 * Backend profile/avatar tests (M01.1): routing + auth, revision CAS, retry
 * idempotency, absence of note/feed attributes, and actual-byte avatar
 * validation through an in-memory DynamoDB/S3 double that evaluates the same
 * conditional expressions the production clients send.
 *
 * Run: `node --import tsx --test amplify/profile/profile.test.ts`
 */
import assert from 'node:assert/strict';
import { deflateSync } from 'node:zlib';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import test from 'node:test';
import { TransactionCanceledException } from '@aws-sdk/client-dynamodb';
import {
  GetCommand, PutCommand, TransactWriteCommand, type DynamoDBDocumentClient,
} from '@aws-sdk/lib-dynamodb';
import type { APIGatewayProxyEventV2WithJWTAuthorizer as Event } from 'aws-lambda';
import type { S3Client } from '@aws-sdk/client-s3';
import { S3AvatarObjects, type AvatarObjects, type PinnedObject } from './avatar_objects';
import { displayNameOf, inspectImage, ProfileError, type AvatarMime } from './contract';
import { handleProfile, isProfilePath, ProfileServiceImpl } from './http_routes';
import { intentSortKey, PROFILE_SORT_KEY, requestSortKey } from './store';

const SUB = '4e1c9f0a-77aa-4c1e-9a1f-2b3c4d5e6f70';
const OTHER = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
const sha = (b: Buffer) => createHash('sha256').update(b).digest('hex');

type Row = Record<string, any>;
const keyOf = (k: Row) => JSON.stringify([k.ownerId, k.noteId]);

/** Minimal conditional DynamoDB double: conditions are evaluated before any item is written. */
class TestDynamo {
  rows = new Map<string, Row>();
  row = (ownerId: string, noteId: string) => this.rows.get(keyOf({ ownerId, noteId }));
  client = { send: async (c: any) => this.send(c) } as unknown as DynamoDBDocumentClient;

  private holds(condition: string | undefined, row: Row | undefined, names: Row, values: Row): boolean {
    if (!condition) return true;
    if (condition.includes(' OR ')) {
      const [left, right] = condition.split(' OR ');
      if (this.holds(left, row, names, values)) return true;
      const less = /^(#\w+) <= (:\w+)$/.exec(right);
      assert.ok(less);
      return typeof row?.[names[less[1]]] === 'number' && row[names[less[1]]] <= values[less[2]];
    }
    const missing = /^attribute_not_exists\((#\w+)\)$/.exec(condition.trim());
    if (missing) return row?.[names[missing[1]] ?? missing[1]] === undefined;
    const equal = /^(#\w+) = (:\w+)$/.exec(condition.trim());
    assert.ok(equal, `Unsupported test condition ${condition}`);
    return row?.[names[equal[1]] ?? equal[1]] === values[equal[2]];
  }

  private applyUpdate(op: Row) {
    for (const key of Object.keys(op.ExpressionAttributeValues ?? {})) {
      assert.ok((op.UpdateExpression + ' ' + op.ConditionExpression).includes(key), `Unused DynamoDB expression value: ${key}`);
    }
    const row: Row = { ...op.Key, ...this.row(op.Key.ownerId, op.Key.noteId) };
    const body = op.UpdateExpression.replace(/^SET /, '');
    for (const assignment of body.split(',')) {
      const [name, value] = assignment.trim().split(' = ');
      const field = op.ExpressionAttributeNames?.[name] ?? name;
      row[field] = op.ExpressionAttributeValues[value];
    }
    this.rows.set(keyOf(row), structuredClone(row));
  }

  private async send(command: any) {
    const name = command?.constructor?.name;
    if (name === 'GetCommand') return { Item: this.row(command.input.Key.ownerId, command.input.Key.noteId) };
    if (name === 'PutCommand') {
      const item = command.input.Item as Row;
      if (!this.holds(command.input.ConditionExpression, this.row(item.ownerId, item.noteId),
        command.input.ExpressionAttributeNames ?? {}, command.input.ExpressionAttributeValues ?? {})) {
        throw Object.assign(new Error('Conditional'), { name: 'ConditionalCheckFailedException' });
      }
      this.rows.set(keyOf(item), structuredClone(item));
      return {};
    }
    if (name === 'TransactWriteCommand') {
      const items: Row[] = command.input.TransactItems;
      const reasons = items.map((entry) => {
        const op = entry.Put ?? entry.Update;
        const row = this.row(op.Key?.ownerId, op.Key?.noteId);
        const ok = this.holds(op.ConditionExpression, row,
          op.ExpressionAttributeNames ?? {}, op.ExpressionAttributeValues ?? {});
        return ok ? { Code: 'None' } : { Code: 'ConditionalCheckFailed' };
      });
      if (reasons.some((r) => r.Code !== 'None')) {
        throw new TransactionCanceledException({
          message: 'Transaction cancelled', $metadata: {}, CancellationReasons: reasons,
        });
      }
      for (const entry of items) {
        if (entry.Put) this.rows.set(keyOf(entry.Put.Item), structuredClone(entry.Put.Item));
        else this.applyUpdate(entry.Update);
      }
      return {};
    }
    throw new Error(`Unsupported command ${name}`);
  }
}

/** Versioned in-memory object double: every write mints a fresh version id. */
class TestAvatars implements AvatarObjects {
  private store = new Map<string, { version: string; bytes: Buffer; mime: AvatarMime }[]>();
  private counter = 0;
  presigned: { key: string; sizeBytes: number; sha256: string; mime: AvatarMime }[] = [];
  reads: string[] = [];
  copies = 0;
  corrupt = false;
  staleReadVersion = false;

  put(key: string, bytes: Buffer, mime: AvatarMime) {
    const version = `v${++this.counter}`;
    this.store.set(key, [...this.store.get(key) ?? [], { version, bytes: Buffer.from(bytes), mime }]);
    return version;
  }

  private latest(key: string) {
    const versions = this.store.get(key) ?? [];
    return versions[versions.length - 1];
  }

  async presignStagingPut(key: string, sizeBytes: number, sha256: string, mime: AvatarMime) {
    this.presigned.push({ key, sizeBytes, sha256, mime });
    return { url: `https://s3.test/${key}`, headers: {
      'content-type': mime, 'x-amz-checksum-sha256': Buffer.from(sha256, 'hex').toString('base64'),
      'x-amz-server-side-encryption': 'AES256',
    } };
  }

  async pin(key: string, expected: { sizeBytes: number; sha256: string }): Promise<PinnedObject> {
    const found = this.latest(key);
    assert.ok(found, `missing ${key}`);
    assert.equal(found.bytes.length, expected.sizeBytes);
    assert.equal(sha(found.bytes), expected.sha256);
    return { version: found.version, sizeBytes: found.bytes.length, mime: found.mime, sha256: sha(found.bytes) };
  }

  /** Mirrors S3AvatarObjects: a version gone/shifted or checksum mismatch is PROFILE_INVALID. */
  async readPinned(key: string, pinned: PinnedObject) {
    const found = (this.store.get(key) ?? []).find((v) => v.version === pinned.version);
    if (!found || this.staleReadVersion) throw new ProfileError('PROFILE_INVALID');
    const bytes = this.corrupt ? Buffer.from(found.bytes).fill(7) : Buffer.from(found.bytes);
    if (bytes.length !== pinned.sizeBytes || sha(bytes) !== pinned.sha256) throw new ProfileError('PROFILE_INVALID');
    this.reads.push(`${key}@${pinned.version}`);
    return bytes;
  }

  async finalize(stageKey: string, pinned: PinnedObject, finalKey: string) {
    const existing = this.latest(finalKey);
    if (existing) return { version: existing.version };
    const source = (this.store.get(stageKey) ?? []).find((v) => v.version === pinned.version);
    assert.ok(source, `missing ${stageKey}@${pinned.version}`);
    this.copies += 1;
    return { version: this.put(finalKey, source.bytes, pinned.mime) };
  }
}

const crc32 = (bytes: Buffer) => {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
};
const png = (width: number, height: number) => {
  const chunk = (type: string, data: Buffer) => {
    const b = Buffer.alloc(data.length + 12);
    b.writeUInt32BE(data.length); b.write(type, 4); data.copy(b, 8);
    b.writeUInt32BE(crc32(b.subarray(4, b.length - 4)), b.length - 4);
    return b;
  };
  const header = Buffer.alloc(13); header.writeUInt32BE(width); header.writeUInt32BE(height, 4); header[8] = 8; header[9] = 2;
  const pixels = Buffer.alloc((width * 3 + 1) * height);
  return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]), chunk('IHDR', header), chunk('IDAT', deflateSync(pixels)), chunk('IEND', Buffer.alloc(0))]);
};
const jpeg = (_width: number, _height: number) => readFileSync('test/presentation/profile/fixtures/avatar_photo.jpg');

const event = (method: string, path: string, body?: unknown, sub = SUB, tokenUse = 'access') => ({
  rawPath: path,
  requestContext: { http: { method }, authorizer: { jwt: { claims: { sub, token_use: tokenUse } } } },
  body: body === undefined ? undefined : JSON.stringify(body),
  isBase64Encoded: false,
  headers: {},
}) as unknown as Event;

const harness = () => {
  const db = new TestDynamo();
  const objects = new TestAvatars();
  const service = new ProfileServiceImpl(db.client, 'NotesTable', objects);
  const call = (method: string, path: string, body?: unknown, sub = SUB, actor = sub) =>
    handleProfile(event(method, path, body, sub), actor, service);
  return { db, objects, service, call };
};

const createBody = (overrides: Row = {}) => ({
  requestId: 'req-0000-0000-0000-0001', expectedRevision: 0,
  displayName: 'Kiet Nguyen', avatarReference: null, ...overrides,
});

test('profile routes are the frozen /me surface', () => {
  for (const path of ['/me/profile', '/me/avatar', '/me/avatar-intents']) assert.equal(isProfilePath(path), true);
  assert.equal(isProfilePath('/me/avatar-intents/abc123/complete'), true);
  assert.equal(isProfilePath('/me/avatar-intents/abc123'), false);
});

test('missing profile is the canonical 404 and the JWT sub must match the actor', async () => {
  const { call } = harness();
  assert.deepEqual(await call('GET', '/me/profile'), {
    statusCode: 404, headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ code: 'PROFILE_MISSING' }),
  });
  const forged = await call('GET', '/me/profile', undefined, OTHER, SUB);
  assert.equal(forged.statusCode, 403);
  assert.equal(JSON.parse(forged.body!).code, 'PROFILE_UNAUTHORIZED');
  assert.equal((await call('GET', '/me/profile', undefined, SUB, OTHER)).statusCode, 403);
  assert.equal((await call('GET', '/me/other')).statusCode, 404);
});

test('creating a profile writes only profile row data - no feed/GSI/relay attributes', async () => {
  const { db, call } = harness();
  const created = await call('POST', '/me/profile', createBody());
  assert.equal(created.statusCode, 200);
  const body = JSON.parse(created.body!);
  assert.deepEqual(body.profile, {
    userId: SUB, displayName: 'Kiet Nguyen', avatarReference: null,
    revision: 1, updatedAt: body.profile.updatedAt,
  });
  const row = db.row(SUB, PROFILE_SORT_KEY)!;
  assert.equal(row.noteId, 'PROFILE#SELF');
  assert.equal(row.revision, 1);
  for (const forbidden of ['changeOwnerId', 'changeSequence', 'relayQueue', 'relayDueAt', 'ttl']) {
    assert.equal(row[forbidden], undefined, `${forbidden} must not be written`);
  }
});

test('same requestId replays the prior outcome instead of overwriting the profile', async () => {
  const { db, call } = harness();
  await call('POST', '/me/profile', createBody());
  const retry = await call('POST', '/me/profile', createBody());
  assert.equal(retry.statusCode, 200);
  assert.equal(JSON.parse(retry.body!).profile.displayName, 'Kiet Nguyen');
  assert.equal(JSON.parse(retry.body!).profile.revision, 1);
  assert.equal(db.row(SUB, PROFILE_SORT_KEY)!.revision, 1);
});

test('stale revision is a conflict and unknown fields are denied', async () => {
  const { call } = harness();
  await call('POST', '/me/profile', createBody());
  const stale = await call('POST', '/me/profile', createBody({ requestId: 'req-0000-0000-0000-0002', expectedRevision: 0 }));
  assert.equal(stale.statusCode, 409);
  assert.equal(JSON.parse(stale.body!).code, 'PROFILE_CONFLICT');

  const forgedOwner = await call('POST', '/me/profile', createBody({ requestId: 'req-0000-0000-0000-0003', expectedRevision: 1, ownerId: OTHER }));
  assert.equal(forgedOwner.statusCode, 403);
  const smuggled = await call('POST', '/me/profile', createBody({ requestId: 'req-0000-0000-0000-0004', expectedRevision: 1, storageKey: 'final/profile/x' }));
  assert.equal(smuggled.statusCode, 422);
  const longName = await call('POST', '/me/profile', createBody({ requestId: 'req-0000-0000-0000-0005', expectedRevision: 1, displayName: 'x'.repeat(101) }));
  assert.equal(longName.statusCode, 422);
  const blankName = await call('POST', '/me/profile', createBody({ requestId: 'req-0000-0000-0000-0006', expectedRevision: 1, displayName: '   ' }));
  assert.equal(blankName.statusCode, 422);
});

test('arbitrary avatar references are rejected; only keep or clear is accepted', async () => {
  const { call } = harness();
  await call('POST', '/me/profile', createBody());
  const arbitrary = await call('POST', '/me/profile', createBody({
    requestId: 'req-0000-0000-0000-0007', expectedRevision: 1, avatarReference: 'av_0123456789abcdef0123456789abcdef',
  }));
  assert.equal(arbitrary.statusCode, 422);
  const cleared = await call('POST', '/me/profile', createBody({
    requestId: 'req-0000-0000-0000-0008', expectedRevision: 1, avatarReference: null,
  }));
  assert.equal(cleared.statusCode, 200);
  assert.equal(JSON.parse(cleared.body!).profile.revision, 2);
});

test('avatar intent is owner-scoped, bounded and returns SSE/checksum upload headers', async () => {
  const { db, objects, call } = harness();
  await call('POST', '/me/profile', createBody());
  const bytes = png(64, 64);
  const response = await call('POST', '/me/avatar-intents', {
    requestId: 'req-1000-0000-0000-0001', expectedProfileRevision: 1,
    mime: 'image/png', sizeBytes: bytes.length, sha256: sha(bytes),
  });
  assert.equal(response.statusCode, 200);
  const intent = JSON.parse(response.body!);
  assert.match(intent.intentId, /^[a-f0-9]{32}$/);
  assert.equal(intent.headers['x-amz-server-side-encryption'], 'AES256');
  assert.match(intent.headers['x-amz-checksum-sha256'], /^[A-Za-z0-9+/=]+$/);
  assert.equal(objects.presigned[0].key, `staging/profile/${SUB}/${intent.intentId}`);
  assert.equal(db.row(SUB, intentSortKey(intent.intentId))!.ttl > 0, true);

  const tooBig = await call('POST', '/me/avatar-intents', {
    requestId: 'req-1000-0000-0000-0002', expectedProfileRevision: 1,
    mime: 'image/png', sizeBytes: 1048577, sha256: 'a'.repeat(64),
  });
  assert.equal(tooBig.statusCode, 422);
  const wrongRevision = await call('POST', '/me/avatar-intents', {
    requestId: 'req-1000-0000-0000-0003', expectedProfileRevision: 0,
    mime: 'image/jpeg', sizeBytes: bytes.length, sha256: sha(bytes),
  });
  assert.equal(wrongRevision.statusCode, 409);
});

test('complete verifies actual bytes, pins the version, associates atomically and retries idempotently', async () => {
  const { db, objects, call } = harness();
  await call('POST', '/me/profile', createBody());
  const bytes = png(512, 256);
  const intent = JSON.parse((await call('POST', '/me/avatar-intents', {
    requestId: 'req-2000-0000-0000-0001', expectedProfileRevision: 1,
    mime: 'image/png', sizeBytes: bytes.length, sha256: sha(bytes),
  })).body!);
  objects.put(`staging/profile/${SUB}/${intent.intentId}`, bytes, 'image/png');
  const path = `/me/avatar-intents/${intent.intentId}/complete`;

  // The client supplies neither key nor version: a body with fields is denied.
  assert.equal((await call('POST', path, { objectVersion: 'v1' })).statusCode, 422);

  const completed = await call('POST', path, {});
  assert.equal(completed.statusCode, 200);
  const profile = JSON.parse(completed.body!).profile;
  assert.match(profile.avatarReference, /^av_[a-f0-9]{32}$/);
  assert.equal(profile.revision, 2);
  assert.equal(objects.copies, 1);

  // Lost ACK: the same intentId returns the settled profile without a second association.
  const retry = await call('POST', path, {});
  assert.equal(retry.statusCode, 200);
  assert.deepEqual(JSON.parse(retry.body!).profile, profile);
  assert.equal(objects.copies, 1);
  assert.equal(db.row(SUB, PROFILE_SORT_KEY)!.revision, 2);

  const binary = await call('GET', '/me/avatar');
  assert.equal(binary.statusCode, 200);
  assert.equal(binary.isBase64Encoded, true);
  assert.equal(binary.headers!['content-type'], 'image/png');
  assert.equal(binary.headers!['cache-control'], 'no-store');
  assert.deepEqual(Buffer.from(binary.body!, 'base64'), bytes);
});

test('malformed, oversized, wrong-checksum and stale-version avatars are denied', async () => {
  const { objects, call } = harness();
  await call('POST', '/me/profile', createBody());
  const staged = async (requestId: string, bytes: Buffer, mime: AvatarMime) => {
    const intent = JSON.parse((await call('POST', '/me/avatar-intents', {
      requestId, expectedProfileRevision: 1, mime, sizeBytes: bytes.length, sha256: sha(bytes),
    })).body!);
    objects.put(`staging/profile/${SUB}/${intent.intentId}`, bytes, mime);
    return `/me/avatar-intents/${intent.intentId}/complete`;
  };

  const truncated = jpeg(200, 200).subarray(0, 20);
  assert.equal((await call('POST', await staged('req-3000-0000-0000-0001', truncated, 'image/jpeg'), {})).statusCode, 422);
  const oversized = png(2049, 10);
  assert.equal((await call('POST', await staged('req-3000-0000-0000-0002', oversized, 'image/png'), {})).statusCode, 422);
  const valid = jpeg(1024, 1024);
  const checksumPath = await staged('req-3000-0000-0000-0003', valid, 'image/jpeg');
  objects.corrupt = true;
  assert.equal((await call('POST', checksumPath, {})).statusCode, 422);
  objects.corrupt = false;
  const versionPath = await staged('req-3000-0000-0000-0004', valid, 'image/jpeg');
  objects.staleReadVersion = true;
  assert.equal((await call('POST', versionPath, {})).statusCode, 422);
  objects.staleReadVersion = false;

  // The successful path still works, and GET /me/avatar reports missing before that.
  assert.equal((await call('GET', '/me/avatar')).statusCode, 404);
  const ok = await staged('req-3000-0000-0000-0005', valid, 'image/jpeg');
  assert.equal((await call('POST', ok, {})).statusCode, 200);
  assert.equal((await call('POST', ok, {})).statusCode, 200);
  const staleIntent = await call('POST', '/me/avatar-intents', {
    requestId: 'req-3000-0000-0000-0006', expectedProfileRevision: 1,
    mime: 'image/jpeg', sizeBytes: valid.length, sha256: sha(valid),
  });
  assert.equal(staleIntent.statusCode, 409);
});

test('a newer staged version does not replace the pinned bytes', async () => {
  const { objects, call } = harness();
  await call('POST', '/me/profile', createBody());
  const bytes = png(32, 32);
  const intent = JSON.parse((await call('POST', '/me/avatar-intents', {
    requestId: 'req-4000-0000-0000-0001', expectedProfileRevision: 1,
    mime: 'image/png', sizeBytes: bytes.length, sha256: sha(bytes),
  })).body!);
  const key = `staging/profile/${SUB}/${intent.intentId}`;
  const pinned = objects.put(key, bytes, 'image/png');
  objects.pin = async () => ({ version: pinned, sizeBytes: bytes.length, mime: 'image/png', sha256: sha(bytes) });
  const read = objects.readPinned.bind(objects);
  // A second upload lands after the pin: the exact pinned version must be read.
  objects.readPinned = async (k, p) => {
    objects.put(key, png(16, 16), 'image/png');
    return read(k, p);
  };
  const response = await call('POST', `/me/avatar-intents/${intent.intentId}/complete`, {});
  assert.equal(response.statusCode, 200);
  assert.deepEqual(objects.reads, [`${key}@${pinned}`]);
  assert.equal(objects.copies, 1);
  assert.equal((await call('POST', `/me/avatar-intents/${'0'.repeat(32)}/complete`, {})).statusCode, 404);
});

test('inspectImage rejects malformed PNG/JPEG headers and accepts both formats', () => {
  assert.deepEqual(inspectImage(png(10, 20), 'image/png'), { width: 10, height: 20 });
  assert.deepEqual(inspectImage(jpeg(20, 10), 'image/jpeg'), { width: 1024, height: 512 });
  assert.throws(() => inspectImage(png(10, 2049), 'image/png'));
  assert.throws(() => inspectImage(png(10, 20).subarray(0, 40), 'image/png'));
  const wrongMagic = png(10, 20); wrongMagic[1] = 0;
  assert.throws(() => inspectImage(wrongMagic, 'image/png'));
  const badSof = jpeg(20, 10); badSof.writeUInt16BE(2, badSof.indexOf(Buffer.from([0xff, 0xc0])) + 2);
  assert.throws(() => inspectImage(badSof, 'image/jpeg'));
  assert.throws(() => inspectImage(Buffer.from('not an image at all, padded to be long enough!!'), 'image/png'));
});

test('profile request rows are bounded by TTL and keep per-account isolation', async () => {
  const { db, call } = harness();
  await call('POST', '/me/profile', createBody());
  const row = db.row(SUB, requestSortKey('req-0000-0000-0000-0001'))!;
  assert.equal(row.kind, 'profile');
  assert.equal(row.ttl > Math.floor(Date.now() / 1000), true);
  assert.equal(db.row(OTHER, requestSortKey('req-0000-0000-0000-0001')), undefined);
  assert.equal(db.row(OTHER, PROFILE_SORT_KEY), undefined);
});

test('S3 adapter rejects prefix/size abuse, version drift and oversized bodies', async () => {
  const calls: string[] = [];
  const answers: unknown[] = [];
  const client = { send: async (command: { constructor: { name: string } }) => {
    calls.push(command.constructor.name);
    const answer = answers.shift();
    if (answer instanceof Error) throw answer;
    return answer;
  } } as unknown as S3Client;
  const objects = new S3AvatarObjects('bucket', client);
  const bytes = png(8, 8);
  const checksum = Buffer.from(sha(bytes), 'hex').toString('base64');
  const head = { VersionId: 'v1', ContentLength: bytes.length, ContentType: 'image/png', ChecksumSHA256: checksum };
  const body = { async *[Symbol.asyncIterator]() { yield bytes; } };
  const read = { VersionId: 'v1', ContentLength: bytes.length, ChecksumSHA256: checksum, Body: body };

  await assert.rejects(() => objects.presignStagingPut('final/profile/x', 10, sha(bytes), 'image/png'));
  await assert.rejects(() => objects.presignStagingPut('staging/profile/x', 1048577, sha(bytes), 'image/png'));

  answers.push(head);
  assert.equal((await objects.pin('staging/profile/sub/i', { sizeBytes: bytes.length, sha256: sha(bytes) })).version, 'v1');
  answers.push({ ...head, ChecksumSHA256: 'AAAA' });
  await assert.rejects(() => objects.pin('staging/profile/sub/i', { sizeBytes: bytes.length, sha256: sha(bytes) }));
  answers.push({ ...head, VersionId: 'null' });
  await assert.rejects(() => objects.pin('staging/profile/sub/i', { sizeBytes: bytes.length, sha256: sha(bytes) }));

  answers.push(read);
  const pinned = { version: 'v1', sizeBytes: bytes.length, mime: 'image/png' as AvatarMime, sha256: sha(bytes) };
  assert.deepEqual(await objects.readPinned('staging/profile/sub/i', pinned), bytes);
  answers.push({ ...read, VersionId: 'v2' });
  await assert.rejects(() => objects.readPinned('staging/profile/sub/i', pinned));

  answers.push(Object.assign(new Error('missing'), { name: 'NotFound' }));
  answers.push({ VersionId: 'v9' });
  answers.push({...head, VersionId: 'v9'});
  assert.deepEqual(await objects.finalize('staging/profile/sub/i', pinned, 'final/profile/sub/a1'), { version: 'v9' });
  answers.push(head);
  await objects.finalize('staging/profile/sub/i', pinned, 'final/profile/sub/a1');
  const copies = calls.filter((name) => name === 'CopyObjectCommand').length;
  assert.equal(copies, 1, 'a settled final key must not be copied twice');
  assert.equal(calls.includes('HeadObjectCommand'), true);
});


test('name bounds count Unicode code points, not UTF16 units', () => {
  assert.equal(displayNameOf('😀'.repeat(100)), '😀'.repeat(100));
  assert.throws(() => displayNameOf('😀'.repeat(101)), ProfileError);
});

test('same request id with changed payload is rejected without changing canonical data', async () => {
  const {db, call} = harness();
  await call('POST', '/me/profile', createBody());
  assert.equal((await call('POST', '/me/profile', createBody({displayName:'Changed', expectedRevision:1}))).statusCode, 422);
  assert.equal(db.row(SUB, PROFILE_SORT_KEY)!.displayName, 'Kiet Nguyen');
});

test('profile routes require access tokens and bounded UTF8 metadata', async () => {
  const {service} = harness();
  assert.equal((await handleProfile(event('GET', '/me/profile', undefined, SUB, 'id'), SUB, service)).statusCode, 403);
  let writes = 0;
  const stub = {...service, writeProfile: async () => {writes++; return {} as any;}} as any;
  const oversized = event('POST', '/me/profile');
  oversized.body = JSON.stringify({name:'é'.repeat(4097)});
  assert.ok(oversized.body.length < 8192);
  assert.equal((await handleProfile(oversized, SUB, stub)).statusCode, 422);
  assert.equal(writes, 0);
});

test('avatar requires name setup and canonical missing-avatar differs from missing-profile', async () => {
  const {call, db} = harness();
  const bytes = png(2,2);
  assert.equal((await call('POST', '/me/avatar-intents', {requestId:'req-setup-0001',expectedProfileRevision:0,mime:'image/png',sizeBytes:bytes.length,sha256:sha(bytes)})).statusCode, 404);
  assert.equal(db.row(SUB, PROFILE_SORT_KEY), undefined);
  const missing = await call('GET', '/me/avatar');
  assert.equal(JSON.parse(missing.body!).code, 'PROFILE_AVATAR_MISSING');
});

test('expired pending intents cannot complete and may be restarted while TTL deletion is delayed', async () => {
  const {db, objects} = harness();
  let time = Date.now();
  const service = new ProfileServiceImpl(db.client, 'NotesTable', objects, () => time);
  await service.writeProfile(SUB, createBody());
  const bytes = png(2,2);
  const request = {requestId:'req-expiry-0001',expectedProfileRevision:1,mime:'image/png',sizeBytes:bytes.length,sha256:sha(bytes)};
  const first = await service.createAvatarIntent(SUB, request);
  objects.put(`staging/profile/${SUB}/${first.intentId}`, bytes, 'image/png');
  time += 3601000;
  await assert.rejects(() => service.completeAvatarIntent(SUB, first.intentId), (error:any) => error.code === 'PROFILE_INVALID');
  const second = await service.createAvatarIntent(SUB, request);
  assert.notEqual(second.intentId, first.intentId);
  assert.equal(db.row(SUB, PROFILE_SORT_KEY)!.revision, 1);
});

test('lost copy ACK retries the same final object before associating once', async () => {
  const {db, objects, service} = harness();
  await service.writeProfile(SUB, createBody());
  const bytes = png(2,2);
  const intent = await service.createAvatarIntent(SUB, {requestId:'req-copy-ack-0001',expectedProfileRevision:1,mime:'image/png',sizeBytes:bytes.length,sha256:sha(bytes)});
  objects.put(`staging/profile/${SUB}/${intent.intentId}`, bytes, 'image/png');
  const copy = objects.finalize.bind(objects);
  let fail = true;
  objects.finalize = async (...args) => {const result = await copy(...args); if (fail) {fail=false; throw new ProfileError('PROFILE_UNAVAILABLE');} return result;};
  await assert.rejects(() => service.completeAvatarIntent(SUB, intent.intentId));
  assert.equal(db.row(SUB, PROFILE_SORT_KEY)!.revision, 1);
  const result = await service.completeAvatarIntent(SUB, intent.intentId);
  assert.equal(result.revision, 2);
  assert.equal(objects.copies, 1);
});

test('full upload retry after completed intent returns its known association', async () => {
  const {objects, service} = harness();
  await service.writeProfile(SUB, createBody());
  const bytes = png(2,2);
  const request = {requestId:'req-full-retry-0001',expectedProfileRevision:1,mime:'image/png',sizeBytes:bytes.length,sha256:sha(bytes)};
  const first = await service.createAvatarIntent(SUB, request);
  objects.put(`staging/profile/${SUB}/${first.intentId}`, bytes, 'image/png');
  await service.completeAvatarIntent(SUB, first.intentId);
  const replay = await service.createAvatarIntent(SUB, request);
  assert.equal(replay.intentId, first.intentId);
  assert.equal((await service.completeAvatarIntent(SUB, replay.intentId)).revision, 2);
  assert.equal(objects.copies, 1);
});

test('header-only PNG without pixel data is rejected', () => {
  const partial = Buffer.concat([png(2,2).subarray(0,33), png(2,2).subarray(-12)]);
  assert.throws(() => inspectImage(partial,'image/png'), ProfileError);
});
