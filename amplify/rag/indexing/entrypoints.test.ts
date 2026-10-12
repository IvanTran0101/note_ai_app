import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createWorkerHandler,createProbeHandler} from './entrypoints';
import {JOB_POLICY_VERSION} from './types';
const job={jobVersion:1,kind:'RECONCILE_ACCOUNT',ownerId:'rag-smoke-alice',noteId:null,
  sourceRevisionHint:null,policyVersion:JOB_POLICY_VERSION,eventId:'manual-1'};
test('manual backfill uses normalized synthetic job; HTTP cannot select worker operation',async()=>{
  let calls=0;
  const run=createWorkerHandler(async()=>{calls++;return {status:'SUCCEEDED',code:'READY'};},'stream',async()=>({}));
  assert.deepEqual(await run({operation:'reconcile',job}),{status:'SUCCEEDED',code:'READY'});
  for(const event of [{operation:'reconcile',job:{...job,ownerId:'real-user'}},
    {operation:'reconcile',job,body:'untrusted'}, {body:'{}',requestContext:{authorizer:{}}}])
    await assert.rejects(run(event));
  assert.equal(calls,1);
});
test('stream must come from the configured ARN',async()=>{
  let calls=0;const run=createWorkerHandler(async()=>{calls++;return{status:'SUCCEEDED',code:'READY'};},'stream',async()=>({}));
  await assert.rejects(run({Records:[{eventSourceARN:'other',eventSource:'aws:dynamodb'}]}));
  assert.equal(calls,0);
});
test('internal probe rejects production owners and caller-selected authority',async()=>{
  let calls=0;const run=createProbeHandler(async()=>{calls++;return{};});
  await run({operation:'retrieve',ownerId:'rag-smoke-alice',body:'{}'});
  await assert.rejects(run({operation:'retrieve',ownerId:'alice',body:'{}'}));
  await assert.rejects(run({operation:'retrieve',ownerId:'rag-smoke-alice',body:'{}',actor:'alice'}));
  assert.equal(calls,1);
});
