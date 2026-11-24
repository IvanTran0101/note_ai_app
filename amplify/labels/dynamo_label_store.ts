import {GetCommand,TransactWriteCommand} from '@aws-sdk/lib-dynamodb';
import type {DynamoDBDocumentClient,TransactWriteCommandInput} from '@aws-sdk/lib-dynamodb';
import {TransactionCanceledException} from '@aws-sdk/client-dynamodb';
import {SyncInvalidMutationError,SyncStorageError} from '../sync/sync_store_models';
import {itemKey,ownerKeyOf,isRetryableCancellation,toStorageError} from '../sync/sync_store_codec';
import {labelSnapshot} from './label_models';
import type {LabelMutation,LabelSnapshot} from './label_models';

export type LabelResult = Readonly<{wireVersion:2;entityType:'label';mutationId:string}>&(
  Readonly<{status:'applied';label:LabelSnapshot;replayed:boolean}>|
  Readonly<{status:'conflict';remoteLabel:LabelSnapshot|null}>);

/** Catalog writes share the existing actor META#SYNC counter and feed. */
export class DynamoLabelStore {
  constructor(readonly table:string,readonly db:DynamoDBDocumentClient){}
  async item(owner:string,sort:string) {
    return (await this.db.send(new GetCommand({TableName:this.table,
      Key:itemKey(ownerKeyOf(owner),sort),ConsistentRead:true}))).Item??null;
  }
  async read(owner:string,id:string) {
    const row=await this.item(owner,`LABEL#${id}`);
    return row?labelSnapshot(row,owner):null;
  }
  async apply(owner:string,r:LabelMutation):Promise<LabelResult> {
    for(let retry=0;retry<4;retry++) {
      const [remote,receipt,meta]=await Promise.all([this.read(owner,r.labelId),
        this.item(owner,`LABELMUTATION#${r.mutationId}`),this.item(owner,'META#SYNC')]);
      const common={wireVersion:2 as const,entityType:'label' as const,mutationId:r.mutationId};
      if(receipt) {
        if(receipt.fingerprint!==r.fingerprint) throw new SyncInvalidMutationError('MUTATION_ID_REUSED','Label mutation ID reused.');
        return {...common,status:'applied',label:labelSnapshot(receipt.resultLabel as Record<string,unknown>,owner),replayed:true};
      }
      if((remote?.revision??0)!==r.baseRevision || (r.operation==='create'?remote!==null:remote===null||remote.deletedAt!==null)) {
        return {...common,status:'conflict',remoteLabel:remote};
      }
      const seen=meta?.lastSequence??0;
      if(!Number.isSafeInteger(seen)||seen<0) throw new SyncStorageError('Invalid actor feed.',{retryable:false});
      const now=new Date().toISOString();
      const label:LabelSnapshot={id:r.labelId,ownerId:owner,name:r.name??remote!.name,
        revision:r.baseRevision+1,createdAt:remote?.createdAt??now,
        serverUpdatedAt:now,deletedAt:r.operation==='delete'?now:null};
      const row={...label,canonicalOwnerId:owner};
      const ownerKey=ownerKeyOf(owner);
      const writes:NonNullable<TransactWriteCommandInput['TransactItems']>=[
        {Update:{TableName:this.table,Key:itemKey(ownerKey,'META#SYNC'),
          UpdateExpression:'SET lastSequence = :next',
          ConditionExpression:'attribute_not_exists(lastSequence) OR lastSequence = :seen',
          ExpressionAttributeValues:{':next':seen+1,':seen':seen}}},
        {Put:{TableName:this.table,Item:{...row,...itemKey(ownerKey,`LABEL#${r.labelId}`)},
          ConditionExpression:remote?'revision = :revision AND deletedAt = :active':'attribute_not_exists(noteId)',
          ...(remote?{ExpressionAttributeValues:{':revision':remote.revision, ':active':null}}:{})}},
        {Put:{TableName:this.table,Item:{...row,...itemKey(ownerKey,`CHANGE#${seen+1}`),entityType:'label',
          changeOwnerId:ownerKey,changeSequence:seen+1}}},
        {Put:{TableName:this.table,Item:{...itemKey(ownerKey,`LABELMUTATION#${r.mutationId}`),
          fingerprint:r.fingerprint,resultLabel:row},ConditionExpression:'attribute_not_exists(noteId)'}},
      ];
      try {
        await this.db.send(new TransactWriteCommand({TransactItems:writes}));
        return {...common,status:'applied',label,replayed:false};
      } catch(error) {
        if(error instanceof TransactionCanceledException&&isRetryableCancellation(error)) continue;
        throw toStorageError(error);
      }
    }
    throw new SyncStorageError('Catalog contention.',{retryable:true});
  }
}
