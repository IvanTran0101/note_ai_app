import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createHash } from 'node:crypto';
import { App, Stack } from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { Function } from 'aws-cdk-lib/aws-lambda';
import { S3Client, HeadObjectCommand, GetObjectCommand, CreateMultipartUploadCommand,
  UploadPartCommand, CompleteMultipartUploadCommand, AbortMultipartUploadCommand,
  ListObjectVersionsCommand, DeleteObjectsCommand } from '@aws-sdk/client-s3';
import { S3AttachmentObjects } from './s3_object_store';
import { createAttachmentStorage } from './infrastructure';
import { CHUNK_BYTES } from './models';
test('CDK storage is private/versioned/TLS/retained; only staging gets CORS PUT/deletion/expiry', () => {
  const app = new App(), stack = new Stack(app, 'StorageTest');
  const fn = Function.fromFunctionArn(stack, 'Fn', 'arn:aws:lambda:us-east-1:123456789012:function:fixture');
  createAttachmentStorage(stack, fn, ['https://notes.example.invalid']);
  const t = Template.fromStack(stack).toJSON();
  const bucket: any = Object.values(t.Resources).find((r: any) => r.Type === 'AWS::S3::Bucket');
  assert.ok(Object.values(bucket.Properties.PublicAccessBlockConfiguration).every(v => v === true));
  assert.equal(bucket.Properties.VersioningConfiguration.Status, 'Enabled'); assert.equal(bucket.DeletionPolicy, 'Retain');
  assert.deepEqual(bucket.Properties.CorsConfiguration.CorsRules[0].AllowedMethods, ['PUT']);
  assert.deepEqual(bucket.Properties.CorsConfiguration.CorsRules[0].AllowedOrigins, ['https://notes.example.invalid']);
  const rules = bucket.Properties.LifecycleConfiguration.Rules;
  assert.ok(rules.every((r: any) => r.Prefix !== 'final/' || !r.ExpirationInDays && !r.NoncurrentVersionExpiration));
  assert.throws(() => createAttachmentStorage(new Stack(app, 'Bad'), fn, ['*']));
});
test('signed PUT is fixed256KiB staging, checksum/encryption-bound and120s; no GET capability', async () => {
  const s3 = new S3Client({region: 'us-east-1', credentials: {accessKeyId: 'synthetic', secretAccessKey: 'synthetic'}});
  const adapter = new S3AttachmentObjects('fixture-bucket', s3);
  const r = await adapter.uploadUrl(`staging/${'a'.repeat(64)}/0`, CHUNK_BYTES, 'b'.repeat(64));
  const url = new URL(r.url); assert.equal(url.searchParams.get('X-Amz-Expires'), '120');
  assert.ok(url.searchParams.get('X-Amz-SignedHeaders')!.includes('x-amz-checksum-sha256'));
  assert.equal(r.headers['x-amz-server-side-encryption'], 'AES256');
  await assert.rejects(() => adapter.uploadUrl('final/x', 1, 'b'.repeat(64)));
  await assert.rejects(() => adapter.uploadUrl('staging/x', CHUNK_BYTES + 1, 'b'.repeat(64)));
  s3.destroy();
});

