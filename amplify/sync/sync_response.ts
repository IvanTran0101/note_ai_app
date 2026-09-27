/**
 * Response shaping for the NoteFlow sync Lambda (M1.2 application-adapter slice B).
 *
 * The one place that knows the HTTP statuses and JSON bodies frozen in
 * `docs/sync_api_contract.md`, so `handler.ts` stays a dispatcher. Every error
 * leaves here as the contract envelope `{code, message, retryable}` built from a
 * canned message table: a provider error message, exception text, stack, token,
 * or request body can never reach a client through this module.
 *
 * Note snapshots travel as the seven fields `SyncNoteSnapshot` in
 * `lib/application/sync/sync_contract.dart` requires - `id`, `title`, `content`,
 * `revision`, `createdAt`, `serverUpdatedAt`, `deletedAt` - which is exactly the
 * store's `NoteSnapshot`. The M1.0 example abbreviates that object; the
 * Application port is what the client can actually construct.
 */

import type { APIGatewayProxyStructuredResultV2 } from 'aws-lambda';
import type { InvalidCursorReason } from './cursor';
import type { AppliedMutation, ChangesPage, ConflictedMutation, NoteSnapshot } from './dynamo_sync_store';
import type { ChangesQueryProblem, MutationProblem } from './request_parser';

/** Contract error codes this slice can emit. */
export type SyncErrorCode =
  | 'UNAUTHORIZED'
  | 'NOT_FOUND'
  | 'INVALID_REQUEST'
  | 'INVALID_MUTATION'
  | 'INVALID_CURSOR'
  | 'REVISION_CONFLICT'
  | 'SERVER_UNAVAILABLE'
  | 'INTERNAL_ERROR';

export type SyncErrorBody = Readonly<{
  code: SyncErrorCode;
  message: string;
  retryable: boolean;
}>;

/** The wire form of one note snapshot; see the module comment. */
export type NoteBody = Readonly<{
  id: string;
  title: string;
  content: string;
  revision: number;
  createdAt: string;
  serverUpdatedAt: string;
  deletedAt: string | null;
}>;

export type AppliedMutationBody = Readonly<{
  status: 'applied';
  mutationId: string;
  note: NoteBody;
}>;

/** The 409 body: `status` is carried by the HTTP status, as the contract shows it. */
export type ConflictBody = Readonly<{
  code: 'REVISION_CONFLICT';
  retryable: false;
  mutationId: string;
  remoteNote: NoteBody | null;
}>;

export type ChangesPageBody = Readonly<{
  items: readonly NoteBody[];
  hasMore: boolean;
  nextCursor?: string;
}>;

const CONTENT_TYPE_JSON = { 'content-type': 'application/json' } as const;

/**
 * Safe, user-facing text for every way a mutation can be refused. The keys are
 * the store's reasons plus the parser's body problem, so a `SyncInvalidMutationError`
 * thrown by the store is mapped by the same table as a body the parser refused.
 */
const MUTATION_MESSAGES: Readonly<Record<MutationProblem, string>> = {
  BODY_MALFORMED: 'The request body must be a JSON object.',
  MUTATION_ID_INVALID: 'A mutation needs a non-empty mutationId of at most 128 characters.',
  MUTATION_ID_REUSED: 'That mutationId was already used for a different request.',
  NOTE_ID_INVALID: 'A mutation needs a non-empty noteId of at most 128 characters.',
  OPERATION_UNSUPPORTED: 'The mutation operation is not supported.',
  BASE_REVISION_INVALID: 'baseRevision must be a non-negative whole number.',
  PAYLOAD_REQUIRED: 'create and update need a title and content payload.',
  PAYLOAD_INVALID: 'A payload needs a string title and content.',
  PAYLOAD_TOO_LARGE: 'The note payload is too large to store.',
};

const CURSOR_MESSAGES: Readonly<Record<InvalidCursorReason, string>> = {
  MALFORMED: 'The sync cursor is not readable.',
  UNSUPPORTED_VERSION: 'This sync cursor came from a different API version.',
  ACCOUNT_MISMATCH: 'This sync cursor was issued to a different account.',
};

const LIMIT_MESSAGE = 'limit must be a whole number from 1 to 100.';

export const jsonResponse = (statusCode: number, body: unknown): APIGatewayProxyStructuredResultV2 => ({
  statusCode,
  headers: CONTENT_TYPE_JSON,
  body: JSON.stringify(body),
});

const errorResponse = (statusCode: number, body: SyncErrorBody): APIGatewayProxyStructuredResultV2 =>
  jsonResponse(statusCode, body);

