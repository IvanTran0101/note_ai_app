import {runtime} from './runtime';
import {createRetrievalProbe} from './probe';
import {createProbeHandler} from './entrypoints';
let handle:ReturnType<typeof createProbeHandler>|undefined;
export async function handler(event:unknown){
  handle??=createProbeHandler(createRetrievalProbe(runtime()));
  return handle(event);
}
