import {test} from 'node:test';
import assert from 'node:assert/strict';
import {App,Stack,Aspects,CfnResource,RemovalPolicy} from 'aws-cdk-lib';
import {Template} from 'aws-cdk-lib/assertions';
import {Table,AttributeType,StreamViewType} from 'aws-cdk-lib/aws-dynamodb';
import {mkdtempSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createRagInfrastructure} from './infrastructure';

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
  template.hasResourceProperties('AWS::S3Vectors::Index',{Dimension:1024,DistanceMetric:'cosine',DataType:'float32'});
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
    if(/^(RagState|RagSnapshots|RagFailures|RagVectors|RagVectorIndex)/.test(id)
      &&['AWS::DynamoDB::Table','AWS::S3::Bucket','AWS::S3Vectors::VectorBucket','AWS::S3Vectors::Index'].includes(resource.Type))
      assert.equal(resource.DeletionPolicy,'Retain',id);
});
