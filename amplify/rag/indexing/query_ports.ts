/**
 * Phase 4 live query ports: the indexed-authority adapter and the retrieval adapter handed to the
 * canonical pipeline via `createQueryPorts(IndexDeps) -> { authority, retrieval }`.
 *
 * The existing pipeline owns fusion (RRF), MMR, evidence assembly, the Jev gate and generation;
 * these ports only serve already-authorized canonical inputs and never duplicate that orchestration.
 *
 *  - `authority.read` loads the Phase 3 canonical state and requires a current manifest: READY
 *    status, the recomputed canonical fingerprint, the current policy identity and matching
 *    account epoch / consent generation. The loaded state is cloned and frozen into a request
 *    binding keyed by that request's own AbortSignal, so no request can observe another's context.
 *  - Retrieval snapshots come only from the immutable artifact port under the manifest's own
 *    owner/version/policy identity, are validated by `validateSnapshot`, and are cached by the
 *    immutable `owner/version/checksum` triple (never by a mutable last-context pointer).
 *  - The scoped lexical corpus is validated with `assertChunkAuthority` before BM25, vectors are
 *    queried with the owner AND version (AND note) filters, and GetVectors responses must match
 *    the requested chunks exactly or the request fails closed.
 */
import { assertChunkAuthority } from '../authority';
import {
  MAX_EMBEDDING_CHARACTERS, MAX_EMBEDDING_TOKENS, countTokens, countUnicodeCharacters,
} from '../chunking';
import { bm25, compareSourceKey } from '../keyword';
import { validateVector } from '../retrieval';
import { RagFailure, sourceKey } from '../types';
import type {
  AuthorityStore, CanonicalState, Chunk, Ranked, RequestContext, RetrievalDeps,
} from '../types';
import { fingerprint } from './jobs';
import { policyIdentity, validateSnapshot } from './snapshot';
import { IndexFailure } from './types';
import type { Document, IndexDeps, IndexState, Manifest, Snapshot } from './types';

export type QueryPorts = Readonly<{ authority: AuthorityStore; retrieval: RetrievalDeps }>;

/** One immutable index generation is cached; a long-lived live process cannot grow without bound. */
export const MAX_SNAPSHOT_CACHE = 1;

/** The per-request binding: the frozen state loaded for this signal and its lazy snapshot. */
type RequestBinding = {
  ownerId: string;
  state: IndexState;
  manifest: Manifest;
  snapshot: Snapshot | null;
  scopeKey: string;
  scoped: readonly Document[] | null;
};

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const deepFreeze = <T>(value: T): T => {
  if (value !== null && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const key of Object.keys(value)) deepFreeze((value as Record<string, unknown>)[key]);
  }
  return value;
};

/** One failure taxonomy for the indexing ports; message text is always a code. */
const toRagFailure = (error: unknown, signal: AbortSignal): RagFailure => {
  if (signal.aborted) return new RagFailure('TIMEOUT');
  if (error instanceof RagFailure) return error;
  if (error instanceof IndexFailure) {
    switch (error.code) {
      case 'TIMEOUT': return new RagFailure('TIMEOUT');
      case 'RATE_LIMITED':
      case 'BUDGET_EXHAUSTED': return new RagFailure('RATE_LIMITED');
      case 'INVALID_PROVIDER_OUTPUT': return new RagFailure('INVALID_PROVIDER_OUTPUT');
      case 'SOURCE_CHANGED': return new RagFailure('SOURCE_CHANGED');
      case 'INVALID_INPUT': return new RagFailure('INVALID_INPUT');
      case 'PROVIDER_UNAVAILABLE': return new RagFailure('PROVIDER_UNAVAILABLE');
      // The Phase 5 guarded store adds these two typed refusals; keep their safe codes instead of
      // flattening them into INDEX_NOT_READY, which would hide a revoked/stale pilot permit.
      case 'LIVE_POLICY_NOT_CONFIGURED': return new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
      case 'CONSENT_REQUIRED': return new RagFailure('CONSENT_REQUIRED');
      default: return new RagFailure('INDEX_NOT_READY');
    }
  }
  return new RagFailure('PROVIDER_UNAVAILABLE');
};

const scopeKeyOf = (context: RequestContext): string => {
  const scope = context.request.scope;
  return scope.type === 'account' ? 'account' : `note\u0000${scope.noteId}`;
};

