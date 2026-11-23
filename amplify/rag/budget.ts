import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import { RagFailure } from './types';

export const PHASE4_BUDGET_KEY = { ownerId: 'BUDGET#PHASE4', noteId: 'COUNTER' } as const;
export const CALL_LIMITS = { jev: 176, deepseek: 24, cohere: 8, query: 8 } as const;
export type BudgetProvider = keyof typeof CALL_LIMITS;
export type BudgetPort = { send(command: GetCommand | UpdateCommand, options: { abortSignal: AbortSignal }): Promise<any> };

/** Reservations include failed calls and are never refunded after uncertain network delivery. */
export function createPhase4Budget(region: string, table: string, supplied?: BudgetPort) {
  if (!/^[a-z]{2}-[a-z]+-\d$/.test(region) || !table) throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  const client = supplied ?? DynamoDBDocumentClient.from(new DynamoDBClient({ region, maxAttempts: 1 }));
  return {
    async reserve(provider: BudgetProvider, inputUpperBound: number, signal: AbortSignal): Promise<void> {
      if (!(provider in CALL_LIMITS) || !Number.isSafeInteger(inputUpperBound) || inputUpperBound < 0) {
        throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
      }
      // USD micros: official peak/cache-miss rates; provider usage is recorded separately.
      const micros = provider === 'jev' ? Math.ceil(inputUpperBound * .042)
        : provider === 'deepseek' ? Math.ceil(inputUpperBound * .3 + 1024 * 1.2) : 0;
      if (micros > 1_000_000) throw new RagFailure('RATE_LIMITED');
      if (signal.aborted) throw new RagFailure('TIMEOUT');
      try {
        await client.send(new UpdateCommand({ TableName: table, Key: PHASE4_BUDGET_KEY,
          UpdateExpression: 'SET #calls = if_not_exists(#calls, :zero) + :one, #usd = if_not_exists(#usd, :zero) + :cost',
          ConditionExpression: '(attribute_not_exists(#calls) OR (#calls >= :zero AND #calls < :limit)) AND (attribute_not_exists(#usd) OR (#usd >= :zero AND #usd <= :remaining))',
          ExpressionAttributeNames: { '#calls': `${provider}Calls`, '#usd': 'reservedUsdMicros' },
          ExpressionAttributeValues: { ':zero': 0, ':one': 1, ':limit': CALL_LIMITS[provider], ':cost': micros, ':remaining': 1_000_000 - micros },
        }), { abortSignal: signal });
      } catch (error) {
        if (signal.aborted) throw new RagFailure('TIMEOUT');
        if (error && typeof error === 'object' && 'name' in error && error.name === 'ConditionalCheckFailedException') {
          throw new RagFailure('RATE_LIMITED');
        }
        throw new RagFailure('PROVIDER_UNAVAILABLE');
      }
    },
    async read(signal: AbortSignal): Promise<Record<string, number>> {
      try {
        const result = await client.send(new GetCommand({ TableName: table, Key: PHASE4_BUDGET_KEY, ConsistentRead: true }), { abortSignal: signal });
        const out: Record<string, number> = {};
        for (const name of ['jevCalls', 'deepseekCalls', 'cohereCalls', 'queryCalls', 'reservedUsdMicros']) {
          const value = result.Item?.[name] ?? 0;
          if (!Number.isSafeInteger(value) || value < 0) throw new Error('invalid');
          out[name] = value;
        }
        return out;
      } catch {
        throw new RagFailure(signal.aborted ? 'TIMEOUT' : 'PROVIDER_UNAVAILABLE');
      }
    },
  };
}
