import {test} from 'node:test';
import assert from 'node:assert/strict';
import {QueryCommand,DeleteCommand} from '@aws-sdk/lib-dynamodb';
import {createRetirementRecovery} from './recovery';
import {policyIdentity} from './snapshot';
import type {Artifacts,IndexStore} from './types';
const old={ownerId:'alice',generation:1,version:'old',fingerprint:'a'.repeat(64),consentGeneration:1,
  accountEpoch:1,status:'READY',snapshotKey:'old',checksum:'b'.repeat(64),policyIdentity:policyIdentity()} as const;
function rig(active=false,fail=false){
  const actions:string[]=[];
  const db={send:async(command:unknown)=>{
    if(command instanceof QueryCommand)return {Items:[{noteId:'RAG#RETIRE#old',manifest:old}]};
    assert.ok(command instanceof DeleteCommand);actions.push('delete-pointer');return {};}};
  const store={load:async()=>({manifest:{...old,version:active?'old':'new'}})} as unknown as IndexStore;
  const artifacts={cleanup:async()=>{actions.push('cleanup');if(fail)throw Error('temporary');}} as unknown as Artifacts;
  return {actions,run:createRetirementRecovery('state','ap-southeast-1',store,artifacts,db as never)};
}
test('cleanup succeeds before the durable recovery pointer is removed',async()=>{
  const r=rig();assert.deepEqual(await r.run('alice',new AbortController().signal),{recovered:1});
  assert.deepEqual(r.actions,['cleanup','delete-pointer']);
});
test('active version is never deleted',async()=>{
  const r=rig(true);await assert.rejects(r.run('alice',new AbortController().signal));assert.deepEqual(r.actions,[]);
});
test('cleanup failure preserves recovery pointer',async()=>{
  const r=rig(false,true);await assert.rejects(r.run('alice',new AbortController().signal));assert.deepEqual(r.actions,['cleanup']);
});

import {ListObjectsV2Command,GetObjectCommand} from '@aws-sdk/client-s3';
import {createOrphanRecovery} from './recovery';
import {checksum,encodeSnapshot,sha256Hex} from './snapshot';
const snapshot={schemaVersion:1,ownerId:'alice',version:'orphan',consentGeneration:1,accountEpoch:1,
  policyIdentity:policyIdentity(),documents:[]} as const;
test('orphan cleanup skips active/recent objects and only deletes a verified expired namespace',async()=>{
  const prefix=`rag/snapshots/${sha256Hex('alice')}/`;
  const deleted:string[]=[];
  const store={load:async()=>({manifest:{snapshotKey:`${prefix}active.json`}})} as unknown as IndexStore;
  const artifacts={cleanup:async(manifest:typeof old)=>{deleted.push(manifest.version);assert.equal(manifest.checksum,checksum(snapshot));}} as unknown as Artifacts;
  const s3={send:async(command:unknown)=>{
    if(command instanceof ListObjectsV2Command)return{Contents:[
      {Key:`${prefix}active.json`,LastModified:new Date(0)},
      {Key:`${prefix}recent.json`,LastModified:new Date()},
      {Key:`${prefix}orphan.json`,LastModified:new Date(0)}]};
    assert.ok(command instanceof GetObjectCommand);assert.equal(command.input.Key,`${prefix}orphan.json`);
    return{Body:{transformToString:async()=>encodeSnapshot(snapshot)}};
  }};
  const result=await createOrphanRecovery('bucket','ap-southeast-1',store,artifacts,s3 as never)('alice',new AbortController().signal);
  assert.deepEqual(result,{recovered:1});assert.deepEqual(deleted,['orphan']);
});
