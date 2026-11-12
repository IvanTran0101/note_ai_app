import { defineFunction, secret } from '@aws-amplify/backend';

/**
 * Summary Cloud Lambda declaration for `POST /ai/summary`.
 *
 * This file only declares how Amplify builds and runs `lambda.ts`; it wires no
 * API and no table. `createSummaryInfrastructure` in `infrastructure.ts`
 * completes the composition in the same stack as this managed function: the
 * quota table, its name in the environment, and separate quota and canonical-note authority permissions.
 *
 * `DEEPSEEK_API_KEY` is a SECRET REFERENCE, not a value. `secret(...)` records
 * the SSM parameter path and Amplify injects the resolved value into the
 * function's environment in memory at runtime initialization (a custom `NodejsFunction`
 * does not support this secret configuration, which is why the function is
 * declared here). Nothing in this repository reads, prints, or defaults the
 * key, and no key value belongs in source or in this declaration.
 *
 * 28 s timeout: a 26 s request bound covers authority, quota and output.
 * The provider receives at most 15 s, shortened to reserve authorized release;
 * the quota check is bounded at 5 s. The invocation
 * finishes before the API integration's timeout (30 s, with a scoped CDK escape hatch; see
 * `infrastructure.ts`).
 *
 * Log retention is bounded to 14 days. The handler logs metadata only -
 * request id, stage, latency, usage, error code - never a JWT, the key, note
 * inputs, or summary text.
 */
export const summary = defineFunction({
  name: 'summary',
  resourceGroupName: 'summary',
  entry: './lambda.ts',
  runtime: 22,
  timeoutSeconds: 28,
  environment: {
    DEEPSEEK_API_KEY: secret('DEEPSEEK_API_KEY'),
  },
  logging: {
    retention: '2 weeks',
  },
});
