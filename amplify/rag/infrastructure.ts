import {Aspects,AspectPriority,CfnResource,Duration,RemovalPolicy,Stack} from 'aws-cdk-lib';
import {AttributeType,BillingMode,Table} from 'aws-cdk-lib/aws-dynamodb';
import {Bucket,BlockPublicAccess,BucketEncryption} from 'aws-cdk-lib/aws-s3';
import {CfnVectorBucket,CfnIndex} from 'aws-cdk-lib/aws-s3vectors';
import {PolicyStatement,CfnPolicy,type IRole} from 'aws-cdk-lib/aws-iam';
import {Runtime,StartingPosition,EventSourceMapping,FilterCriteria,FilterRule} from 'aws-cdk-lib/aws-lambda';
import {NodejsFunction} from 'aws-cdk-lib/aws-lambda-nodejs';
import {LogGroup,RetentionDays} from 'aws-cdk-lib/aws-logs';
import {fileURLToPath} from 'node:url';
import {existsSync,readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import jobs from '../../docs/rag/index_job_policy_v1.json';
import tokenizerManifest from '../../docs/rag/embeddinggemma_tokenizer_manifest.json';
import {secret} from '@aws-amplify/backend';
import {Construct} from 'constructs';
import {isValidIdentifier} from './contract';
import {CONSENT_SORT_KEY,NOTE_KEY_PREFIX,OWNER_KEY_PREFIX,PROTECTION_KEY_PREFIX} from './indexing/jobs';
import {MAX_PILOT_OWNERS,isCognitoSub} from './phase5/pilot_policy';
import {RUNTIME_CORPUS_KIND,RUNTIME_ELIGIBLE_OWN_NOTES_KIND} from './phase5/runtime_config';

/**
 * One compiled pilot account. Reviewed-pilot mode lists the exact note ids; the dynamic
 * `eligible-own-notes.v1` mode always carries an empty list because canonical eligibility, not a
 * frozen id list, decides which notes may be embedded.
 */
export type RagPilotOwner=Readonly<{ownerId:string;noteIds:readonly string[]}>;
/**
 * Only the dynamic `eligible-own-notes.v1` scope owns the explicit stream admission flag. The
 * reviewed gold and legacy scopes stay byte-compatible and can never carry it.
 */
export type RagPilotScope=
  |Readonly<{kind:typeof RUNTIME_CORPUS_KIND;owners:readonly RagPilotOwner[]}>
  |Readonly<{kind:typeof RUNTIME_ELIGIBLE_OWN_NOTES_KIND;owners:readonly RagPilotOwner[];streamEnabled?:boolean}>;

const isRecord=(value:unknown):value is Record<string,unknown>=>typeof value==='object'&&value!==null&&!Array.isArray(value);
const hasExactKeys=(value:Record<string,unknown>,required:readonly string[]):boolean=>
  Object.keys(value).length===required.length&&required.every(key=>Object.prototype.hasOwnProperty.call(value,key));

/**
 * Validates the pilot scope compiled into the ESM filters. Omitting the scope keeps the exact
 * legacy `OWNER#rag-smoke-` smoke path. Supplying `{owners:[...]}` selects the reviewed-pilot
 * mode: one to five unique lowercase Cognito-sub owners, each with a non-empty unique list of safe
 * note ids. Supplying `{kind:'eligible-own-notes.v1',owners:[...]}` selects the explicit dynamic
 * mode: the same exact owner set, but every `noteIds` list must be empty. Only that dynamic object
 * may also carry an explicit boolean `streamEnabled` (default false); the reviewed and legacy
 * shapes reject the key. There is no broad fallback from an unknown `kind`, and a zero-owner scope
 * fails closed rather than producing no filters, which would match every partition.
 */
export function readRagPilotScope(value:unknown):RagPilotScope{
  if(!isRecord(value))
    throw Error('RAG pilot scope must be an exact object');
  const hasKind=Object.prototype.hasOwnProperty.call(value,'kind');
  let dynamic=false;
  let streamEnabled=false;
  if(hasKind){
    const kind=value['kind'];
    if(kind===RUNTIME_ELIGIBLE_OWN_NOTES_KIND){
      dynamic=true;
      if(Object.prototype.hasOwnProperty.call(value,'streamEnabled')){
        if(!hasExactKeys(value,['kind','owners','streamEnabled']))
          throw Error('RAG pilot scope must be an exact {kind,owners,streamEnabled} object');
        const rawStreamEnabled=value['streamEnabled'];
        if(typeof rawStreamEnabled!=='boolean')
          throw Error('RAG pilot scope streamEnabled must be a boolean');
        streamEnabled=rawStreamEnabled;
      }else if(!hasExactKeys(value,['kind','owners'])){
        throw Error('RAG pilot scope must be an exact {kind,owners} object');
      }
    }else if(kind!==RUNTIME_CORPUS_KIND){
      throw Error('RAG pilot scope kind must be reviewed-pilot or eligible-own-notes.v1');
    }else if(!hasExactKeys(value,['kind','owners'])){
      // Reviewed gold keeps its exact legacy shape; stream admission is dynamic-only.
      throw Error('RAG pilot scope must be an exact {kind,owners} object');
    }
  }else if(!hasExactKeys(value,['owners'])){
    throw Error('RAG pilot scope must be an exact {owners} object');
  }
  const rawOwners=value['owners'];
  if(!Array.isArray(rawOwners)||rawOwners.length===0||rawOwners.length>MAX_PILOT_OWNERS)
    throw Error('RAG pilot scope needs one to five owners');
  const owners:RagPilotOwner[]=[];
  const seenOwners=new Set<string>();
  for(const raw of rawOwners){
    if(!isRecord(raw)||!hasExactKeys(raw,['ownerId','noteIds']))
      throw Error('each RAG pilot owner needs exact ownerId/noteIds');
    const ownerId=raw['ownerId'];
    if(!isCognitoSub(ownerId)||seenOwners.has(ownerId))
      throw Error('RAG pilot owner must be a unique lowercase Cognito sub');
    seenOwners.add(ownerId);
    const rawNotes=raw['noteIds'];
    if(!Array.isArray(rawNotes))
      throw Error('each RAG pilot owner needs a noteIds array');
    if(dynamic){
      if(rawNotes.length!==0)
        throw Error('eligible-own-notes pilot owner noteIds must be empty');
      owners.push(Object.freeze({ownerId,noteIds:Object.freeze([])}));
      continue;
    }
    if(rawNotes.length===0)
      throw Error('each RAG pilot owner needs at least one approved note id');
    const noteIds:string[]=[];
    const seenNotes=new Set<string>();
    for(const noteId of rawNotes){
      if(!isValidIdentifier(noteId)||seenNotes.has(noteId))
        throw Error('RAG pilot note ids must be safe and unique per owner');
      seenNotes.add(noteId);
      noteIds.push(noteId);
    }
    owners.push(Object.freeze({ownerId,noteIds:Object.freeze(noteIds)}));
  }
  return Object.freeze(dynamic
    ?{kind:RUNTIME_ELIGIBLE_OWN_NOTES_KIND,owners:Object.freeze(owners),streamEnabled}
    :{kind:RUNTIME_CORPUS_KIND,owners:Object.freeze(owners)});
}

/** The same backend identity Amplify uses for its secret parameter paths. */
export type RagBackendIdentifier=Readonly<{
  type:'sandbox'|'branch'|'standalone';namespace:string;name:string;
}>;
export type RagSecretEnvironment=Readonly<{
  CLOUDFLARE_ACCESS_CLIENT_ID:string;CLOUDFLARE_ACCESS_CLIENT_SECRET:string;
}>;

/**
 * Reads the Amplify CDK context that names the backend deployment. The three keys are the ones
 * the Amplify deployment engine sets; no SSM path is constructed here. The returned value is
 * handed to the official `secret(...).resolve` helper, and its branch path is derived by the
 * official `resolvePath` helper so this code never guesses Amplify's sanitized path format.
 */
export function readBackendIdentifier(scope:Stack):RagBackendIdentifier{
  const read=(key:string):string=>{
    const value=scope.node.getContext(key);
    if(typeof value!=='string'||value.length===0)throw Error(`RAG infrastructure needs Amplify CDK context ${key}`);
    return value;
  };
  const type=read('amplify-backend-type');
  if(type!=='sandbox'&&type!=='branch'&&type!=='standalone')
    throw Error('RAG infrastructure needs a supported Amplify deployment type');
  return Object.freeze({type,namespace:read('amplify-backend-namespace'),name:read('amplify-backend-name')});
}

/**
 * The two branch-level SSM parameter ARNs this RAG-only fetcher may read. The path is derived by
 * the official Amplify `resolvePath` helper (same sanitized namespace/name/type/hash as the
 * fetcher itself), then pinned to the current stack account and region. The shared namespace is
 * deliberately absent: the reviewed secrets live in this sandbox branch, and a RAG worker must
 * never inherit permission to read every branch or shared parameter in the account.
 */
export function ragSecretParameterArns(scope:Stack,backend:RagBackendIdentifier):readonly string[]{
  const unsupported=(scope.account===''||scope.region==='');
  if(unsupported)throw Error('RAG secret fetcher needs a concrete account and region');
  return Object.freeze((['CLOUDFLARE_ACCESS_CLIENT_ID','CLOUDFLARE_ACCESS_CLIENT_SECRET'] as const).map(name=>{
    const {branchSecretPath}=secret(name).resolvePath(backend);
    if(!branchSecretPath.startsWith('/amplify/'))
      throw Error('RAG secret path is not an Amplify branch parameter');
    return `arn:aws:ssm:${scope.region}:${scope.account}:parameter${branchSecretPath}`;
  }));
}

/**
 * Replaces the provider role's generated SSM grant with exactly the two branch parameter ARNs.
 * Amplify's stock provider widens the resource to `arn:aws:ssm:*:*` plus the shared namespace;
 * this RAG-only provider is scoped immediately after construction so no wildcard or cross-region
 * read survives synth. The provider itself is still the official Amplify fetcher, so resolution
 * semantics and the NoEcho custom-resource attributes are unchanged.
 */
function restrictRagSecretFetcher(secretScope:Construct,arns:readonly string[]):void{
  const provider=secretScope.node.tryFindChild('AmplifySecretFetcherResourceProviderLambda');
  const role=(provider as unknown as {role?:IRole}|undefined)?.role;
  if(role===undefined)throw Error('Amplify secret fetcher provider role is missing');
  const policy=role.node.tryFindChild('DefaultPolicy');
  const cfn=policy?.node.defaultChild;
  if(!(cfn instanceof CfnPolicy))throw Error('Amplify secret fetcher provider policy is missing');
  cfn.addPropertyOverride('PolicyDocument',{
    Version:'2012-10-17',
    Statement:[{Effect:'Allow',Action:'ssm:GetParameter',Resource:[...arns]}],
  });
}

/** Both Cloudflare Access secrets, resolved by Amplify at deploy; no literal value is read here. */
export function resolveRagSecrets(scope:Stack):RagSecretEnvironment{
  const backend=readBackendIdentifier(scope);
  // A dedicated construct keeps this provider separate from every other Amplify secret consumer,
  // so narrowing its IAM policy cannot change an unrelated function's secret resolution.
  const secretScope=scope.node.tryFindChild('RagEmbeddingSecrets')??new Construct(scope,'RagEmbeddingSecrets');
  const value=(name:'CLOUDFLARE_ACCESS_CLIENT_ID'|'CLOUDFLARE_ACCESS_CLIENT_SECRET'):string=>
    secret(name).resolve(secretScope,backend).unsafeUnwrap();
  const environment=Object.freeze({
    CLOUDFLARE_ACCESS_CLIENT_ID:value('CLOUDFLARE_ACCESS_CLIENT_ID'),
    CLOUDFLARE_ACCESS_CLIENT_SECRET:value('CLOUDFLARE_ACCESS_CLIENT_SECRET'),
  });
  restrictRagSecretFetcher(secretScope,ragSecretParameterArns(scope,backend));
  return environment;
}

const readSecretEnvironment=(value:unknown):RagSecretEnvironment|undefined=>{
  if(value===undefined)return undefined;
  if(!isRecord(value)||!hasExactKeys(value,['CLOUDFLARE_ACCESS_CLIENT_ID','CLOUDFLARE_ACCESS_CLIENT_SECRET']))
    throw Error('RAG embedding secrets must be exactly the two named runtime values');
  const id=value['CLOUDFLARE_ACCESS_CLIENT_ID'];
  const clientSecret=value['CLOUDFLARE_ACCESS_CLIENT_SECRET'];
  if(typeof id!=='string'||id.length===0||typeof clientSecret!=='string'||clientSecret.length===0)
    throw Error('RAG embedding secrets must be non-empty runtime values');
  return Object.freeze({CLOUDFLARE_ACCESS_CLIENT_ID:id,CLOUDFLARE_ACCESS_CLIENT_SECRET:clientSecret});
};

// Additive resources in SyncStack: existing Notes/Auth/Attachment IDs stay intact.
export function createRagInfrastructure(scope:Stack,notes:Table,pilot?:RagPilotScope,secrets?:RagSecretEnvironment){
  // Re-validate the supplied scope (never trust a caller cast) before anything is created.
  const approved=pilot===undefined?undefined:readRagPilotScope(pilot);
  const secretEnvironment=readSecretEnvironment(secrets);
  const tokenizerDir=resolve(fileURLToPath(new URL('../../output/rag/embeddinggemma-tokenizer/',import.meta.url)));
  for(const [file,digest] of Object.entries(tokenizerManifest.files)){
    const path=resolve(tokenizerDir,file);
    if(!existsSync(path)||createHash('sha256').update(readFileSync(path)).digest('hex')!==digest)
      throw Error('Run python3 tool/rag/prepare_embeddinggemma_tokenizer.py before RAG synth');
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
  // Preserve the Cohere-era logical index exactly as deployed (rag-v1, 1024) for rollback and
  // investigation. Never change its dimension or reuse it for the new profile.
  const legacyIndex=new CfnIndex(scope,'RagVectorIndex',{indexName:'rag-v1',vectorBucketArn:vectors.attrVectorBucketArn,
    dimension:1024,dataType:'float32',distanceMetric:'cosine'});
  legacyIndex.applyRemovalPolicy(RemovalPolicy.RETAIN);
  // Additive EmbeddingGemma index. The runtime selects this ARN; the two indexes never mix keys.
  const activeIndex=new CfnIndex(scope,'RagEmbeddingGemmaVectorIndex',{indexName:'rag-eg2-q8-768-v1',
    vectorBucketArn:vectors.attrVectorBucketArn,dimension:768,dataType:'float32',distanceMetric:'cosine'});
  activeIndex.applyRemovalPolicy(RemovalPolicy.RETAIN);
  const retained = new Set([state.node.defaultChild, snapshots.node.defaultChild, failures.node.defaultChild,
    vectors, legacyIndex, activeIndex]);
  // Amplify sandbox otherwise overwrites explicit Retain with Destroy on every resource.
  Aspects.of(scope).add({ visit(node) {
    if (CfnResource.isCfnResource(node) && retained.has(node)) node.applyRemovalPolicy(RemovalPolicy.RETAIN);
  } }, { priority: AspectPriority.DEFAULT + 1 });
  const environment={RAG_REGION:scope.region,RAG_NOTES_TABLE:notes.tableName,RAG_STATE_TABLE:state.tableName,
    RAG_SNAPSHOT_BUCKET:snapshots.bucketName,RAG_VECTOR_INDEX_ARN:activeIndex.attrIndexArn,
    RAG_TOKENIZER_DIR:'/var/task/tokenizer',RAG_STREAM_ARN:notes.tableStreamArn!,
    ...(secretEnvironment ?? {})};
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
    // Self-hosted EmbeddingGemma needs no Bedrock model grant; only the active index is reachable.
    fn.addToRolePolicy(new PolicyStatement({actions:['s3:GetObject'],resources:[snapshots.arnForObjects('rag/snapshots/*')]}));
    fn.addToRolePolicy(new PolicyStatement({actions:['s3vectors:GetVectors','s3vectors:QueryVectors'],resources:[activeIndex.attrIndexArn]}));
  }
  probe.addToRolePolicy(new PolicyStatement({actions:['dynamodb:UpdateItem'],resources:[state.tableArn],
    conditions:{'ForAllValues:StringEquals':{'dynamodb:LeadingKeys':['BUDGET#SMOKE']},Null:{'dynamodb:LeadingKeys':'false'}}}));
  worker.addToRolePolicy(new PolicyStatement({actions:['dynamodb:ConditionCheckItem'],resources:[notes.tableArn]}));
  worker.addToRolePolicy(new PolicyStatement({actions:['dynamodb:PutItem','dynamodb:UpdateItem','dynamodb:DeleteItem'],resources:[state.tableArn]}));
  // Checkpoint resume/record is worker-only: the probe stays a read-only snapshot consumer.
  worker.addToRolePolicy(new PolicyStatement({actions:['s3:GetObject'],
    resources:[snapshots.arnForObjects('rag/checkpoints/*')]}));
  worker.addToRolePolicy(new PolicyStatement({actions:['s3:PutObject','s3:DeleteObject'],
    resources:[snapshots.arnForObjects('rag/snapshots/*'),snapshots.arnForObjects('rag/checkpoints/*')]}));
  worker.addToRolePolicy(new PolicyStatement({actions:['s3:ListBucket'],resources:[snapshots.bucketArn],
    conditions:{StringLike:{'s3:prefix':['rag/snapshots/*','rag/checkpoints/*']}}}));
  worker.addToRolePolicy(new PolicyStatement({actions:['s3vectors:PutVectors','s3vectors:DeleteVectors'],resources:[activeIndex.attrIndexArn]}));
  const streamGrant = notes.grantStreamRead(worker);
  worker.addToRolePolicy(new PolicyStatement({actions:['s3:PutObject'],resources:[failures.arnForObjects('*')],
    conditions:{StringEquals:{'s3:ResourceAccount':scope.account}}}));
  worker.addToRolePolicy(new PolicyStatement({actions:['s3:ListBucket'],resources:[failures.bucketArn],
    conditions:{StringEquals:{'s3:ResourceAccount':scope.account}}}));
  // Pilot mode selects the adapter in the worker. The mapping itself defaults disabled on this
  // first dynamic deploy; enabling is a separate controlled rollout after worker proof.
  if(approved!==undefined)worker.addEnvironment('RAG_PILOT_PHASE5','synthetic-only');
  // One filter per approved owner, never a wildcard owner and never a cross-owner OR. The
  // dynamic `eligible-own-notes.v1` mode admits only that exact `OWNER#<sub>` partition plus
  // `NOTE#`/`PROTECTION#` prefixes and the exact `RAG#CONSENT` row; no other `RAG#` row matches.
  // The reviewed mode keeps its exact note/protection keys. Absent scope keeps the legacy smoke
  // filter. Both pilot modes keep failure destinations on the retained private S3 bucket.
  const filters=approved===undefined
    ?[FilterCriteria.filter({eventName:['INSERT','MODIFY','REMOVE'],dynamodb:{Keys:{ownerId:{S:FilterRule.beginsWith('OWNER#rag-smoke-')},
      noteId:{S:[{prefix:'NOTE#'},{prefix:'PROTECTION#'},'RAG#CONSENT']}}}})]
    :approved.kind===RUNTIME_ELIGIBLE_OWN_NOTES_KIND
      ?approved.owners.map(owner=>FilterCriteria.filter({eventName:['INSERT','MODIFY','REMOVE'],dynamodb:{Keys:{
        ownerId:{S:[`${OWNER_KEY_PREFIX}${owner.ownerId}`]},
        noteId:{S:[{prefix:NOTE_KEY_PREFIX},{prefix:PROTECTION_KEY_PREFIX},CONSENT_SORT_KEY]}}}}))
      :approved.owners.map(owner=>FilterCriteria.filter({eventName:['INSERT','MODIFY','REMOVE'],dynamodb:{Keys:{
        ownerId:{S:[`${OWNER_KEY_PREFIX}${owner.ownerId}`]},
        noteId:{S:[...owner.noteIds.map(id=>`${NOTE_KEY_PREFIX}${id}`),
          ...owner.noteIds.map(id=>`${PROTECTION_KEY_PREFIX}${id}`),CONSENT_SORT_KEY]}}}}));
  // Only the validated dynamic scope may opt in; reviewed/legacy keep the policy default false.
  const streamEnabled=approved!==undefined&&approved.kind===RUNTIME_ELIGIBLE_OWN_NOTES_KIND
    ?approved.streamEnabled??false
    :jobs.stream.enabledByDefault;
  const mapping=new EventSourceMapping(scope,'RagNoteStream',{target:worker,eventSourceArn:notes.tableStreamArn!,
    enabled:streamEnabled,startingPosition:StartingPosition.TRIM_HORIZON,batchSize:jobs.stream.batchSize,maxBatchingWindow:Duration.seconds(jobs.stream.batchingWindowSeconds),
    parallelizationFactor:jobs.stream.parallelizationFactor,retryAttempts:jobs.stream.maximumRetryAttempts,maxRecordAge:Duration.seconds(jobs.stream.maximumRecordAgeSeconds),reportBatchItemFailures:true,
    onFailure:{bind:()=>({destination:failures.bucketArn})},filters});
  streamGrant.applyBefore(mapping);
  return {worker,probe,mapping,state,snapshots,failures,vectors,legacyIndex,activeIndex,index:activeIndex};
}
