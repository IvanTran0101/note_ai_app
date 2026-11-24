/**
 * Opaque change-feed cursor for the NoteFlow sync slice (M1.2).
 *
 * A cursor is all the API hands back to say "you have seen changes up to here".
 * It is deliberately not a storage key: nothing in it names the table, the
 * change index, the partition/sort-key shapes, or a region, so all of those can
 * change without a client-visible format change.
 *
 * Wire format: `base64url(JSON({ v, k, s }))`.
 *
 * - `v` versions the payload, so a future encoding is rejected instead of
 *   misread as the current one.
 * - `k` binds the cursor to the account it was issued to. `decodeChangeCursor`
 *   recomputes it from the caller's JWT-derived `ownerId` and rejects a cursor
 *   minted for somebody else, so a copied or replayed cursor cannot be used
 *   against another account. It is a digest rather than the raw `sub`, so the
 *   subject does not travel in a query string.
 * - `s` is the last change sequence the caller has seen.
 *
 * Decoding trusts nothing: alphabet, length, JSON shape, version, binding, and
 * sequence are all checked, and anything unexpected raises
 * `SyncInvalidCursorError` (a client error for the handler to map, not a 500).
 *
 * Not here: signing. A cursor carries no authority of its own - every read is
 * scoped by the JWT-derived owner and never by the cursor - so a tampered
 * cursor can at worst move its own sender to another point in its own feed.
 *
 * This module is pure: no AWS SDK, no CDK, no I/O. Run its checks with
 * `npx tsx amplify/sync/cursor.test.ts`.
 */

/** Why a cursor was rejected; useful for a handler log line, never for a client. */
export type InvalidCursorReason = 'MALFORMED' | 'UNSUPPORTED_VERSION' | 'ACCOUNT_MISMATCH';

export class SyncInvalidCursorError extends Error {
  readonly code = 'INVALID_CURSOR';
  readonly reason: InvalidCursorReason;

  constructor(reason: InvalidCursorReason, message: string) {
    super(message);
    this.name = 'SyncInvalidCursorError';
    this.reason = reason;
  }
}

/**
 * FNV-1a with `Math.imul`, which keeps the 32-bit multiply exact.
 * `charCodeAt` walks UTF-16 code units, so the result is deterministic for a
 * given string in every runtime this backend targets.
 */
const fnv1a = (value: string, seed: number): number => {
  let hash = seed >>> 0;
  for (let index = 0; index < value.length; index += 1) {
    hash = Math.imul(hash ^ value.charCodeAt(index), 0x01000193) >>> 0;
  }
  return hash;
};

/** Four independent offset bases, so the digest is 128 bits wide. */
const DIGEST_SEEDS = [0x811c9dc5, 0x9e3779b9, 0x85ebca6b, 0xc2b2ae35] as const;

/**
 * Deterministic 128-bit hex digest of one string: four differently seeded
 * FNV-1a passes, so a collision needs four simultaneous 32-bit collisions.
 *
 * It is not a cryptographic primitive and is not used as one:
 *
 * - the cursor binding only has to notice that a cursor was minted for another
 *   account (a forged match still reads only the caller's own feed), and
 * - the mutation fingerprint only has to notice that a reused `mutationId`
 *   carries a different request, and an account can only collide with itself.
 *
 * It is stable across processes, cold starts, and deployments, which a salted
 * or random hash would not be: cursors stay valid after a redeploy.
 */
export const stableDigest = (value: string): string =>
  DIGEST_SEEDS.map((seed) => fnv1a(value, seed).toString(16).padStart(8, '0')).join('');

const CURSOR_VERSION = 1;

/** A payload is a version, a 32-character digest, and a counter; anything longer is not ours. */
const MAX_CURSOR_LENGTH = 160;

const BASE64_URL = /^[A-Za-z0-9_-]+$/;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const isSequence = (value: unknown): value is number =>
  typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;

/**
 * Node 22 provides `btoa`/`atob`/`TextEncoder` globally and this backend has no
 * `@types/node` (see `package.json`), so TypeScript sees the DOM declarations.
 * Cursor payloads are ASCII by construction - keys, a hex digest, digits - so
 * the latin1 constraint of `btoa` cannot bite, and decoding validates the
 * alphabet before `atob` sees it.
 */
const toBase64Url = (payload: Record<string, unknown>): string =>
  btoa(JSON.stringify(payload)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

const fromBase64Url = (value: string): string =>
  atob(value.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(value.length / 4) * 4, '='));

/** Domain-separated so a digest minted for one purpose can never be replayed as another. */
const accountBindingOf = (ownerId: string): string => stableDigest(`cursor-account:${ownerId}`);

const malformed = (): SyncInvalidCursorError =>
  new SyncInvalidCursorError('MALFORMED', 'The sync cursor is not readable.');

/**
 * Mints the cursor for the last change sequence `ownerId` has seen.
 * Only the store and the handler call this; clients treat the result as opaque.
 */
export const encodeChangeCursor = (ownerId: string, sequence: number): string => {
  if (!isSequence(sequence)) {
    // A programming error, not client input: the sequence comes from storage.
    throw new RangeError('A change cursor needs a non-negative whole sequence number.');
  }
  return toBase64Url({ v: CURSOR_VERSION, k: accountBindingOf(ownerId), s: sequence });
};

/**
 * Decodes a cursor for `ownerId` and returns the last change sequence it
 * covers. A missing cursor means "from the beginning" and yields `0`.
 *
 * The owner must come from the verified JWT; passing anything a request body
 * supplied defeats the account binding.
 */
export const decodeChangeCursor = (cursor: string | null | undefined, ownerId: string): number => {
  if (cursor === null || cursor === undefined || cursor === '') {
    return 0;
  }
  if (typeof cursor !== 'string' || cursor.length > MAX_CURSOR_LENGTH || !BASE64_URL.test(cursor)) {
    throw malformed();
  }

  let payload: unknown;
  try {
    payload = JSON.parse(fromBase64Url(cursor));
  } catch {
    throw malformed();
  }

  if (!isRecord(payload)) {
    throw malformed();
  }
  if (payload.v !== CURSOR_VERSION) {
    throw new SyncInvalidCursorError('UNSUPPORTED_VERSION', 'This sync cursor came from a different API version.');
  }
  const sequence = payload.s;
  if (typeof payload.k !== 'string' || !isSequence(sequence)) {
    throw malformed();
  }
  if (payload.k !== accountBindingOf(ownerId)) {
    throw new SyncInvalidCursorError('ACCOUNT_MISMATCH', 'This sync cursor was issued to a different account.');
  }
  return sequence;
};
