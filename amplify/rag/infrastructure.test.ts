import {test} from 'node:test';
import assert from 'node:assert/strict';
import {App,Stack,Aspects,CfnResource,RemovalPolicy} from 'aws-cdk-lib';
import {Template} from 'aws-cdk-lib/assertions';
import {Table,AttributeType,StreamViewType} from 'aws-cdk-lib/aws-dynamodb';
import {mkdtempSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createRagInfrastructure,ragSecretParameterArns,readRagPilotScope,resolveRagSecrets} from './infrastructure';

test('Phase3 resources are private, retained, disabled and query role cannot mutate canonical notes',()=>{
  const app=new App({outdir:mkdtempSync(join(tmpdir(),'rag-synth-'))});
  const stack=new Stack(app,'Test',{env:{account:'864946423771',region:'ap-southeast-1'}});
  const notes=new Table(stack,'ExistingNotes',{partitionKey:{name:'ownerId',type:AttributeType.STRING},
    sortKey:{name:'noteId',type:AttributeType.STRING},stream:StreamViewType.NEW_IMAGE});
  // Model the actual inherited Amplify sandbox aspect, which runs after construction.
  Aspects.of(stack).add({visit(node){if(CfnResource.isCfnResource(node))node.applyRemovalPolicy(RemovalPolicy.DESTROY);}});
  createRagInfrastructure(stack,notes);
  const template=Template.fromStack(stack);
  template.hasResourceProperties('AWS::Lambda::EventSourceMapping',{Enabled:false,BatchSize:10,
    MaximumBatchingWindowInSeconds:5,ParallelizationFactor:1,MaximumRetryAttempts:2,
    MaximumRecordAgeInSeconds:3600,StartingPosition:'TRIM_HORIZON',FunctionResponseTypes:['ReportBatchItemFailures']});
  template.hasResourceProperties('AWS::Lambda::Function',{MemorySize:512,Timeout:120,ReservedConcurrentExecutions:1});
  template.hasResourceProperties('AWS::S3Vectors::Index',{IndexName:'rag-v1',Dimension:1024,DistanceMetric:'cosine',DataType:'float32'});
  template.hasResourceProperties('AWS::S3Vectors::Index',{IndexName:'rag-eg2-q8-768-v1',Dimension:768,DistanceMetric:'cosine',DataType:'float32'});
  template.hasResourceProperties('AWS::S3::Bucket',{LifecycleConfiguration:{Rules:[{ExpirationInDays:7,Status:'Enabled'}]}});
  const resources=template.toJSON().Resources;
  const stream = Object.entries(resources).find(([id]) => id.startsWith('RagNoteStream'))![1] as any;
  assert.ok(stream.DependsOn.some((id: string) => id.startsWith('RagWorkerServiceRoleDefaultPolicy')));
  const probePolicies=Object.entries(resources).filter(([id])=>id.startsWith('RagRetrievalProbe')&&id.includes('DefaultPolicy'));
  assert.equal(probePolicies.length,1);
  const statements=(probePolicies[0][1] as any).Properties.PolicyDocument.Statement;
  const actions=statements.flatMap((s:any)=>[s.Action].flat());
  for(const denied of ['dynamodb:PutItem','dynamodb:DeleteItem','dynamodb:ConditionCheckItem',
    's3:PutObject','s3:DeleteObject','s3:ListBucket','s3vectors:PutVectors','s3vectors:DeleteVectors'])
    assert.ok(!actions.includes(denied),denied);
  const workerPolicy = Object.entries(resources).find(([id]) => id.startsWith('RagWorkerServiceRoleDefaultPolicy'))![1] as any;
  const failureWrite = workerPolicy.Properties.PolicyDocument.Statement.find((s: any) => s.Action === 's3:PutObject');
  assert.ok(failureWrite);
  assert.deepEqual(failureWrite.Condition, { StringEquals: { 's3:ResourceAccount': '864946423771' } });
  assert.equal(failureWrite.Resource['Fn::Join'][1].at(-1), '/*');
  const update=statements.find((s:any)=>[s.Action].flat().includes('dynamodb:UpdateItem'));
  assert.deepEqual(update.Condition,{'ForAllValues:StringEquals':{'dynamodb:LeadingKeys':['BUDGET#SMOKE']},
    Null:{'dynamodb:LeadingKeys':'false'}});
  assert.equal(Object.keys(template.findResources('AWS::Lambda::Permission')).length,0);
  for(const [id,resource] of Object.entries(resources) as [string,any][])
    if(/^(RagState|RagSnapshots|RagFailures|RagVectors|RagVectorIndex|RagEmbeddingGemmaVectorIndex)/.test(id)
      &&['AWS::DynamoDB::Table','AWS::S3::Bucket','AWS::S3Vectors::VectorBucket','AWS::S3Vectors::Index'].includes(resource.Type))
      assert.equal(resource.DeletionPolicy,'Retain',id);
});

