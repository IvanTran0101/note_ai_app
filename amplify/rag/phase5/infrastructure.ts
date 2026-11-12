import {Duration,Stack} from 'aws-cdk-lib';
import {
  CfnIntegration,CorsHttpMethod,HttpApi,HttpMethod,PayloadFormatVersion,
} from 'aws-cdk-lib/aws-apigatewayv2';
import {HttpJwtAuthorizer} from 'aws-cdk-lib/aws-apigatewayv2-authorizers';
import {HttpLambdaIntegration} from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import type {ITable} from 'aws-cdk-lib/aws-dynamodb';
import {PolicyStatement} from 'aws-cdk-lib/aws-iam';
import type {IFunction} from 'aws-cdk-lib/aws-lambda';
import {policy} from '../types';
import {CONSENT_PATH} from './consent_handler';
import {MAX_PILOT_OWNERS,isCognitoSub} from './pilot_policy';

/**
 * Phase 5 HTTP + query-role wiring (plan 5.1B/5.3C).
 *
 * The API and every policy are created in `Stack.of(handler)` — the stack that already owns the
 * managed RAG Lambda — never in `SyncStack`. The Lambda role references the notes/state tables
 * through normal cross-stack references, so putting the routes beside the function avoids a
 * reverse dependency (and therefore a stack cycle); the two-stack fixture test proves `app.synth`
 * still succeeds.
 *
 * Exactly three routes exist, each with the Cognito JWT authorizer: `POST` query and `GET`/`PUT`
 * consent. There is no default route, no `ANY` method, no unauthenticated route, no default
 * authorizer and no Lambda Function URL. The integration uses payload format 2.0 and the supported
 * 30s HTTP API limit, above the Lambda's own 28s timeout and the 26s in-handler request deadline.
 *
 * CORS is pinned to the reviewed web origin and the local development origin, with only the
 * methods/headers the client actually sends, `retry-after` exposed and credentials disabled.
 *
 * IAM is narrowed from the Autopilot baseline to the exact runtime needs of the query role:
 *  - `ConditionCheckItem` on the state table, only the `CONFIG#PHASE5` partition, for the consent
 *    write transaction's config guard;
 *  - `UpdateItem` on the notes table, only the approved `OWNER#<sub>` partition, constrained to the
 *    consent CAS attributes (the sort key itself cannot be constrained by IAM, so the application
 *    keeps the exact `RAG#CONSENT` guard);
 *  - `GetItem`/`PutItem`/`UpdateItem`/`DeleteItem` on the state table, only the `BUDGET#PHASE5`
 *    partition, for the pilot counters and the in-flight lease.
 * The existing private Phase 4 grants (including `BUDGET#SMOKE`/`BUDGET#PHASE4`) stay untouched.
 */

/** The exact two reviewed browser origins; a wildcard or unknown origin is refused at synth. */
export const RAG_ALLOWED_ORIGINS: readonly string[] = Object.freeze([
  'https://noteflow.trananhminh.uk',
  'https://localhost:8782',
]);
const RAG_ALLOWED_HEADERS: readonly string[] = Object.freeze(['authorization','content-type']);
const RAG_EXPOSED_HEADERS: readonly string[] = Object.freeze(['retry-after']);
/**
 * The consent CAS attributes the notes-row update reads or writes; the sort key stays app-guarded.
 * The four `PendingRelays`/`ChangesByOwnerSequence` index keys are required by official DynamoDB
 * FGAC: `dynamodb:Attributes` must name the primary and every index key the update can touch.
 */
const CONSENT_ROW_ATTRIBUTES: readonly string[] = Object.freeze([
  'ownerId','noteId','accepted','version','generation','ttl','canonicalOwnerId',
  'relayQueue','relayDueAt','changeOwnerId','changeSequence',
]);
const RAG_QUERY_PATH: string = policy.technicalDefaults.wire.route;

const isRecord=(value:unknown):value is Record<string,unknown>=>
  typeof value==='object'&&value!==null&&!Array.isArray(value);

const readAudience=(value:unknown):readonly string[]=>{
  if(!Array.isArray(value)||value.length===0||value.some(entry=>typeof entry!=='string'||entry.length===0))
    throw Error('Phase5 RAG API needs at least one Cognito app-client audience');
  return Object.freeze([...value]);
};

const readOrigins=(value:unknown):readonly string[]=>{
  if(value===undefined)return RAG_ALLOWED_ORIGINS;
  if(!Array.isArray(value)||value.length===0)
    throw Error('Phase5 RAG API needs at least one allowed origin');
  for(const origin of value){
    if(typeof origin!=='string'||!RAG_ALLOWED_ORIGINS.includes(origin))
      throw Error(`Phase5 RAG API origin is not one of the reviewed origins: ${String(origin)}`);
  }
  return Object.freeze([...new Set(value as string[])]);
};

/** IAM can only scope the partition key (`LeadingKeys`); the consent sort key stays app-guarded. */
const readOwnerKeys=(value:unknown):readonly string[]=>{
  if(!Array.isArray(value)||value.length===0||value.length>MAX_PILOT_OWNERS)
    throw Error('Phase5 RAG query role needs one to five approved owners');
  const keys=value.map(ownerId=>{
    if(!isCognitoSub(ownerId))throw Error('Phase5 RAG query role owner must be a lowercase Cognito sub');
    return `OWNER#${ownerId}`;
  });
  return Object.freeze([...new Set(keys)]);
};

