import {Aspects,AspectPriority,CfnResource,Duration,RemovalPolicy,Stack} from 'aws-cdk-lib';
import {AttributeType,BillingMode,Table} from 'aws-cdk-lib/aws-dynamodb';
import {Bucket,BlockPublicAccess,BucketEncryption} from 'aws-cdk-lib/aws-s3';
import {CfnVectorBucket,CfnIndex} from 'aws-cdk-lib/aws-s3vectors';
import {PolicyStatement} from 'aws-cdk-lib/aws-iam';
import {Runtime,StartingPosition,EventSourceMapping,FilterCriteria,FilterRule} from 'aws-cdk-lib/aws-lambda';
import {NodejsFunction} from 'aws-cdk-lib/aws-lambda-nodejs';
import {LogGroup,RetentionDays} from 'aws-cdk-lib/aws-logs';
import {fileURLToPath} from 'node:url';
import {existsSync,readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import jobs from '../../docs/rag/index_job_policy_v1.json';
import tokenizerManifest from '../../docs/rag/tokenizer_manifest.json';

// Additive resources in SyncStack: existing Notes/Auth/Attachment IDs stay intact.
export function createRagInfrastructure(scope:Stack,notes:Table){
  const tokenizerDir=resolve(fileURLToPath(new URL('../../output/rag/tokenizer/',import.meta.url)));
  for(const [file,digest] of Object.entries(tokenizerManifest.files)){
    const path=resolve(tokenizerDir,file);
    if(!existsSync(path)||createHash('sha256').update(readFileSync(path)).digest('hex')!==digest)
      throw Error('Run python3 tool/rag/prepare_tokenizer.py before RAG synth');
  }
  const state=new Table(scope,'RagState',{partitionKey:{name:'ownerId',type:AttributeType.STRING},
    sortKey:{name:'noteId',type:AttributeType.STRING},billingMode:BillingMode.PAY_PER_REQUEST,
    removalPolicy:RemovalPolicy.RETAIN});
  const snapshots=new Bucket(scope,'RagSnapshots',{blockPublicAccess:BlockPublicAccess.BLOCK_ALL,
    encryption:BucketEncryption.S3_MANAGED,enforceSSL:true,removalPolicy:RemovalPolicy.RETAIN});
  const failures=new Bucket(scope,'RagFailures',{blockPublicAccess:BlockPublicAccess.BLOCK_ALL,
    encryption:BucketEncryption.S3_MANAGED,enforceSSL:true,removalPolicy:RemovalPolicy.RETAIN,
    lifecycleRules:[{expiration:Duration.days(jobs.failureRetentionDays)}]});
  const vectors=new CfnVectorBucket(scope,'RagVectors',{});
  vectors.applyRemovalPolicy(RemovalPolicy.RETAIN);
  const index=new CfnIndex(scope,'RagVectorIndex',{indexName:'rag-v1',vectorBucketArn:vectors.attrVectorBucketArn,
    dimension:1024,dataType:'float32',distanceMetric:'cosine'});
  index.applyRemovalPolicy(RemovalPolicy.RETAIN);
  const retained = new Set([state.node.defaultChild, snapshots.node.defaultChild, failures.node.defaultChild, vectors, index]);
  // Amplify sandbox otherwise overwrites explicit Retain with Destroy on every resource.
  Aspects.of(scope).add({ visit(node) {
    if (CfnResource.isCfnResource(node) && retained.has(node)) node.applyRemovalPolicy(RemovalPolicy.RETAIN);
  } }, { priority: AspectPriority.DEFAULT + 1 });
  const environment={RAG_REGION:scope.region,RAG_NOTES_TABLE:notes.tableName,RAG_STATE_TABLE:state.tableName,
    RAG_SNAPSHOT_BUCKET:snapshots.bucketName,RAG_VECTOR_INDEX_ARN:index.attrIndexArn,
    RAG_TOKENIZER_DIR:'/var/task/tokenizer',RAG_STREAM_ARN:notes.tableStreamArn!};
  const make=(id:string,entry:string,timeout:number)=>{
    const logs=new LogGroup(scope,`${id}Logs`,{retention:RetentionDays.ONE_WEEK,removalPolicy:RemovalPolicy.RETAIN});
    retained.add(logs.node.defaultChild);
    return new NodejsFunction(scope,id,{entry:fileURLToPath(new URL(entry,import.meta.url)),handler:'handler',
      runtime:Runtime.NODEJS_22_X,timeout:Duration.seconds(timeout),memorySize:jobs.workerMemoryMb,logGroup:logs,environment,
      ...(id==='RagWorker'?{reservedConcurrentExecutions:jobs.reservedConcurrency}:{}),
      bundling:{externalModules:[],commandHooks:{beforeBundling:()=>[],beforeInstall:()=>[],
        afterBundling:(_input,output)=>[`mkdir -p '${output}/tokenizer'`,
          `cp '${tokenizerDir}/tokenizer.json' '${tokenizerDir}/tokenizer_config.json' '${output}/tokenizer/'`]}}});
  };
  const worker=make('RagWorker','./indexing/worker_lambda.ts',jobs.workerTimeoutSeconds);
  const probe=make('RagRetrievalProbe','./indexing/probe_lambda.ts',28);
  // Autopilot baseline is narrowed to the approved resources/actions; no object-lock/KMS grants.
  for(const fn of [worker,probe]){
    fn.addToRolePolicy(new PolicyStatement({actions:['dynamodb:GetItem','dynamodb:Query'],resources:[notes.tableArn]}));
    fn.addToRolePolicy(new PolicyStatement({actions:['dynamodb:GetItem','dynamodb:Query'],resources:[state.tableArn]}));
    fn.addToRolePolicy(new PolicyStatement({actions:['bedrock:InvokeModel'],resources:[scope.formatArn({service:'bedrock',account:'',
      resource:'foundation-model',resourceName:'cohere.embed-multilingual-v3'})]}));
    fn.addToRolePolicy(new PolicyStatement({actions:['s3:GetObject'],resources:[snapshots.arnForObjects('rag/snapshots/*')]}));
    fn.addToRolePolicy(new PolicyStatement({actions:['s3vectors:GetVectors','s3vectors:QueryVectors'],resources:[index.attrIndexArn]}));
  }
  probe.addToRolePolicy(new PolicyStatement({actions:['dynamodb:UpdateItem'],resources:[state.tableArn],
    conditions:{'ForAllValues:StringEquals':{'dynamodb:LeadingKeys':['BUDGET#SMOKE']},Null:{'dynamodb:LeadingKeys':'false'}}}));
  worker.addToRolePolicy(new PolicyStatement({actions:['dynamodb:ConditionCheckItem'],resources:[notes.tableArn]}));
  worker.addToRolePolicy(new PolicyStatement({actions:['dynamodb:PutItem','dynamodb:UpdateItem','dynamodb:DeleteItem'],resources:[state.tableArn]}));
  worker.addToRolePolicy(new PolicyStatement({actions:['s3:PutObject','s3:DeleteObject'],resources:[snapshots.arnForObjects('rag/snapshots/*')]}));
  worker.addToRolePolicy(new PolicyStatement({actions:['s3:ListBucket'],resources:[snapshots.bucketArn],
    conditions:{StringLike:{'s3:prefix':['rag/snapshots/*']}}}));
  worker.addToRolePolicy(new PolicyStatement({actions:['s3vectors:PutVectors','s3vectors:DeleteVectors'],resources:[index.attrIndexArn]}));
  const streamGrant = notes.grantStreamRead(worker);
  worker.addToRolePolicy(new PolicyStatement({actions:['s3:PutObject'],resources:[failures.arnForObjects('*')],
    conditions:{StringEquals:{'s3:ResourceAccount':scope.account}}}));
  worker.addToRolePolicy(new PolicyStatement({actions:['s3:ListBucket'],resources:[failures.bucketArn],
    conditions:{StringEquals:{'s3:ResourceAccount':scope.account}}}));
  const mapping=new EventSourceMapping(scope,'RagNoteStream',{target:worker,eventSourceArn:notes.tableStreamArn!,
    enabled:jobs.stream.enabledByDefault,startingPosition:StartingPosition.TRIM_HORIZON,batchSize:jobs.stream.batchSize,maxBatchingWindow:Duration.seconds(jobs.stream.batchingWindowSeconds),
    parallelizationFactor:jobs.stream.parallelizationFactor,retryAttempts:jobs.stream.maximumRetryAttempts,maxRecordAge:Duration.seconds(jobs.stream.maximumRecordAgeSeconds),reportBatchItemFailures:true,
    onFailure:{bind:()=>({destination:failures.bucketArn})},filters:[FilterCriteria.filter({
      eventName:['INSERT','MODIFY','REMOVE'],dynamodb:{Keys:{ownerId:{S:FilterRule.beginsWith('OWNER#rag-smoke-')},
        noteId:{S:[{prefix:'NOTE#'},{prefix:'PROTECTION#'},'RAG#CONSENT']}}}})]});
  streamGrant.applyBefore(mapping);
  return {worker,probe,mapping,state,snapshots,failures,vectors,index};
}
