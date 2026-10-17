/**
 * Phase 5 guarded index store (plan 5.1D/5.3B): a transparent `IndexStore` decorator that adds
 * the pilot scope permit without inventing any indexing algorithm. It wraps the existing
 * `createIndexStore` and never rewrites a state, epoch, fingerprint or the publish CAS: `load`
 * hands back the original canonical `IndexState` object, `acquire`/`publish` forward the exact
 * original bound state, lease, manifest and clock, and `reserveEmbedding` is replaced by the
 * atomic generic pilot `budget.acquireEmbedding`.
 *
 * Every call re-reads the immutable runtime config and compares the whole captured identity
 * (version, generation, policy, corpus). A config that moved mid-run fails closed as
 * `SOURCE_CHANGED`; a config that cannot be read or parsed fails as `LIVE_POLICY_NOT_CONFIGURED`.
 * A non-member owner is refused before the underlying body load, so an unreviewed account never
 * reaches canonical text or a paid stage.
 *
 * Consent semantics mirror the worker: `accepted && version === CONSENT_VERSION` is a permit.
 * With no permit the guard allows the listed owner's cleanup/BLOCKED path even when the policy is
 * disabled and without any corpus hash; with a permit it additionally requires an enabled policy.
 * In reviewed-pilot mode every eligible canonical note must appear with its exact approved note id
 * and `embeddingInputDigest(title, content)`; an unknown eligible id or a drifted digest fails
 * closed. In `eligible-own-notes.v1` mode only that frozen id/digest loop is skipped: the exact
 * configured owner, fresh canonical load/bind, consent version, config equality and the
 * fingerprint/publish guards are unchanged. Protected/deleted/unsynced notes are simply excluded
 * by the worker's `isEligibleNote`, and the returned state keeps every note unchanged. `finish` is
 * unguarded on purpose: a failed lease must always be releasable, even after a revoke, a config
 * change or a non-member job.
 */
import { CONSENT_VERSION, isValidIdentifier } from '../contract';
import { isEligibleNote } from '../authority';
import { bindIndexState, fingerprint } from '../indexing/jobs';
import { embeddingInputDigest } from '../indexing/snapshot';
import { IndexFailure } from '../indexing/types';
import type { IndexState, IndexStore, JobStatus, Lease, Manifest } from '../indexing/types';
import { RagFailure } from '../types';
import {
  RUNTIME_ELIGIBLE_OWN_NOTES_KIND, parseRuntimeConfig, sameRuntimeConfig,
} from './runtime_config';
import type { RuntimeConfig } from './runtime_config';
import type { PilotBudget } from './pilot_budget';

export type PilotIndexStoreDeps = Readonly<{
  store: IndexStore;
  budget: Pick<PilotBudget, 'acquireEmbedding'>;
  readConfig: (signal: AbortSignal) => Promise<RuntimeConfig>;
  config: RuntimeConfig;
}>;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const requireSignal = (signal: unknown): AbortSignal => {
  if (!(signal instanceof AbortSignal)) throw new IndexFailure('INVALID_INPUT', false);
  if (signal.aborted) throw new IndexFailure('TIMEOUT', true);
  return signal;
};

/** The worker's own consent reading; a wrong version is not a permit, so it stays cleanup. */
const consentAccepted = (state: IndexState): boolean =>
  state.consent.accepted === true && state.consent.version === CONSENT_VERSION;

/**
 * Transient port failures must stay replayable: the SDK/config reader reports 429/5xx as
 * RATE_LIMITED/PROVIDER_UNAVAILABLE and a fired deadline as TIMEOUT. Schema/membership and every
 * other INVALID_* code stay terminal. `SOURCE_CHANGED` is thrown by this module as retryable so a
 * newer invocation can re-read the latest config within the stream's bounded retry budget.
 */
const TRANSIENT_FAILURES = new Set(['TIMEOUT', 'RATE_LIMITED', 'PROVIDER_UNAVAILABLE']);

/** One failure taxonomy at the `IndexStore` boundary; every code is a safe, text-free string. */
const asIndexFailure = (error: unknown, signal: AbortSignal): IndexFailure => {
  if (signal.aborted) return new IndexFailure('TIMEOUT', true);
  if (error instanceof IndexFailure) return error;
  if (error instanceof RagFailure) return new IndexFailure(error.code, TRANSIENT_FAILURES.has(error.code));
  return new IndexFailure('PORT_FAILURE', true);
};

