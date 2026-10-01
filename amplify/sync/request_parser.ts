/**
 * Request parsing for the NoteFlow sync Lambda (M1.2 application-adapter slice B).
 *
 * Turns raw HTTP input - a JSON body, a query-string map - into the values the
 * store port accepts, and reports a `problem` instead of throwing, so the
 * handler maps every refusal to one contract envelope. This module is pure: no
 * AWS SDK, no I/O, and no transport types, so its checks run with
 * `npx tsx amplify/sync/request_parser.test.ts` (see `docs/sync_api_contract.md`).
 *
 * Field-level problems reuse the store's `InvalidMutationReason` vocabulary, so
 * a body refused here and a body refused by `DynamoSyncStore` reach the client
 * through the same 422 message table in `sync_response.ts`. The store still
 * re-validates every mutation: it is the authority for callers that do not come
 * through HTTP, and the identifier limits mirrored below are repeated there.
 *
 * The cursor is deliberately not inspected. It is opaque, and only
 * `decodeChangeCursor` in `cursor.ts` can judge it, because the judgement needs
 * the caller's `ownerId`; the parser only carries it through.
 */

import type { InvalidMutationReason, SyncMutation, SyncOperation } from './dynamo_sync_store';

/** Contract defaults for `GET /sync/changes`; the store clamps to the same window. */
export const DEFAULT_CHANGE_LIMIT = 50;
export const MAX_CHANGE_LIMIT = 100;

/**
 * Mirrors `MAX_IDENTIFIER_LENGTH` / `CONTROL_CHARACTERS` in
 * `dynamo_sync_store.ts`. Kept in step by its checks, not by an import: the
 * store does not export them, and the parser must stay free of store code.
 */
const MAX_IDENTIFIER_LENGTH = 128;
const CONTROL_CHARACTERS = /[\u0000-\u001f\u007f]/;
const UTC_TIMESTAMP = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?Z$/;
const UNSIGNED_INTEGER = /^\d+$/;

const isUtcTimestamp = (value: unknown): value is string => {
  if (typeof value !== 'string') return false;
  const parts = UTC_TIMESTAMP.exec(value);
  if (parts === null) return false;
  const parsed = new Date(value);
  return Number.isFinite(parsed.getTime()) &&
    parsed.getUTCFullYear() === Number(parts[1]) &&
    parsed.getUTCMonth() + 1 === Number(parts[2]) &&
    parsed.getUTCDate() === Number(parts[3]) &&
    parsed.getUTCHours() === Number(parts[4]) &&
    parsed.getUTCMinutes() === Number(parts[5]) &&
    parsed.getUTCSeconds() === Number(parts[6]);
};

/** The body was absent, unreadable, or not a JSON object; no single field to blame. */
export type BodyProblem = 'BODY_MALFORMED';

/** Why a mutation request was refused before or during application. */
export type MutationProblem = InvalidMutationReason | BodyProblem;

export type MutationParseResult =
  | Readonly<{ ok: true; mutation: SyncMutation }>
  | Readonly<{ ok: false; problem: MutationProblem }>;

/** The only query problem this layer can see: an unreadable cursor is the codec's call. */
export type ChangesQueryProblem = 'LIMIT_INVALID';

export type ChangesQueryParseResult =
  | Readonly<{ ok: true; cursor: string | undefined; limit: number }>
  | Readonly<{ ok: false; problem: ChangesQueryProblem }>;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const isOperation = (value: unknown): value is SyncOperation =>
  value === 'create' || value === 'update' || value === 'delete';

/** Identity is a string the store can key on: non-blank, bounded, control-character free. */
const readIdentifier = (value: unknown): string | null =>
  typeof value === 'string' &&
  value.trim().length > 0 &&
  value.length <= MAX_IDENTIFIER_LENGTH &&
  !CONTROL_CHARACTERS.test(value)
    ? value
    : null;

const readBaseRevision = (value: unknown): number | null =>
  typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 ? value : null;

