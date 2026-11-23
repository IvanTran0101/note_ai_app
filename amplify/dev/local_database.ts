/** Encrypted disk persistence for the loopback SDK double. Not an AWS adapter. */
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { TestDynamo } from '../sharing/test_dynamo';

export class LocalDatabase {
  readonly db = new TestDynamo();
  private readonly state: string;
  private readonly key: Buffer;
  constructor(directory: string) {
    const allowed = resolve('output/m06-local');
    if (resolve(directory) !== allowed) throw Error('Local dev output directory required');
    mkdirSync(allowed, { recursive: true });
    this.state = join(allowed, 'database.enc');
    const keyFile = join(allowed, 'database.key');
    if (!existsSync(keyFile)) {
      if (existsSync(this.state)) throw Error('Local dev key missing; preserve existing state');
      writeFileSync(keyFile, randomBytes(32), { flag: 'wx', mode: 0o600 });
    }
    this.key = readFileSync(keyFile);
    if (this.key.length !== 32) throw Error('Invalid local dev key');
    if (existsSync(this.state)) this.restore();
  }
  private restore() {
    const packet = readFileSync(this.state);
    if (packet.length < 29 || packet[0] !== 1) throw Error('Invalid local dev state; no reset');
    const decipher = createDecipheriv('aes-256-gcm', this.key, packet.subarray(1, 13));
    decipher.setAuthTag(packet.subarray(13, 29));
    const plain = Buffer.concat([decipher.update(packet.subarray(29)), decipher.final()]);
    try {
      const rows = JSON.parse(plain.toString('utf8'));
      if (!Array.isArray(rows) || rows.some(r => typeof r.ownerId !== 'string' || typeof r.noteId !== 'string')) {
        throw Error('Invalid local dev rows; no reset');
      }
      rows.forEach(row => this.db.put(row));
    } finally { plain.fill(0); }
  }
  save() {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.key, iv);
    const plain = Buffer.from(JSON.stringify([...this.db.rows.values()]));
    try {
      const encrypted = Buffer.concat([cipher.update(plain), cipher.final()]);
      writeFileSync(this.state + '.tmp', Buffer.concat([Buffer.from([1]), iv, cipher.getAuthTag(), encrypted]), { mode: 0o600 });
      renameSync(this.state + '.tmp', this.state);
    } finally { plain.fill(0); }
    // SDK double's diagnostic transaction history must not grow during manual dev.
    this.db.transactions.length = 0;
  }
}
