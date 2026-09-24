import type {
  APIGatewayProxyEventV2WithJWTAuthorizer,
  APIGatewayProxyHandlerV2WithJWTAuthorizer,
  APIGatewayProxyStructuredResultV2,
} from 'aws-lambda';

/**
 * NoteFlow remote sync Lambda (M1.1 skeleton).
 *
 * Serves the routes frozen in `docs/sync_api_contract.md`:
 *
 * - `GET  /sync/health`    -> `200 { "ok": true }`
 * - `POST /sync/mutations` -> `501`, implemented in a later slice
 * - `GET  /sync/changes`   -> `501`, implemented in a later slice
 *
 * This slice owns transport only: no DynamoDB, no mutation handling, and no
 * change feed. The API Gateway resource, JWT authorizer, and CORS live in
 * `amplify/sync/http_api.ts`; nothing of that resource definition is repeated
 * here.
 *
 * The function is invoked behind the API Gateway JWT authorizer, hence the
 * authorizer-aware event type. Identity comes from the verified claims only,
 * and request bodies, headers, and raw tokens are never read into logs or
 * echoed into responses.
 */

/** Paths of the frozen contract; `http_api.ts` routes the same three. */
const HEALTH_PATH = '/sync/health';
const MUTATIONS_PATH = '/sync/mutations';
const CHANGES_PATH = '/sync/changes';

/** Contract error envelope (`docs/sync_api_contract.md`, "Error envelope"). */
type SyncErrorBody = Readonly<{
  code: 'NOT_FOUND' | 'NOT_IMPLEMENTED' | 'INTERNAL_ERROR';
  message: string;
  retryable: boolean;
}>;

const NOT_FOUND: SyncErrorBody = {
  code: 'NOT_FOUND',
  message: 'This route does not exist.',
  retryable: false,
};

const NOT_IMPLEMENTED: SyncErrorBody = {
  code: 'NOT_IMPLEMENTED',
  message: 'Remote sync is not available yet.',
  retryable: false,
};

const INTERNAL_ERROR: SyncErrorBody = {
  code: 'INTERNAL_ERROR',
  message: 'The request could not be completed.',
  retryable: true,
};

type SyncRoute = 'health' | 'mutations' | 'changes' | 'unknown';

/**
 * Routes on path alone: the HTTP API already restricts each path to its
 * contract method, so there is no second method table to keep in step.
 */
const routeOf = (path: string): SyncRoute => {
  switch (path) {
    case HEALTH_PATH:
      return 'health';
    case MUTATIONS_PATH:
      return 'mutations';
    case CHANGES_PATH:
      return 'changes';
    default:
      return 'unknown';
  }
};

/**
 * The Cognito subject that owns every note the sync routes will read and write.
 * Verified claims are the only identity source the handler trusts: an `ownerId`
 * in a request body is never authoritative.
 *
 * Optional chaining keeps a direct, authorizer-less invocation from throwing.
 */
const ownerSubOf = (event: APIGatewayProxyEventV2WithJWTAuthorizer): string | undefined => {
  const sub = event.requestContext.authorizer?.jwt?.claims?.['sub'];
  return typeof sub === 'string' ? sub : undefined;
};

const json = (statusCode: number, body: unknown): APIGatewayProxyStructuredResultV2 => ({
  statusCode,
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify(body),
});

export const handler: APIGatewayProxyHandlerV2WithJWTAuthorizer = async (event) => {
  try {
    const route = routeOf(event.rawPath);

    if (route === 'health') {
      return json(200, { ok: true });
    }

    if (route !== 'unknown') {
      // The mutation and change-feed slices key their storage on this subject.
      // It is read once here, at the trust boundary, and never logged: only
      // whether it resolved is recorded.
      console.info('sync route not implemented', {
        route,
        ownerResolved: ownerSubOf(event) !== undefined,
      });
      return json(501, NOT_IMPLEMENTED);
    }

    return json(404, NOT_FOUND);
  } catch {
    // No exception detail crosses the contract: no message, stack, or request data.
    return json(500, INTERNAL_ERROR);
  }
};