test('pinned version existence distinguishes expiry from transient S3 failure', async () => {
  let state = 'exists';
  const client = {send: async (c: HeadObjectCommand) => {
    assert.equal(c.input.VersionId, 'pinned');
    if (state === 'expired') throw Object.assign(Error(), {name: 'NoSuchVersion'});
    if (state === 'offline') throw Object.assign(Error(), {name: 'TimeoutError'});
    return {VersionId: 'pinned'};
  }} as unknown as S3Client;
  const adapter = new S3AttachmentObjects('b', client);
  assert.equal(await adapter.hasVersion('staging/x', 'pinned'), true);
  state = 'expired'; assert.equal(await adapter.hasVersion('staging/x', 'pinned'), false);
  state = 'offline'; await assert.rejects(() => adapter.hasVersion('staging/x', 'pinned'));
});
test('S3 final assembly buffers bounded5MiB parts; exact version Range and unknown Complete ACK reuse', async () => {
  const bytes = Buffer.alloc(5 * 1024 * 1024 + 19, 65), sha256 = createHash('sha256').update(bytes).digest('hex');
  const parts: Buffer[] = [], commands: any[] = []; let version: string | null = null;
  const client = {send: async (c: any) => {
    commands.push(c);
    if (c instanceof HeadObjectCommand) {
      if (!version) throw Object.assign(Error(), {name: 'NotFound'});
      return {VersionId: version, ContentLength: bytes.length};
    }
    if (c instanceof CreateMultipartUploadCommand) return {UploadId: 'upload'};
    if (c instanceof UploadPartCommand) { parts.push(Buffer.from(c.input.Body as Uint8Array)); return {ETag: `part${parts.length}`}; }
    if (c instanceof CompleteMultipartUploadCommand) { version = 'pinned-v1'; return {VersionId: version}; }
    if (c instanceof GetObjectCommand) return {VersionId: version, ContentLength: 10,
      Body: (async function* () { yield bytes.subarray(5, 15); })()};
    if (c instanceof AbortMultipartUploadCommand) return {};
    throw Error('Unexpected');
  }} as unknown as S3Client;
  const adapter = new S3AttachmentObjects('b', client);
  const m = {fileName: 'x.txt', mimeType: 'text/plain', sizeBytes: bytes.length, sha256};
  const source = async function* () { for (let i = 0; i < bytes.length; i += CHUNK_BYTES) yield bytes.subarray(i, i + CHUNK_BYTES); };
  assert.equal(await adapter.finalize('final/fixed', m, source()), 'pinned-v1');
  assert.deepEqual(parts.map(x => x.length), [5 * 1024 * 1024, 19]); assert.deepEqual(Buffer.concat(parts), bytes);
  assert.equal(await adapter.finalize('final/fixed', m, source()), 'pinned-v1');
  assert.equal(commands.filter(c => c instanceof CreateMultipartUploadCommand).length, 1);
  const read = []; for await (const b of adapter.read('final/fixed', 'pinned-v1', 5, 15)) read.push(Buffer.from(b));
  assert.deepEqual(Buffer.concat(read), bytes.subarray(5, 15));
  assert.equal(commands.at(-1).input.VersionId, 'pinned-v1');
});
test('failed final checksum aborts incomplete multipart; staging cleanup paginates only its prefix', async () => {
  const commands: any[] = []; let pages = 0;
  const prefix = `staging/${'a'.repeat(64)}/`;
  const client = {send: async (c: any) => {
    commands.push(c);
    if (c instanceof HeadObjectCommand) throw Object.assign(Error(), {name: 'NotFound'});
    if (c instanceof CreateMultipartUploadCommand) return {UploadId: 'u'};
    if (c instanceof AbortMultipartUploadCommand) return {};
    if (c instanceof ListObjectVersionsCommand) {
      pages++; return {Versions: [{Key: `${prefix}${pages}`, VersionId: `v${pages}`}],
        IsTruncated: pages === 1, NextKeyMarker: pages === 1 ? `${prefix}1` : undefined, NextVersionIdMarker: 'v1'};
    }
    if (c instanceof DeleteObjectsCommand) return {};
    throw Error('Unexpected');
  }} as unknown as S3Client;
  const adapter = new S3AttachmentObjects('b', client);
  await assert.rejects(() => adapter.finalize('final/fixed', {fileName: 'x.txt', mimeType: 'text/plain', sizeBytes: 1,
    sha256: '0'.repeat(64)}, (async function* () {yield Buffer.from('x');})()));
  assert.equal(commands.filter(c => c instanceof AbortMultipartUploadCommand).length, 1);
  await adapter.removeStaging(prefix); assert.equal(pages, 2);
  assert.ok(commands.filter(c => c instanceof DeleteObjectsCommand).every(c => c.input.Delete!.Objects!.every((x: any) => x.Key.startsWith(prefix))));
  await assert.rejects(() => adapter.removeStaging('final/'));
});
