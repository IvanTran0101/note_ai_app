import type { APIGatewayProxyHandlerV2WithJWTAuthorizer } from 'aws-lambda';
import { createDeepSeekProvider } from './deepseek_client';
import { DynamoSummaryQuota } from './quota';
import { createSummaryHandler } from './summary_handler';

declare const process: { env: Record<string, string | undefined>; };

let quota: DynamoSummaryQuota | undefined;
let quotaTable: string | undefined;
// Amplify leaves this placeholder when its runtime resolver finds no secret value.
const UNRESOLVED_SECRET = '<value will be resolved during runtime>';

const unconfiguredResponse = () => ({
  statusCode: 500,
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ error: { code: 'unexpected' }, requestId: crypto.randomUUID() }),
});

/** Read the current key each invocation: Amplify refreshes secrets in warm containers. */
export const handler: APIGatewayProxyHandlerV2WithJWTAuthorizer = async (event) => {
  const apiKey = process.env.DEEPSEEK_API_KEY?.trim();
  const tableName = process.env.SUMMARY_QUOTA_TABLE_NAME?.trim();
  if (!apiKey || apiKey === UNRESOLVED_SECRET || !tableName) {
    console.error('summary function misconfigured', { code: 'unexpected' });
    return unconfiguredResponse();
  }
  try {
    if (!quota || quotaTable !== tableName) {
      quota = new DynamoSummaryQuota({ tableName });
      quotaTable = tableName;
    }
    const currentQuota = quota;
    const inner = createSummaryHandler({
      generate: createDeepSeekProvider({ apiKey }),
      consumeQuota: (accountId, nowMs) => currentQuota.consume(accountId, nowMs),
    });
    return await inner(event);
  } catch {
    console.error('summary function composition failed', { code: 'unexpected' });
    return unconfiguredResponse();
  }
};
