import { defineFunction, secret } from '@aws-amplify/backend';

/** IAM-invoked synthetic Phase4 only. No HTTP route or Flutter output is created. */
export const ragQuery = defineFunction({
  name: 'rag-query', resourceGroupName: 'rag', entry: './private_lambda.ts',
  runtime: 22, memoryMB: 512, timeoutSeconds: 28,
  environment: {
    DEEPSEEK_API_KEY: secret('DEEPSEEK_API_KEY'),
    TYPESAFE_API_KEY: secret('TYPESAFE_API_KEY'),
  },
  logging: { retention: '1 week' },
});
