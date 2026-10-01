import { Duration } from 'aws-cdk-lib';
import {
  CorsHttpMethod,
  HttpApi,
  HttpMethod,
  PayloadFormatVersion,
} from 'aws-cdk-lib/aws-apigatewayv2';
import { HttpJwtAuthorizer } from 'aws-cdk-lib/aws-apigatewayv2-authorizers';
import { HttpLambdaIntegration } from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import type { IFunction } from 'aws-cdk-lib/aws-lambda';
import type { Construct } from 'constructs';

/**
 * NoteFlow remote sync HTTP API (M1.1 skeleton).
 *
 * Creates the API Gateway HTTP API, the Cognito JWT authorizer, the Lambda
 * integration, and the CORS preflight for the routes frozen in
 * `docs/sync_api_contract.md` and served by `amplify/sync/handler.ts`:
 *
 * - `GET  /sync/health`
 * - `POST /sync/mutations`
 * - `GET  /sync/changes`
 *
 * The root composes this from `amplify/backend.ts`; the resource definition
 * stays out of the handler so the Lambda bundle carries no CDK code.
 *
 * @see https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-jwt-authorizer.html
 */

/** Mirrors the routing table in `handler.ts`. */
const HEALTH_PATH = '/sync/health';
const MUTATIONS_PATH = '/sync/mutations';
const CHANGES_PATH = '/sync/changes';

/** Headers the contract's client sends: `Authorization` plus a JSON body. */
const SYNC_REQUEST_HEADERS = ['authorization', 'content-type', 'x-note-unlock-grant'];

export type SyncHttpApiProps = Readonly<{
  /** Scope the API is created in, e.g. `backend.createStack('SyncStack')`. */
  scope: Construct;
  /** The sync Lambda, e.g. `backend.sync.resources.lambda`. */
  handler: IFunction;
  /** User pool issuer, e.g. `backend.auth.resources.userPool.userPoolProviderUrl`. */
  issuerUrl: string;
  /** App client id(s) whose tokens are accepted, e.g. the pool client id. */
  audience: string[];
  /** Browser origins allowed to call the API. @default ['*'] */
  allowedOrigins?: string[];
}>;

export type SyncHttpApi = Readonly<{
  api: HttpApi;
  authorizer: HttpJwtAuthorizer;
}>;

/**
 * Wires the sync Lambda to a JWT-protected HTTP API with web CORS.
 *
 * The authorizer validates the token's `aud` claim against `audience`, and CDK
 * requires that list to be non-empty. Check the value against the token the
 * Flutter client actually sends: Cognito ID tokens carry `aud` (app client id),
 * while access tokens carry `client_id` instead.
 */
export const createSyncHttpApi = ({
  scope,
  handler,
  issuerUrl,
  audience,
  allowedOrigins = ['*'],
}: SyncHttpApiProps): SyncHttpApi => {
  if (audience.length === 0) {
    throw new Error('createSyncHttpApi requires at least one audience (Cognito app client id).');
  }

  const authorizer = new HttpJwtAuthorizer('SyncJwtAuthorizer', issuerUrl, {
    jwtAudience: audience,
  });

  const integration = new HttpLambdaIntegration('SyncLambdaIntegration', handler, {
    // 2.0 is the payload format the handler's `APIGatewayProxyEventV2` types describe.
    payloadFormatVersion: PayloadFormatVersion.VERSION_2_0,
  });

  const api = new HttpApi(scope, 'SyncHttpApi', {
    apiName: 'noteflow-sync',
    description: 'NoteFlow remote note sync API (M1.1 skeleton).',
    corsPreflight: {
      allowOrigins: allowedOrigins,
      allowMethods: [CorsHttpMethod.GET, CorsHttpMethod.POST, CorsHttpMethod.OPTIONS],
      allowHeaders: SYNC_REQUEST_HEADERS,
      // The client sends a bearer token rather than cookies, so a wildcard
      // origin cannot be used for credentialed cross-site requests.
      allowCredentials: false,
      maxAge: Duration.hours(1),
    },
  });

  // No default authorizer: each route states its authorizer explicitly.
  api.addRoutes({ path: HEALTH_PATH, methods: [HttpMethod.GET], integration, authorizer });
  api.addRoutes({ path: MUTATIONS_PATH, methods: [HttpMethod.POST], integration, authorizer });
  api.addRoutes({ path: CHANGES_PATH, methods: [HttpMethod.GET], integration, authorizer });
  api.addRoutes({ path: '/notes/{proxy+}', methods: [HttpMethod.GET, HttpMethod.POST], integration, authorizer });

  return { api, authorizer };
};