const PILOT_OWNER='993a958c-1051-70fe-41b4-f5c997da1652';
// The one reviewed six-note pilot: five synthetic notes plus the one exact reviewed existing note.
const REVIEWED_EXISTING_NOTE='note-1791284611425000-3';
const PILOT_NOTES=['p5-hs','p5-cost','p5-iris','p5-truc-a','p5-truc-b',REVIEWED_EXISTING_NOTE];
const pilotScope=()=>readRagPilotScope({owners:[{ownerId:PILOT_OWNER,noteIds:PILOT_NOTES}]});
const dynamicScope=(streamEnabled?:boolean)=>{
  const scope=readRagPilotScope({kind:'eligible-own-notes.v1',
    owners:[{ownerId:PILOT_OWNER,noteIds:[]}],...(streamEnabled===undefined?{}:{streamEnabled})});
  if(scope.kind!=='eligible-own-notes.v1')throw Error('expected dynamic RAG pilot scope');
  return scope;
};
const pick=(resources:Record<string,any>,predicate:(id:string)=>boolean):any=>{
  const key=Object.keys(resources).find(predicate);
  assert.ok(key,'resource match');
  return resources[key!];
};
const eventMapping=(resources:Record<string,any>)=>pick(resources,id=>id.startsWith('RagNoteStream'));
const workerFunction=(resources:Record<string,any>)=>pick(resources,id=>
  id.startsWith('RagWorker')&&!id.includes('Logs')&&!id.includes('ServiceRole'));

test('pilot scope preserves every stable resource id, keeps mapping disabled and pins exact owner/note filters',()=>{
  const app=new App({outdir:mkdtempSync(join(tmpdir(),'rag-pilot-synth-'))});
  const stack=new Stack(app,'Test',{env:{account:'864946423771',region:'ap-southeast-1'}});
  const notes=new Table(stack,'ExistingNotes',{partitionKey:{name:'ownerId',type:AttributeType.STRING},
    sortKey:{name:'noteId',type:AttributeType.STRING},stream:StreamViewType.NEW_IMAGE});
  createRagInfrastructure(stack,notes,pilotScope());
  const resources=Template.fromStack(stack).toJSON().Resources as Record<string,any>;
  for(const id of ['RagState','RagSnapshots','RagFailures','RagVectors','RagVectorIndex',
    'RagEmbeddingGemmaVectorIndex','RagWorker','RagRetrievalProbe','RagNoteStream'])
    assert.ok(Object.keys(resources).some(key=>key.startsWith(id)),id);
  const mapping=eventMapping(resources);
  assert.equal(mapping.Properties.Enabled,false);
  assert.equal(mapping.Properties.FilterCriteria.Filters.length,1);
  const pattern=JSON.parse(mapping.Properties.FilterCriteria.Filters[0].Pattern);
  assert.deepEqual(pattern.eventName,['INSERT','MODIFY','REMOVE']);
  assert.deepEqual(pattern.dynamodb.Keys.ownerId.S,[`OWNER#${PILOT_OWNER}`]);
  const noteFilters:unknown[]=pattern.dynamodb.Keys.noteId.S;
  // Exactly the six reviewed notes in both canonical and protection form, plus the one consent row.
  assert.equal(PILOT_NOTES.length,6);
  assert.equal(noteFilters.length,PILOT_NOTES.length*2+1);
  assert.deepEqual(noteFilters,[
    ...PILOT_NOTES.map(id=>`NOTE#${id}`),...PILOT_NOTES.map(id=>`PROTECTION#${id}`),'RAG#CONSENT']);
  assert.ok(noteFilters.includes(`NOTE#${REVIEWED_EXISTING_NOTE}`),'reviewed existing note admitted');
  assert.ok(noteFilters.includes('RAG#CONSENT'),'consent row admitted');
  // Every entry stays an exact sort key, so no unreviewed note can slip in through a prefix.
  assert.ok(noteFilters.every(entry=>typeof entry==='string'),'no prefix fallback');
  assert.ok(!JSON.stringify(pattern).includes('"prefix"'),'no beginsWith fallback');
  for(const unrelated of ['NOTE#note-1791284611425000-4','PROTECTION#note-1791284611425000-4',
    'NOTE#p5-unreviewed','PROTECTION#p5-unreviewed','NOTE#p5-hs-extra','RAG#SMOKE','RAG#CONSENT#x'])
    assert.ok(!noteFilters.includes(unrelated),unrelated);
  const worker=workerFunction(resources);
  assert.equal(worker.Properties.Environment.Variables.RAG_PILOT_PHASE5,'synthetic-only');
  // The worker/probe point at the additive 768 index, never the retained 1024 one.
  const active=Object.entries(resources).find(([,resource]:[string,any])=>
    resource.Type==='AWS::S3Vectors::Index'&&resource.Properties.IndexName==='rag-eg2-q8-768-v1');
  assert.ok(active,'active EmbeddingGemma index exists');
  assert.deepEqual(worker.Properties.Environment.Variables.RAG_VECTOR_INDEX_ARN,
    {'Fn::GetAtt':[active![0],'IndexArn']});
});