export type Phase5InfrastructureProps=Readonly<{
  /** The managed RAG Lambda, e.g. `backend.ragQuery.resources.lambda`. */
  handler:IFunction;
  notesTable:ITable;
  stateTable:ITable;
  /** The approved pilot Cognito subs; the query role can update only their consent partitions. */
  ownerIds:readonly string[];
  /** User pool issuer, e.g. `https://cognito-idp.<region>.amazonaws.com/<poolId>`. */
  issuerUrl:string;
  /** App client id(s) whose access tokens are accepted. */
  audience:readonly string[];
  /** Browser origins allowed to call the API. @default the two reviewed origins */
  allowedOrigins?:readonly string[];
}>;

export type Phase5Infrastructure=Readonly<{api:HttpApi}>;

export function createPhase5Infrastructure(props:Phase5InfrastructureProps):Phase5Infrastructure{
  if(!isRecord(props))throw Error('Phase5 RAG infrastructure needs props');
  const {handler,notesTable,stateTable}=props;
  if(typeof handler?.addToRolePolicy!=='function'||!handler.node)
    throw Error('Phase5 RAG infrastructure needs a CDK Function handler');
  if(typeof props.issuerUrl!=='string'||props.issuerUrl.length===0)
    throw Error('Phase5 RAG API needs a Cognito issuer URL');
  const audience=readAudience(props.audience);
  const origins=readOrigins(props.allowedOrigins);
  const ownerKeys=readOwnerKeys(props.ownerIds);
  const stack=Stack.of(handler);

  // The authorizer validates issuer/audience/signature; the Lambda still requires token_use=access.
  const authorizer=new HttpJwtAuthorizer('RagJwtAuthorizer',props.issuerUrl,{jwtAudience:[...audience]});
  const integration=new HttpLambdaIntegration('RagLambdaIntegration',handler,{
    payloadFormatVersion:PayloadFormatVersion.VERSION_2_0,
    // CDK 2.268's L2 validates against an outdated 29s cap; HTTP APIs support 30s.
    timeout:Duration.seconds(29),
  });
  const api=new HttpApi(stack,'RagHttpApi',{
    apiName:'noteflow-rag',
    description:'NoteFlow RAG pilot API (Phase 5).',
    corsPreflight:{
      allowOrigins:[...origins],
      allowMethods:[CorsHttpMethod.GET,CorsHttpMethod.PUT,CorsHttpMethod.POST,CorsHttpMethod.OPTIONS],
      allowHeaders:[...RAG_ALLOWED_HEADERS],
      exposeHeaders:[...RAG_EXPOSED_HEADERS],
      // A bearer token is not a cookie, so credentialed cross-site requests stay unnecessary.
      allowCredentials:false,
      maxAge:Duration.hours(1),
    },
  });

  // No default authorizer and no default/ANY route: every route states its authorizer explicitly.
  const routes=[
    ...api.addRoutes({path:RAG_QUERY_PATH,methods:[HttpMethod.POST],integration,authorizer}),
    ...api.addRoutes({path:CONSENT_PATH,methods:[HttpMethod.GET,HttpMethod.PUT],integration,authorizer}),
  ];
  const cfn=routes[0].node.findChild('RagLambdaIntegration')?.node.defaultChild;
  if(!(cfn instanceof CfnIntegration))throw Error('Phase5 RAG integration construct missing.');
  cfn.timeoutInMillis=30_000;

  // Consent write transaction: the exact `CONFIG#PHASE5` config row must still match.
  handler.addToRolePolicy(new PolicyStatement({
    actions:['dynamodb:ConditionCheckItem'],
    resources:[stateTable.tableArn],
    conditions:{
      'ForAllValues:StringEquals':{'dynamodb:LeadingKeys':['CONFIG#PHASE5']},
      Null:{'dynamodb:LeadingKeys':'false'},
    },
  }));
  // Canonical consent row only: exact approved owner partition and the consent CAS attributes.
  handler.addToRolePolicy(new PolicyStatement({
    actions:['dynamodb:UpdateItem'],
    resources:[notesTable.tableArn],
    conditions:{
      'ForAllValues:StringEquals':{
        'dynamodb:LeadingKeys':[...ownerKeys],
        'dynamodb:Attributes':[...CONSENT_ROW_ATTRIBUTES],
      },
      Null:{'dynamodb:LeadingKeys':'false','dynamodb:Attributes':'false'},
    },
  }));
  // Pilot counters and lease live under the one `BUDGET#PHASE5` partition (counters + lease).
  handler.addToRolePolicy(new PolicyStatement({
    actions:['dynamodb:GetItem','dynamodb:PutItem','dynamodb:UpdateItem','dynamodb:DeleteItem'],
    resources:[stateTable.tableArn],
    conditions:{
      'ForAllValues:StringEquals':{'dynamodb:LeadingKeys':['BUDGET#PHASE5']},
      Null:{'dynamodb:LeadingKeys':'false'},
    },
  }));

  return {api};
}
