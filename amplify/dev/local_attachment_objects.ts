/** Encrypted loopback object fixture. No AWS identity and no plaintext disk bytes. */
import { createCipheriv, createDecipheriv, createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync, renameSync, readdirSync, unlinkSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { AttachmentError, CHUNK_BYTES } from '../attachments/models';
import type { FileMetadata } from '../attachments/models';
import type { AttachmentObjectStore } from '../attachments/object_store';
export class LocalAttachmentObjects implements AttachmentObjectStore {
  readonly directory: string; readonly key: Buffer;
  constructor(directory = 'output/m06-local/attachments') {
    this.directory = resolve(directory);
    if (this.directory !== resolve('output/m06-local/attachments')) throw new AttachmentError('invalid');
    mkdirSync(this.directory, {recursive: true}); const keyFile = join(this.directory, 'objects.key');
    if (!existsSync(keyFile)) {
      if (readdirSync(this.directory).length) throw new AttachmentError('unavailable');
      writeFileSync(keyFile, randomBytes(32), {flag: 'wx', mode: 0o600});
    }
    this.key = readFileSync(keyFile); if (this.key.length !== 32) throw new AttachmentError('unavailable');
  }
  private name(key: string, suffix: string) {
    return join(this.directory, `${createHash('sha256').update(key).digest('hex')}-${suffix}.enc`);
  }
  private seal(path: string, plain: Buffer) {
    const iv = randomBytes(12), cipher = createCipheriv('aes-256-gcm', this.key, iv);
    const data = Buffer.concat([cipher.update(plain), cipher.final()]);
    writeFileSync(path + '.tmp', Buffer.concat([iv, cipher.getAuthTag(), data]), {mode: 0o600}); renameSync(path + '.tmp', path);
  }
  private open(path: string) {
    const data = readFileSync(path); const d = createDecipheriv('aes-256-gcm', this.key, data.subarray(0, 12));
    d.setAuthTag(data.subarray(12, 28)); return Buffer.concat([d.update(data.subarray(28)), d.final()]);
  }
  async uploadUrl(key: string, size: number, sha256: string) {
    const payload = Buffer.from(JSON.stringify({key, size, sha256, exp: Date.now() + 120000})).toString('base64url');
    const signature = createHmac('sha256', this.key).update(payload).digest('base64url');
    return {url: `http://127.0.0.1:8796/dev/attachment-put?cap=${payload}.${signature}`,
      headers: {'content-type': 'application/octet-stream'}};
  }
  async put(capability: string, bytes: Buffer) {
    const [payload, signature, extra] = capability.split('.');
    if (!payload || !signature || extra) throw new AttachmentError('denied');
    const expected = createHmac('sha256', this.key).update(payload).digest();
    const supplied = Buffer.from(signature, 'base64url');
    if (expected.length !== supplied.length || !timingSafeEqual(expected, supplied)) throw new AttachmentError('denied');
    const {key, size, sha256, exp} = JSON.parse(Buffer.from(payload, 'base64url').toString());
    if (!/^staging\/[a-f0-9]{64}\/\d{1,3}$/.test(key) || !Number.isSafeInteger(exp) || exp <= Date.now() ||
        size <= 0 || size > CHUNK_BYTES || bytes.length !== size ||
        createHash('sha256').update(bytes).digest('hex') !== sha256) throw new AttachmentError('invalid');
    const version = randomBytes(16).toString('hex');
    this.seal(this.name(key, version), bytes);
    const head = Buffer.from(JSON.stringify({version, size, sha256}));
    try { this.seal(this.name(key, 'head'), head); } finally { head.fill(0); }
  }
  async pin(key: string, expected: number, sha256: string) {
    const bytes = this.open(this.name(key, 'head'));
    try {
      const h = JSON.parse(bytes.toString());
      if (h.size !== expected || h.sha256 !== sha256) throw new AttachmentError('invalid');
      return {version: h.version as string, sizeBytes: expected, sha256};
    } finally { bytes.fill(0); }
  }
  async *read(key: string, version: string, start: number, end: number) {
    if (key.startsWith('staging/')) {
      const plain = this.open(this.name(key, version));
      try { if (end > plain.length) throw new AttachmentError('invalid'); yield Buffer.from(plain.subarray(start, end)); }
      finally { plain.fill(0); } return;
    }
    const metadata = this.open(this.name(key, `${version}-manifest`)); let manifest;
    try { manifest = JSON.parse(metadata.toString()); } finally { metadata.fill(0); }
    if (start < 0 || end > manifest.size) throw new AttachmentError('invalid');
    for (let i = Math.floor(start / CHUNK_BYTES); i * CHUNK_BYTES < end; i++) {
      const p = this.open(this.name(key, `${version}-${i}`));
      try { const base = i * CHUNK_BYTES; yield Buffer.from(p.subarray(Math.max(0, start - base), Math.min(p.length, end - base))); }
      finally { p.fill(0); }
    }
  }
  async finalize(key: string, m: FileMetadata, chunks: AsyncIterable<Uint8Array>) {
    const head = this.name(key, 'head');
    if (existsSync(head)) {
      const p = this.open(head); try { const h = JSON.parse(p.toString());
        if (h.size !== m.sizeBytes || h.sha256 !== m.sha256) throw new AttachmentError('invalid'); return h.version as string;
      } finally { p.fill(0); }
    }
    const version = randomBytes(16).toString('hex'), buffer = Buffer.alloc(CHUNK_BYTES);
    let used = 0, index = 0, total = 0; const hash = createHash('sha256');
    const flush = () => { this.seal(this.name(key, `${version}-${index++}`), buffer.subarray(0, used)); used = 0; buffer.fill(0); };
    try {
      for await (const part of chunks) {
        total += part.length; if (total > m.sizeBytes) throw new AttachmentError('invalid'); hash.update(part);
        for (let offset = 0; offset < part.length;) {
          const size = Math.min(buffer.length - used, part.length - offset);
          buffer.set(part.subarray(offset, offset + size), used); used += size; offset += size;
          if (used === buffer.length) flush();
        }
      }
      if (total !== m.sizeBytes || hash.digest('hex') !== m.sha256) throw new AttachmentError('invalid');
      if (used) flush();
      const p = Buffer.from(JSON.stringify({version, size: total, sha256: m.sha256}));
      try { this.seal(this.name(key, `${version}-manifest`), p); this.seal(head, p); } finally { p.fill(0); }
      return version;
    } finally { buffer.fill(0); }
  }
  async removeStaging(prefix: string) {
    if (!/^staging\/[a-f0-9]{64}\/$/.test(prefix)) throw new AttachmentError('invalid');
    // All possible bounded chunk keys. Never touches final objects or the key.
    const names = new Set(Array.from({length: 200}, (_, i) => createHash('sha256').update(`${prefix}${i}`).digest('hex')));
    for (const name of readdirSync(this.directory)) if (names.has(name.split('-')[0]) && name.endsWith('.enc')) unlinkSync(join(this.directory, name));
  }
}
