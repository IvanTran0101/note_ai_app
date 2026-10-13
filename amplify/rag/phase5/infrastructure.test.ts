import {test} from 'node:test';
import assert from 'node:assert/strict';
import {App,Duration,Stack} from 'aws-cdk-lib';
import {Template} from 'aws-cdk-lib/assertions';
import {AttributeType,StreamViewType,Table} from 'aws-cdk-lib/aws-dynamodb';
import {Code,Function,Runtime} from 'aws-cdk-lib/aws-lambda';
import {mkdtempSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createRagInfrastructure,readRagPilotScope} from '../infrastructure';
import {createPhase5Infrastructure} from './infrastructure';

const ACCOUNT='864946423771';
const REGION='ap-southeast-1';
const OWNER='993a958c-1051-70fe-41b4-f5c997da1652';
const ISSUER=`https://cognito-idp.${REGION}.amazonaws.com/${REGION}_TestPool`;
const AUDIENCE='note-flow-test-client';
// The one reviewed six-note pilot: five synthetic notes plus the one exact reviewed existing note.
const NOTE_IDS=['p5-hs','p5-cost','p5-iris','p5-truc-a','p5-truc-b','note-1791284611425000-3'];
const ENV={account:ACCOUNT,region:REGION};
// The consent CAS attributes plus the four physical GSI keys DynamoDB FGAC requires to be listed.
const CONSENT_ATTRIBUTES=['ownerId','noteId','accepted','version','generation','ttl','canonicalOwnerId',
  'relayQueue','relayDueAt','changeOwnerId','changeSequence'];
const CONSENT_DENIED_ATTRIBUTES=['title','content','permissions','ownerSub','noteBody','*'];

const outdir=()=>mkdtempSync(join(tmpdir(),'rag-p5-synth-'));

const managedFunction=(stack:Stack,id='ManagedRag')=>new Function(stack,id,{
  runtime:Runtime.NODEJS_22_X,code:Code.fromInline('exports.handler=()=>{}'),handler:'index.handler',
  memorySize:512,timeout:Duration.seconds(28),
});

const fixture=()=>{
  const app=new App({outdir:outdir()});
  const stack=new Stack(app,'Test',{env:ENV});
  const notes=new Table(stack,'Notes',{partitionKey:{name:'ownerId',type:AttributeType.STRING},
    sortKey:{name:'noteId',type:AttributeType.STRING},stream:StreamViewType.NEW_IMAGE});
  const state=new Table(stack,'State',{partitionKey:{name:'ownerId',type:AttributeType.STRING},
    sortKey:{name:'noteId',type:AttributeType.STRING}});
  const fn=managedFunction(stack);
  return {app,stack,notes,state,fn};
};

test('Phase5 API is JWT-only with exact routes, CORS, payload 2.0 and a 30s integration',()=>{
  const {stack,notes,state,fn}=fixture();
  createPhase5Infrastructure({handler:fn,notesTable:notes,stateTable:state,ownerIds:[OWNER],
    issuerUrl:ISSUER,audience:[AUDIENCE]});
  const template=Template.fromStack(stack);

  const routes=template.findResources('AWS::ApiGatewayV2::Route');
  assert.equal(Object.keys(routes).length,3);
  const routeKeys=Object.values(routes).map((route:any)=>route.Properties.RouteKey).sort();
  assert.deepEqual(routeKeys,['GET /ai/rag/consent','POST /ai/rag/query','PUT /ai/rag/consent']);
  for(const route of Object.values(routes) as any[]){
    assert.equal(route.Properties.AuthorizationType,'JWT',route.Properties.RouteKey);
    assert.ok(route.Properties.AuthorizerId,route.Properties.RouteKey);
    assert.notEqual(route.Properties.RouteKey,'$default');
  }

  const authorizers=template.findResources('AWS::ApiGatewayV2::Authorizer');
  assert.equal(Object.keys(authorizers).length,1);
  const authorizer=(Object.values(authorizers)[0] as any);
  assert.equal(authorizer.Properties.AuthorizerType,'JWT');
  assert.deepEqual(authorizer.Properties.JwtConfiguration,{Audience:[AUDIENCE],Issuer:ISSUER});

  const integrations=template.findResources('AWS::ApiGatewayV2::Integration');
  assert.equal(Object.keys(integrations).length,1);
  const integration=(Object.values(integrations)[0] as any);
  assert.equal(integration.Properties.PayloadFormatVersion,'2.0');
  assert.equal(integration.Properties.TimeoutInMillis,30_000);

  template.hasResourceProperties('AWS::ApiGatewayV2::Api',{CorsConfiguration:{
    AllowOrigins:['https://noteflow.trananhminh.uk','https://localhost:8782'],
    AllowMethods:['GET','PUT','POST','OPTIONS'],
    AllowHeaders:['authorization','content-type'],
    ExposeHeaders:['retry-after'],
    AllowCredentials:false,
  }});
  // No Function URL and no unauthenticated surface at all.
  assert.equal(Object.keys(template.findResources('AWS::Lambda::Url')).length,0);
});

