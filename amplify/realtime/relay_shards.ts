import { createHash } from 'node:crypto';
import type { TransactWriteCommandInput } from '@aws-sdk/lib-dynamodb';
import { MAX_EVENT_ACTORS } from '../sharing/actor_feed';
import type { RelayEvent } from './relay';

type Write = NonNullable<TransactWriteCommandInput['TransactItems']>[number];

/** Parent normalization pages stay inside DynamoDB's 100-item transaction cap. */
export const MAX_NORMALIZE_SHARDS = 99;
export const MAX_NORMALIZE_ACTORS = MAX_NORMALIZE_SHARDS * MAX_EVENT_ACTORS;

export const shardEventId = (parentEventId: string, shard: number): string => {
  const suffix = `-s${shard}`;
  if (parentEventId.length + suffix.length <= 50) return `${parentEventId}${suffix}`;
  return `e${createHash('sha256').update(`${parentEventId}/${shard}`).digest('hex').slice(0, 49)}`;
};

const chunks = <T>(items: readonly T[], size: number): T[][] => {
  const result: T[][] = [];
  for (let index = 0; index < items.length; index += size) result.push(items.slice(index, index + size));
  return result;
};

const childUpdate = (table: string, event: RelayEvent, actors: readonly string[], now: number, shard: number): Write => {
  const eventId = shardEventId(event.eventId, shard);
  return { Update: {
    TableName: table, Key: { ownerId: event.ownerId, noteId: `EVENT#${eventId}` },
    ConditionExpression: 'attribute_not_exists(noteId)',
    UpdateExpression: 'SET eventId = :eventId, canonicalOwnerId = :owner, targetNoteId = :target, ' +
      'revision = :revision, protectionRevision = :protectionRevision, sharingRevision = :sharingRevision, ' +
      'actors = :actors, relayStatus = :pending, relayQueue = :pending, relayDueAt = :now, ' +
      'nextAttemptAt = :now, attempts = :zero, splitFromEventId = :parent, createdAt = :createdAt',
    ExpressionAttributeValues: { ':eventId': eventId, ':owner': event.canonicalOwnerId,
      ':target': event.targetNoteId, ':revision': event.revision,
      ':protectionRevision': event.protectionRevision, ':sharingRevision': event.sharingRevision ?? 0,
      ':actors': [...actors], ':pending': 'pending', ':now': now, ':zero': 0,
      ':parent': event.eventId,
      ':createdAt': event.createdAt ?? new Date(now).toISOString() },
  } };
};

const parentUpdate = (table: string, event: RelayEvent, offset: number, nextOffset: number,
  now: number, leaseMs: number, final: boolean): Write => {
  // DynamoDB rejects unused expression-value bindings. Keep each page variant's
  // binding map disjoint with the expression branch that actually references it.
  const values: Record<string, unknown> = { ':pending': 'pending', ':lease': event.leaseId,
    ':offset': offset, ':next': nextOffset };
  if (final) values[':split'] = 'split';
  else values[':until'] = now + leaseMs;
  return {
    Update: {
      TableName: table, Key: { ownerId: event.ownerId, noteId: event.noteId },
      ConditionExpression: 'relayStatus = :pending AND leaseId = :lease AND ' +
        '(attribute_not_exists(splitOffset) OR splitOffset = :offset)',
      UpdateExpression: final
        ? 'SET relayStatus = :split, splitOffset = :next REMOVE relayQueue, relayDueAt, leaseId, leaseUntil'
        : 'SET relayStatus = :pending, splitOffset = :next, relayDueAt = :until, leaseId = :lease, leaseUntil = :until',
      ExpressionAttributeValues: values,
    },
  };
};

/** One Update-only page: at most 99 deterministic children plus the parent fence. */
export function normalizationPage(table: string, event: RelayEvent, offset: number,
  now: number, leaseMs: number): { writes: Write[]; nextOffset: number } {
  const end = Math.min(offset + MAX_NORMALIZE_ACTORS, event.actors.length);
  const shards = chunks(event.actors.slice(offset, end), MAX_EVENT_ACTORS);
  const firstShard = offset / MAX_EVENT_ACTORS;
  const writes: Write[] = shards.map((actors, index) =>
    childUpdate(table, event, actors, now, firstShard + index));
  writes.push(parentUpdate(table, event, offset, end, now, leaseMs, end >= event.actors.length));
  return { writes, nextOffset: end };
}