test('dynamic eligible-own-notes scope keeps the exact owner and only NOTE/PROTECTION/RAG#CONSENT filters',()=>{
  assert.equal(dynamicScope().kind,'eligible-own-notes.v1');
  assert.equal(dynamicScope().streamEnabled,false,'dynamic stream default is false');
  const app=new App({outdir:mkdtempSync(join(tmpdir(),'rag-dynamic-synth-'))});
  const stack=new Stack(app,'Test',{env:{account:'864946423771',region:'ap-southeast-1'}});
  const notes=new Table(stack,'ExistingNotes',{partitionKey:{name:'ownerId',type:AttributeType.STRING},
    sortKey:{name:'noteId',type:AttributeType.STRING},stream:StreamViewType.NEW_IMAGE});
  createRagInfrastructure(stack,notes,dynamicScope());
  const resources=Template.fromStack(stack).toJSON().Resources as Record<string,any>;
  const mapping=eventMapping(resources);
  assert.equal(mapping.Properties.Enabled,false,'first dynamic deploy stays disabled');
  assert.equal(mapping.Properties.FilterCriteria.Filters.length,1);
  const pattern=JSON.parse(mapping.Properties.FilterCriteria.Filters[0].Pattern);
  assert.deepEqual(pattern.eventName,['INSERT','MODIFY','REMOVE']);
  assert.deepEqual(pattern.dynamodb.Keys.ownerId.S,[`OWNER#${PILOT_OWNER}`]);
  assert.deepEqual(pattern.dynamodb.Keys.noteId.S,
    [{prefix:'NOTE#'},{prefix:'PROTECTION#'},'RAG#CONSENT']);
  assert.ok(!JSON.stringify(pattern).includes('rag-smoke-'),'no legacy wildcard owner');
  assert.ok(!JSON.stringify(pattern).includes('RAG#SMOKE'),'no other RAG row pattern');
  assert.ok(!JSON.stringify(pattern).includes('"prefix":"RAG#'),'no RAG prefix');
  assert.ok(!JSON.stringify(pattern).includes(REVIEWED_EXISTING_NOTE),'no frozen note id');
  assert.equal(workerFunction(resources).Properties.Environment.Variables.RAG_PILOT_PHASE5,'synthetic-only');
  // The existing private failure bucket and its 7-day retention are unchanged in dynamic mode.
  templateHasRetainedFailures(Template.fromStack(stack));
});

const templateHasRetainedFailures=(template:Template):void=>{
  template.hasResourceProperties('AWS::S3::Bucket',{LifecycleConfiguration:{Rules:[{ExpirationInDays:7,Status:'Enabled'}]}});
};

