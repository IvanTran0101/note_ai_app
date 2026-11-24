import { stableDigest } from '../sync/cursor';
import { SyncInvalidMutationError } from '../sync/sync_store_models';
export type LabelSnapshot = Readonly<{id:string;ownerId:string;name:string;
  revision:number;createdAt:string;serverUpdatedAt:string;deletedAt:string|null}>;
export type LabelMutation = Readonly<{mutationId:string;labelId:string;
  operation:'create'|'update'|'delete';baseRevision:number;name?:string;fingerprint:string}>;
const invalid = ():never => {throw new SyncInvalidMutationError('PAYLOAD_INVALID','Invalid label contract.');};
export function labelId(raw:unknown):string {
  if(typeof raw!=='string'||!raw.trim()||raw.length>128||/[\u0000-\u001f\u007f]/.test(raw)) return invalid();
  return raw;
}
export function labelName(raw:unknown):string {
  if(typeof raw!=='string') return invalid();
  const value=raw.trim();
  if(!value||[...value].length>64||/[\u0000-\u001f\u007f]/.test(value)) return invalid();
  return value;
}
export function labelIds(raw:unknown):readonly string[] {
  if(!Array.isArray(raw)||raw.length>32) return invalid();
  const ids=raw.map(labelId).sort();
  if(new Set(ids).size!==ids.length) return invalid();
  return ids;
}
export function parseLabelMutation(raw:unknown):LabelMutation {
  if(!raw||typeof raw!=='object'||Array.isArray(raw)) return invalid();
  const r=raw as Record<string,unknown>;
  if(r.wireVersion!==2||r.entityType!=='label'||'ownerId'in r||'noteId'in r||
      'accessRevision'in r||'protectionChange'in r) return invalid();
  const mutationId=labelId(r.mutationId),id=labelId(r.labelId),operation=r.operation;
  if(operation!=='create'&&operation!=='update'&&operation!=='delete') return invalid();
  if(!Number.isSafeInteger(r.baseRevision)||(r.baseRevision as number)<0) return invalid();
  const name=operation==='delete'?undefined:labelName((r.payload as Record<string,unknown>|undefined)?.name);
  return {mutationId,labelId:id,operation,baseRevision:r.baseRevision as number,
    ...(name===undefined?{}:{name}),
    fingerprint:stableDigest(`v2:label:${JSON.stringify([id,operation,r.baseRevision,name??null])}`)};
}
export function labelSnapshot(raw:Record<string,unknown>,owner:string):LabelSnapshot {
  if(raw.canonicalOwnerId!==owner||!Number.isSafeInteger(raw.revision)||(raw.revision as number)<1||
      !Number.isFinite(Date.parse(raw.createdAt as string))||
      !Number.isFinite(Date.parse(raw.serverUpdatedAt as string))||
      raw.deletedAt!==null&&!Number.isFinite(Date.parse(raw.deletedAt as string))) return invalid();
  return {id:labelId(raw.id),ownerId:owner,name:labelName(raw.name),revision:raw.revision as number,
    createdAt:raw.createdAt as string,serverUpdatedAt:raw.serverUpdatedAt as string,
    deletedAt:raw.deletedAt as string|null};
}