const requireSignal = (signal: unknown): AbortSignal => {
  if (!(signal instanceof AbortSignal)) throw new RagFailure('PROVIDER_UNAVAILABLE');
  return signal;
};

/** A manifest is current only when it re-derives from the loaded state under the live policy. */
const isCurrentManifest = (state: IndexState): boolean => {
  const manifest = state.manifest;
  return (
    manifest !== null &&
    manifest.status === 'READY' &&
    manifest.ownerId === state.ownerId &&
    manifest.fingerprint === fingerprint(state) &&
    manifest.policyIdentity === policyIdentity() &&
    manifest.accountEpoch === state.accountEpoch &&
    manifest.consentGeneration === state.consent.generation
  );
};

export function createQueryPorts(deps: IndexDeps): QueryPorts {
  if (!isRecord(deps) || !isRecord(deps.store) || typeof deps.store.load !== 'function' ||
      !isRecord(deps.artifacts) || !isRecord(deps.embedding) || typeof deps.embedding.embed !== 'function') {
    throw new IndexFailure('INVALID_STATE', false);
  }
  /** Immutable snapshots keyed by owner/version/checksum; never by "the last request". */
  const cache = new Map<string, Snapshot>();
  const inFlight = new Map<string, Promise<Snapshot>>();
  const requests = new WeakMap<AbortSignal, RequestBinding>();

  const snapshotKeyOf = (ownerId: string, manifest: Manifest): string =>
    `${ownerId}\u0000${manifest.version}\u0000${manifest.checksum}`;

  const remember = (key: string, snapshot: Snapshot): void => {
    if (cache.size >= MAX_SNAPSHOT_CACHE && !cache.has(key)) {
      const oldest = cache.keys().next();
      if (!oldest.done) cache.delete(oldest.value);
    }
    cache.set(key, snapshot);
  };

  /** Read one snapshot under the manifest identity, verify it, then cache the immutable value. */
  const loadSnapshot = async (binding: RequestBinding, signal: AbortSignal): Promise<Snapshot> => {
    const key = snapshotKeyOf(binding.ownerId, binding.manifest);
    const cached = cache.get(key);
    if (cached !== undefined) return cached;
    let pending = inFlight.get(key);
    if (pending === undefined) {
      pending = (async (): Promise<Snapshot> => {
        try {
          const snapshot = validateSnapshot(await deps.artifacts.read(binding.manifest, signal));
          if (
            snapshot.ownerId !== binding.ownerId ||
            snapshot.version !== binding.manifest.version ||
            snapshot.accountEpoch !== binding.state.accountEpoch ||
            snapshot.consentGeneration !== binding.state.consent.generation
          ) {
            throw new IndexFailure('INDEX_NOT_READY', false);
          }
          remember(key, snapshot);
          return snapshot;
        } finally {
          inFlight.delete(key);
        }
      })();
      inFlight.set(key, pending);
    }
    return pending;
  };

  const bindingFor = (context: RequestContext): RequestBinding => {
    const binding = requests.get(context.signal);
    if (binding === undefined || binding.ownerId !== context.actor) {
      throw new RagFailure('INDEX_NOT_READY');
    }
    return binding;
  };

  const ensureSnapshot = async (binding: RequestBinding, context: RequestContext): Promise<Snapshot> => {
    if (binding.snapshot === null) {
      try {
        binding.snapshot = await loadSnapshot(binding, context.signal);
      } catch (error) {
        throw toRagFailure(error, context.signal);
      }
    }
    return binding.snapshot;
  };

  /** The scoped lexical corpus: every document is validated against the frozen canonical context. */
  const scopedDocuments = (binding: RequestBinding, context: RequestContext): readonly Document[] => {
    const scopeKey = scopeKeyOf(context);
    if (binding.scoped !== null && binding.scopeKey === scopeKey) return binding.scoped;
    const scope = context.request.scope;
    const documents = binding.snapshot === null
      ? []
      : binding.snapshot.documents.filter(
          (document) => scope.type === 'account' || document.chunk.noteId === scope.noteId,
        );
    for (const document of documents) assertChunkAuthority(document.chunk, context);
    binding.scopeKey = scopeKey;
    binding.scoped = Object.freeze(documents);
    return binding.scoped;
  };

  const authority: AuthorityStore = Object.freeze({
    read: async (actor: string, signal: AbortSignal): Promise<CanonicalState> => {
      const io = requireSignal(signal);
      let loaded: IndexState;
      try {
        loaded = await deps.store.load(actor, io);
      } catch (error) {
        throw toRagFailure(error, io);
      }
      if (io.aborted) throw new RagFailure('TIMEOUT');
      if (!isRecord(loaded) || loaded.ownerId !== actor || !Array.isArray(loaded.notes)) {
        throw new RagFailure('PROVIDER_UNAVAILABLE');
      }
      let state: IndexState;
      try {
        // Clone and freeze: a caller mutating the returned state later cannot retune this request.
        state = deepFreeze(structuredClone(loaded));
      } catch {
        throw new RagFailure('PROVIDER_UNAVAILABLE');
      }
      const manifest = state.manifest;
      const current = isCurrentManifest(state);
      if (current && manifest !== null) {
        requests.set(io, {
          ownerId: actor,
          state,
          manifest,
          snapshot: null,
          scopeKey: '',
          scoped: null,
        });
      }
      return Object.freeze({
        actorId: actor,
        sessionGeneration: state.accountEpoch,
        consent: state.consent,
        indexReady: current,
        manifestVersion: manifest?.version ?? '',
        notes: state.notes,
      });
    },
  });

  const retrieval: RetrievalDeps = Object.freeze({
    embedQuery: async (
      question: string,
      signal: AbortSignal,
      beforeDispatch?: () => Promise<void>,
    ): Promise<readonly number[]> => {
      const io = requireSignal(signal);
      const binding = requests.get(io);
      if (binding === undefined) throw new RagFailure('INDEX_NOT_READY');
      if (typeof question !== 'string' || question.trim().length === 0) throw new RagFailure('INVALID_INPUT');
      if (countTokens(deps.embedding.count, question) > MAX_EMBEDDING_TOKENS) {
        throw new RagFailure('INPUT_TOO_LONG');
      }
      if (countUnicodeCharacters(question) > MAX_EMBEDDING_CHARACTERS) throw new RagFailure('INPUT_TOO_LONG');
      try {
        // The shared smoke counter is reserved before the single query call, failures included.
        await deps.store.reserveEmbedding(binding.ownerId, io);
        // The reservation is async: a permit/consent/source change that lands while it is in
        // flight must be observed before the paid embedding call. The pipeline supplies the
        // captured `context.revalidate`; a direct caller without one gets a fresh re-read and
        // must still present the exact canonical fingerprint. The same callback is forwarded into
        // the embedding port, which re-runs it after its own reservation/signing window.
        const revalidateBeforeEmbed: () => Promise<void> = typeof beforeDispatch === 'function'
          ? beforeDispatch
          : async () => {
              const latest = await deps.store.load(binding.ownerId, io);
              if (fingerprint(latest) !== fingerprint(binding.state)) {
                throw new IndexFailure('SOURCE_CHANGED', false);
              }
            };
        await revalidateBeforeEmbed();
        const produced = await deps.embedding.embed([question], 'search_query', io, revalidateBeforeEmbed);
        if (!Array.isArray(produced) || produced.length !== 1) {
          throw new IndexFailure('INVALID_PROVIDER_OUTPUT', false);
        }
        const vector = produced[0];
        validateVector(vector);
        return vector;
      } catch (error) {
        throw toRagFailure(error, io);
      }
    },

    vectorSearch: async (vector: readonly number[], context: RequestContext): Promise<readonly Ranked[]> => {
      validateVector(vector);
      const binding = bindingFor(context);
      // An empty eligible scope is a legitimate empty result and must not reach the index.
      if (context.notes.length === 0) return Object.freeze([]);
      await ensureSnapshot(binding, context);
      const scoped = scopedDocuments(binding, context);
      if (scoped.length === 0) return Object.freeze([]);
      let keys: readonly string[];
      try {
        keys = await deps.artifacts.query(
          vector,
          binding.ownerId,
          binding.manifest.version,
          context.request.scope.type === 'note' ? context.request.scope.noteId : null,
          context.signal,
        );
      } catch (error) {
        throw toRagFailure(error, context.signal);
      }
      const byVectorKey = new Map(scoped.map((document) => [document.vectorKey, document] as const));
      const ranked: Ranked[] = [];
      const seen = new Set<string>();
      for (const key of keys) {
        const document = byVectorKey.get(key);
        // A key outside the scoped snapshot is a foreign or stale index generation.
        if (document === undefined) throw new RagFailure('SOURCE_CHANGED');
        const identity = sourceKey(document.chunk);
        if (seen.has(identity)) throw new RagFailure('INDEX_NOT_READY');
        seen.add(identity);
        assertChunkAuthority(document.chunk, context);
        ranked.push(Object.freeze({ chunk: document.chunk, rank: ranked.length + 1 }));
      }
      return Object.freeze(ranked);
    },

    keywordSearch: async (question: string, context: RequestContext): Promise<readonly Ranked[]> => {
      const binding = bindingFor(context);
      if (context.notes.length === 0) return Object.freeze([]);
      await ensureSnapshot(binding, context);
      const scoped = scopedDocuments(binding, context);
      if (scoped.length === 0) return Object.freeze([]);
      try {
        return bm25(question, scoped.map((document) => document.chunk));
      } catch (error) {
        throw toRagFailure(error, context.signal);
      }
    },

    getVectors: async (
      chunks: readonly Chunk[],
      context: RequestContext,
    ): Promise<ReadonlyMap<string, readonly number[]>> => {
      const binding = bindingFor(context);
      if (!Array.isArray(chunks)) throw new RagFailure('INVALID_INPUT');
      const vectors = new Map<string, readonly number[]>();
      if (chunks.length === 0) return vectors;
      await ensureSnapshot(binding, context);
      const scoped = scopedDocuments(binding, context);
      const bySource = new Map(scoped.map((document) => [sourceKey(document.chunk), document] as const));
      const keys: string[] = [];
      for (const chunk of chunks) {
        assertChunkAuthority(chunk, context);
        const resolved = bySource.get(sourceKey(chunk));
        if (resolved === undefined) throw new RagFailure('INDEX_NOT_READY');
        keys.push(resolved.vectorKey);
      }
      let stored: ReadonlyMap<string, readonly number[]>;
      try {
        stored = await deps.artifacts.getVectors(keys, context.signal);
      } catch (error) {
        throw toRagFailure(error, context.signal);
      }
      // Partial or oversized responses fail closed: every requested chunk needs its own vector.
      if (stored === null || typeof stored !== 'object' || typeof stored.get !== 'function') {
        throw new RagFailure('INDEX_NOT_READY');
      }
      if (typeof stored.size !== 'number' || stored.size !== keys.length) throw new RagFailure('INDEX_NOT_READY');
      for (let index = 0; index < chunks.length; index += 1) {
        const key = keys[index];
        const vector = stored.get(key);
        if (vector === undefined) throw new RagFailure('INDEX_NOT_READY');
        validateVector(vector);
        const chunk = chunks[index];
        if (chunk === undefined) throw new RagFailure('INVALID_INPUT');
        vectors.set(sourceKey(chunk), vector);
      }
      return vectors;
    },

    neighbors: async (anchors: readonly Chunk[], context: RequestContext): Promise<readonly Chunk[]> => {
      const binding = bindingFor(context);
      if (!Array.isArray(anchors)) throw new RagFailure('INVALID_INPUT');
      if (anchors.length === 0) return Object.freeze([]);
      await ensureSnapshot(binding, context);
      const scoped = scopedDocuments(binding, context);
      const out: Chunk[] = [];
      const seen = new Set<string>();
      for (const anchor of anchors) {
        assertChunkAuthority(anchor, context);
        for (const document of scoped) {
          const chunk = document.chunk;
          // policy.context.sameNoteRevisionSection with previous/next 1: ordinal distance exactly 1.
          if (
            chunk.noteId !== anchor.noteId ||
            chunk.revision !== anchor.revision ||
            chunk.sectionId !== anchor.sectionId ||
            Math.abs(chunk.ordinal - anchor.ordinal) !== 1
          ) {
            continue;
          }
          const identity = sourceKey(chunk);
          if (seen.has(identity)) continue;
          seen.add(identity);
          out.push(chunk);
        }
      }
      out.sort(compareSourceKey);
      return Object.freeze(out);
    },
  });

  return Object.freeze({ authority, retrieval });
}
