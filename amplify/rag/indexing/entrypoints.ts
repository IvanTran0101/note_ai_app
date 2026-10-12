import type {DynamoDBStreamEvent} from 'aws-lambda';
import {createStreamHandler,runManualJob} from './stream';
import {jobsFromStream,parseJob} from './jobs';
import {isValidIdentifier} from '../contract';
import {IndexFailure} from './types';
import type {IndexWorker} from './worker';
export const SMOKE_OWNER_PREFIX='rag-smoke-';
const record=(value:unknown):value is Record<string,unknown>=>!!value&&typeof value==='object'&&!Array.isArray(value);
const smokeOwner=(owner:unknown):owner is string=>isValidIdentifier(owner)&&owner.startsWith(SMOKE_OWNER_PREFIX);
const keys=(value:Record<string,unknown>,allowed:string[])=>Object.keys(value).length===allowed.length&&allowed.every(k=>Object.hasOwn(value,k));
export function createWorkerHandler(worker:IndexWorker,streamArn:string,
  recover:(owner:string,signal:AbortSignal)=>Promise<unknown>) {
  const stream=createStreamHandler(worker,metadata=>console.log(JSON.stringify(metadata)));
  return async(event:unknown)=>{
    if(!record(event))throw new IndexFailure('INVALID_JOB');
    if(Array.isArray(event.Records)){
      if(event.Records.some(r=>!record(r)||r.eventSourceARN!==streamArn||r.eventSource!=='aws:dynamodb'))throw new IndexFailure('UNTRUSTED_STREAM');
      const typed=event as unknown as DynamoDBStreamEvent;
      if(jobsFromStream(typed).some(j=>!smokeOwner(j.ownerId)))throw new IndexFailure('SYNTHETIC_ONLY');
      return stream(typed);
    }
    if(event.operation==='reconcile'&&keys(event,['operation','job'])){
      const job=parseJob(event.job);
      if(!smokeOwner(job.ownerId))throw new IndexFailure('SYNTHETIC_ONLY');
      return runManualJob(worker,job);
    }
    if(event.operation==='recover'&&keys(event,['operation','ownerId'])&&smokeOwner(event.ownerId))
      return recover(event.ownerId,AbortSignal.timeout(110_000));
    throw new IndexFailure('INVALID_JOB');
  };
}
export function createProbeHandler(probe:(owner:string,body:string)=>Promise<unknown>){
  return async(event:unknown)=>{
    if(!record(event)||!keys(event,['operation','ownerId','body'])||event.operation!=='retrieve'
      ||!smokeOwner(event.ownerId)||typeof event.body!=='string')throw new IndexFailure('SYNTHETIC_ONLY');
    return probe(event.ownerId,event.body);
  };
}
