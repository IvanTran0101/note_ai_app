/** Durable metadata delivery; cursor HTTP sync remains the content authority. */
export type RelayKey = Readonly<{ ownerId: string; noteId: string }>;
export type RelayEvent = RelayKey & Readonly<{
  eventId: string; canonicalOwnerId: string; targetNoteId: string;
  revision: number; protectionRevision: number; actors: readonly string[];
  attempts: number; leaseId: string;
}>;
export type RevisionSignal = Readonly<{
  version: 1; eventId: string; ownerId: string; noteId: string;
  invalidate: true; revision?: number; protectionRevision?: number;
  accessRevision?: number;
}>;
export interface RelayStore {
  claim(key: RelayKey, now: number): Promise<RelayEvent | null>;
  complete(event: RelayEvent, now: number): Promise<void>;
  retry(event: RelayEvent, due: number, dead: boolean): Promise<void>;
  due(now: number, limit: number): Promise<RelayKey[]>;
}
export interface RelayPublisher { publish(actor: string, signal: RevisionSignal): Promise<void> }
export interface RelayAccess {
  /** null means revoked/missing; errors must propagate for recovery. */
  read(actor: string, owner: string, note: string): Promise<number | null>;
}
export const MAX_ATTEMPTS = 20;
export const retryDelay = (attempt: number, jitter = Math.random()): number =>
  Math.round(Math.min(900_000, 1000 * 2 ** Math.min(attempt, 10)) * (0.75 + jitter * 0.5));

export class RevisionRelay {
  constructor(readonly store: RelayStore, readonly access: RelayAccess,
    readonly publisher: RelayPublisher, readonly clock = Date.now,
    readonly jitter = Math.random) {}

  async deliver(key: RelayKey): Promise<void> {
    const event = await this.store.claim(key, this.clock());
    if (!event) return;
    try {
      if (event.attempts > MAX_ATTEMPTS) {
        await this.store.retry(event, this.clock(), true);
        return;
      }
      for (const actor of event.actors) {
        const access = actor === event.canonicalOwnerId ? 0 :
          await this.access.read(actor, event.canonicalOwnerId, event.targetNoteId);
        // Always invalidate. A revoked actor receives no revision/role/private data.
        const signal: RevisionSignal = {
          version: 1, eventId: event.eventId, ownerId: event.canonicalOwnerId,
          noteId: event.targetNoteId, invalidate: true,
          ...(access === null ? {} : { revision: event.revision,
            protectionRevision: event.protectionRevision, accessRevision: access }),
        };
        await this.publisher.publish(actor, signal);
      }
      await this.store.complete(event, this.clock());
    } catch {
      // Stable eventId survives a lost publish ACK. Subscribers dedupe, then pull.
      await this.store.retry(event, this.clock() + retryDelay(event.attempts, this.jitter()),
        event.attempts >= MAX_ATTEMPTS);
    }
  }

  async recover(): Promise<void> {
    for (const key of await this.store.due(this.clock(), 100)) await this.deliver(key);
  }
}
