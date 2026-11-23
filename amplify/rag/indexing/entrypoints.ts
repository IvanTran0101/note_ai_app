import type {DynamoDBStreamEvent} from 'aws-lambda';
import {WORKER_MARGIN_MS,createStreamHandler,remainingUntil,runManualJob} from './stream';
import {jobsFromStream,parseJob} from './jobs';
import {isValidIdentifier} from '../contract';
import {IndexFailure,WORKER_MS} from './types';
import type {IndexWorker} from './worker';
export const SMOKE_OWNER_PREFIX='rag-smoke-';
/** The only non-default value that selects the pilot adapter; anything else fails closed. */
export const PILOT_PHASE5_MODE='synthetic-only';
export type WorkerMode='private'|'pilot';
const record=(value:unknown):value is Record<string,unknown>=>!!value&&typeof value==='object'&&!Array.isArray(value);
const smokeOwner=(owner:unknown):owner is string=>isValidIdentifier(owner)&&owner.startsWith(SMOKE_OWNER_PREFIX);
const keys=(value:Record<string,unknown>,allowed:string[])=>Object.keys(value).length===allowed.length&&allowed.every(k=>Object.hasOwn(value,k));

/**
 * `RAG_PILOT_PHASE5` is a mode selector, never a permit. Absent keeps the exact legacy
 * private-smoke handler; `synthetic-only` selects the pilot adapter, which still derives every
 * permission from the trusted config. Any other value is INVALID_STATE, not a fallback.
 */
export function resolveWorkerMode(value:string|undefined):WorkerMode{
  if(value===undefined)return 'private';
  if(value===PILOT_PHASE5_MODE)return 'pilot';
  throw new IndexFailure('INVALID_STATE');
}

/** The owner of one exact-shape manual operation, or null when it is not a trusted manual body. */
const manualOwner=(event:unknown):string|null=>{
  if(!record(event))return null;
  if(event.operation==='reconcile'&&keys(event,['operation','job'])){
    try{return parseJob(event.job).ownerId;}catch{return null;}
  }
  if(event.operation==='recover'&&keys(event,['operation','ownerId'])&&isValidIdentifier(event.ownerId))
    return event.ownerId;
  return null;
};

/**
 * Pilot-mode router. A stream batch always goes to the pilot adapter (no smoke-prefix stream
 * fallback); only a valid private IAM manual reconcile/recover for a `rag-smoke-` owner reaches
 * the existing handler. Every other invocation, including malformed/unknown operations, goes to
 * the pilot adapter, which rejects it rather than granting any synthetic bypass.
 */
export function createWorkerDispatch(
  privateHandler:(event:unknown,deadlineAt?:number)=>Promise<unknown>,
  pilotHandler:(event:unknown,deadlineAt?:number)=>Promise<unknown>,
):(event:unknown,deadlineAt?:number)=>Promise<unknown>{
  if(typeof privateHandler!=='function'||typeof pilotHandler!=='function')
    throw new IndexFailure('INVALID_STATE');
  return async(event:unknown,deadlineAt?:number)=>{
    if(record(event)&&Array.isArray(event.Records))return pilotHandler(event,deadlineAt);
    const owner=manualOwner(event);
    if(owner!==null&&smokeOwner(owner))return privateHandler(event,deadlineAt);
    return pilotHandler(event,deadlineAt);
  };
}
export function createWorkerHandler(worker:IndexWorker,streamArn:string,
  recover:(owner:string,signal:AbortSignal)=>Promise<unknown>) {
  const stream=createStreamHandler(worker,metadata=>console.log(JSON.stringify(metadata)));
  return async(event:unknown,deadlineAt?:number)=>{
    if(!record(event))throw new IndexFailure('INVALID_JOB');
    if(Array.isArray(event.Records)){
      if(event.Records.some(r=>!record(r)||r.eventSourceARN!==streamArn||r.eventSource!=='aws:dynamodb'))throw new IndexFailure('UNTRUSTED_STREAM');
      const typed=event as unknown as DynamoDBStreamEvent;
      if(jobsFromStream(typed).some(j=>!smokeOwner(j.ownerId)))throw new IndexFailure('SYNTHETIC_ONLY');
      return stream(typed,deadlineAt);
    }
    if(event.operation==='reconcile'&&keys(event,['operation','job'])){
      const job=parseJob(event.job);
      if(!smokeOwner(job.ownerId))throw new IndexFailure('SYNTHETIC_ONLY');
      return runManualJob(worker,job,undefined,deadlineAt);
    }
    if(event.operation==='recover'&&keys(event,['operation','ownerId'])&&smokeOwner(event.ownerId))
      return recover(event.ownerId,AbortSignal.timeout(
        deadlineAt===undefined?WORKER_MS-WORKER_MARGIN_MS:remainingUntil(deadlineAt)));
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
