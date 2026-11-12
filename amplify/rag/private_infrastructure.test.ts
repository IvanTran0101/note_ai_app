import {test} from 'node:test';
import assert from 'node:assert/strict';
import {App,Stack,Duration} from 'aws-cdk-lib';
import {Template} from 'aws-cdk-lib/assertions';
import {Table,AttributeType,StreamViewType} from 'aws-cdk-lib/aws-dynamodb';
import {Function,Runtime,Code} from 'aws-cdk-lib/aws-lambda';
import {mkdtempSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createRagInfrastructure,readRagPilotScope} from './infrastructure';
import {createPrivateRagInfrastructure} from './private_infrastructure';

test('private query has bounded concurrency/read-only source access and no public invocation surface',()=>{
 const app=new App({outdir:mkdtempSync(join(tmpdir(),'rag-phase4-synth-'))});
 const stack=new Stack(app,'Test',{env:{account:'864946423771',region:'ap-southeast-1'}});
 const notes=new Table(stack,'ExistingNotes',{partitionKey:{name:'ownerId',type:AttributeType.STRING},sortKey:{name:'noteId',type:AttributeType.STRING},stream:StreamViewType.NEW_IMAGE});
 const rag=createRagInfrastructure(stack,notes);
 const fn=new Function(stack,'PrivateQuery',{runtime:Runtime.NODEJS_22_X,code:Code.fromInline('exports.handler=()=>{}'),handler:'index.handler',memorySize:512,timeout:Duration.seconds(28)});
 createPrivateRagInfrastructure(fn,notes,rag);
 const t=Template.fromStack(stack),r=t.toJSON().Resources;
 const query=Object.entries(r).find(([id])=>id.startsWith('PrivateQuery')&&(r[id] as any).Type==='AWS::Lambda::Function')![1] as any;
 assert.equal(query.Properties.ReservedConcurrentExecutions,1);
 assert.equal(query.Properties.Environment.Variables.RAG_PRIVATE_PHASE4,'synthetic-only');
 assert.equal(query.Properties.Environment.Variables.RAG_TOKENIZER_DIR,'/opt');
 assert.equal(query.Properties.Environment.Variables.RAG_VECTOR_INDEX_ARN['Fn::GetAtt'][1],'IndexArn');
 assert.equal(query.Properties.Environment.Variables.RAG_QUERY_ADMISSION_ENABLED,'false');
 // The managed query reads the additive 768 EmbeddingGemma index, never the retained Cohere one.
 const active=Object.entries(r).find(([,resource]:[string,any])=>
   resource.Type==='AWS::S3Vectors::Index'&&resource.Properties.IndexName==='rag-eg2-q8-768-v1');
 assert.ok(active,'active EmbeddingGemma index exists');
 assert.deepEqual(query.Properties.Environment.Variables.RAG_VECTOR_INDEX_ARN,{'Fn::GetAtt':[active![0],'IndexArn']});
 const legacy=Object.entries(r).find(([,resource]:[string,any])=>
   resource.Type==='AWS::S3Vectors::Index'&&resource.Properties.IndexName==='rag-v1');
 assert.ok(legacy,'legacy Cohere index is retained');
 assert.equal((legacy![1] as any).Properties.Dimension,1024);
 assert.equal((legacy![1] as any).DeletionPolicy,'Retain');
 assert.equal(query.Properties.Layers.length,2);
 const policy=Object.entries(r).find(([id])=>id.startsWith('PrivateQuery')&&id.includes('DefaultPolicy'))![1] as any;
 const stmts=policy.Properties.PolicyDocument.Statement;
 const actions=stmts.flatMap((s:any)=>[s.Action].flat());
 assert.ok(!actions.includes('bedrock:InvokeModel'),'self-hosted embedding needs no Bedrock grant');
 for(const denied of ['dynamodb:PutItem','dynamodb:DeleteItem','dynamodb:ConditionCheckItem','s3:PutObject','s3:DeleteObject','s3vectors:PutVectors','s3vectors:DeleteVectors'])assert.ok(!actions.includes(denied),denied);
 const update=stmts.find((s:any)=>[s.Action].flat().includes('dynamodb:UpdateItem'));
 assert.deepEqual(update.Condition,{'ForAllValues:StringEquals':{'dynamodb:LeadingKeys':['BUDGET#SMOKE','BUDGET#PHASE4']},Null:{'dynamodb:LeadingKeys':'false'}});
 assert.equal(Object.keys(t.findResources('AWS::Lambda::Permission')).length,0);
 assert.equal(Object.keys(t.findResources('AWS::Lambda::Url')).length,0);
 assert.equal(Object.keys(t.findResources('AWS::ApiGatewayV2::Route')).length,0);
});

test('pilot scope keeps the private Phase4 query surface unchanged and closed',()=>{
  const app=new App({outdir:mkdtempSync(join(tmpdir(),'rag-pilot-private-synth-'))});
  const stack=new Stack(app,'Test',{env:{account:'864946423771',region:'ap-southeast-1'}});
  const notes=new Table(stack,'ExistingNotes',{partitionKey:{name:'ownerId',type:AttributeType.STRING},sortKey:{name:'noteId',type:AttributeType.STRING},stream:StreamViewType.NEW_IMAGE});
  const rag=createRagInfrastructure(stack,notes,readRagPilotScope({owners:[{ownerId:'993a958c-1051-70fe-41b4-f5c997da1652',
    noteIds:['p5-hs','p5-cost','p5-iris','p5-truc-a','p5-truc-b','note-1791284611425000-3']}]}));
  const fn=new Function(stack,'PrivateQuery',{runtime:Runtime.NODEJS_22_X,code:Code.fromInline('exports.handler=()=>{}'),handler:'index.handler',memorySize:512,timeout:Duration.seconds(28)});
  createPrivateRagInfrastructure(fn,notes,rag);
  const t=Template.fromStack(stack),r=t.toJSON().Resources;
  const query=Object.entries(r).find(([id])=>id.startsWith('PrivateQuery')&&(r[id] as any).Type==='AWS::Lambda::Function')![1] as any;
  assert.equal(query.Properties.ReservedConcurrentExecutions,1);
  assert.equal(query.Properties.Environment.Variables.RAG_PRIVATE_PHASE4,'synthetic-only');
  assert.equal(query.Properties.Environment.Variables.RAG_TOKENIZER_DIR,'/opt');
  assert.equal(query.Properties.Layers.length,2);
  const policy=Object.entries(r).find(([id])=>id.startsWith('PrivateQuery')&&id.includes('DefaultPolicy'))![1] as any;
  const update=(policy.Properties.PolicyDocument.Statement as any[]).find((s:any)=>[s.Action].flat().includes('dynamodb:UpdateItem'));
  assert.deepEqual(update.Condition,{'ForAllValues:StringEquals':{'dynamodb:LeadingKeys':['BUDGET#SMOKE','BUDGET#PHASE4']},Null:{'dynamodb:LeadingKeys':'false'}});
  assert.equal(Object.keys(t.findResources('AWS::Lambda::Permission')).length,0);
  assert.equal(Object.keys(t.findResources('AWS::Lambda::Url')).length,0);
  assert.equal(Object.keys(t.findResources('AWS::ApiGatewayV2::Route')).length,0);
});
