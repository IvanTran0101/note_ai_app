import type { DynamoDBStreamEvent, DynamoDBBatchResponse, ScheduledEvent } from 'aws-lambda';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { DynamoNoteAcl } from '../sharing/dynamo_note_acl';
import { DynamoRelayStore } from './dynamo_relay_store';
import { AppSyncPublisher } from './appsync_publisher';
import { RevisionRelay } from './relay';

const db = DynamoDBDocumentClient.from(new DynamoDBClient({ region: process.env.NOTES_TABLE_REGION }));
const table = process.env.NOTES_TABLE_NAME!;
const acl = new DynamoNoteAcl(table, db);
const relay = new RevisionRelay(new DynamoRelayStore(table, db), {
  async read(actor, owner, note) {
    const s = await acl.read(actor, owner, note);
    return s?.status === 'active' ? s.accessRevision : null;
  },
}, new AppSyncPublisher(process.env.EVENT_HTTP_ENDPOINT!, process.env.NOTES_TABLE_REGION!));

export async function handler(event: DynamoDBStreamEvent | ScheduledEvent): Promise<DynamoDBBatchResponse> {
  if (!('Records' in event)) {
    await relay.recover();
    return { batchItemFailures: [] };
  }
  const failures: DynamoDBBatchResponse['batchItemFailures'] = [];
  for (const record of event.Records) {
    const ownerId = record.dynamodb?.Keys?.ownerId?.S;
    const noteId = record.dynamodb?.Keys?.noteId?.S;
    if (!ownerId || !noteId?.startsWith('EVENT#') || record.eventName === 'REMOVE') continue;
    try { await relay.deliver({ ownerId, noteId }); }
    catch { failures.push({ itemIdentifier: record.dynamodb!.SequenceNumber! }); }
  }
  return { batchItemFailures: failures };
}
