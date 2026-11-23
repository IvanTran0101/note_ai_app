import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  MAX_EMBEDDING_TOKENS, QUERY_PREFIX, chunkNote, queryEmbeddingText,
} from '../chunking';
import { CONSENT_VERSION } from '../contract';
import { createRetrievalProbe } from './probe';
import { fingerprint } from './jobs';
import { policyIdentity, checksum, embeddingInputDigest, sha256Hex } from './snapshot';
import type { IndexDeps, IndexState, Snapshot } from './types';
import { policy } from '../types';
const count = (t: string) => Array.from(t).length;
const floats = [1, ...Array(policy.embedding.dimensions - 1).fill(0)];
function rig(empty = false) {
  let state: IndexState = { ownerId: 'alice', accountEpoch: 1,
    consent: { accepted: true, version: CONSENT_VERSION, generation: 1 }, manifest: null,
    notes: empty ? [] : [{ownerId:'alice',noteId:'one',title:'Việt Nam',content:'Mã SLGH031 có dự trữ 80 giờ.',
      revision:1,protectionRevision:0,synced:true,protected:false,deleted:false,available:true}] };
  const snapshot: Snapshot = { schemaVersion:1,ownerId:'alice',version:'v1',consentGeneration:1,accountEpoch:1,
    policyIdentity:policyIdentity(), documents:(state.notes.length ? chunkNote(state.notes[0],count) : []).map(chunk=>({chunk,
      vectorKey:sha256Hex(chunk.chunkId),embeddingDigest:embeddingInputDigest(chunk.title,chunk.text)})) };
  state = {...state,manifest:{ownerId:'alice',generation:1,version:'v1',fingerprint:fingerprint(state),
    consentGeneration:1,accountEpoch:1,status:'READY',snapshotKey:'test',checksum:checksum(snapshot),policyIdentity:policyIdentity()}};
  let paid=0, reads=0, embedded=0, hook:(()=>void)|null=null;
  const texts: string[] = [];
  const deps: IndexDeps = {store:{load:async()=>structuredClone(state),acquire:async()=>null,publish:async()=>false,
    finish:async()=>{}, reserveEmbedding:async()=>{paid++;}}, embedding:{count,embed:async(input)=>{
      embedded++; texts.push(...input); hook?.(); return [floats];}},artifacts:{read:async()=>{reads++;return snapshot;},
      put:async()=>({key:'test',checksum:checksum(snapshot)}),putVectors:async()=>{},cleanup:async()=>{},
      query:async()=>[],getVectors:async keys=>new Map(keys.map(k=>[k,floats]))}};
  return {run:createRetrievalProbe(deps),state:()=>state,set:(s:IndexState)=>{state=s;},
    calls:()=>({paid,reads,embedded}),texts:()=>texts,afterEmbedding:(fn:()=>void)=>{hook=fn;}};
}
const body=JSON.stringify({wireVersion:1,question:'SLGH031',scope:{type:'account'}});
test('cold/warm snapshot retrieval includes lexical-only passage with no reranker call',async()=>{
  const r=rig(); const result=await r.run('alice',body);
  assert.equal(result.anchors.length,1);assert.equal(result.vectorKeys.length,0);
  assert.equal(result.keywordChunkIds.length,1); await r.run('alice',body);
  assert.deepEqual(r.calls(),{paid:2,reads:1,embedded:2});
  assert.deepEqual(r.texts(),[queryEmbeddingText('SLGH031'),queryEmbeddingText('SLGH031')]);
});
test('the framed query, not the raw question, is bounded before any reservation',async()=>{
  const r=rig();
  const raw='a'.repeat(500);
  assert.ok(count(raw)<=MAX_EMBEDDING_TOKENS,'raw question is within the token cap');
  assert.ok(count(queryEmbeddingText(raw))>MAX_EMBEDDING_TOKENS,'the frame pushes it over');
  await assert.rejects(r.run('alice',JSON.stringify({wireVersion:1,question:raw,scope:{type:'account'}})),
    (error:unknown)=>(error as {code?:string}).code==='INPUT_TOO_LONG');
  assert.deepEqual(r.calls(),{paid:0,reads:1,embedded:0});
  assert.deepEqual(r.texts(),[]);
});
test('the probe preserves the raw question with exactly one frame',async()=>{
  const r=rig(); const raw='  SLGH031  ';
  await r.run('alice',JSON.stringify({wireVersion:1,question:raw,scope:{type:'account'}}));
  assert.deepEqual(r.texts(),[QUERY_PREFIX+raw]);
});
test('foreign actor and unavailable note scope cannot reach model',async()=>{
  const r=rig();await assert.rejects(r.run('bob',body));
  await assert.rejects(r.run('alice',JSON.stringify({wireVersion:1,question:'SLGH031',scope:{type:'note',noteId:'missing'}})));
  assert.equal(r.calls().paid,0);
});
test('revoke invalidates warm cache before provider egress',async()=>{
  const r=rig();await r.run('alice',body);const s=r.state();
  r.set({...s,consent:{...s.consent,accepted:false,generation:2}});
  await assert.rejects(r.run('alice',body));assert.equal(r.calls().paid,1);
});
test('protection change during embedding prevents evidence release',async()=>{
  const r=rig();r.afterEmbedding(()=>{const s=r.state();r.set({...s,accountEpoch:2,
    notes:s.notes.map(n=>({...n,protected:true,protectionRevision:1}))});});
  await assert.rejects(r.run('alice',body)); assert.equal(r.calls().embedded,1);
});

test('empty eligible corpus returns diagnostics with zero model/budget calls',async()=>{
  const r=rig(true);const result=await r.run('alice',body);
  assert.deepEqual(result.anchors,[]);assert.deepEqual(r.calls(),{paid:0,reads:1,embedded:0});
});
