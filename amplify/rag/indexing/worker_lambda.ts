import {runtime} from './runtime';
import {createIndexWorker} from './worker';
import {createWorkerDispatch,createWorkerHandler,resolveWorkerMode} from './entrypoints';
import {createRetirementRecovery,createOrphanRecovery,createCheckpointRecovery} from './recovery';
import {WORKER_MARGIN_MS,remainingUntil} from './stream';
import {createPilotWorkerHandler} from '../phase5/pilot_worker';
import {createRuntimeConfigReader} from '../phase5/runtime_config';
import {createPilotBudget} from '../phase5/pilot_budget';
import {IndexFailure,WORKER_MS} from './types';
import type {IndexStore} from './types';
import type {Context} from 'aws-lambda';

type Handler=(event:unknown,deadlineAt?:number)=>Promise<unknown>;

const isRecord=(value:unknown):value is Record<string,unknown>=>
  !!value&&typeof value==='object'&&!Array.isArray(value);

/**
 * Trusted invocation deadline (epoch ms), captured before any cold `runtime()` composition. With
 * no Lambda context it is the fixed 110s worker budget (the 120s cap less the 10s cutoff margin),
 * so the margin is subtracted exactly once, at capture, and cold setup/config time is charged to
 * it. With a context it is the context's remaining time minus the same margin, never above the
 * fixed cap. A context that reports a non-finite or non-positive remaining fails closed instead
 * of granting an unbounded window. The deadline is injected only through this trusted second
 * argument, never an event/body/settings value.
 */
export const invocationDeadlineFrom=(context:unknown,now:()=>number=Date.now):number=>{
  const at=now();
  if(!isRecord(context)||typeof context['getRemainingTimeInMillis']!=='function')
    return at+WORKER_MS-WORKER_MARGIN_MS;
  const remaining=(context as {getRemainingTimeInMillis:()=>unknown}).getRemainingTimeInMillis();
  if(typeof remaining!=='number'||!Number.isFinite(remaining)||remaining<=0)
    throw new IndexFailure('INVALID_STATE',false);
  return at+Math.max(0,Math.min(WORKER_MS,remaining)-WORKER_MARGIN_MS);
};

/** Exact legacy private-smoke composition: one raw store and the IAM manual reconcile/recover. */
const composePrivate=(deps:ReturnType<typeof runtime>,streamArn:string):Handler=>{
  const retired=createRetirementRecovery(deps.stateTable,deps.region,deps.store,deps.artifacts);
  const orphans=createOrphanRecovery(deps.snapshotBucket,deps.region,deps.store,deps.artifacts);
  const checkpoints=createCheckpointRecovery(deps.store,deps.artifacts);
  return createWorkerHandler(createIndexWorker(deps),streamArn,async(owner,signal)=>({
    retired:await retired(owner,signal),orphans:await orphans(owner,signal),
    checkpoints:await checkpoints(owner,signal)}));
};

/**
 * Pilot adapter composition. The raw runtime is cached here (SDK clients/tokenizers are safe to
 * reuse); the trusted config, guarded store and worker are rebuilt inside the handler on every
 * invocation. The private handler is retained only for exact-shape IAM manual
 * `reconcile`/`recover` of a `rag-smoke-` owner; streams and every other operation route to the
 * pilot adapter, so a stream can never fall back to the smoke-prefix path.
 */
const composePilot=(deps:ReturnType<typeof runtime>,streamArn:string):Handler=>{
  const configReader=createRuntimeConfigReader({region:deps.region,stateTable:deps.stateTable});
  const budget=createPilotBudget(deps.region,deps.stateTable);
  const pilot=createPilotWorkerHandler({
    readConfig:(signal)=>configReader.read(signal),
    runtime:()=>deps,
    budget,
    recover:async(owner:string,signal:AbortSignal,store:IndexStore)=>({
      retired:await createRetirementRecovery(deps.stateTable,deps.region,store,deps.artifacts)(owner,signal),
      orphans:await createOrphanRecovery(deps.snapshotBucket,deps.region,store,deps.artifacts)(owner,signal),
      checkpoints:await createCheckpointRecovery(store,deps.artifacts)(owner,signal)}),
    streamArn,
  });
  return createWorkerDispatch(composePrivate(deps,streamArn),pilot);
};

let handle:Handler|undefined;
export async function handler(event:unknown,context?:Context){
  // The one budget is captured before any cold runtime composition so setup/config time counts.
  const deadlineAt=invocationDeadlineFrom(context);
  // A trusted context already inside the cutoff margin (or the fallback after a slow import)
  // times out before the cold tokenizer/SDK composition starts; it never earns a fresh window.
  if(remainingUntil(deadlineAt)<=0)throw new IndexFailure('TIMEOUT',true);
  if(!handle){
    const mode=resolveWorkerMode(process.env['RAG_PILOT_PHASE5']);
    const deps=runtime();
    const streamArn=process.env.RAG_STREAM_ARN;if(!streamArn)throw Error('INVALID_STATE');
    handle=mode==='private'?composePrivate(deps,streamArn):composePilot(deps,streamArn);
  }
  // Cold composition is charged to the same budget: refuse dispatch once it is spent.
  if(remainingUntil(deadlineAt)<=0)throw new IndexFailure('TIMEOUT',true);
  return handle(event,deadlineAt);
}