test('dynamic streamEnabled true enables the mapping without widening filters, owner or index ARN',()=>{
  assert.equal(dynamicScope(true).streamEnabled,true);
  const app=new App({outdir:mkdtempSync(join(tmpdir(),'rag-dynamic-stream-synth-'))});
  const stack=new Stack(app,'Test',{env:{account:'864946423771',region:'ap-southeast-1'}});
  const notes=new Table(stack,'ExistingNotes',{partitionKey:{name:'ownerId',type:AttributeType.STRING},
    sortKey:{name:'noteId',type:AttributeType.STRING},stream:StreamViewType.NEW_IMAGE});
  createRagInfrastructure(stack,notes,dynamicScope(true));
  const resources=Template.fromStack(stack).toJSON().Resources as Record<string,any>;
  const mapping=eventMapping(resources);
  assert.equal(mapping.Properties.Enabled,true);
  assert.equal(mapping.Properties.FilterCriteria.Filters.length,1);
  const pattern=JSON.parse(mapping.Properties.FilterCriteria.Filters[0].Pattern);
  assert.deepEqual(pattern.dynamodb.Keys.ownerId.S,[`OWNER#${PILOT_OWNER}`]);
  assert.deepEqual(pattern.dynamodb.Keys.noteId.S,
    [{prefix:'NOTE#'},{prefix:'PROTECTION#'},'RAG#CONSENT']);
  assert.ok(!JSON.stringify(pattern).includes(REVIEWED_EXISTING_NOTE),'no frozen note id');
  assert.ok(!JSON.stringify(pattern).includes('rag-smoke-'),'no legacy wildcard owner');
  const worker=workerFunction(resources);
  assert.equal(worker.Properties.Environment.Variables.RAG_PILOT_PHASE5,'synthetic-only');
  const active=Object.entries(resources).find(([,resource]:[string,any])=>
    resource.Type==='AWS::S3Vectors::Index'&&resource.Properties.IndexName==='rag-eg2-q8-768-v1');
  assert.ok(active,'active EmbeddingGemma index exists');
  assert.deepEqual(worker.Properties.Environment.Variables.RAG_VECTOR_INDEX_ARN,
    {'Fn::GetAtt':[active![0],'IndexArn']});
  templateHasRetainedFailures(Template.fromStack(stack));
});

test('dynamic scope parsing refuses mixed note ids, unknown kinds and malformed owners',()=>{
  assert.equal(readRagPilotScope({kind:'eligible-own-notes.v1',owners:[
    {ownerId:PILOT_OWNER,noteIds:[]}]}).owners[0].noteIds.length,0);
  assert.equal(dynamicScope(true).streamEnabled,true);
  assert.equal(dynamicScope(false).streamEnabled,false);
  assert.throws(()=>readRagPilotScope({kind:'eligible-own-notes.v1',owners:[
    {ownerId:PILOT_OWNER,noteIds:[]}],streamEnabled:'true'}),/boolean/);
  assert.throws(()=>readRagPilotScope({kind:'eligible-own-notes.v1',owners:[
    {ownerId:PILOT_OWNER,noteIds:[]}],streamEnabled:1}),/boolean/);
  assert.throws(()=>readRagPilotScope({kind:'eligible-own-notes.v1',owners:[
    {ownerId:PILOT_OWNER,noteIds:[]}],streamEnabled:undefined}),/boolean/);
  assert.throws(()=>readRagPilotScope({kind:'eligible-own-notes.v1',owners:[
    {ownerId:PILOT_OWNER,noteIds:['p5-hs']}]}),/empty/);
  assert.throws(()=>readRagPilotScope({kind:'reviewed-pilot',owners:[
    {ownerId:PILOT_OWNER,noteIds:[]}]}),/note id|one to five|exact|kind/);
  assert.throws(()=>readRagPilotScope({kind:'eligible-own-notes.v2',owners:[
    {ownerId:PILOT_OWNER,noteIds:[]}]}),/kind/);
  assert.throws(()=>readRagPilotScope({kind:'eligible-own-notes.v1',owners:[
    {ownerId:PILOT_OWNER,noteIds:[],caseHash:null}]}),/exact ownerId/);
  assert.throws(()=>readRagPilotScope({kind:'eligible-own-notes.v1',owners:[
    {ownerId:PILOT_OWNER,noteIds:[]},{ownerId:PILOT_OWNER,noteIds:[]}]}),/unique/);
  assert.throws(()=>readRagPilotScope({kind:'eligible-own-notes.v1',owners:[
    {ownerId:'NOT-A-SUB',noteIds:[]}]}),/Cognito sub/);
});