test('Phase5 query role narrows consent/budget/config grants and adds no broad writes',()=>{
  const {stack,notes,state,fn}=fixture();
  createPhase5Infrastructure({handler:fn,notesTable:notes,stateTable:state,ownerIds:[OWNER],
    issuerUrl:ISSUER,audience:[AUDIENCE]});
  const template=Template.fromStack(stack);

  const policies=template.findResources('AWS::IAM::Policy');
  const policy=(Object.values(policies).find((candidate:any)=>
    candidate.Properties.PolicyDocument.Statement.some((s:any)=>[s.Action].flat().includes('dynamodb:ConditionCheckItem'))
  ) as any);
  assert.ok(policy,'managed RAG role policy with the Phase5 statements');
  const statements=policy.Properties.PolicyDocument.Statement as any[];

  const configCheck=statements.find((s:any)=>[s.Action].flat().includes('dynamodb:ConditionCheckItem'));
  assert.ok(configCheck,'state CONFIG#PHASE5 condition-check grant');
  assert.deepEqual([configCheck.Action].flat(),['dynamodb:ConditionCheckItem']);
  assert.deepEqual(configCheck.Condition['ForAllValues:StringEquals']['dynamodb:LeadingKeys'],['CONFIG#PHASE5']);
  assert.deepEqual(configCheck.Condition.Null,{'dynamodb:LeadingKeys':'false'});

  const consentUpdate=statements.find((s:any)=>[s.Action].flat().includes('dynamodb:UpdateItem'));
  assert.ok(consentUpdate,'canonical consent row update grant');
  assert.deepEqual([consentUpdate.Action].flat(),['dynamodb:UpdateItem']);
  assert.deepEqual(consentUpdate.Condition['ForAllValues:StringEquals']['dynamodb:LeadingKeys'],[`OWNER#${OWNER}`]);
  assert.deepEqual(consentUpdate.Condition['ForAllValues:StringEquals']['dynamodb:Attributes'],CONSENT_ATTRIBUTES);
  // Official FGAC needs the primary plus all index keys, but the whitelist must stay exactly that
  // and never grow to a note payload attribute or a wildcard.
  const consentAttributes=consentUpdate.Condition['ForAllValues:StringEquals']['dynamodb:Attributes'];
  for(const required of ['relayQueue','relayDueAt','changeOwnerId','changeSequence'])
    assert.ok(consentAttributes.includes(required),required);
  for(const denied of CONSENT_DENIED_ATTRIBUTES)
    assert.ok(!consentAttributes.includes(denied),`consent whitelist must not add ${denied}`);
  assert.equal(consentAttributes.length,CONSENT_ATTRIBUTES.length,'consent whitelist has no extra attribute');
  assert.deepEqual(consentUpdate.Condition.Null,{'dynamodb:LeadingKeys':'false','dynamodb:Attributes':'false'});

  const budget=statements.find((s:any)=>[s.Action].flat().includes('dynamodb:PutItem'));
  assert.ok(budget,'pilot budget counter/lease grant');
  assert.deepEqual([budget.Action].flat().sort(),
    ['dynamodb:DeleteItem','dynamodb:GetItem','dynamodb:PutItem','dynamodb:UpdateItem'].sort());
  assert.deepEqual(budget.Condition['ForAllValues:StringEquals']['dynamodb:LeadingKeys'],['BUDGET#PHASE5']);
  assert.deepEqual(budget.Condition.Null,{'dynamodb:LeadingKeys':'false'});

  const actions=statements.flatMap((s:any)=>[s.Action].flat());
  for(const denied of ['dynamodb:Scan','dynamodb:TransactWriteItems','dynamodb:BatchWriteItem',
    's3:PutObject','s3:DeleteObject','s3:GetObject','s3vectors:PutVectors','s3vectors:DeleteVectors',
    'kms:Decrypt','iam:PassRole','dynamodb:DeleteTable']){
    assert.ok(!actions.includes(denied),denied);
  }
  for(const statement of statements){
    assert.ok(!JSON.stringify(statement.Resource).includes('"*"'),'wildcard resource');
  }
});

