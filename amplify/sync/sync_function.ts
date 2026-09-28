import { RemovalPolicy, Stack } from 'aws-cdk-lib';
import type { ITable } from 'aws-cdk-lib/aws-dynamodb';
import { PolicyStatement } from 'aws-cdk-lib/aws-iam';
import { Runtime } from 'aws-cdk-lib/aws-lambda';
import { NodejsFunction } from 'aws-cdk-lib/aws-lambda-nodejs';
import { LogGroup, RetentionDays } from 'aws-cdk-lib/aws-logs';

/**
 * NoteFlow remote sync Lambda (M1.1 skeleton).
 *
 * Bundles `amplify/sync/handler.ts` - the transport-only handler for the routes
 * in `docs/sync_api_contract.md` - and gives it the smallest runtime surface the
 * later mutation slice needs: where the notes table lives, and item-level
 * DynamoDB access to that one table.
 *
 * `createSyncHttpApi` in `amplify/sync/http_api.ts` takes this function as its
 * `handler`; `amplify/backend.ts` owns the composition.
 */

/**
 * Absolute entry path, resolved from this file so it is found whatever
 * directory the Amplify CLI runs from. `decodeURIComponent` undoes the file-URL
 * escaping `pathname` keeps (`fileURLToPath` needs @types/node, which this
 * backend does not depend on).
 */
const HANDLER_ENTRY = decodeURIComponent(new URL('./handler.ts', import.meta.url).pathname);

export type SyncFunction = Readonly<{
  /** The bundled handler; pass it to `createSyncHttpApi({ handler })`. */
  lambda: NodejsFunction;
  /** Explicit log group, so retention is bounded and teardown removes it. */
  logGroup: LogGroup;
}>;

export const createSyncFunction = (stack: Stack, table: ITable): SyncFunction => {
  const logGroup = new LogGroup(stack, 'SyncFunctionLogGroup', {
    retention: RetentionDays.TWO_WEEKS,
    removalPolicy: RemovalPolicy.DESTROY,
  });

  const lambda = new NodejsFunction(stack, 'SyncFunction', {
    entry: HANDLER_ENTRY,
    handler: 'handler',
    runtime: Runtime.NODEJS_22_X,
    description: 'NoteFlow remote sync API handler (M1.1 skeleton).',
    // Passing the group sets the function's logging config, so Lambda writes
    // into this group instead of creating an unbounded `/aws/lambda/*` one.
    logGroup,
    environment: {
      NOTES_TABLE_NAME: table.tableName,
      // The runtime reserves AWS_REGION, so the table's region travels under an
      // app-owned name for the M1.2 DynamoDB client.
      NOTES_TABLE_REGION: stack.region,
    },
  });

  // Only the item/query/transaction actions required by the next sync slice.
  // No Scan, batch, table-admin, or cross-table permission is granted.
  lambda.addToRolePolicy(
    new PolicyStatement({
      actions: [
        'dynamodb:GetItem',
        'dynamodb:PutItem',
        'dynamodb:UpdateItem',
        'dynamodb:Query',
        'dynamodb:TransactWriteItems',
        'dynamodb:DescribeTable',
      ],
      resources: [table.tableArn, `${table.tableArn}/index/*`],
    }),
  );

  return { lambda, logGroup };
};
