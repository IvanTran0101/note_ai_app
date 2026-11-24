import {test} from 'node:test';
import assert from 'node:assert/strict';
import {QueryCommand,DeleteCommand} from '@aws-sdk/lib-dynamodb';
import {createRetirementRecovery,createCheckpointRecovery} from './recovery';
import {policyIdentity} from './snapshot';
import type {Artifacts,IndexStore} from './types';
import type {Checkpoint} from './checkpoint';
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

// -------------------------------------------------------------------------------------------
// Checkpoint sweep (Patch 5B): stale checkpoints are reaped staged-vectors-first, JSON-last;
// the live manifest's own lease and anything younger than minAgeMs are never touched; a late
// write by a dead lease is reaped by the next rerun; port-less artifacts sweep nothing.
// -------------------------------------------------------------------------------------------
const ck=(leaseToken:string,createdAt:number,keys:readonly string[]=[]):Checkpoint=>({
  schemaVersion:1,ownerId:'alice',policyIdentity:policyIdentity(),consentGeneration:1,leaseToken,
  createdAt,entries:keys.map((key)=>({embeddingDigest:sha256Hex(`digest#${key}`),vectorKey:key}))});

test('the sweep reaps a stale checkpoint vectors-first, JSON-last and spares live and young ones',async()=>{
  const actions:string[]=[];
  const checkpoints=new Map<string,Checkpoint>([
    ['live',ck('live',0,['k-live'])],             // the live manifest's own lease: old but untouchable
    ['stale',ck('stale',0,['k-stale'])],          // past every window: reaped, vectors before JSON
    ['young',ck('young',Date.now(),['k-young'])], // younger than minAgeMs: its lease may still be live
  ]);
  const store={load:async()=>({manifest:{version:'live'}})} as unknown as IndexStore;
  const artifacts={
    listCheckpoints:async()=>[...checkpoints.values()],
    deleteStagedVectors:async(keys:readonly string[])=>{actions.push(`vectors#${keys.join(',')}`);},
    deleteCheckpoints:async(_ownerId:string,_signal:AbortSignal,...tokens:string[])=>{
      for(const token of tokens){actions.push(`json#${token}`);checkpoints.delete(token);}},
  } as unknown as Artifacts;
  const sweep=createCheckpointRecovery(store,artifacts);
  assert.deepEqual(await sweep('alice',new AbortController().signal),{swept:1});
  assert.deepEqual(actions,['vectors#k-stale','json#stale'],'staged vectors are deleted before the JSON');
  assert.deepEqual([...checkpoints.keys()].sort(),['live','young']);
});

test('a late checkpoint write after a sweep is reaped by the next sweep',async()=>{
  const checkpoints=new Map<string,Checkpoint>();
  const deleted:string[]=[];
  const store={load:async()=>({manifest:null})} as unknown as IndexStore;
  const artifacts={
    listCheckpoints:async()=>[...checkpoints.values()],
    deleteStagedVectors:async()=>{},
    deleteCheckpoints:async(_ownerId:string,_signal:AbortSignal,...tokens:string[])=>{
      for(const token of tokens){deleted.push(token);checkpoints.delete(token);}},
  } as unknown as Artifacts;
  const sweep=createCheckpointRecovery(store,artifacts);
  // The first sweep reaps the original object; the dead lease's late record() re-puts the same
  // checkpoint after it, and an idempotent rerun reaps the late write too.
  checkpoints.set('stale',ck('stale',0,['k-stale']));
  assert.deepEqual(await sweep('alice',new AbortController().signal),{swept:1});
  checkpoints.set('stale',ck('stale',0,['k-stale']));
  assert.deepEqual(await sweep('alice',new AbortController().signal),{swept:1},'the rerun reaps the late write');
  assert.deepEqual(deleted,['stale','stale']);
});

test('artifacts without the optional checkpoint ports sweep nothing and never throw',async()=>{
  const store={load:async()=>{throw new Error('the sweep must never need the store without ports');}} as unknown as IndexStore;
  const signal=new AbortController().signal;
  assert.deepEqual(await createCheckpointRecovery(store,{} as unknown as Artifacts)('alice',signal),{swept:0});
  // A partially capable port is exactly as inert: any missing optional method disables sweeping.
  const partial={listCheckpoints:async()=>[]} as unknown as Artifacts;
  assert.deepEqual(await createCheckpointRecovery(store,partial)('alice',signal),{swept:0});
});