test('reviewed and legacy scopes never accept a streamEnabled key',()=>{
  assert.throws(()=>readRagPilotScope({owners:[
    {ownerId:PILOT_OWNER,noteIds:PILOT_NOTES}],streamEnabled:true}),/exact/);
  assert.throws(()=>readRagPilotScope({kind:'reviewed-pilot',owners:[
    {ownerId:PILOT_OWNER,noteIds:PILOT_NOTES}],streamEnabled:true}),/exact/);
  assert.throws(()=>readRagPilotScope({kind:'reviewed-pilot',owners:[
    {ownerId:PILOT_OWNER,noteIds:PILOT_NOTES}],streamEnabled:false}),/exact/);
});

test('secret ARNs are the exact two branch parameters for this account and region',()=>{
  const app=new App({outdir:mkdtempSync(join(tmpdir(),'rag-secret-arn-'))});
  const stack=new Stack(app,'Test',{env:{account:'864946423771',region:'ap-southeast-1'}});
  // The deployed sandbox identity named by the operator; the path must not include /shared/.
  const backend={type:'sandbox',namespace:'note_ai_app',name:'noteflow-smoke'} as const;
  const prefix='arn:aws:ssm:ap-southeast-1:864946423771:parameter/amplify/noteaiapp/noteflowsmoke-sandbox-98162ed7f2';
  assert.deepEqual(ragSecretParameterArns(stack,backend),[
    `${prefix}/CLOUDFLARE_ACCESS_CLIENT_ID`,
    `${prefix}/CLOUDFLARE_ACCESS_CLIENT_SECRET`,
  ]);
});

test('worker and probe receive Amplify-resolved Cloudflare secrets, never template literals',()=>{
  const app=new App({outdir:mkdtempSync(join(tmpdir(),'rag-secret-synth-')),context:{
    'amplify-backend-namespace':'noteaiapp',
    'amplify-backend-name':'noteflowsmoke-sandbox-test',
    'amplify-backend-type':'sandbox',
  }});
  const stack=new Stack(app,'Test',{env:{account:'864946423771',region:'ap-southeast-1'}});
  const notes=new Table(stack,'ExistingNotes',{partitionKey:{name:'ownerId',type:AttributeType.STRING},
    sortKey:{name:'noteId',type:AttributeType.STRING},stream:StreamViewType.NEW_IMAGE});
  createRagInfrastructure(stack,notes,undefined,resolveRagSecrets(stack));
  const resources=Template.fromStack(stack).toJSON().Resources as Record<string,any>;
  const fetcher=Object.entries(resources).find(([,resource]:[string,any])=>
    resource.Type==='Custom::AmplifySecretFetcherResource');
  assert.ok(fetcher,'Amplify secret fetcher custom resource');
  const worker=workerFunction(resources);
  for(const name of ['CLOUDFLARE_ACCESS_CLIENT_ID','CLOUDFLARE_ACCESS_CLIENT_SECRET']){
    const value=worker.Properties.Environment.Variables[name];
    assert.equal(typeof value,'object',`${name} is a deploy-time reference`);
    assert.deepEqual(value['Fn::GetAtt'],[fetcher![0],name]);
  }
  // The two values are never written as plaintext anywhere in the synthesized template.
  assert.ok(!JSON.stringify(resources).includes('cloudflare-access-value'));
  // The RAG-only fetcher's provider role may read exactly the two branch parameters, pinned to
  // this stack's account/region; Amplify's stock wildcard + shared-prefix grant must be gone.
  const sanitize=(value:string)=>value.replace(/[^A-Za-z0-9]/g,'');
  const bindingHash=createHash('sha512').update('noteaiapp').update('noteflowsmoke-sandbox-test')
    .digest('hex').slice(0,10);
  const branchPrefix=`/amplify/${sanitize('noteaiapp')}/${sanitize('noteflowsmoke-sandbox-test')}-sandbox-${bindingHash}`;
  const expectedResources=[
    `arn:aws:ssm:ap-southeast-1:864946423771:parameter${branchPrefix}/CLOUDFLARE_ACCESS_CLIENT_ID`,
    `arn:aws:ssm:ap-southeast-1:864946423771:parameter${branchPrefix}/CLOUDFLARE_ACCESS_CLIENT_SECRET`,
  ];
  const ssmStatements=Object.values(resources)
    .filter((resource:any)=>resource.Type==='AWS::IAM::Policy')
    .flatMap((resource:any)=>resource.Properties.PolicyDocument.Statement as any[])
    .filter((statement:any)=>[statement.Action].flat().includes('ssm:GetParameter'));
  assert.deepEqual(ssmStatements,[{
    Effect:'Allow',Action:'ssm:GetParameter',Resource:expectedResources,
  }]);
  const serializedResources=JSON.stringify(resources);
  assert.ok(!serializedResources.includes('arn:aws:ssm:*:*:parameter'),'no wildcard account/region');
  assert.ok(!serializedResources.includes('/shared/'),'no shared-namespace parameter');
  const invalidApp=new App({outdir:mkdtempSync(join(tmpdir(),'rag-secret-invalid-'))});
  const invalidStack=new Stack(invalidApp,'Test',{env:{account:'864946423771',region:'ap-southeast-1'}});
  const invalidNotes=new Table(invalidStack,'ExistingNotes',{partitionKey:{name:'ownerId',type:AttributeType.STRING},
    sortKey:{name:'noteId',type:AttributeType.STRING},stream:StreamViewType.NEW_IMAGE});
  assert.throws(()=>createRagInfrastructure(invalidStack,invalidNotes,undefined,
    {CLOUDFLARE_ACCESS_CLIENT_ID:'x'} as never),/two named|runtime values/);
});

