import {runtime} from './runtime';
import {createIndexWorker} from './worker';
import {createWorkerHandler} from './entrypoints';
import {createRetirementRecovery,createOrphanRecovery} from './recovery';
let handle:ReturnType<typeof createWorkerHandler>|undefined;
export async function handler(event:unknown){
  if(!handle){
    const deps=runtime();
    const retired=createRetirementRecovery(deps.stateTable,deps.region,deps.store,deps.artifacts);
    const orphans=createOrphanRecovery(deps.snapshotBucket,deps.region,deps.store,deps.artifacts);
    const streamArn=process.env.RAG_STREAM_ARN;if(!streamArn)throw Error('INVALID_STATE');
    handle=createWorkerHandler(createIndexWorker(deps),streamArn,async(owner,signal)=>({
      retired:await retired(owner,signal),orphans:await orphans(owner,signal)}));
  }
  return handle(event);
}
