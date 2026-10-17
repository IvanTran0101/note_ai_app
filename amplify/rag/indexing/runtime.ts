import {createIndexStore} from './store';
import {createArtifacts} from './artifacts';
import {createSelfHostedEmbedding} from './self_hosted_embedding';
import {loadEmbeddingGemmaTokenCounter} from './tokenizer';
import {IndexFailure} from './types';
export function runtime(){
  const required=(name:string)=>{const value=process.env[name];if(!value||value.includes('<value will be resolved'))throw new IndexFailure('INVALID_STATE');return value;};
  const region=required('RAG_REGION'),notesTable=required('RAG_NOTES_TABLE'),stateTable=required('RAG_STATE_TABLE');
  const snapshotBucket=required('RAG_SNAPSHOT_BUCKET');
  // One EmbeddingGemma profile for worker, query and probe. Cloudflare Access secrets are injected
  // by the runtime (Amplify secret refs for the managed Lambda, the scoped fetcher for CDK
  // worker/probe); they are never read from the event or written to a log.
  return {region,stateTable,snapshotBucket,
    store:createIndexStore({region,notesTable,stateTable}),
    artifacts:createArtifacts({region,snapshotBucket,vectorIndexArn:required('RAG_VECTOR_INDEX_ARN')}),
    embedding:createSelfHostedEmbedding({
      clientId:required('CLOUDFLARE_ACCESS_CLIENT_ID'),
      clientSecret:required('CLOUDFLARE_ACCESS_CLIENT_SECRET'),
    },loadEmbeddingGemmaTokenCounter(required('RAG_TOKENIZER_DIR'))),
    log:(metadata:Readonly<Record<string,string|number>>)=>console.log(JSON.stringify(metadata))};
}
