import { RemovalPolicy, Stack } from 'aws-cdk-lib';
import { AttributeType, BillingMode, ProjectionType, Table } from 'aws-cdk-lib/aws-dynamodb';

/**
 * NoteFlow remote sync table (M1.2 persistence slice A).
 *
 * One owner-scoped table for the contract frozen in `docs/sync_api_contract.md`.
 * Items are addressed by `ownerId` (the Cognito `sub` taken from the verified
 * JWT) and `noteId`, and the sort-key prefix tells the item roles apart:
 *
 * - `META#SYNC`          one per account: `lastSequence`, the account's change
 *                        counter. Every applied mutation takes the next number.
 * - `NOTE#<noteId>`      the current note snapshot, or its tombstone.
 * - `MUTATION#<id>`      the idempotency record of one applied mutation.
 * - `CHANGE#<sequence>`  the change-feed row for one applied mutation: a full
 *                        snapshot or tombstone, copied at apply time.
 *
 * The change feed is the `ChangesByOwnerSequence` GSI. Only `CHANGE#` items
 * carry `changeOwnerId`/`changeSequence`, so the index is sparse and holds
 * exactly one row per applied mutation: the live `NOTE#` item must never carry
 * those attributes, or a single change would be listed twice under one
 * sequence. The cursor the API returns stays opaque to clients; the codec that
 * mints and validates it is `amplify/sync/cursor.ts`, and the store that reads
 * this index is `amplify/sync/dynamo_sync_store.ts` - that file repeats the
 * index name as a runtime constant, because the Lambda cannot import CDK code.
 *
 * Development sandbox settings: on-demand billing, and the table goes away with
 * the stack so the `noteflow-dev` sandbox tears down without leftovers.
 * Production hardening (retain, point-in-time recovery, deletion protection)
 * belongs to the deployment slice.
 *
 * TTL cleans up grant/challenge/rate-limit records. Note and change rows have
 * no TTL; security checks always compare the server clock before access.
 */
export const createNotesTable = (stack: Stack): Table => {
  const table = new Table(stack, 'NotesTable', {
    partitionKey: { name: 'ownerId', type: AttributeType.STRING },
    sortKey: { name: 'noteId', type: AttributeType.STRING },
    billingMode: BillingMode.PAY_PER_REQUEST,
    timeToLiveAttribute: 'ttl',
    removalPolicy: RemovalPolicy.DESTROY,
  });

  // `ProjectionType.ALL` on purpose: the change feed hands callers the whole
  // snapshot or tombstone, so a keys-only index would only add read-after-write
  // gaps and a second read per change.
  table.addGlobalSecondaryIndex({
    indexName: 'ChangesByOwnerSequence',
    partitionKey: { name: 'changeOwnerId', type: AttributeType.STRING },
    sortKey: { name: 'changeSequence', type: AttributeType.NUMBER },
    projectionType: ProjectionType.ALL,
  });

  return table;
};
