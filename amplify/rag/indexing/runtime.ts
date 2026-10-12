import {createIndexStore} from './store';
import {createArtifacts} from './artifacts';
import {createEmbedding} from './embedding';
import {loadTokenCounter} from './tokenizer';
import {IndexFailure} from './types';
export function runtime(){
  const required=(name:string)=>{const value=process.env[name];if(!value)throw new IndexFailure('INVALID_STATE');return value;};
  const region=required('RAG_REGION'),notesTable=required('RAG_NOTES_TABLE'),stateTable=required('RAG_STATE_TABLE');
  const snapshotBucket=required('RAG_SNAPSHOT_BUCKET');
  return {region,stateTable,snapshotBucket,
    store:createIndexStore({region,notesTable,stateTable}),
    artifacts:createArtifacts({region,snapshotBucket,vectorIndexArn:required('RAG_VECTOR_INDEX_ARN')}),
    embedding:createEmbedding(region,loadTokenCounter(required('RAG_TOKENIZER_DIR'))),
    log:(metadata:Readonly<Record<string,string|number>>)=>console.log(JSON.stringify(metadata))};
}
