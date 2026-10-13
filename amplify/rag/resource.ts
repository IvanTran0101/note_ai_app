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
  },
  logging: { retention: '1 week' },
});