test('Phase5 API and role live with the managed function stack and synth without a cycle',()=>{
  const app=new App({outdir:outdir()});
  const notesStack=new Stack(app,'NotesStack',{env:ENV});
  const notes=new Table(notesStack,'ExistingNotes',{partitionKey:{name:'ownerId',type:AttributeType.STRING},
    sortKey:{name:'noteId',type:AttributeType.STRING},stream:StreamViewType.NEW_IMAGE});
  const rag=createRagInfrastructure(notesStack,notes,
    readRagPilotScope({owners:[{ownerId:OWNER,noteIds:NOTE_IDS}]}));
  const fnStack=new Stack(app,'ManagedFunctionStack',{env:ENV});
  const fn=managedFunction(fnStack);
  const phase5=createPhase5Infrastructure({handler:fn,notesTable:notes,stateTable:rag.state,ownerIds:[OWNER],
    issuerUrl:ISSUER,audience:[AUDIENCE]});
  assert.equal(Stack.of(phase5.api),fnStack);

  // A successful full-app synth is the no-dependency-cycle evidence: the API/role are in the
  // managed-function stack while the tables they reference stay in the notes stack.
  const assembly=app.synth();
  const fnResources=assembly.getStackArtifact(fnStack.artifactId).template.Resources ?? {};
  const notesResources=assembly.getStackArtifact(notesStack.artifactId).template.Resources ?? {};
  assert.ok(Object.values(fnResources).some((resource:any)=>resource.Type==='AWS::ApiGatewayV2::Api'));
  assert.ok(!Object.values(notesResources).some((resource:any)=>resource.Type==='AWS::ApiGatewayV2::Api'));
  assert.ok(Object.values(fnResources).some((resource:any)=>resource.Type==='AWS::IAM::Policy'));

  // The reviewed six-note scope is the exact filter that rides with the notes stack: both keys per
  // reviewed note plus the one consent row, with no prefix fallback and no unreviewed note.
  const mapping=(Object.values(notesResources) as any[]).find((resource:any)=>
    resource.Type==='AWS::Lambda::EventSourceMapping');
  assert.ok(mapping,'pilot stream mapping stays in the notes stack');
  const pattern=JSON.parse(mapping.Properties.FilterCriteria.Filters[0].Pattern);
  assert.equal(pattern.dynamodb.Keys.noteId.S.length,NOTE_IDS.length*2+1);
  assert.deepEqual(pattern.dynamodb.Keys.ownerId.S,[`OWNER#${OWNER}`]);
  assert.deepEqual(pattern.dynamodb.Keys.noteId.S,[
    ...NOTE_IDS.map(id=>`NOTE#${id}`),...NOTE_IDS.map(id=>`PROTECTION#${id}`),'RAG#CONSENT']);
});

test('Phase5 API refuses an empty audience, wildcard origin, bad owner and empty owner list',()=>{
  const attempt=(overrides:any)=>{
    const {notes,state,fn}=fixture();
    createPhase5Infrastructure({handler:fn,notesTable:notes,stateTable:state,ownerIds:[OWNER],
      issuerUrl:ISSUER,audience:[AUDIENCE],...overrides});
  };
  assert.throws(()=>attempt({audience:[]}),/audience/);
  assert.throws(()=>attempt({audience:['','x']}),/audience/);
  assert.throws(()=>attempt({allowedOrigins:['*']}),/origin/);
  assert.throws(()=>attempt({allowedOrigins:['https://evil.example']}),/origin/);
  assert.throws(()=>attempt({ownerIds:[]}),/owner/);
  assert.throws(()=>attempt({ownerIds:['993a958c-1051-70fe-41b4-f5c997da1652','NOT-A-SUB']}),/Cognito sub/);
});
