import type { Context } from 'aws-lambda';
import type { DynamoDBStreamEvent, DynamoDBBatchResponse, ScheduledEvent } from 'aws-lambda';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { DynamoNoteAcl } from '../sharing/dynamo_note_acl';
import { DynamoRelayStore } from './dynamo_relay_store';
import { AppSyncPublisher } from './appsync_publisher';
import { RevisionRelay } from './relay';
import type { RelayBudget } from './budget';
import { InvocationBudget } from './budget';
import type { RelayKey } from './relay';

export interface RelayRunner {
  deliver(key: RelayKey, budget?: RelayBudget): Promise<void>;
  recover(budget?: RelayBudget): Promise<void>;
}

let productionRelay: RevisionRelay | undefined;
function relay(): RevisionRelay {
  if (productionRelay) return productionRelay;
  const db = DynamoDBDocumentClient.from(new DynamoDBClient({ region: process.env.NOTES_TABLE_REGION }));
  const table = process.env.NOTES_TABLE_NAME!;
  const acl = new DynamoNoteAcl(table, db);
  return productionRelay = new RevisionRelay(new DynamoRelayStore(table, db), {
    async read(actor, owner, note, signal) {
      const s = await acl.read(actor, owner, note, signal);
      return s?.status === 'active' ? s.accessRevision : null;
    },
  }, new AppSyncPublisher(process.env.EVENT_HTTP_ENDPOINT!, process.env.NOTES_TABLE_REGION!));
}

async function run(runner: RelayRunner, event: DynamoDBStreamEvent | ScheduledEvent,
  context?: Context, clock = Date.now): Promise<DynamoDBBatchResponse> {
  const budget = context ? new InvocationBudget(clock, () => context.getRemainingTimeInMillis()) : undefined;
  if (!('Records' in event)) {
    await runner.recover(budget);
    return { batchItemFailures: [] };
  }
  const failures: DynamoDBBatchResponse['batchItemFailures'] = [];
  for (const record of event.Records) {
    const ownerId = record.dynamodb?.Keys?.ownerId?.S;
    const noteId = record.dynamodb?.Keys?.noteId?.S;
    const sequence = record.dynamodb?.SequenceNumber;
    if (!ownerId || !noteId?.startsWith('EVENT#') || record.eventName === 'REMOVE' || !sequence) continue;
    if (budget?.expired()) { failures.push({ itemIdentifier: sequence }); continue; }
    try { await runner.deliver({ ownerId, noteId }, budget); }
    catch { failures.push({ itemIdentifier: sequence }); }
  }
  return { batchItemFailures: failures };
}

export function createHandler(runner: RelayRunner, clock = Date.now) {
  return (event: DynamoDBStreamEvent | ScheduledEvent, context?: Context) => run(runner, event, context, clock);
}

export async function handler(event: DynamoDBStreamEvent | ScheduledEvent,
  context?: Context): Promise<DynamoDBBatchResponse> {
  return run(relay(), event, context);
}
