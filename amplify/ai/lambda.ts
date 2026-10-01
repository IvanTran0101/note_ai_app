import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { DynamoProtectionStore } from '../protection/dynamo_protection_store';
import { ProtectionAuthorizer } from '../protection/authorizer';
import { OwnerNoteAcl } from '../protection/protection_store';
import { DynamoSummaryNoteAuthority } from './summary_note_authority';
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
  const notesTable = process.env.NOTES_TABLE_NAME?.trim();
  if (!notesTable || !apiKey || apiKey === UNRESOLVED_SECRET || !tableName) {
    console.error('summary function misconfigured', { code: 'unexpected' });
    return unconfiguredResponse();
  }
  try {
    if (!quota || quotaTable !== tableName) {
      quota = new DynamoSummaryQuota({ tableName });
      quotaTable = tableName;
    }
    const currentQuota = quota;
    const db = DynamoDBDocumentClient.from(new DynamoDBClient({ maxAttempts: 1 }),
      { marshallOptions: { removeUndefinedValues: true } });
    const store = new DynamoProtectionStore(notesTable, db);
    const authority = new DynamoSummaryNoteAuthority(notesTable, db, store,
      new ProtectionAuthorizer(store, new OwnerNoteAcl()));
    const inner = createSummaryHandler({
      generate: createDeepSeekProvider({ apiKey, timeoutMs: 15_000 }),
      security: authority,
      consumeQuota: (accountId, nowMs) => currentQuota.consume(accountId, nowMs),
    });
    return await inner(event);
  } catch {
    console.error('summary function composition failed', { code: 'unexpected' });
    return unconfiguredResponse();
  }
};
