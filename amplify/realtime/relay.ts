import type { RelayBudget } from './budget';
/** Durable metadata delivery; cursor HTTP sync remains the content authority. */
export type RelayKey = Readonly<{ ownerId: string; noteId: string }>;
export type RelayEvent = RelayKey & Readonly<{
  eventId: string; canonicalOwnerId: string; targetNoteId: string;
  revision: number; protectionRevision: number; sharingRevision?: number; createdAt?: string;
  actors: readonly string[]; attempts: number; leaseId: string; splitOffset?: number;
}>;
export type RevisionSignal = Readonly<{
  version: 1; eventId: string; ownerId: string; noteId: string;
  invalidate: true; revision?: number; protectionRevision?: number;
  accessRevision?: number;
}>;
export interface RelayStore {
  claim(key: RelayKey, now: number, signal?: AbortSignal): Promise<RelayEvent | null>;
  complete(event: RelayEvent, now: number, signal?: AbortSignal): Promise<void>;
  retry(event: RelayEvent, due: number, dead: boolean, signal?: AbortSignal): Promise<void>;
  due(now: number, limit: number, signal?: AbortSignal): Promise<RelayKey[]>;
}
export interface RelayPublisher {
  publish(actor: string, signal: RevisionSignal, requestSignal?: AbortSignal): Promise<void>;
}
export interface RelayAccess {
  /** null means revoked/missing; errors must propagate for recovery. */
  read(actor: string, owner: string, note: string, signal?: AbortSignal): Promise<number | null>;
}
export const MAX_ATTEMPTS = 20;
export const ACTOR_CONCURRENCY = 5;
export const MAX_PUBLISH_MS = 8_000;
export const retryDelay = (attempt: number, jitter = Math.random()): number =>
  Math.round(Math.min(900_000, 1000 * 2 ** Math.min(attempt, 10)) * (0.75 + jitter * 0.5));

export class RelayDeadlineError extends Error {
  constructor() { super('Relay invocation budget exhausted'); this.name = 'RelayDeadlineError'; }
}

/** Start at most `limit` workers, stop starting after the first failure, and await all started. */
async function runBounded<T>(items: readonly T[], limit: number, worker: (item: T) => Promise<void>): Promise<void> {
  let next = 0;
  let failed = false;
  let firstError: unknown;
  const run = async () => {
    while (!failed) {
      const index = next++;
      if (index >= items.length) return;
      try { await worker(items[index]); }
      catch (error) { if (!failed) { failed = true; firstError = error; } return; }
    }
  };
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, run));
  if (failed) throw firstError;
}

export class RevisionRelay {
  constructor(readonly store: RelayStore, readonly access: RelayAccess,
    readonly publisher: RelayPublisher, readonly clock = Date.now,
    readonly jitter = Math.random) {}

  async deliver(key: RelayKey, budget?: RelayBudget): Promise<void> {
    if (budget?.expired()) throw new RelayDeadlineError();
    const event = await this.store.claim(key, this.clock(), budget?.workSignal());
    if (!event) return;
    if (event.attempts > MAX_ATTEMPTS) {
      // The 21st claim is bookkeeping only; exactly 20 dispatches are allowed.
      await this.store.retry(event, this.clock(), true, budget?.bookkeepingSignal());
      return;
    }
    try {
      await this.publishActors(event, budget);
      await this.store.complete(event, this.clock(), budget?.bookkeepingSignal());
    } catch {
      // Stable eventId survives a lost publish ACK. Subscribers dedupe, then pull.
      await this.store.retry(event, this.clock() + retryDelay(event.attempts, this.jitter()),
        event.attempts >= MAX_ATTEMPTS, budget?.bookkeepingSignal());
    }
  }

  async recover(budget?: RelayBudget): Promise<void> {
    if (budget?.expired()) return;
    let keys: RelayKey[];
    try {
      keys = await this.store.due(this.clock(), 100, budget?.workSignal());
    } catch (error) {
      if (budget?.expired()) return;
      throw error;
    }
    for (const key of keys) {
      if (budget?.expired()) break;
      // Untouched scheduled keys remain pending; one bad key never aborts the pass.
      try { await this.deliver(key, budget); } catch { /* lease/retry state owns the next attempt */ }
    }
  }

  private async publishActors(event: RelayEvent, budget?: RelayBudget): Promise<void> {
    await runBounded(event.actors, ACTOR_CONCURRENCY, async (actor) => {
      if (budget?.expired()) throw new RelayDeadlineError();
      const accessSignal = budget?.workSignal();
      const access = actor === event.canonicalOwnerId ? 0 :
        await this.access.read(actor, event.canonicalOwnerId, event.targetNoteId, accessSignal);
      accessSignal?.throwIfAborted();
      if (budget?.expired()) throw new RelayDeadlineError();
      // Always invalidate. A revoked actor receives no revision/role/private data.
      const signal: RevisionSignal = {
        version: 1, eventId: event.eventId, ownerId: event.canonicalOwnerId,
        noteId: event.targetNoteId, invalidate: true,
        ...(access === null ? {} : { revision: event.revision,
          protectionRevision: event.protectionRevision, accessRevision: access }),
      };
      const publishSignal = budget ? budget.workSignal(MAX_PUBLISH_MS) : AbortSignal.timeout(MAX_PUBLISH_MS);
      await this.publisher.publish(actor, signal, publishSignal);
    });
  }
}