/**
 * Parses a `POST /sync/mutations` body.
 *
 * `create` and `update` need a `{title, content}` payload. `pinnedAt` is
 * optional for old clients; when omitted on update, the stored value survives.
 * A `delete` is
 * payload-free by contract: one sent alongside it is ignored rather than
 * refused, and the store writes a payload-free tombstone either way.
 *
 * Unknown fields are ignored, so a later additive contract change does not
 * break older servers.
 */
export const parseMutationBody = (body: string | null | undefined): MutationParseResult => {
  if (typeof body !== 'string' || body.length === 0) {
    return { ok: false, problem: 'BODY_MALFORMED' };
  }

  let decoded: unknown;
  try {
    decoded = JSON.parse(body);
  } catch {
    return { ok: false, problem: 'BODY_MALFORMED' };
  }
  if (!isRecord(decoded)) {
    return { ok: false, problem: 'BODY_MALFORMED' };
  }

  const mutationId = readIdentifier(decoded.mutationId);
  if (mutationId === null) {
    return { ok: false, problem: 'MUTATION_ID_INVALID' };
  }

  const noteId = readIdentifier(decoded.noteId);
  if (noteId === null) {
    return { ok: false, problem: 'NOTE_ID_INVALID' };
  }

  const operation = decoded.operation;
  if (!isOperation(operation)) {
    return { ok: false, problem: 'OPERATION_UNSUPPORTED' };
  }

  const baseRevision = readBaseRevision(decoded.baseRevision);
  if (baseRevision === null) {
    return { ok: false, problem: 'BASE_REVISION_INVALID' };
  }

  if (operation === 'delete') {
    return { ok: true, mutation: { mutationId, noteId, operation, baseRevision } };
  }

  const payload = decoded.payload;
  if (!isRecord(payload)) {
    return { ok: false, problem: 'PAYLOAD_REQUIRED' };
  }

  const { title, content } = payload;
  if (
    typeof title !== 'string' ||
    typeof content !== 'string' ||
    title.trim().length === 0 ||
    content.trim().length === 0
  ) {
    return { ok: false, problem: 'PAYLOAD_INVALID' };
  }

  const hasPinnedAt = Object.prototype.hasOwnProperty.call(payload, 'pinnedAt');
  const pinnedAt = payload.pinnedAt;
  if (
    hasPinnedAt &&
    pinnedAt !== null &&
    !isUtcTimestamp(pinnedAt)
  ) {
    return { ok: false, problem: 'PAYLOAD_INVALID' };
  }

  return {
    ok: true,
    mutation: {
      mutationId,
      noteId,
      operation,
      baseRevision,
      payload: {
        title,
        content,
        ...(hasPinnedAt ? { pinnedAt: pinnedAt as string | null } : {}),
      },
    },
  };
};

/**
 * Reads `limit` as a whole number in 1..100, defaulting to 50 when the caller
 * sends none. A non-numeric, zero, or over-cap value is refused instead of
 * silently clamped: a client that asks for more than the contract serves should
 * learn that, not poll for a page it never receives.
 */
const readLimit = (value: unknown): number | null => {
  if (value === undefined || value === null || value === '') {
    return DEFAULT_CHANGE_LIMIT;
  }
  if (typeof value !== 'string' || !UNSIGNED_INTEGER.test(value)) {
    return null;
  }
  const limit = Number(value);
  return Number.isSafeInteger(limit) && limit >= 1 && limit <= MAX_CHANGE_LIMIT ? limit : null;
};

/**
 * Parses a `GET /sync/changes` query string.
 *
 * A missing or empty cursor means "from the beginning" and travels to the store
 * as `undefined`, which is how `decodeChangeCursor` reads it. Any other value
 * is passed through untouched: the cursor is opaque to this layer.
 */
export const parseChangesQuery = (
  query: Readonly<Record<string, string | undefined>> | null | undefined,
): ChangesQueryParseResult => {
  const limit = readLimit(query?.limit);
  if (limit === null) {
    return { ok: false, problem: 'LIMIT_INVALID' };
  }

  const cursor = query?.cursor;
  return { ok: true, cursor: cursor === undefined || cursor === '' ? undefined : cursor, limit };
};
