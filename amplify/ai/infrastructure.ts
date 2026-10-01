import { Duration, RemovalPolicy, Stack } from 'aws-cdk-lib';
import {
  CfnIntegration,
  CorsHttpMethod,
  HttpApi,
  HttpMethod,
  PayloadFormatVersion,
} from 'aws-cdk-lib/aws-apigatewayv2';
import { HttpJwtAuthorizer } from 'aws-cdk-lib/aws-apigatewayv2-authorizers';
import { HttpLambdaIntegration } from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import { AttributeType, BillingMode, Table, type ITable } from 'aws-cdk-lib/aws-dynamodb';
import { PolicyStatement } from 'aws-cdk-lib/aws-iam';
import type { IFunction } from 'aws-cdk-lib/aws-lambda';

/**
 * Summary Cloud infrastructure: one JWT-protected HTTP API route and one quota
 * table, both placed in the stack that already owns the managed handler.
 *
 * `Stack.of(handler)` is deliberate. The handler is the Amplify-managed
 * function; a table or API created in a second stack would make that function
 * reference resources across a stack boundary, and the composition would need
 * cross-stack exports or hit a cycle. Everything here lands beside the handler
 * instead, and `backend.ts` (root-owned) calls this with
 * `summary.resources.lambda`.
 *
 * The table mirrors the item layout in `quota.ts`: partition key
 * `accountWindow` (`<sub>#<epochMinute>`, string), on-demand billing, and TTL
 * on `expiresAt`. TTL is cleanup only - the limiter is the conditional update,
 * never the deletion. Sandbox settings destroy the table with the stack.
 *
 * The role gets exactly `dynamodb:UpdateItem` on this table: the quota is one
 * atomic conditional update, so no read, query, scan, or write on the notes
 * table is granted or needed. `SUMMARY_QUOTA_TABLE_NAME` is the only variable
 * added here; the provider key is the managed function's secret.
 *
 * The API serves exactly one route, `POST /ai/summary`, behind the Cognito JWT
 * authorizer: there is no default route and no unauthenticated route. The
 * integration uses payload format 2.0 and a 30 s timeout, above the function's
 * 28 s. This CDK version still validates the L2 against 29 s, so the single
 * summary route's L1 integration is adjusted to the supported HTTP API limit.
 * CORS allows
 * `POST`/`OPTIONS` with `authorization` and `content-type`, and exposes
 * `Retry-After` so a browser client can read the quota hint.
 */

/** The contract's only route; the API serves nothing else. */
const SUMMARY_PATH = '/ai/summary';

/** Environment name `lambda.ts` reads; the table name only, never a key. */
const QUOTA_TABLE_ENV = 'SUMMARY_QUOTA_TABLE_NAME';

/** Part of the table/`quota.ts` interface: the TTL attribute is a row field. */
const QUOTA_TABLE_TTL_ATTRIBUTE = 'expiresAt';

/** Headers the contract's client sends: bearer token plus a JSON body. */
const SUMMARY_REQUEST_HEADERS = ['authorization', 'content-type', 'x-note-unlock-grant'];

/** `Retry-After` is the only response header the browser client must read. */
const SUMMARY_EXPOSED_HEADERS = ['retry-after'];

/**
 * This CDK version's L2 still validates a 29s limit. The summary route's
 * scoped L1 override below preserves the supported HTTP API 30s limit, above
 * the function's 28s timeout.
 */
const INTEGRATION_TIMEOUT = Duration.seconds(29);

/**
 * `IFunction` omits `addEnvironment` in this CDK version even though the
 * Amplify-managed summary function is a `NodejsFunction` - a concrete CDK
 * `Function` - at runtime. This narrow bridge keeps the public prop the
 * `IFunction` that `defineFunction` exposes, and fails loudly if a function
 * that cannot carry an environment variable is ever passed in.
 */
type EnvironmentExtendableFunction = Readonly<{
  addEnvironment: (key: string, value: string) => void;
}>;

