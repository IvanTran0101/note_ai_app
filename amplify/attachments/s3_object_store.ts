import { createHash } from 'node:crypto';
import { S3Client, PutObjectCommand, HeadObjectCommand, GetObjectCommand,
  CreateMultipartUploadCommand, UploadPartCommand, CompleteMultipartUploadCommand,
  AbortMultipartUploadCommand, ListObjectVersionsCommand, DeleteObjectsCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { AttachmentError, CHUNK_BYTES } from './models';
import type { FileMetadata } from './models';
import type { AttachmentObjectStore } from './object_store';

/** Version-pinned private S3 adapter. 256KiB staging; final assembly <=5MiB buffer. */
export class S3AttachmentObjects implements AttachmentObjectStore {
  constructor(readonly bucket: string, readonly client = new S3Client({})) {
    if (!bucket) throw new AttachmentError('unavailable');
  }
  async uploadUrl(key: string, size: number, sha256: string) {
    if (!key.startsWith('staging/') || size <= 0 || size > CHUNK_BYTES) throw new AttachmentError('invalid');
    const checksum = Buffer.from(sha256, 'hex').toString('base64');
    const command = new PutObjectCommand({Bucket: this.bucket, Key: key, ContentLength: size,
      ContentType: 'application/octet-stream', ChecksumSHA256: checksum, ServerSideEncryption: 'AES256'});
    const url = await getSignedUrl(this.client, command, {expiresIn: 120,
      unhoistableHeaders: new Set(['x-amz-checksum-sha256', 'x-amz-server-side-encryption'])});
    return {url, headers: {'content-type': 'application/octet-stream',
      'x-amz-checksum-sha256': checksum, 'x-amz-server-side-encryption': 'AES256'}};
  }
  async pin(key: string, size: number, sha256: string) {
    const h = await this.client.send(new HeadObjectCommand({Bucket: this.bucket, Key: key, ChecksumMode: 'ENABLED'}));
    if (!h.VersionId || h.VersionId === 'null' || h.ContentLength !== size ||
        h.ChecksumSHA256 !== Buffer.from(sha256, 'hex').toString('base64')) throw new AttachmentError('invalid');
    return {version: h.VersionId, sizeBytes: size, sha256};
  }
  async *read(key: string, version: string, start: number, end: number) {
    const r = await this.client.send(new GetObjectCommand({Bucket: this.bucket, Key: key,
      VersionId: version, Range: `bytes=${start}-${end - 1}`}));
    if (!r.Body || r.VersionId !== version || r.ContentLength !== end - start) throw new AttachmentError('invalid');
    let n = 0;
    for await (const bytes of r.Body as AsyncIterable<Uint8Array>) {
      n += bytes.length; if (n > end - start) throw new AttachmentError('invalid'); yield bytes;
    }
    if (n !== end - start) throw new AttachmentError('invalid');
  }
  async hasVersion(key: string, version: string) {
    try {
      const h = await this.client.send(new HeadObjectCommand({Bucket: this.bucket, Key: key, VersionId: version}));
      return h.VersionId === version;
    } catch (e) {
      if (['NotFound', 'NoSuchKey', 'NoSuchVersion'].includes((e as Error).name)) return false;
      throw new AttachmentError('unavailable');
    }
  }
  async finalize(key: string, m: FileMetadata, chunks: AsyncIterable<Uint8Array>) {
    if (!key.startsWith('final/')) throw new AttachmentError('invalid');
    // Unknown Complete ACK: stable server-generated key can be inspected. Full
    // actual-byte validation of the returned version is mandatory in the use case.
    try {
      const old = await this.client.send(new HeadObjectCommand({Bucket: this.bucket, Key: key}));
      if (old.VersionId && old.VersionId !== 'null' && old.ContentLength === m.sizeBytes) return old.VersionId;
      throw new AttachmentError('invalid');
    } catch (e) { if ((e as Error).name !== 'NotFound' && (e as Error).name !== 'NoSuchKey') throw e; }
    const started = await this.client.send(new CreateMultipartUploadCommand({Bucket: this.bucket,
      Key: key, ContentType: m.mimeType, ServerSideEncryption: 'AES256'}));
    if (!started.UploadId) throw new AttachmentError('unavailable');
    const upload = started.UploadId, buffer = Buffer.alloc(5 * 1024 * 1024);
    const parts: {PartNumber: number; ETag: string}[] = []; let used = 0, total = 0;
    const flush = async () => {
      const p = await this.client.send(new UploadPartCommand({Bucket: this.bucket, Key: key,
        UploadId: upload, PartNumber: parts.length + 1, Body: buffer.subarray(0, used), ContentLength: used}));
      if (!p.ETag) throw new AttachmentError('unavailable');
      parts.push({PartNumber: parts.length + 1, ETag: p.ETag}); used = 0; buffer.fill(0);
    };
    try {
      const hash = createHash('sha256');
      for await (const bytes of chunks) {
        total += bytes.length; if (total > m.sizeBytes) throw new AttachmentError('invalid'); hash.update(bytes);
        for (let offset = 0; offset < bytes.length;) {
          const count = Math.min(buffer.length - used, bytes.length - offset);
          buffer.set(bytes.subarray(offset, offset + count), used); used += count; offset += count;
          if (used === buffer.length) await flush();
        }
      }
      if (total !== m.sizeBytes || hash.digest('hex') !== m.sha256) throw new AttachmentError('invalid');
      if (used) await flush();
      const result = await this.client.send(new CompleteMultipartUploadCommand({Bucket: this.bucket,
        Key: key, UploadId: upload, MultipartUpload: {Parts: parts}}));
      if (!result.VersionId || result.VersionId === 'null') throw new AttachmentError('invalid');
      return result.VersionId;
    } catch (e) {
      // Abort affects only incomplete parts, never a successfully completed version.
      await this.client.send(new AbortMultipartUploadCommand({Bucket: this.bucket, Key: key, UploadId: upload})).catch(() => {});
      throw e;
    } finally { buffer.fill(0); }
  }
  async removeStaging(prefix: string) {
    if (!/^staging\/[a-f0-9]{64}\/$/.test(prefix)) throw new AttachmentError('invalid');
    let keyMarker: string | undefined, versionMarker: string | undefined;
    do {
      const r = await this.client.send(new ListObjectVersionsCommand({Bucket: this.bucket, Prefix: prefix,
        KeyMarker: keyMarker, VersionIdMarker: versionMarker}));
      const objects = [...r.Versions ?? [], ...r.DeleteMarkers ?? []].map(x => ({Key: x.Key!, VersionId: x.VersionId!}));
      if (objects.some(x => !x.Key.startsWith(prefix) || !x.VersionId)) throw new AttachmentError('invalid');
      if (objects.length) {
        const removed = await this.client.send(new DeleteObjectsCommand({Bucket: this.bucket, Delete: {Objects: objects, Quiet: true}}));
        if (removed.Errors?.length) throw new AttachmentError('unavailable');
      }
      keyMarker = r.IsTruncated ? r.NextKeyMarker : undefined;
      versionMarker = r.IsTruncated ? r.NextVersionIdMarker : undefined;
    } while (keyMarker);
  }
}