const hasStoreShape = (value: unknown): boolean =>
  isRecord(value) &&
  typeof value['load'] === 'function' &&
  typeof value['acquire'] === 'function' &&
  typeof value['publish'] === 'function' &&
  typeof value['finish'] === 'function' &&
  typeof value['reserveEmbedding'] === 'function';

/**
 * Builds the guard over one underlying `IndexStore`, one pilot budget and one captured config.
 * The captured config is validated (and deep-frozen) at construction; every later read must
 * reproduce it exactly or the call fails closed before any paid work.
 */
export function createPilotIndexStore(deps: PilotIndexStoreDeps): IndexStore {
  if (!isRecord(deps)) throw new IndexFailure('INVALID_STATE', false);
  const store = deps['store'];
  const budget = deps['budget'];
  const readConfig = deps['readConfig'];
  if (!hasStoreShape(store)) throw new IndexFailure('INVALID_STATE', false);
  if (!isRecord(budget) || typeof budget['acquireEmbedding'] !== 'function') {
    throw new IndexFailure('INVALID_STATE', false);
  }
  if (typeof readConfig !== 'function') throw new IndexFailure('INVALID_STATE', false);

  let captured: RuntimeConfig;
  try {
    captured = parseRuntimeConfig(deps['config']);
  } catch {
    throw new IndexFailure('LIVE_POLICY_NOT_CONFIGURED', false);
  }

  const isListedOwner = (ownerId: string): boolean =>
    Object.prototype.hasOwnProperty.call(captured.corpus.owners, ownerId);
  // Dynamic mode has no frozen note id/digest list; canonical eligibility and freshness are the
  // only body authority. Every other permit check below is shared with the reviewed mode.
  const dynamicCorpus = captured.corpus.kind === RUNTIME_ELIGIBLE_OWN_NOTES_KIND;

  /**
   * Every permitted call re-reads the whole config and demands the captured identity. The port is
   * awaited: a reader that resolves after the deadline and ignores the abort signal must never be
   * admitted, so the signal is re-checked before the value is parsed or compared. The read and the
   * comparison both happen before the caller can reach a provider or a publish.
   */
  const readConfigNow = async (signal: AbortSignal): Promise<RuntimeConfig> => {
    if (signal.aborted) throw new IndexFailure('TIMEOUT', true);
    let raw: unknown;
    try {
      raw = await readConfig(signal);
    } catch (error) {
      throw asIndexFailure(error, signal);
    }
    // The port awaited its own I/O; a deadline that fired during it still cancels the permit.
    if (signal.aborted) throw new IndexFailure('TIMEOUT', true);
    let current: RuntimeConfig;
    try {
      current = parseRuntimeConfig(raw);
    } catch (error) {
      throw asIndexFailure(error, signal);
    }
    if (signal.aborted) throw new IndexFailure('TIMEOUT', true);
    if (!sameRuntimeConfig(current, captured)) throw new IndexFailure('SOURCE_CHANGED', true);
    return current;
  };

  /**
   * Loads and validates the canonical state for a listed owner, applying the permit only when
   * consent is accepted. Membership is checked before the body load; with no permit the state is
   * returned untouched for the worker's cleanup/BLOCKED path, and with a permit every eligible
   * note must match an approved id and embedding-input digest exactly.
   *
   * The canonical load is awaited, so the permit can be withdrawn while it is in flight (a reader
   * that ignores the abort signal included). Once, after the load, the same captured immutable
   * config identity is re-read and the deadline re-checked before any state is authorized: that is
   * the single shared guard every `load`/`acquire`/`reserveEmbedding`/`publish` path runs before a
   * paid stage, a final dispatch or a publish CAS.
   */
  const authorize = async (ownerId: string, signal: AbortSignal): Promise<IndexState> => {
    if (!isValidIdentifier(ownerId)) throw new IndexFailure('INVALID_INPUT', false);
    if (!isListedOwner(ownerId)) throw new IndexFailure('LIVE_POLICY_NOT_CONFIGURED', false);
    const state = await store.load(ownerId, signal);
    await readConfigNow(signal);
    const bound = bindIndexState(state, ownerId);
    if (consentAccepted(bound)) {
      if (captured.policy.enabled !== true) throw new IndexFailure('LIVE_POLICY_NOT_CONFIGURED', false);
      const approved = captured.corpus.owners[bound.ownerId];
      if (approved === undefined) throw new IndexFailure('LIVE_POLICY_NOT_CONFIGURED', false);
      if (!dynamicCorpus) {
        const digestById = new Map<string, string>();
        for (const entry of approved) digestById.set(entry.noteId, entry.inputDigest);
        for (const note of bound.notes) {
          if (!isEligibleNote(note, bound.ownerId)) continue;
          const approvedDigest = digestById.get(note.noteId);
          if (approvedDigest === undefined) throw new IndexFailure('SOURCE_CHANGED', true);
          if (embeddingInputDigest(note.title, note.content) !== approvedDigest) {
            throw new IndexFailure('SOURCE_CHANGED', true);
          }
        }
      }
    }
    return state;
  };

  return Object.freeze({
    async load(ownerId: string, signal: AbortSignal): Promise<IndexState> {
      const deadline = requireSignal(signal);
      try {
        await readConfigNow(deadline);
        return await authorize(ownerId, deadline);
      } catch (error) {
        throw asIndexFailure(error, deadline);
      }
    },

    async acquire(
      state: IndexState, requested: string, nowMs: number, signal: AbortSignal,
    ): Promise<Lease | null> {
      const deadline = requireSignal(signal);
      try {
        await readConfigNow(deadline);
        const ownerId = isRecord(state) ? state['ownerId'] : undefined;
        if (!isValidIdentifier(ownerId)) throw new IndexFailure('INVALID_INPUT', false);
        const fresh = await authorize(ownerId, deadline);
        // A canonical move between the caller's load and this lease is a superseded run; the
        // original fingerprint/state/clock are still what the underlying CAS receives.
        if (fingerprint(fresh) !== fingerprint(state)) throw new IndexFailure('SOURCE_CHANGED', true);
        return await store.acquire(state, requested, nowMs, deadline);
      } catch (error) {
        throw asIndexFailure(error, deadline);
      }
    },

    async publish(
      state: IndexState, lease: Lease, manifest: Manifest, nowMs: number, signal: AbortSignal,
    ): Promise<boolean> {
      const deadline = requireSignal(signal);
      try {
        const config = await readConfigNow(deadline);
        const ownerId = isRecord(state) ? state['ownerId'] : undefined;
        if (!isValidIdentifier(ownerId)) throw new IndexFailure('INVALID_INPUT', false);
        const fresh = await authorize(ownerId, deadline);
        const status = isRecord(manifest) ? manifest['status'] : undefined;
        if (status === 'READY') {
          // READY needs the full permit; authorize already checked corpus when accepted.
          if (config.policy.enabled !== true || !consentAccepted(fresh)) {
            throw new IndexFailure('SOURCE_CHANGED', true);
          }
        } else if (status === 'BLOCKED') {
          // BLOCKED is the revoked/no-paid cleanup path only; an accepted state must be READY.
          if (consentAccepted(fresh)) throw new IndexFailure('SOURCE_CHANGED', true);
        } else {
          throw new IndexFailure('INVALID_INPUT', false);
        }
        return await store.publish(state, lease, manifest, nowMs, deadline);
      } catch (error) {
        throw asIndexFailure(error, deadline);
      }
    },

    async reserveEmbedding(ownerId: string, signal: AbortSignal): Promise<void> {
      const deadline = requireSignal(signal);
      try {
        const config = await readConfigNow(deadline);
        const fresh = await authorize(ownerId, deadline);
        if (config.policy.enabled !== true || !consentAccepted(fresh)) {
          throw new IndexFailure('LIVE_POLICY_NOT_CONFIGURED', false);
        }
        // Exactly one atomic pilot debit; the underlying global embedding counter is never used
        // directly and the deprecated Cohere counter is preserved, not incremented.
        await budget.acquireEmbedding(deadline);
      } catch (error) {
        throw asIndexFailure(error, deadline);
      }
    },

    /** Always forwarded, with the bounded signal the worker supplied: releasing must not depend on config. */
    async finish(
      ownerId: string, lease: Lease, status: JobStatus, code: string, nowMs: number, signal: AbortSignal,
    ): Promise<void> {
      return store.finish(ownerId, lease, status, code, nowMs, signal);
    },
  });
}
