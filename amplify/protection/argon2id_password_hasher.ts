import { randomBytes, timingSafeEqual } from 'node:crypto';
import { argon2idAsync } from '@noble/hashes/argon2.js';
import type { PasswordHasher } from './password_hasher';
import { NoteSecurityError } from './protection_store';

const PARAMETERS = { t: 3, m: 65_536, p: 1, dkLen: 32, maxmem: 70 * 1024 * 1024 };

export const requirePassword = (password: unknown): string => {
  if (typeof password !== 'string' || password.length < 8 ||
      Buffer.byteLength(password, 'utf8') > 512) throw new NoteSecurityError('invalidInput');
  return password;
};

/** Fixed bounded Argon2id parameters; no client-controlled KDF work factor. */
export class Argon2idPasswordHasher implements PasswordHasher {
  async hash(password: string): Promise<string> {
    requirePassword(password);
    const salt = randomBytes(16);
    const derived = await argon2idAsync(password, salt, PARAMETERS);
    try {
      return `argon2id-v1$${salt.toString('base64')}$${Buffer.from(derived).toString('base64')}`;
    } finally { derived.fill(0); }
  }

  async verify(password: string, representation: string): Promise<boolean> {
    requirePassword(password);
    const parts = representation.split('$');
    if (parts.length !== 3 || parts[0] !== 'argon2id-v1') throw new NoteSecurityError('unavailable');
    const salt = Buffer.from(parts[1], 'base64');
    const expected = Buffer.from(parts[2], 'base64');
    if (salt.length !== 16 || expected.length !== 32) throw new NoteSecurityError('unavailable');
    const derived = await argon2idAsync(password, salt, PARAMETERS);
    try { return timingSafeEqual(derived, expected); }
    finally { derived.fill(0); expected.fill(0); }
  }
}
