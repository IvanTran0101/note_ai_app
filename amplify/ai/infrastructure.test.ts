/**
 * Focused CDK assertions for the Summary Cloud infrastructure in
 * `infrastructure.ts`.
 *
 * A dummy Lambda with inline code stands in for the managed function, so the
 * stack synthesizes purely offline: no Amplify sandbox, no deployment, no
 * network, no provider key. The checks read the synthesized CloudFormation
 * template, which is what the placement and permission decisions actually
 * produce.
 *
 * Run with `npx tsx amplify/ai/infrastructure.test.ts` after the staged files
 * are copied into the project, where the CDK dependencies resolve.
 */
import { App, Duration, Stack } from 'aws-cdk-lib';
import { Match, Template } from 'aws-cdk-lib/assertions';
import { Code, Function as LambdaFunction, Runtime } from 'aws-cdk-lib/aws-lambda';

import { createNotesTable } from '../sync/notes_table';
import { createSummaryInfrastructure } from './infrastructure';

const ISSUER = 'https://cognito-idp.us-east-1.amazonaws.com/us-east-1_test';
const AUDIENCE = ['test-app-client-id'];

type IamStatement = Record<string, unknown>;

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
    throw new Error(`${label}: expected true`);
  }
};

const dummyHandler = (stack: Stack): LambdaFunction =>
  new LambdaFunction(stack, 'SummaryHandler', {
    runtime: Runtime.NODEJS_22_X,
    handler: 'index.handler',
    timeout: Duration.seconds(28),
    code: Code.fromInline('exports.handler = async () => ({ statusCode: 200, body: "{}" });'),
  });

const buildStack = (allowedOrigins?: string[]) => {
  const app = new App();
  const stack = new Stack(app, 'SummaryInfraTestStack');
  const handler = dummyHandler(stack);
  const result = createSummaryInfrastructure({
    handler,
    notesTable: createNotesTable(stack),
    issuerUrl: ISSUER,
    audience: AUDIENCE,
    ...(allowedOrigins === undefined ? {} : { allowedOrigins }),
  });
  return { stack, handler, result, template: Template.fromStack(stack) };
};

/** Every statement of every inline IAM policy in the template. */
const statementsOf = (template: Template): IamStatement[] => {
  const statements: IamStatement[] = [];
  for (const policy of Object.values(template.findResources('AWS::IAM::Policy'))) {
    const document = (policy as { Properties?: { PolicyDocument?: { Statement?: unknown; }; }; })
      .Properties?.PolicyDocument;
    const documentStatements = Array.isArray(document?.Statement) ? document.Statement : [];
    for (const statement of documentStatements) {
      if (typeof statement === 'object' && statement !== null) {
        statements.push(statement as IamStatement);
      }
    }
  }
  return statements;
};

const actionsOf = (statement: IamStatement): string[] => {
  const action = statement.Action;
  const list = Array.isArray(action) ? action : [action];
  return list.filter((value): value is string => typeof value === 'string');
};

