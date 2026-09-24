/**
 * Focused pure checks for `amplify/sync/cursor.ts` (M1.2 persistence slice A).
 *
 * Run with `npx tsx amplify/sync/cursor.test.ts`. The backend has no test
 * runner and no `@types/node` (see `package.json`), so this file stays a plain
 * script: no imports beyond the module under test, no fixtures, no mocks. A
 * failing check rethrows, which exits the process non-zero.
 *
 * The store itself is not covered here: `DynamoSyncStore` needs a live
 * DynamoDB table, so its checks belong to an integration test in a later slice.
 */
import { SyncInvalidCursorError, decodeChangeCursor, encodeChangeCursor, stableDigest } from './cursor';

let passed = 0;

const check = (name: string, run: () => void): void => {
  try {
    run();
    passed += 1;
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
};

const assertEqual = <T>(actual: T, expected: T, label: string): void => {
  if (actual !== expected) {
    throw new Error(`${label}: expected ${String(expected)}, got ${String(actual)}`);
  }
};

const assertTrue = (value: boolean, label: string): void => {
  if (!value) {
    throw new Error(label);
  }
};

const assertRejects = (run: () => unknown, reason: SyncInvalidCursorError['reason'], label: string): void => {
  try {
    run();
  } catch (error) {
    if (error instanceof SyncInvalidCursorError) {
      assertEqual(error.reason, reason, `${label} (reason)`);
      return;
    }
    throw new Error(`${label}: expected SyncInvalidCursorError, got ${String(error)}`);
  }
  throw new Error(`${label}: expected a SyncInvalidCursorError`);
};

/** Mirrors the module's wire format so the checks can forge payloads. */
const encodePayload = (payload: unknown): string =>
  btoa(JSON.stringify(payload)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

const OWNER = 'user-123';
const OTHER_OWNER = 'user-456';

check('a missing cursor starts at the beginning', () => {
  assertEqual(decodeChangeCursor(undefined, OWNER), 0, 'undefined');
  assertEqual(decodeChangeCursor(null, OWNER), 0, 'null');
  assertEqual(decodeChangeCursor('', OWNER), 0, 'empty');
});

check('a cursor round-trips for its own account', () => {
  for (const sequence of [0, 1, 41, 9_007_199_254_740_991]) {
    assertEqual(decodeChangeCursor(encodeChangeCursor(OWNER, sequence), OWNER), sequence, `sequence ${sequence}`);
  }
});

check('a cursor is bound to the account it was issued to', () => {
  assertRejects(
    () => decodeChangeCursor(encodeChangeCursor(OWNER, 41), OTHER_OWNER),
    'ACCOUNT_MISMATCH',
    'other account',
  );
});

check('a cursor exposes neither the subject nor storage details', () => {
  const cursor = encodeChangeCursor(OWNER, 41);
  for (const secret of [OWNER, 'OWNER#', 'META#SYNC', 'NOTE#', 'CHANGE#', 'ChangesByOwnerSequence', 'changeSequence']) {
    assertTrue(!cursor.includes(secret), `cursor must not contain ${secret}`);
  }
});

check('the payload layout is pinned, so a live cursor keeps decoding', () => {
  assertEqual(stableDigest('user-123'), '8c93cc934a36643f40b5f9e17b3571c3', 'stableDigest');
  assertEqual(
    encodeChangeCursor(OWNER, 41),
    'eyJ2IjoxLCJrIjoiYTY2Y2YxM2ZmMTNlMjFiYmZkNjYxMjgxOWYyMjg1NmYiLCJzIjo0MX0',
    'encodeChangeCursor',
  );
  assertEqual(
    encodeChangeCursor(OWNER, 0),
    'eyJ2IjoxLCJrIjoiYTY2Y2YxM2ZmMTNlMjFiYmZkNjYxMjgxOWYyMjg1NmYiLCJzIjowfQ',
    'encodeChangeCursor at sequence 0',
  );
});

check('the digest is deterministic, wide, and input-sensitive', () => {
  assertEqual(stableDigest('mutation:["create","a",0,null,null]').length, 32, 'hex length');
  assertEqual(stableDigest('a'), stableDigest('a'), 'determinism');
  assertTrue(stableDigest('a') !== stableDigest('b'), 'different input, different digest');
  assertTrue(stableDigest('cursor-account:a') !== stableDigest('mutation:a'), 'domain separation');
});

check('malformed cursors are rejected as unreadable', () => {
  const malformed: unknown[] = [
    'not base64!',
    'AAAA', // valid alphabet, invalid base64 payload
    encodePayload([1, 2, 3]), // not a JSON object
    encodePayload({ v: 1, k: stableDigest('cursor-account:user-123') }), // no sequence
    encodePayload({ v: 1, k: 7, s: 1 }), // binding is not a string
    encodePayload({ v: 1, k: stableDigest('cursor-account:user-123'), s: -1 }),
    encodePayload({ v: 1, k: stableDigest('cursor-account:user-123'), s: 1.5 }),
    encodePayload({ v: 1, k: stableDigest('cursor-account:user-123'), s: '1' }),
    'a'.repeat(161), // longer than any cursor this backend mints
  ];
  for (const cursor of malformed) {
    assertRejects(() => decodeChangeCursor(cursor as string, OWNER), 'MALFORMED', String(cursor).slice(0, 32));
  }
});

check('a cursor from another API version is rejected as such', () => {
  assertRejects(
    () => decodeChangeCursor(encodePayload({ v: 2, k: stableDigest('cursor-account:user-123'), s: 1 }), OWNER),
    'UNSUPPORTED_VERSION',
    'version 2',
  );
});

check('minting a cursor refuses a sequence storage could never produce', () => {
  for (const sequence of [-1, 1.5, Number.NaN, Number.MAX_SAFE_INTEGER + 1]) {
    let threw = false;
    try {
      encodeChangeCursor(OWNER, sequence);
    } catch (error) {
      threw = error instanceof RangeError;
    }
    assertTrue(threw, `sequence ${sequence} must be refused`);
  }
});

console.log(`${passed} cursor checks passed`);
