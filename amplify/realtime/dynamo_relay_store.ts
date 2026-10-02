import { QueryCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import type { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { randomUUID } from 'node:crypto';
import type { RelayEvent, RelayKey, RelayStore } from './relay';

export const RELAY_INDEX = 'PendingRelays';
export const LEASE_MS = 120_000;
const channelActor = (x: unknown): x is string =>
  typeof x === 'string' && /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,48}[A-Za-z0-9])?$/.test(x);
export function decodeEvent(row: Record<string, unknown>): RelayEvent {
  if (!channelActor(row.canonicalOwnerId) || !channelActor(row.eventId) ||
      row.ownerId !== `OWNER#${row.canonicalOwnerId}` || row.noteId !== `EVENT#${row.eventId}` ||
      typeof row.targetNoteId !== 'string' || !row.targetNoteId || row.targetNoteId.length > 512 ||
      !Array.isArray(row.actors) || !row.actors.length || row.actors.length > 21 ||
      !row.actors.every(channelActor) || new Set(row.actors).size !== row.actors.length ||
      !['revision', 'protectionRevision', 'attempts'].every(k =>
        Number.isSafeInteger(row[k]) && Number(row[k]) >= 0) ||
      typeof row.leaseId !== 'string') throw new Error('Invalid relay intent');
  return row as unknown as RelayEvent;
}
const conditional = (e: unknown) => (e as { name?: string })?.name === 'ConditionalCheckFailedException';

export class DynamoRelayStore implements RelayStore {
  constructor(readonly table: string, readonly db: DynamoDBDocumentClient) {}
  async claim(key: RelayKey, now: number): Promise<RelayEvent | null> {
    try {
      const r = await this.db.send(new UpdateCommand({ TableName: this.table, Key: key,
        ConditionExpression: 'relayStatus = :pending AND relayDueAt <= :now AND (attribute_not_exists(leaseUntil) OR leaseUntil <= :now)',
        UpdateExpression: 'SET leaseId = :lease, leaseUntil = :until, relayDueAt = :until ADD attempts :one',
        ExpressionAttributeValues: { ':pending': 'pending', ':now': now,
          ':lease': randomUUID(), ':until': now + LEASE_MS, ':one': 1 },
        ReturnValues: 'ALL_NEW' }));
      return decodeEvent(r.Attributes ?? {});
    } catch (e) {
      if (conditional(e)) return null;
      throw e;
    }
  }
  async complete(event: RelayEvent, now: number): Promise<void> {
    await this.finish(event, 'done', { ':ttl': Math.floor(now / 1000) + 7 * 86400 },
      'SET relayStatus = :status, ttl = :ttl REMOVE relayQueue, relayDueAt, leaseId, leaseUntil');
  }
  async retry(event: RelayEvent, due: number, dead: boolean): Promise<void> {
    await this.finish(event, dead ? 'dead' : 'pending', dead ? {} : { ':due': due }, dead ?
      'SET relayStatus = :status REMOVE relayQueue, relayDueAt, leaseId, leaseUntil' :
      'SET relayStatus = :status, relayDueAt = :due, nextAttemptAt = :due REMOVE leaseId, leaseUntil');
  }
  private async finish(event: RelayEvent, status: string,
    values: Record<string, unknown>, expression: string): Promise<void> {
    try {
      await this.db.send(new UpdateCommand({ TableName: this.table,
        Key: { ownerId: event.ownerId, noteId: event.noteId },
        ConditionExpression: 'relayStatus = :pending AND leaseId = :lease',
        UpdateExpression: expression,
        ExpressionAttributeValues: { ':pending': 'pending', ':lease': event.leaseId,
          ':status': status, ...values } }));
    } catch (e) { if (!conditional(e)) throw e; }
  }
  async due(now: number, limit: number): Promise<RelayKey[]> {
    const keys: RelayKey[] = [];
    let start: Record<string, unknown> | undefined;
    do {
      const r = await this.db.send(new QueryCommand({ TableName: this.table,
        IndexName: RELAY_INDEX, KeyConditionExpression: 'relayQueue = :pending AND relayDueAt <= :now',
        ExpressionAttributeValues: { ':pending': 'pending', ':now': now },
        Limit: limit - keys.length, ExclusiveStartKey: start }));
      for (const item of r.Items ?? []) {
        // Keys-only candidates; claim is a conditional strong authority check.
        if (typeof item.ownerId === 'string' && typeof item.noteId === 'string' &&
            item.noteId.startsWith('EVENT#')) keys.push({ ownerId: item.ownerId, noteId: item.noteId });
      }
      start = r.LastEvaluatedKey;
    } while (start && keys.length < limit);
    return keys;
  }
}