const main = (): void => {
  const { stack, result, template } = buildStack();

  check('the API serves one protected POST /ai/summary route', () => {
    template.resourceCountIs('AWS::ApiGatewayV2::Route', 1);
    template.hasResourceProperties('AWS::ApiGatewayV2::Route', {
      RouteKey: 'POST /ai/summary',
      AuthorizationType: 'JWT',
      AuthorizerId: Match.anyValue(),
    });
    template.resourceCountIs('AWS::ApiGatewayV2::Authorizer', 1);
    template.hasResourceProperties('AWS::ApiGatewayV2::Authorizer', {
      AuthorizerType: 'JWT',
      JwtConfiguration: { Audience: AUDIENCE, Issuer: ISSUER },
    });
  });

  check('the integration is payload 2.0 at 30 s, above the 28 s function timeout', () => {
    // Scoped L1 override preserves the approved HTTP API 30s limit despite the L2 cap.
    template.hasResourceProperties('AWS::ApiGatewayV2::Integration', {
      IntegrationType: 'AWS_PROXY',
      PayloadFormatVersion: '2.0',
      TimeoutInMillis: 30_000,
    });
    template.hasResourceProperties('AWS::Lambda::Function', {
      Runtime: 'nodejs22.x',
      Handler: 'index.handler',
      Timeout: 28,
    });
  });

  check('CORS allows POST/OPTIONS with the client headers and exposes Retry-After', () => {
    template.hasResourceProperties('AWS::ApiGatewayV2::Api', {
      ProtocolType: 'HTTP',
      CorsConfiguration: {
        AllowOrigins: ['*'],
        AllowMethods: ['POST', 'OPTIONS'],
        AllowHeaders: ['authorization', 'content-type', 'x-note-unlock-grant'],
        ExposeHeaders: ['retry-after'],
        AllowCredentials: false,
        MaxAge: 3600,
      },
    });
  });

  check('the quota table is on-demand, accountWindow-keyed, TTL-bounded, and torn down', () => {
    template.resourceCountIs('AWS::DynamoDB::Table', 2);
    template.hasResourceProperties('AWS::DynamoDB::Table', {
      BillingMode: 'PAY_PER_REQUEST',
      KeySchema: [{ AttributeName: 'accountWindow', KeyType: 'HASH' }],
      AttributeDefinitions: [{ AttributeName: 'accountWindow', AttributeType: 'S' }],
      TimeToLiveSpecification: { AttributeName: 'expiresAt', Enabled: true },
    });
    template.hasResource('AWS::DynamoDB::Table', {
      DeletionPolicy: 'Delete',
      UpdateReplacePolicy: 'Delete',
      Properties: Match.anyValue(),
    });
  });

  check('the function gets the table name and only UpdateItem on the quota table', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      Environment: { Variables: Match.objectLike({ SUMMARY_QUOTA_TABLE_NAME: Match.anyValue() }) },
    });

    const dynamoStatements = statementsOf(template).filter((statement) =>
      actionsOf(statement).some((action) => action.startsWith('dynamodb:')),
    );
    assertEqual(dynamoStatements.length, 2, 'separate quota and canonical authority policies');
    const canonical = dynamoStatements.find(s => !actionsOf(s).includes('dynamodb:UpdateItem'))!;
    assertEqual(JSON.stringify(actionsOf(canonical)), JSON.stringify(['dynamodb:GetItem', 'dynamodb:PutItem', 'dynamodb:ConditionCheckItem']), 'canonical read/run/condition only');
    const dynamoStatement = dynamoStatements.find(s => actionsOf(s).includes('dynamodb:UpdateItem')); 
    if (dynamoStatement === undefined) {
      throw new Error('expected the DynamoDB statement');
    }
    assertEqual(JSON.stringify(actionsOf(dynamoStatement)), JSON.stringify(['dynamodb:UpdateItem']), 'actions');
    assertTrue(
      JSON.stringify(dynamoStatement.Resource).includes('SummaryQuotaTable'),
      'the statement is scoped to the quota table arn',
    );

    const allActions = statementsOf(template).flatMap(actionsOf);
    assertTrue(
      !allActions.some((action) => action.startsWith('dynamodb:') && !['dynamodb:UpdateItem', 'dynamodb:GetItem', 'dynamodb:PutItem', 'dynamodb:ConditionCheckItem'].includes(action)),
      'quota plus scoped canonical run authority; no Query/Scan or table administration',
    );
    assertTrue(
      !JSON.stringify(template.toJSON()).includes('DEEPSEEK'),
      'no provider key name or value is declared here',
    );
  });

  check('the table and API are created in the handler stack, not a second stack', () => {
    assertTrue(Stack.of(result.api) === stack, 'api shares the handler stack');
    assertTrue(Stack.of(result.table) === stack, 'table shares the handler stack');
    assertEqual(Stack.of(result.api).stackName, 'SummaryInfraTestStack', 'stack identity');
    template.resourceCountIs('AWS::ApiGatewayV2::Api', 1);
  });

  check('allowedOrigins is honored and an empty audience is refused', () => {
    const custom = buildStack(['https://app.example']);
    custom.template.hasResourceProperties('AWS::ApiGatewayV2::Api', {
      CorsConfiguration: Match.objectLike({ AllowOrigins: ['https://app.example'] }),
    });

    const app = new App();
    const stack = new Stack(app, 'AudienceStack');
    let thrown: unknown;
    try {
      createSummaryInfrastructure({
        handler: dummyHandler(stack), notesTable: createNotesTable(stack),
        issuerUrl: ISSUER,
        audience: [],
      });
    } catch (error) {
      thrown = error;
    }
    assertTrue(thrown instanceof Error, 'an empty audience throws');
    assertTrue(
      thrown instanceof Error && thrown.message.includes('audience'),
      'the failure names the missing audience',
    );
  });
};

main();
console.log(`${passed} Summary infrastructure checks passed`);
