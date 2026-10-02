import { Duration, Stack } from 'aws-cdk-lib';
import { CfnApi, CfnChannelNamespace } from 'aws-cdk-lib/aws-appsync';
import type { Table } from 'aws-cdk-lib/aws-dynamodb';
import { Rule, Schedule } from 'aws-cdk-lib/aws-events';
import { LambdaFunction } from 'aws-cdk-lib/aws-events-targets';
import { PolicyStatement } from 'aws-cdk-lib/aws-iam';
import { FilterCriteria, FilterRule, Runtime, StartingPosition } from 'aws-cdk-lib/aws-lambda';
import { DynamoEventSource } from 'aws-cdk-lib/aws-lambda-event-sources';
import { NodejsFunction } from 'aws-cdk-lib/aws-lambda-nodejs';
import { fileURLToPath } from 'node:url';

export const CHANNEL_HANDLER = `import { util } from '@aws-appsync/utils';
export function onSubscribe(ctx) {
  if (!ctx.identity || !ctx.identity.sub || ctx.info.channel.path !== '/notes/' + ctx.identity.sub) {
    util.unauthorized();
  }
}`;
export function createRealtimeInfrastructure(scope: Stack, table: Table, pool: string, client: string) {
  const cognito = 'AMAZON_COGNITO_USER_POOLS';
  const api = new CfnApi(scope, 'NoteRevisionEvents', {
    name: 'NoteFlowRevisionEvents', eventConfig: {
      authProviders: [{ authType: cognito, cognitoConfig: { userPoolId: pool,
        awsRegion: scope.region, appIdClientRegex: `^${client}$` } }, { authType: 'AWS_IAM' }],
      connectionAuthModes: [{ authType: cognito }],
      defaultSubscribeAuthModes: [{ authType: cognito }],
      defaultPublishAuthModes: [{ authType: 'AWS_IAM' }],
    },
  });
  const namespace = new CfnChannelNamespace(scope, 'NoteRevisionNamespace', {
    apiId: api.attrApiId, name: 'notes', codeHandlers: CHANNEL_HANDLER,
    publishAuthModes: [{ authType: 'AWS_IAM' }], subscribeAuthModes: [{ authType: cognito }],
  });
  const httpEndpoint = `https://${api.attrDnsHttp}/event`;
  const socketEndpoint = `wss://${api.attrDnsRealtime}/event/realtime`;
  const relay = new NodejsFunction(scope, 'NoteRevisionRelay', {
    entry: fileURLToPath(new URL('./handler.ts', import.meta.url)), handler: 'handler',
    runtime: Runtime.NODEJS_22_X, timeout: Duration.seconds(60), memorySize: 256,
    environment: { NOTES_TABLE_NAME: table.tableName, NOTES_TABLE_REGION: scope.region,
      EVENT_HTTP_ENDPOINT: httpEndpoint },
  });
  relay.addToRolePolicy(new PolicyStatement({ actions: ['dynamodb:GetItem', 'dynamodb:UpdateItem',
    'dynamodb:Query'], resources: [table.tableArn, `${table.tableArn}/index/PendingRelays`] }));
  relay.addToRolePolicy(new PolicyStatement({ actions: ['appsync:EventPublish'],
    resources: [namespace.attrChannelNamespaceArn] }));
  relay.addEventSource(new DynamoEventSource(table, {
    startingPosition: StartingPosition.TRIM_HORIZON, batchSize: 10,
    reportBatchItemFailures: true, retryAttempts: 3,
    filters: [FilterCriteria.filter({ eventName: FilterRule.isEqual('INSERT'),
      dynamodb: { Keys: { noteId: { S: FilterRule.beginsWith('EVENT#') } } } })],
  }));
  new Rule(scope, 'RecoverNoteRevisionRelays', { schedule: Schedule.rate(Duration.minutes(1)),
    targets: [new LambdaFunction(relay)] });
  return { api, namespace, relay, httpEndpoint, socketEndpoint };
}
