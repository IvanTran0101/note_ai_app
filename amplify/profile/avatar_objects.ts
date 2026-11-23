/**
 * Dedicated avatar object adapter.
 *
 * The note attachment store (`amplify/attachments/s3_object_store.ts`) is
 * chunked for 256KiB multipart traffic and binds objects to a Note, so avatar
 * bytes need their own tiny adapter instead of a fake Note. Same installed SDK,
 * same private/versioned bucket conventions: PUT presign into
 * `staging/profile/<sub>/<intentId>`, then an immutable, version-pinned copy to
 * `final/profile/<sub>/<avatarId>` (SSE-S3, SHA256 checksum enforced on read).
 */
import { createHash } from 'node:crypto';
import {
  CopyObjectCommand,
  GetObjectCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { MAX_AVATAR_BYTES, ProfileError, type AvatarMime } from './contract';

export type PinnedObject = Readonly<{ version: string; sizeBytes: number; mime: AvatarMime; sha256: string }>;

/** Upload credentials are transient and restricted to one exact staging key. */
export interface AvatarObjects {
  presignStagingPut(key: string, sizeBytes: number, sha256: string, mime: AvatarMime):
    Promise<Readonly<{ url: string; headers: Record<string, string> }>>;
  pin(key: string, expected: Readonly<{ sizeBytes: number; sha256: string }>): Promise<PinnedObject>;
  readPinned(key: string, pinned: PinnedObject): Promise<Buffer>;
  /** Copy the pinned staging version to its immutable final key; idempotent. */
  finalize(stageKey: string, pinned: PinnedObject, finalKey: string):
    Promise<Readonly<{ version: string }>>;
}

const STAGING_PREFIX = 'staging/profile/';
const FINAL_PREFIX = 'final/profile/';
const checksumOf = (sha256: string) => Buffer.from(sha256, 'hex').toString('base64');
const asUnavailable = <T>(run: () => Promise<T>): Promise<T> =>
  run().catch((error) => {
    if (error instanceof ProfileError) throw error;
    throw new ProfileError('PROFILE_UNAVAILABLE', true);
  });

export class S3AvatarObjects implements AvatarObjects {
  constructor(readonly bucket: string, readonly client = new S3Client({})) {
    if (!bucket) throw new ProfileError('PROFILE_UNAVAILABLE');
  }

  async presignStagingPut(key: string, sizeBytes: number, sha256: string, mime: AvatarMime) {
    if (!key.startsWith(STAGING_PREFIX) || !Number.isSafeInteger(sizeBytes) ||
        sizeBytes < 1 || sizeBytes > MAX_AVATAR_BYTES || !/^[a-f0-9]{64}$/.test(sha256)) {
      throw new ProfileError('PROFILE_INVALID');
    }
    const checksum = checksumOf(sha256);
    return asUnavailable(async () => {
      const command = new PutObjectCommand({
        Bucket: this.bucket, Key: key, ContentLength: sizeBytes, ContentType: mime,
        ChecksumSHA256: checksum, ServerSideEncryption: 'AES256',
      });
      // Short-lived: the client uploads immediately, then finalises. The
      // signature covers checksum + encryption, and unhoistableHeaders keeps
      // those tuples signed instead of query-string hoisted.
      const url = await getSignedUrl(this.client, command, {
        expiresIn: 120,
        unhoistableHeaders: new Set(['x-amz-checksum-sha256', 'x-amz-server-side-encryption']),
      });
      return { url, headers: {
        'content-type': mime,
        'x-amz-checksum-sha256': checksum,
        'x-amz-server-side-encryption': 'AES256',
      } };
    });
  }

  async pin(key: string, expected: Readonly<{ sizeBytes: number; sha256: string }>): Promise<PinnedObject> {
    if (!key.startsWith(STAGING_PREFIX)) throw new ProfileError('PROFILE_INVALID');
    return asUnavailable(async () => {
      const head = await this.client.send(new HeadObjectCommand({
        Bucket: this.bucket, Key: key, ChecksumMode: 'ENABLED',
      }));
      const mime = head.ContentType as AvatarMime | undefined;
      if (!head.VersionId || head.VersionId === 'null' || head.ContentLength !== expected.sizeBytes ||
          head.ChecksumSHA256 !== checksumOf(expected.sha256) ||
          (mime !== 'image/png' && mime !== 'image/jpeg')) {
        throw new ProfileError('PROFILE_INVALID');
      }
      return { version: head.VersionId, sizeBytes: expected.sizeBytes, mime, sha256: expected.sha256 };
    });
  }

  async readPinned(key: string, pinned: PinnedObject): Promise<Buffer> {
    if (!key.startsWith(STAGING_PREFIX) && !key.startsWith(FINAL_PREFIX)) throw new ProfileError('PROFILE_INVALID');
    return asUnavailable(async () => {
      const result = await this.client.send(new GetObjectCommand({
        Bucket: this.bucket, Key: key, VersionId: pinned.version, ChecksumMode: 'ENABLED',
      }));
      if (result.VersionId !== pinned.version || result.ContentLength !== pinned.sizeBytes ||
          result.ChecksumSHA256 !== checksumOf(pinned.sha256) || !result.Body) {
        throw new ProfileError('PROFILE_INVALID');
      }
      const chunks: Buffer[] = [];
      let total = 0;
      for await (const part of result.Body as AsyncIterable<Uint8Array>) {
        total += part.length;
        // Bound the read before the buffer can grow past the 1MiB contract.
        if (total > pinned.sizeBytes || total > MAX_AVATAR_BYTES) throw new ProfileError('PROFILE_INVALID');
        chunks.push(Buffer.from(part));
      }
      const bytes = Buffer.concat(chunks);
      if (total !== pinned.sizeBytes || createHash('sha256').update(bytes).digest('hex') !== pinned.sha256) {
        throw new ProfileError('PROFILE_INVALID');
      }
      return bytes;
    });
  }

  async finalize(stageKey: string, pinned: PinnedObject, finalKey: string) {
    if (!stageKey.startsWith(STAGING_PREFIX) || !finalKey.startsWith(FINAL_PREFIX)) {
      throw new ProfileError('PROFILE_INVALID');
    }
    return asUnavailable(async () => {
      try {
        // A lost ACK means the copy already happened: the stable final key is
        // inspected before copying again, and an existing version wins.
        const existing = await this.client.send(new HeadObjectCommand({
          Bucket: this.bucket, Key: finalKey, ChecksumMode: 'ENABLED',
        }));
        if (existing.VersionId && existing.VersionId !== 'null' &&
            existing.ContentType === pinned.mime && existing.ContentLength === pinned.sizeBytes && existing.ChecksumSHA256 === checksumOf(pinned.sha256)) {
          return { version: existing.VersionId };
        }
        throw new ProfileError('PROFILE_INVALID');
      } catch (error) {
        if (error instanceof ProfileError) throw error;
        const name = (error as Error).name;
        if (name !== 'NotFound' && name !== 'NoSuchKey') throw error;
      }
      const copied = await this.client.send(new CopyObjectCommand({
        Bucket: this.bucket, Key: finalKey,
        CopySource: `${this.bucket}/${stageKey}?versionId=${encodeURIComponent(pinned.version)}`,
        ContentType: pinned.mime, ServerSideEncryption: 'AES256', ChecksumAlgorithm: 'SHA256',
      }));
      if (!copied.VersionId || copied.VersionId === 'null') throw new ProfileError('PROFILE_UNAVAILABLE', true);
      const finalHead = await this.client.send(new HeadObjectCommand({Bucket: this.bucket, Key: finalKey, VersionId: copied.VersionId, ChecksumMode: 'ENABLED'}));
      if (finalHead.VersionId !== copied.VersionId || finalHead.ContentLength !== pinned.sizeBytes || finalHead.ContentType !== pinned.mime || finalHead.ChecksumSHA256 !== checksumOf(pinned.sha256)) throw new ProfileError('PROFILE_INVALID');
      return { version: copied.VersionId };
    });
  }
}