/** Projects a stored snapshot onto the wire shape, so storage fields cannot leak. */
export const noteBodyOf = (note: NoteSnapshot): NoteBody => ({
  id: note.id,
  title: note.title,
  content: note.content,
  revision: note.revision,
  createdAt: note.createdAt,
  serverUpdatedAt: note.serverUpdatedAt,
  deletedAt: note.deletedAt,
});

/**
 * The applied result, minus the store's `replayed` flag: it is bookkeeping for
 * the store, and the contract's applied body carries only these three fields.
 */
export const appliedMutationBody = ({ mutationId, note }: AppliedMutation): AppliedMutationBody => ({
  status: 'applied',
  mutationId,
  note: noteBodyOf(note),
});

/** `remoteNote` is `null` when the account has no stored note to conflict with. */
export const conflictBody = ({ mutationId, remoteNote }: ConflictedMutation): ConflictBody => ({
  code: 'REVISION_CONFLICT',
  retryable: false,
  mutationId,
  remoteNote: remoteNote === null ? null : noteBodyOf(remoteNote),
});

/**
 * The change page. `nextCursor` is copied only when the store minted one: it is
 * optional on the port, and an absent cursor must stay absent rather than be
 * serialized as `null`.
 */
export const changesPageBody = ({ items, nextCursor, hasMore }: ChangesPage): ChangesPageBody => {
  const body: { items: NoteBody[]; hasMore: boolean; nextCursor?: string } = {
    items: items.map(noteBodyOf),
    hasMore,
  };
  if (typeof nextCursor === 'string' && nextCursor.length > 0) {
    body.nextCursor = nextCursor;
  }
  return body;
};

export const appliedMutationResponse = (result: AppliedMutation): APIGatewayProxyStructuredResultV2 =>
  jsonResponse(200, appliedMutationBody(result));

export const conflictResponse = (result: ConflictedMutation): APIGatewayProxyStructuredResultV2 =>
  jsonResponse(409, conflictBody(result));

export const changesResponse = (page: ChangesPage): APIGatewayProxyStructuredResultV2 =>
  jsonResponse(200, changesPageBody(page));

/**
 * Reached only when the authorizer was bypassed: the deployed API rejects an
 * unauthenticated `/sync/*` call before the Lambda runs.
 */
export const unauthorizedResponse = (): APIGatewayProxyStructuredResultV2 =>
  errorResponse(401, {
    code: 'UNAUTHORIZED',
    message: 'Sign in to use remote sync.',
    retryable: false,
  });

export const notFoundResponse = (): APIGatewayProxyStructuredResultV2 =>
  errorResponse(404, {
    code: 'NOT_FOUND',
    message: 'This route does not exist.',
    retryable: false,
  });

export const invalidMutationResponse = (problem: MutationProblem): APIGatewayProxyStructuredResultV2 =>
  errorResponse(422, {
    code: 'INVALID_MUTATION',
    message: MUTATION_MESSAGES[problem],
    retryable: false,
  });

/**
 * A refused change-feed query. `limit` is a request-shape problem and a cursor
 * is a codec problem, so they carry different codes; both are client errors
 * with no retry value.
 */
export const invalidChangesResponse = (
  problem: ChangesQueryProblem | InvalidCursorReason,
): APIGatewayProxyStructuredResultV2 =>
  problem === 'LIMIT_INVALID'
    ? errorResponse(422, { code: 'INVALID_REQUEST', message: LIMIT_MESSAGE, retryable: false })
    : errorResponse(422, { code: 'INVALID_CURSOR', message: CURSOR_MESSAGES[problem], retryable: false });

/**
 * Storage failed. `retryable` comes from the store, so a throttled or contended
 * write is a 503 the client may send again, while a failure the same request
 * would repeat (bad data, denied call, missing table) is a 500 it must not.
 */
export const storageFailureResponse = (retryable: boolean): APIGatewayProxyStructuredResultV2 =>
  retryable
    ? errorResponse(503, {
        code: 'SERVER_UNAVAILABLE',
        message: 'Remote sync is temporarily unavailable. Try again.',
        retryable: true,
      })
    : errorResponse(500, {
        code: 'INTERNAL_ERROR',
        message: 'The request could not be completed.',
        retryable: false,
      });

/** The catch-all: nothing about the failure itself is described to the client. */
export const internalErrorResponse = (): APIGatewayProxyStructuredResultV2 =>
  errorResponse(500, {
    code: 'INTERNAL_ERROR',
    message: 'The request could not be completed.',
    retryable: true,
  });
