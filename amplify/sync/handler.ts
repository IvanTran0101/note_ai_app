import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import type {
  APIGatewayProxyEventV2WithJWTAuthorizer,
  APIGatewayProxyHandlerV2WithJWTAuthorizer,
  APIGatewayProxyStructuredResultV2,
} from 'aws-lambda';
import { SyncInvalidCursorError } from './cursor';
import { DynamoSyncStore, SyncInvalidMutationError, SyncStorageError } from './dynamo_sync_store';
import type { SyncStore } from './dynamo_sync_store';
import { parseChangesQuery, parseMutationBody } from './request_parser';
import { Argon2idPasswordHasher } from '../protection/argon2id_password_hasher';
import { DynamoProtectionStore } from '../protection/dynamo_protection_store';
import { ProtectionUseCases } from '../protection/use_cases';
import { NoteSecurityError, OwnerNoteAcl } from '../protection/protection_store';
import { SesRecoveryMailer } from '../protection/ses_recovery_mailer';
import { handleProtection, securityErrorResponse, unlockGrantOf } from '../protection/handler';
import {
  appliedMutationResponse,
  changesResponse,
  conflictResponse,
  internalErrorResponse,
  invalidChangesResponse,
  invalidMutationResponse,
  jsonResponse,
  notFoundResponse,
  storageFailureResponse,
  unauthorizedResponse,
} from './sync_response';

/**
 * NoteFlow remote sync Lambda (M1.2 application-adapter slice B).
 *
 * Serves the routes frozen in `docs/sync_api_contract.md`:
 *
 * - `GET  /sync/health`    -> `200 { "ok": true }`
 * - `POST /sync/mutations` -> `200` applied, `409` conflict, `422` invalid
 * - `GET  /sync/changes`   -> `200` page, `422` invalid cursor or limit
 * - anything else          -> `404`
 *
 * This file owns transport only: method/path routing, the identity check, and
 * the store calls. Body and query parsing live in `request_parser.ts`, JSON
 * bodies and statuses in `sync_response.ts`, and note/mutation semantics in
 * `dynamo_sync_store.ts`; the API Gateway resource, JWT authorizer, and CORS
 * stay in `http_api.ts`. There is no router class: the dispatch is three small
 * functions.
 *
 * Identity comes from the verified claims only - a body `ownerId` is never
 * authoritative - and no token, request body, identifier, or exception text is
 * ever logged or echoed. Logs carry a route, a problem class, and at most the
 * class name of an unexpected error.
 */

/**
 * `process` is described by `@types/node`, which this backend does not depend on
 * (see `package.json`), so the two variables the function reads are declared
 * here. A module-scoped declaration only shadows the global of the same name.
 */
declare const process: { env: Record<string, string | undefined> };

/** Paths of the frozen contract; `http_api.ts` routes the same three. */
const HEALTH_PATH = '/sync/health';
const MUTATIONS_PATH = '/sync/mutations';
const CHANGES_PATH = '/sync/changes';

type SyncRoute = 'health' | 'mutations' | 'changes' | 'unknown';

/**
 * `NOTES_TABLE_NAME` is set by `sync_function.ts`; `NOTES_TABLE_REGION` travels
 * under an app-owned name because the Lambda runtime reserves `AWS_REGION`.
 */
const NOTES_TABLE_NAME = process.env.NOTES_TABLE_NAME ?? '';
const NOTES_TABLE_REGION = process.env.NOTES_TABLE_REGION;

/**
 * One document client and one store per container, built at module scope so a
 * warm Lambda reuses the SDK's HTTP connections across invocations instead of
 * rebuilding them per request. The marshalling options match the ones the store
 * applies to its own default client; passing the client in keeps its lifecycle
 * - and the region the function was deployed with - owned here.
 *
 * A missing table name fails the constructor during container init, which is the
 * intended behaviour for a misconfigured deployment: no route, not even health,
 * should report healthy against no storage.
 */
const documentClient = DynamoDBDocumentClient.from(
  new DynamoDBClient(NOTES_TABLE_REGION === undefined ? {} : { region: NOTES_TABLE_REGION }),
  { marshallOptions: { removeUndefinedValues: true } },
);

const security = new ProtectionUseCases(new DynamoProtectionStore(NOTES_TABLE_NAME, documentClient),
  new Argon2idPasswordHasher(), new OwnerNoteAcl(),
  new SesRecoveryMailer(process.env.NOTE_SECURITY_SENDER ?? ''), Date.now,
  Number(process.env.NOTE_SECURITY_GRANT_TTL_MS ?? '900000'));
const store: SyncStore = new DynamoSyncStore({ tableName: NOTES_TABLE_NAME, documentClient, security });

const methodOf = (event: APIGatewayProxyEventV2WithJWTAuthorizer): string =>
  event.requestContext?.http?.method?.toUpperCase() ?? '';

/**
 * An empty method means the event did not come through API Gateway (a direct
 * invoke, or a test), so the path decides on its own, as it did in M1.1. A
 * method that is present must be the contract's one.
 */
