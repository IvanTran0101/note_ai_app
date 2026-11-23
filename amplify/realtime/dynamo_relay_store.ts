import { GetCommand, QueryCommand, TransactWriteCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import type { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { randomUUID } from 'node:crypto';
import { MAX_EVENT_ACTORS } from '../sharing/actor_feed';
import type { RelayEvent, RelayKey, RelayStore } from './relay';
import { normalizationPage } from './relay_shards';

export const RELAY_INDEX = 'PendingRelays';
export const LEASE_MS = 120_000;
const channelActor = (x: unknown): x is string =>
  typeof x === 'string' && /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,48}[A-Za-z0-9])?$/.test(x);
/** Transaction reasons are only a CAS loss when every non-None reason is a condition refusal. */
const conditional = (e: unknown): boolean => {
  const name = (e as { name?: string })?.name;
  if (name === 'ConditionalCheckFailedException') return true;
  if (name !== 'TransactionCanceledException') return false;
  const reasons = (e as { CancellationReasons?: { Code?: unknown }[] }).CancellationReasons;
  if (!Array.isArray(reasons) || reasons.length === 0) return false;
  let sawConditional = false;
  for (const reason of reasons) {
    const code = reason?.Code;
    if (code === 'None') continue;
    if (code !== 'ConditionalCheckFailed') return false;
    sawConditional = true;
  }
  return sawConditional;
};
const validation = (e: unknown) => (e as { name?: string })?.name === 'ValidationException';
const options = (signal?: AbortSignal) => signal ? { abortSignal: signal } : undefined;

export function decodeEvent(row: Record<string, unknown>): RelayEvent {
  if (!channelActor(row.canonicalOwnerId) || !channelActor(row.eventId) ||
      row.ownerId !== `OWNER#${row.canonicalOwnerId}` || row.noteId !== `EVENT#${row.eventId}` ||
      typeof row.targetNoteId !== 'string' || !row.targetNoteId || row.targetNoteId.length > 512 ||
      !Array.isArray(row.actors) || !row.actors.length ||
      !row.actors.every(channelActor) || new Set(row.actors).size !== row.actors.length ||
      !['revision', 'protectionRevision', 'attempts'].every(k =>
        Number.isSafeInteger(row[k]) && Number(row[k]) >= 0) ||
      (row.sharingRevision !== undefined &&
        (!Number.isSafeInteger(row.sharingRevision) || Number(row.sharingRevision) < 0)) ||
      typeof row.leaseId !== 'string') throw new Error('Invalid relay intent');
  if (row.splitOffset !== undefined &&
      (!Number.isSafeInteger(row.splitOffset) || Number(row.splitOffset) < 0 ||
       Number(row.splitOffset) > row.actors.length || Number(row.splitOffset) % MAX_EVENT_ACTORS !== 0)) {
    throw new Error('Invalid relay split offset');
  }
  return row as unknown as RelayEvent;
}

