import { pbkdf2, timingSafeEqual } from 'node:crypto';
import { NoteSecurityError } from './protection_store';

export const isLocalPasswordVerifier = (value: unknown): value is string => {
  if (typeof value !== 'string' || !/^pbkdf2-sha256-v1\$[A-Za-z0-9+/]{22}==\$[A-Za-z0-9+/]{43}=$/.test(value)) return false;
  const [, salt, digest] = value.split('$');
  return Buffer.from(salt, 'base64').toString('base64') === salt &&
    Buffer.from(digest, 'base64').toString('base64') === digest;
};

/** Fixed cost, length and algorithm. Never accept client work parameters. */
export const verifyLocalPassword = async (password: string, representation: string): Promise<boolean> => {
  if (!isLocalPasswordVerifier(representation)) throw new NoteSecurityError('unavailable');
  const [, salt, hash] = representation.split('$');
  const expected = Buffer.from(hash, 'base64');
  const derived = await new Promise<Buffer>((resolve, reject) =>
    pbkdf2(password, Buffer.from(salt, 'base64'), 600_000, 32, 'sha256',
      (error, key) => error ? reject(new NoteSecurityError('unavailable')) : resolve(key)));
  try { return timingSafeEqual(derived, expected); }
  finally { derived.fill(0); expected.fill(0); }
};