const matchesMethod = (expected: string, method: string): boolean => method === '' || method === expected;

const routeOf = (method: string, path: string): SyncRoute => {
  switch (path) {
    case HEALTH_PATH:
      return matchesMethod('GET', method) ? 'health' : 'unknown';
    case MUTATIONS_PATH:
      return matchesMethod('POST', method) ? 'mutations' : 'unknown';
    case CHANGES_PATH:
      return matchesMethod('GET', method) ? 'changes' : 'unknown';
    default:
      return 'unknown';
  }
};

/**
 * The Cognito subject that owns every note these routes read and write. Verified
 * claims are the only identity source the handler trusts; optional chaining
 * keeps an authorizer-less direct invocation from throwing, so a missing
 * identity is a 401 rather than a 500.
 */
const ownerSubOf = (event: APIGatewayProxyEventV2WithJWTAuthorizer): string | undefined => {
  const sub = event.requestContext?.authorizer?.jwt?.claims?.['sub'];
  return typeof sub === 'string' ? sub : undefined;
};

/** An error's class name is a classifier, never request content. */
const errorNameOf = (error: unknown): string => {
  const name = (error as { name?: unknown } | null | undefined)?.name;
  return typeof name === 'string' ? name : 'UnknownError';
};

const logRejected = (route: SyncRoute, problem: string): void => {
  console.info('sync request rejected', { route, problem });
};

/**
 * Maps what the store throws onto the contract's client and retryable failures.
 * `undefined` means the error is not one this layer knows, and the caller lets
 * the dispatcher turn it into a safe 500.
 */
const responseForStoreError = (
  route: SyncRoute,
  error: unknown,
): APIGatewayProxyStructuredResultV2 | undefined => {
  if (error instanceof NoteSecurityError) return securityErrorResponse(error);
  if (error instanceof SyncInvalidMutationError) {
    logRejected(route, error.reason);
    return invalidMutationResponse(error.reason);
  }
  if (error instanceof SyncInvalidCursorError) {
    logRejected(route, error.reason);
    return invalidChangesResponse(error.reason);
  }
  if (error instanceof SyncStorageError) {
    console.warn('sync storage failure', { route, retryable: error.retryable });
    return storageFailureResponse(error.retryable);
  }
  return undefined;
};

const handleMutation = async (
  event: APIGatewayProxyEventV2WithJWTAuthorizer,
  ownerId: string,
): Promise<APIGatewayProxyStructuredResultV2> => {
  const parsed = parseMutationBody(event.body);
  if (!parsed.ok) {
    logRejected('mutations', parsed.problem);
    return invalidMutationResponse(parsed.problem);
  }

  try {
    const result = await store.applyMutation(ownerId, parsed.mutation, { actorId: ownerId, grant: unlockGrantOf(event) });
    return result.status === 'applied' ? appliedMutationResponse(result) : conflictResponse(result);
  } catch (error) {
    const mapped = responseForStoreError('mutations', error);
    if (mapped !== undefined) {
      return mapped;
    }
    throw error;
  }
};

const handleChanges = async (
  event: APIGatewayProxyEventV2WithJWTAuthorizer,
  ownerId: string,
): Promise<APIGatewayProxyStructuredResultV2> => {
  const parsed = parseChangesQuery(event.queryStringParameters);
  if (!parsed.ok) {
    logRejected('changes', parsed.problem);
    return invalidChangesResponse(parsed.problem);
  }

  try {
    return changesResponse(await store.listChanges(ownerId, parsed.cursor, parsed.limit));
  } catch (error) {
    const mapped = responseForStoreError('changes', error);
    if (mapped !== undefined) {
      return mapped;
    }
    throw error;
  }
};

export const handler: APIGatewayProxyHandlerV2WithJWTAuthorizer = async (event) => {
  let route: SyncRoute = 'unknown';
  try {
    route = routeOf(methodOf(event), event.rawPath);
    if (event.rawPath.startsWith('/notes/')) {
      const actor = ownerSubOf(event);
      return actor ? await handleProtection(event, actor, security) : unauthorizedResponse();
    }

    // M1.1 behaviour, unchanged: health answers without an identity so the
    // deployment can be probed. The deployed API still puts it behind the JWT
    // authorizer, so an anonymous caller never reaches this line.
    if (route === 'health') {
      return jsonResponse(200, { ok: true });
    }
    if (route === 'unknown') {
      return notFoundResponse();
    }

    const ownerId = ownerSubOf(event);
    if (ownerId === undefined) {
      // Only reachable when the authorizer was bypassed (a direct invoke).
      return unauthorizedResponse();
    }

    return route === 'mutations' ? await handleMutation(event, ownerId) : await handleChanges(event, ownerId);
  } catch (error) {
    if (error instanceof NoteSecurityError) return securityErrorResponse(error);
    // Nothing about the failure crosses the contract: no message, stack, cause,
    // token, or request data is logged or returned.
    console.error('sync request failed', { route, errorName: errorNameOf(error) });
    return internalErrorResponse();
  }
};
