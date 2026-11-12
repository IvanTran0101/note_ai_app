import { GetCommand, type DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { labelSnapshot } from './label_models';
import { itemKey, ownerKeyOf } from '../sync/sync_store_codec';
import type { NoteSnapshot } from '../sync/sync_store_models';

/** Call only after read authorization; no full owner catalog is returned. */
export async function projectNoteLabels(client: DynamoDBDocumentClient, table: string,
    owner: string, note: NoteSnapshot, recipient = false): Promise<NoteSnapshot> {
  if (note.deletedAt !== null || note.contentAvailable === false) {
    return {...note, labelIds: [], labelProjections: []};
  }
  const rows = await Promise.all((note.labelIds ?? []).map(async id => {
    const result = await client.send(new GetCommand({TableName: table,
      Key: itemKey(ownerKeyOf(owner), `LABEL#${id}`), ConsistentRead: true}));
    return result.Item ? labelSnapshot(result.Item, owner) : null;
  }));
  const active = rows.filter(row => row !== null && row.deletedAt === null);
  return {...note, labelIds: recipient ? active.map(row => row!.id) : note.labelIds ?? [],
    labelProjections: active.map(row => ({id: row!.id, name: row!.name}))};
}
