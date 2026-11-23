import {test} from 'node:test';
import assert from 'node:assert/strict';
import {
  PILOT_PHASE5_MODE,createProbeHandler,createWorkerDispatch,createWorkerHandler,resolveWorkerMode,
} from './entrypoints';
import {IndexFailure,JOB_POLICY_VERSION} from './types';
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
test('worker mode defaults to private and only the explicit pilot value is accepted',()=>{
  assert.equal(resolveWorkerMode(undefined),'private');
  assert.equal(resolveWorkerMode(PILOT_PHASE5_MODE),'pilot');
  for(const value of ['pilot','synthetic','SYNTHETIC-ONLY',''])
    assert.throws(()=>resolveWorkerMode(value),
      (error:unknown)=>error instanceof IndexFailure&&error.code==='INVALID_STATE');
});
test('pilot dispatch routes streams and non-smoke manual ops to the adapter, never a smoke fallback',async()=>{
  const privateCalls:unknown[]=[],pilotCalls:unknown[]=[];
  const dispatch=createWorkerDispatch(
    async(event)=>{privateCalls.push(event);return 'private';},
    async(event)=>{pilotCalls.push(event);return 'pilot';});
  const real='00000001-0000-4000-8000-000000000001';
  assert.equal(await dispatch({Records:[{eventSourceARN:'arn',eventSource:'aws:dynamodb'}]}),'pilot');
  assert.equal(await dispatch({operation:'reconcile',job:{...job,ownerId:'rag-smoke-alice'}}),'private');
  assert.equal(await dispatch({operation:'recover',ownerId:'rag-smoke-alice'}),'private');
  assert.equal(await dispatch({operation:'reconcile',job:{...job,ownerId:real}}),'pilot');
  assert.equal(await dispatch({operation:'recover',ownerId:real}),'pilot');
  // A smoke stream can never fall back through the private prefix path, and unknown/malformed
  // operations are never handed to the private handler as a synthetic bypass.
  assert.equal(await dispatch({Records:[{eventSourceARN:'arn',eventSource:'aws:dynamodb'}]}),'pilot');
  assert.equal(await dispatch({operation:'delete'}),'pilot');
  assert.equal(await dispatch({body:'{}'}),'pilot');
  assert.equal(privateCalls.length,2);
  assert.equal(pilotCalls.length,6);
});
test('dispatch construction validates both handlers',()=>{
  const isInvalid=(error:unknown)=>error instanceof IndexFailure&&error.code==='INVALID_STATE';
  assert.throws(()=>createWorkerDispatch(null as never,async()=>{}),isInvalid);
  assert.throws(()=>createWorkerDispatch(async()=>{},null as never),isInvalid);
});
test('legitimate private IAM manual reconcile/recover still works with no body widening',async()=>{
  const recovered:string[]=[];
  const run=createWorkerHandler(async()=>({status:'SUCCEEDED',code:'READY'}),'stream',
    async(owner)=>{recovered.push(owner);return{};});
  assert.deepEqual(await run({operation:'reconcile',job}),{status:'SUCCEEDED',code:'READY'});
  assert.deepEqual(await run({operation:'recover',ownerId:'rag-smoke-alice'}),{});
  assert.deepEqual(recovered,['rag-smoke-alice']);
  for(const event of [{operation:'reconcile',job:{...job,ownerId:'real-user'}},
    {operation:'reconcile',job,body:'{}'},{operation:'recover',ownerId:'real-user'},
    {body:'{}',requestContext:{authorizer:{jwt:{claims:{sub:'real-user'}}}}}])
    await assert.rejects(run(event));
});
test('dispatch forwards the trusted deadline only to the selected private/pilot handler',async()=>{
  const privateArgs:Array<number|undefined>=[],pilotArgs:Array<number|undefined>=[];
  const dispatch=createWorkerDispatch(
    async(_event,deadlineAt)=>{privateArgs.push(deadlineAt);return 'private';},
    async(_event,deadlineAt)=>{pilotArgs.push(deadlineAt);return 'pilot';});
  assert.equal(await dispatch({Records:[]},111),'pilot');
  assert.equal(await dispatch({operation:'recover',ownerId:'rag-smoke-alice'},222),'private');
  assert.deepEqual(pilotArgs,[111]);
  assert.deepEqual(privateArgs,[222]);
});
test('private manual reconcile receives the remaining invocation budget',async()=>{
  const original=Date.now;Date.now=()=>0;
  try{
    const seen:Array<number|undefined>=[];
    const run=createWorkerHandler(async(_job,remainingMs)=>{
      seen.push(remainingMs);return {status:'SUCCEEDED',code:'READY'};
    },'stream',async()=>({}));
    assert.deepEqual(await run({operation:'reconcile',job},7_000),{status:'SUCCEEDED',code:'READY'});
    assert.deepEqual(seen,[7_000]);
  }finally{Date.now=original;}
});
test('private recover uses the remaining timeout, never a fresh 110s window',async()=>{
  const signals:AbortSignal[]=[];
  const run=createWorkerHandler(async()=>({status:'SUCCEEDED',code:'READY'}),'stream',
    async(_owner,signal)=>{signals.push(signal);return{};});
  await run({operation:'recover',ownerId:'rag-smoke-alice'},Date.now()-1);
  await new Promise((resolve)=>setTimeout(resolve,5));
  assert.equal(signals.length,1);
  assert.equal(signals[0]?.aborted,true,'an expired invocation deadline aborts recovery instead of granting 110s');
});
test('a private handler deadline that is invalid fails closed',async()=>{
  const run=createWorkerHandler(async()=>({status:'SUCCEEDED',code:'READY'}),'stream',async()=>({}));
  await assert.rejects(run({operation:'reconcile',job},Number.NaN),
    (error:unknown)=>error instanceof IndexFailure&&error.code==='INVALID_STATE');
});
