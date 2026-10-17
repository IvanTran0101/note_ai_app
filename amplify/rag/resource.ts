import { defineFunction, secret } from '@aws-amplify/backend';

/**
 * Managed RAG Lambda: the Phase 5 HTTP entry routes `POST /ai/rag/query` and
 * `GET|PUT /ai/rag/consent`, and forwards a non-HTTP invocation unchanged to the
 * existing IAM-invoked Phase 4 private handler. No output is granted here.
 */
export const ragQuery = defineFunction({
  name: 'rag-query', resourceGroupName: 'rag', entry: './phase5/http_lambda.ts',
  runtime: 22, memoryMB: 512, timeoutSeconds: 28,
  environment: {
    DEEPSEEK_API_KEY: secret('DEEPSEEK_API_KEY'),
    TYPESAFE_API_KEY: secret('TYPESAFE_API_KEY'),
    // Cloudflare Access Service Auth for the self-hosted EmbeddingGemma endpoint. Amplify
    // resolves these server-side; no value reaches a client or the CDK template as plaintext.
    CLOUDFLARE_ACCESS_CLIENT_ID: secret('CLOUDFLARE_ACCESS_CLIENT_ID'),
    CLOUDFLARE_ACCESS_CLIENT_SECRET: secret('CLOUDFLARE_ACCESS_CLIENT_SECRET'),
  },
  logging: { retention: '1 week' },
});
