/**
 * Focused checks for the DynamoDB change-feed cursor behavior. The injected
 * document client avoids AWS calls and simulates eventual GSI visibility.
 * Run with `npx tsx amplify/sync/dynamo_sync_store.test.ts`.
 */
import {
  GetCommand,
  QueryCommand,
  TransactWriteCommand,
  type DynamoDBDocumentClient,
} from '@aws-sdk/lib-dynamodb';

import { decodeChangeCursor } from './cursor';
import { DynamoSyncStore } from './dynamo_sync_store';

let passed = 0;

const check = async (name: string, run: () => Promise<void>): Promise<void> => {
  try {
    await run();
    passed += 1;
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
};

const assertEqual = <T>(actual: T, expected: T, label: string): void => {
  if (actual !== expected) {
    throw new Error(`${label}: expected ${String(expected)}, got ${String(actual)}`);
  }
};

const change = (sequence: number): Record<string, unknown> => ({
  changeSequence: sequence,
  id: `note-${sequence}`,
  title: `title-${sequence}`,
  content: `content-${sequence}`,
  revision: 1,
  createdAt: '2026-09-25T00:00:00.000Z',
  serverUpdatedAt: '2026-09-25T00:00:01.000Z',
  deletedAt: null,
});

const storeWithVisibleRows = (getRows: () => Record<string, unknown>[]): DynamoSyncStore => {
  const documentClient = {
    async send(command: unknown) {
      const input = (command as QueryCommand).input;
      const after = input.ExpressionAttributeValues?.[':after'] as number;
      return {
        Items: getRows().filter((row) => Number(row.changeSequence) > after),
      };
    },
  } as unknown as DynamoDBDocumentClient;
  return new DynamoSyncStore({ tableName: 'notes', documentClient });
};

const applyUpdate = async (pinnedAt?: string | null) => {
  const existingPin = '2026-09-25T09:00:00.000Z';
  let writtenPin: unknown;
  let transactions = 0;
  const remote = {
    id: 'note-1',
    title: 'Old title',
    content: 'Old body',
    revision: 4,
    createdAt: '2026-09-24T00:00:00.000Z',
    serverUpdatedAt: '2026-09-25T08:00:00.000Z',
    pinnedAt: existingPin,
    deletedAt: null,
  };
  const documentClient = {
    async send(command: unknown) {
      if (command instanceof GetCommand) {
        const sortKey = command.input.Key?.noteId;
        return sortKey === 'NOTE#note-1' ? { Item: remote } : {};
      }
      if (command instanceof TransactWriteCommand) {
        transactions++;
        const notePut = command.input.TransactItems?.find((item) =>
          (item.Put?.Item as Record<string, unknown> | undefined)?.noteId === 'NOTE#note-1',
        );
        writtenPin = (notePut?.Put?.Item as Record<string, unknown> | undefined)?.pinnedAt;
      }
      return {};
    },
  } as unknown as DynamoDBDocumentClient;
  const store = new DynamoSyncStore({ tableName: 'notes', documentClient });
  const result = await store.applyMutation('user-1', {
    mutationId: 'mutation-pin',
    noteId: 'note-1',
    operation: 'update',
    baseRevision: 4,
    payload: {
      title: 'New title',
      content: 'New body',
      ...(pinnedAt === undefined ? {} : { pinnedAt }),
    },
  });
  if (result.status !== 'applied') throw new Error('expected an applied update');
  return { note: result.note, writtenPin, transactions };
};

const main = async (): Promise<void> => {
  let visibleRows = [change(1), change(3), change(4)];
  const store = storeWithVisibleRows(() => visibleRows);

  await check('a GSI gap stops cursor advancement and a later poll recovers', async () => {
    const first = await store.listChanges('user-1', null, 50);
    assertEqual(first.items.length, 1, 'contiguous items before the gap');
    assertEqual(first.items[0]?.id, 'note-1', 'first item');
    assertEqual(decodeChangeCursor(first.nextCursor, 'user-1'), 1, 'cursor before gap');
    assertEqual(first.hasMore, false, 'a known gap stops this poll');

    visibleRows = [change(2), change(3), change(4)];
    const recovered = await store.listChanges('user-1', first.nextCursor, 50);
    assertEqual(recovered.items.length, 3, 'items after the missing row appears');
    assertEqual(decodeChangeCursor(recovered.nextCursor, 'user-1'), 4, 'recovered cursor');
  });

  visibleRows = [change(1), change(2), change(4)];
  await check('a gap beyond a full page still makes hasMore false', async () => {
    const page = await store.listChanges('user-2', null, 2);
    assertEqual(page.items.length, 2, 'full contiguous page');
    assertEqual(decodeChangeCursor(page.nextCursor, 'user-2'), 2, 'page cursor');
    assertEqual(page.hasMore, false, 'do not request past the known gap');
  });

  visibleRows = [change(1), change(2), change(3)];
  await check('ordinary contiguous pages keep pagination behavior', async () => {
    const first = await store.listChanges('user-3', null, 2);
    assertEqual(first.items.length, 2, 'first page size');
    assertEqual(first.hasMore, true, 'a contiguous extra row means more');
    assertEqual(decodeChangeCursor(first.nextCursor, 'user-3'), 2, 'first page cursor');

    const last = await store.listChanges('user-3', first.nextCursor, 2);
    assertEqual(last.items.length, 1, 'last page size');
    assertEqual(last.hasMore, false, 'last page status');
    assertEqual(decodeChangeCursor(last.nextCursor, 'user-3'), 3, 'last page cursor');
  });

  await check('an update without pinnedAt preserves the owner pin', async () => {
    const result = await applyUpdate();
    assertEqual(result.note.pinnedAt, '2026-09-25T09:00:00.000Z', 'returned pin');
    assertEqual(result.writtenPin, '2026-09-25T09:00:00.000Z', 'stored pin');
    assertEqual(result.transactions, 1, 'atomic transaction count');
  });

  await check('an explicit null pinnedAt unpins the owner note', async () => {
    const result = await applyUpdate(null);
    assertEqual(result.note.pinnedAt, null, 'returned pin');
    assertEqual(result.writtenPin, null, 'stored pin');
    assertEqual(result.transactions, 1, 'atomic transaction count');
  });
};

main().then(() => console.log(`${passed} DynamoSyncStore checks passed`));
