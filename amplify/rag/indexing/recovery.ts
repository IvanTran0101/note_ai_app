// Recovery reads retired versions only; active artifacts are never selected for deletion.
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, QueryCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';
import { isValidIdentifier } from '../contract';
import { validateManifest } from './snapshot';
import { IndexFailure, type Artifacts, type IndexStore } from './types';

type Client = Pick<DynamoDBDocumentClient, 'send'>;
export function createRetirementRecovery(table: string, region: string, store: IndexStore,
  artifacts: Artifacts, db: Client = DynamoDBDocumentClient.from(new DynamoDBClient({region,maxAttempts:1}))) {
  return async (ownerId: string, signal: AbortSignal) => {
    if (!isValidIdentifier(ownerId)) throw new IndexFailure('INVALID_JOB');
    let cursor: Record<string, unknown> | undefined;
    let recovered = 0;
    do {
      const page = await db.send(new QueryCommand({TableName:table,ConsistentRead:true,
        KeyConditionExpression:'ownerId = :owner AND begins_with(noteId, :prefix)',
        ExpressionAttributeValues:{':owner':`OWNER#${ownerId}`,':prefix':'RAG#RETIRE#'},
        ...(cursor ? {ExclusiveStartKey:cursor} : {})}),{abortSignal:signal});
      for (const row of page.Items ?? []) {
        const old = validateManifest(row.manifest, ownerId);
        if (row.noteId !== `RAG#RETIRE#${old.version}`) throw new IndexFailure('INVALID_STATE');
        const live = await store.load(ownerId, signal);
        if (live.manifest?.version === old.version) throw new IndexFailure('ACTIVE_VERSION');
        await artifacts.cleanup(old, signal);
        await db.send(new DeleteCommand({TableName:table,Key:{ownerId:`OWNER#${ownerId}`,noteId:row.noteId},
          ConditionExpression:'manifest.#version = :version AND manifest.checksum = :checksum',
          ExpressionAttributeNames:{'#version':'version'},
          ExpressionAttributeValues:{':version':old.version,':checksum':old.checksum}}),{abortSignal:signal});
        recovered++;
      }
      if (cursor && JSON.stringify(cursor) === JSON.stringify(page.LastEvaluatedKey)) throw new IndexFailure('INVALID_STATE');
      cursor = page.LastEvaluatedKey;
    } while (cursor);
    return {recovered};
  };
}

import {S3Client,ListObjectsV2Command,GetObjectCommand} from '@aws-sdk/client-s3';
import {checksum,decodeSnapshot,sha256Hex} from './snapshot';
import {LEASE_MS} from './types';
export function createOrphanRecovery(bucket:string,region:string,store:IndexStore,artifacts:Artifacts,
  s3:Pick<S3Client,'send'>=new S3Client({region,maxAttempts:1})) {
  return async(ownerId:string,signal:AbortSignal)=>{
    if(!isValidIdentifier(ownerId))throw new IndexFailure('INVALID_JOB');
    const prefix=`rag/snapshots/${sha256Hex(ownerId)}/`;
    let cursor:string|undefined, recovered=0;
    do {
      const page=await s3.send(new ListObjectsV2Command({Bucket:bucket,Prefix:prefix,ContinuationToken:cursor}),{abortSignal:signal});
      for(const object of page.Contents??[]){
        // Past lease expiry and a full day: no worker can still publish this immutable version.
        if(!object.Key?.startsWith(prefix)||!object.LastModified
          ||Date.now()-object.LastModified.getTime()<Math.max(86_400_000,LEASE_MS))continue;
        const state=await store.load(ownerId,signal);
        if(state.manifest?.snapshotKey===object.Key)continue;
        const read=await s3.send(new GetObjectCommand({Bucket:bucket,Key:object.Key}),{abortSignal:signal});
        const text=await read.Body?.transformToString();
        if(!text)throw new IndexFailure('INDEX_NOT_READY');
        let raw: unknown;
        try { raw = JSON.parse(text); } catch { throw new IndexFailure('INDEX_NOT_READY'); }
        if(!raw||typeof raw!=='object'||!('policyIdentity'in raw)||typeof raw.policyIdentity!=='string')throw new IndexFailure('INDEX_NOT_READY');
        const snapshot=decodeSnapshot(text,raw.policyIdentity);
        if(snapshot.ownerId!==ownerId||object.Key!==`${prefix}${snapshot.version}.json`)throw new IndexFailure('INDEX_NOT_READY');
        await artifacts.cleanup({ownerId,generation:0,version:snapshot.version,fingerprint:'0'.repeat(64),
          consentGeneration:snapshot.consentGeneration,accountEpoch:snapshot.accountEpoch,status:'BLOCKED',
          snapshotKey:object.Key,checksum:checksum(snapshot),policyIdentity:snapshot.policyIdentity},signal);
        recovered++;
      }
      if(cursor&&cursor===page.NextContinuationToken)throw new IndexFailure('INVALID_STATE');
      cursor=page.NextContinuationToken;
    }while(cursor);
    return{recovered};
  };
}
