import { RemovalPolicy, Stack } from 'aws-cdk-lib';
import { AttributeType, BillingMode, Table } from 'aws-cdk-lib/aws-dynamodb';

/**
 * NoteFlow remote sync table (M1.1 skeleton).
 *
 * One owner-scoped table for the contract frozen in `docs/sync_api_contract.md`:
 * `ownerId` is the Cognito `sub` taken from the verified JWT, `noteId` addresses
 * one note, and every access is a key lookup on that pair. Items carry the
 * snapshot fields the handler will write from M1.2 on: title, content,
 * revision, createdAt, serverUpdatedAt, deletedAt (tombstone marker).
 *
 * Development sandbox settings: on-demand billing, and the table goes away with
 * the stack so the `noteflow-dev` sandbox tears down without leftovers.
 * Production hardening (retain, point-in-time recovery, deletion protection)
 * belongs to the deployment slice.
 *
 * No GSI and no stream: the DynamoDB change-feed/cursor strategy is still the
 * open M1.1 backend decision (RISK-0034), and Application keeps the cursor
 * opaque either way.
 */
export const createNotesTable = (stack: Stack): Table =>
  new Table(stack, 'NotesTable', {
    partitionKey: { name: 'ownerId', type: AttributeType.STRING },
    sortKey: { name: 'noteId', type: AttributeType.STRING },
    billingMode: BillingMode.PAY_PER_REQUEST,
    removalPolicy: RemovalPolicy.DESTROY,
  });