test('absent pilot scope keeps the exact legacy smoke filter and no pilot worker mode',()=>{
  const app=new App({outdir:mkdtempSync(join(tmpdir(),'rag-legacy-synth-'))});
  const stack=new Stack(app,'Test',{env:{account:'864946423771',region:'ap-southeast-1'}});
  const notes=new Table(stack,'ExistingNotes',{partitionKey:{name:'ownerId',type:AttributeType.STRING},
    sortKey:{name:'noteId',type:AttributeType.STRING},stream:StreamViewType.NEW_IMAGE});
  createRagInfrastructure(stack,notes);
  const resources=Template.fromStack(stack).toJSON().Resources as Record<string,any>;
  const mapping=eventMapping(resources);
  assert.equal(mapping.Properties.Enabled,false);
  assert.equal(mapping.Properties.FilterCriteria.Filters.length,1);
  const pattern=JSON.parse(mapping.Properties.FilterCriteria.Filters[0].Pattern);
  assert.deepEqual(pattern.dynamodb.Keys.ownerId.S,[{prefix:'OWNER#rag-smoke-'}]);
  assert.deepEqual(pattern.dynamodb.Keys.noteId.S,[{prefix:'NOTE#'},{prefix:'PROTECTION#'},'RAG#CONSENT']);
  assert.equal(workerFunction(resources).Properties.Environment.Variables.RAG_PILOT_PHASE5,undefined);
});

test('pilot scope fails closed on an empty, over-cap, malformed or duplicate owner set',()=>{
  assert.throws(()=>readRagPilotScope({owners:[]}),/one to five/);
  assert.throws(()=>readRagPilotScope({owners:[{ownerId:'NOT-A-SUB',noteIds:['p5-hs']}]}),/Cognito sub/);
  assert.throws(()=>readRagPilotScope({owners:[{ownerId:PILOT_OWNER,noteIds:[]}]}),/note id/);
  assert.throws(()=>readRagPilotScope({owners:[{ownerId:PILOT_OWNER,noteIds:['p5-hs','p5-hs']}]}),/unique/);
  assert.throws(()=>readRagPilotScope({owners:[
    {ownerId:PILOT_OWNER,noteIds:['p5-hs']},{ownerId:PILOT_OWNER,noteIds:['p5-cost']}]}),/unique/);
  const overCap=Array.from({length:6},(_,index)=>({ownerId:`00000000-0000-4000-8000-00000000000${index}`,noteIds:['p5-hs']}));
  assert.throws(()=>readRagPilotScope({owners:overCap}),/one to five/);
});