/** Invalid rows are quarantined only after a fenced claim, never translated into a lease-lost retry. */
export class DynamoRelayStore implements RelayStore {
  constructor(readonly table: string, readonly db: DynamoDBDocumentClient) {}
  async claim(key: RelayKey, now: number, signal?: AbortSignal): Promise<RelayEvent | null> {
    const leaseId = randomUUID();
    const until = now + LEASE_MS;
    let attributes: Record<string, unknown> | undefined;
    try {
      const r = await this.db.send(new UpdateCommand({ TableName: this.table, Key: key,
        ConditionExpression: 'relayStatus = :pending AND relayDueAt <= :now AND (attribute_not_exists(leaseUntil) OR leaseUntil <= :now)',
        UpdateExpression: 'SET leaseId = :lease, leaseUntil = :until, relayDueAt = :until ADD attempts :one',
        ExpressionAttributeValues: { ':pending': 'pending', ':now': now,
          ':lease': leaseId, ':until': until, ':one': 1 },
        ReturnValues: 'ALL_NEW' }), options(signal));
      attributes = r.Attributes;
    } catch (error) {
      if (conditional(error)) return null;
      if (validation(error)) {
        const observed = await this.malformedAttempts(key, signal);
        if (observed) {
          // Fence the exact observed payload before quarantining, so a concurrent
          // repair or another worker's lease wins instead of being dead-lettered.
          if (await this.claimMalformed(key, now, leaseId, until, observed, signal)) {
            await this.quarantineClaimed(key, leaseId, signal);
          }
          return null;
        }
      }
      throw error;
    }
    let event: RelayEvent;
    try { event = decodeEvent(attributes ?? {}); }
    catch {
      await this.quarantineClaimed(key, leaseId, signal);
      return null;
    }
    if (event.actors.length > MAX_EVENT_ACTORS) {
      await this.normalize(event, now, signal);
      return null;
    }
    return event;
  }
  async complete(event: RelayEvent, now: number, signal?: AbortSignal): Promise<void> {
    await this.finish(event, 'done', { ':ttl': Math.floor(now / 1000) + 7 * 86400 },
      'SET relayStatus = :status, ttl = :ttl REMOVE relayQueue, relayDueAt, leaseId, leaseUntil', signal);
  }
  async retry(event: RelayEvent, due: number, dead: boolean, signal?: AbortSignal): Promise<void> {
    await this.finish(event, dead ? 'dead' : 'pending', dead ? {} : { ':due': due }, dead ?
      'SET relayStatus = :status REMOVE relayQueue, relayDueAt, leaseId, leaseUntil' :
      'SET relayStatus = :status, relayDueAt = :due, nextAttemptAt = :due REMOVE leaseId, leaseUntil', signal);
  }
  private async finish(event: RelayEvent, status: string,
    values: Record<string, unknown>, expression: string, signal?: AbortSignal): Promise<void> {
    try {
      await this.db.send(new UpdateCommand({ TableName: this.table,
        Key: { ownerId: event.ownerId, noteId: event.noteId },
        ConditionExpression: 'relayStatus = :pending AND leaseId = :lease',
        UpdateExpression: expression,
        ExpressionAttributeValues: { ':pending': 'pending', ':lease': event.leaseId,
          ':status': status, ...values } }), options(signal));
    } catch (e) { if (!conditional(e)) throw e; }
  }
  async due(now: number, limit: number, signal?: AbortSignal): Promise<RelayKey[]> {
    if (limit <= 0) return [];
    const keys: RelayKey[] = [];
    let start: Record<string, unknown> | undefined;
    do {
      signal?.throwIfAborted();
      const r = await this.db.send(new QueryCommand({ TableName: this.table,
        IndexName: RELAY_INDEX, KeyConditionExpression: 'relayQueue = :pending AND relayDueAt <= :now',
        ExpressionAttributeValues: { ':pending': 'pending', ':now': now },
        Limit: Math.max(1, limit - keys.length), ExclusiveStartKey: start }), options(signal));
      for (const item of r.Items ?? []) {
        // Keys-only candidates; claim is a conditional strong authority check.
        if (typeof item.ownerId === 'string' && typeof item.noteId === 'string' &&
            item.noteId.startsWith('EVENT#')) keys.push({ ownerId: item.ownerId, noteId: item.noteId });
      }
      start = r.LastEvaluatedKey;
    } while (start && keys.length < limit);
    return keys;
  }
  /** The observed malformed payload, or null when the raw row is repaired/not pending. */
  private async malformedAttempts(key: RelayKey,
    signal?: AbortSignal): Promise<{ present: boolean; value?: unknown } | null> {
    const row = await this.raw(key, signal);
    if (!row || row.relayStatus !== 'pending') return null;
    if (typeof row.attempts === 'number' && Number.isSafeInteger(row.attempts) && row.attempts >= 0) return null;
    return row.attempts === undefined ? { present: false } : { present: true, value: row.attempts };
  }
  /** Lease the original key without ADD, pinned to the exact malformed attempts value. */
  private async claimMalformed(key: RelayKey, now: number, leaseId: string, until: number,
    observed: { present: boolean; value?: unknown }, signal?: AbortSignal): Promise<boolean> {
    const values: Record<string, unknown> = { ':pending': 'pending', ':now': now,
      ':lease': leaseId, ':until': until };
    if (observed.present) values[':observed'] = observed.value;
    const attempts = observed.present ? 'attempts = :observed' : 'attribute_not_exists(attempts)';
    try {
      await this.db.send(new UpdateCommand({ TableName: this.table, Key: key,
        ConditionExpression: 'relayStatus = :pending AND relayDueAt <= :now AND ' +
          '(attribute_not_exists(leaseUntil) OR leaseUntil <= :now) AND ' + attempts,
        UpdateExpression: 'SET leaseId = :lease, leaseUntil = :until, relayDueAt = :until',
        ExpressionAttributeValues: values }), options(signal));
      return true;
    } catch (error) {
      if (conditional(error)) return false;
      throw error;
    }
  }
  private async raw(key: RelayKey, signal?: AbortSignal): Promise<Record<string, unknown> | null> {
    const r = await this.db.send(new GetCommand({ TableName: this.table,
      Key: key, ConsistentRead: true }), options(signal));
    return r.Item ?? null;
  }
  private async quarantineClaimed(key: RelayKey, leaseId: string, signal?: AbortSignal): Promise<void> {
    await this.quarantine(key, 'relayStatus = :pending AND leaseId = :lease',
      { ':lease': leaseId }, 'SET relayStatus = :dead, quarantineReason = :reason, leaseId = :lease ' +
      'REMOVE relayQueue, relayDueAt, leaseUntil', signal);
  }
  private async quarantine(key: RelayKey, condition: string, values: Record<string, unknown>,
    expression: string, signal?: AbortSignal): Promise<void> {
    try {
      await this.db.send(new UpdateCommand({ TableName: this.table, Key: key,
        ConditionExpression: condition, UpdateExpression: expression,
        ExpressionAttributeValues: { ':pending': 'pending', ':dead': 'dead',
          ':reason': 'schema-invalid', ...values } }), options(signal));
    } catch (error) {
      // Another owner won the fence; transport errors remain retryable.
      if (!conditional(error)) throw error;
    }
  }
  private async normalize(event: RelayEvent, now: number, signal?: AbortSignal): Promise<void> {
    let offset = event.splitOffset ?? 0;
    while (offset < event.actors.length) {
      signal?.throwIfAborted();
      const page = normalizationPage(this.table, event, offset, now, LEASE_MS);
      try {
        await this.db.send(new TransactWriteCommand({ TransactItems: page.writes }), options(signal));
      } catch (error) {
        if (!conditional(error)) throw error;
        const parent = await this.raw({ ownerId: event.ownerId, noteId: event.noteId }, signal);
        // A replaced lease/status means another worker owns the parent. A still-owned
        // parent means a child fence (or offset) conflicted: retryable, never lease loss.
        if (!parent || parent.relayStatus !== 'pending' || parent.leaseId !== event.leaseId ||
            (parent.splitOffset ?? 0) !== offset) return;
        throw new Error('Relay normalization conflict');
      }
      offset = page.nextOffset;
    }
  }
}