export type SummaryInfrastructureProps = Readonly<{
  /** The managed Summary Lambda, e.g. `summary.resources.lambda`. */
  handler: IFunction;
  notesTable: ITable;
  /** User pool issuer, e.g. `backend.auth.resources.userPool.userPoolProviderUrl`. */
  issuerUrl: string;
  /** App client id(s) whose tokens are accepted. */
  audience: string[];
  /** Browser origins allowed to call the API. @default ['*'] */
  allowedOrigins?: string[];
}>;

export type SummaryInfrastructure = Readonly<{
  api: HttpApi;
  table: Table;
}>;

const addQuotaTableEnvironment = (handler: IFunction, table: Table): void => {
  const target = handler as IFunction & Partial<EnvironmentExtendableFunction>;
  if (typeof target.addEnvironment !== 'function') {
    throw new Error(
      'createSummaryInfrastructure needs a CDK Function handler whose environment can take the quota table name.',
    );
  }
  target.addEnvironment(QUOTA_TABLE_ENV, table.tableName);
};

export const createSummaryInfrastructure = ({
  handler,
  notesTable,
  issuerUrl,
  audience,
  allowedOrigins = ['*'],
}: SummaryInfrastructureProps): SummaryInfrastructure => {
  if (audience.length === 0) {
    throw new Error('createSummaryInfrastructure requires at least one audience (Cognito app client id).');
  }

  const stack = Stack.of(handler);

  const table = new Table(stack, 'SummaryQuotaTable', {
    partitionKey: { name: 'accountWindow', type: AttributeType.STRING },
    billingMode: BillingMode.PAY_PER_REQUEST,
    timeToLiveAttribute: QUOTA_TABLE_TTL_ATTRIBUTE,
    removalPolicy: RemovalPolicy.DESTROY,
  });

  addQuotaTableEnvironment(handler, table);
  (handler as IFunction & EnvironmentExtendableFunction).addEnvironment('NOTES_TABLE_NAME', notesTable.tableName);
  handler.addToRolePolicy(new PolicyStatement({
    actions: ['dynamodb:GetItem', 'dynamodb:PutItem', 'dynamodb:ConditionCheckItem'],
    resources: [notesTable.tableArn],
  }));
  // One atomic conditional update is the whole quota, so `UpdateItem` on this
  // table is the entire DynamoDB surface. No notes-table access is granted.
  handler.addToRolePolicy(
    new PolicyStatement({
      actions: ['dynamodb:UpdateItem'],
      resources: [table.tableArn],
    }),
  );

  // The authorizer validates the token's signature and audience; the handler
  // still requires an access token (`token_use`), which the gateway does not.
  const authorizer = new HttpJwtAuthorizer('SummaryJwtAuthorizer', issuerUrl, {
    jwtAudience: audience,
  });

  const integration = new HttpLambdaIntegration('SummaryLambdaIntegration', handler, {
    payloadFormatVersion: PayloadFormatVersion.VERSION_2_0,
    // Above the function's 28 s, so the handler's own deadline wins.
    timeout: INTEGRATION_TIMEOUT,
  });

  const api = new HttpApi(stack, 'SummaryHttpApi', {
    apiName: 'noteflow-summary',
    description: 'NoteFlow Summary Cloud API (Phase 2).',
    corsPreflight: {
      allowOrigins: allowedOrigins,
      allowMethods: [CorsHttpMethod.POST, CorsHttpMethod.OPTIONS],
      allowHeaders: SUMMARY_REQUEST_HEADERS,
      exposeHeaders: SUMMARY_EXPOSED_HEADERS,
      // A bearer token is not a cookie, so credentialed cross-site requests are
      // unnecessary and a wildcard origin stays safe.
      allowCredentials: false,
      maxAge: Duration.hours(1),
    },
  });

  // No default authorizer and no default route: every request to this route is
  // authorized before the Lambda runs.
  const [route] = api.addRoutes({ path: SUMMARY_PATH, methods: [HttpMethod.POST], integration, authorizer });
  // CDK 2.268's L2 validates against an outdated 29s cap; HTTP APIs support 30s.
  const cfn = route.node.findChild('SummaryLambdaIntegration').node.defaultChild;
  if (!(cfn instanceof CfnIntegration)) throw new Error('Summary integration construct missing.');
  cfn.timeoutInMillis = 30_000;

  return { api, table };
};
