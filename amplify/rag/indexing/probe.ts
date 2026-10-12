// Internal IAM-only retrieval probe; Phase 4 owns Jev and answer generation.
import { beginContext, assertChunkAuthority } from '../authority';
import { parseRequest, CONSENT_VERSION } from '../contract';
import { bm25 } from '../keyword';
import { rrf, mmr, validateVector } from '../retrieval';
import { sourceKey, RagFailure, type Chunk, type Ranked } from '../types';
import { countTokens, countUnicodeCharacters, MAX_EMBEDDING_TOKENS, MAX_EMBEDDING_CHARACTERS } from '../chunking';
import { fingerprint } from './jobs';
import { policyIdentity, validateSnapshot } from './snapshot';
import { IndexFailure, type IndexDeps, type IndexState, type Snapshot } from './types';

export function createRetrievalProbe(deps: IndexDeps) {
  // One immutable entry, keyed by account/version/checksum; canonical reads always precede use.
  let cache: { key: string; snapshot: Snapshot } | null = null;
  return async (ownerId: string, body: string) => {
    const request = parseRequest(body);
    const signal = AbortSignal.timeout(26_000);
    const states = new Map<string, IndexState>();
    const authority = { read: async (actor: string, ioSignal: AbortSignal) => {
      const state = await deps.store.load(actor, ioSignal);
      states.set(actor, state);
      const manifest = state.manifest;
      return { actorId: actor, sessionGeneration: state.accountEpoch,
        consent: state.consent, notes: state.notes,
        manifestVersion: manifest?.version ?? '',
        indexReady: manifest?.status === 'READY' && manifest.fingerprint === fingerprint(state)
          && manifest.policyIdentity === policyIdentity()
          && manifest.accountEpoch === state.accountEpoch
          && manifest.consentGeneration === state.consent.generation };
    }};
    const context = await beginContext(ownerId, request, authority, signal);
    const state = states.get(ownerId)!;
    const manifest = state.manifest!;
    if (state.consent.version !== CONSENT_VERSION) throw new RagFailure('CONSENT_REQUIRED');
    const cacheKey = JSON.stringify([ownerId, manifest.version, manifest.checksum]);
    if (cache?.key !== cacheKey) {
      cache = null;
      const snapshot = validateSnapshot(await deps.artifacts.read(manifest, signal));
      if (snapshot.ownerId !== ownerId || snapshot.version !== manifest.version
        || snapshot.accountEpoch !== state.accountEpoch
        || snapshot.consentGeneration !== state.consent.generation) throw new RagFailure('INDEX_NOT_READY');
      cache = { key: cacheKey, snapshot };
    }
    const documents = cache.snapshot.documents;
    // Validate the entire scoped lexical corpus, including keyword-only candidates.
    const scoped = documents.filter(d => request.scope.type === 'account' || d.chunk.noteId === request.scope.noteId);
    for (const d of scoped) assertChunkAuthority(d.chunk, context);
    await context.revalidate();
    if (scoped.length === 0) return { provenance: 'internal-retrieval-probe', manifestVersion: manifest.version,
      checksum: manifest.checksum, vectorKeys: [], keywordChunkIds: [], anchors: [], neighbors: [] };
    const keyword = bm25(request.question, scoped.map(d => d.chunk));
    const tokens = countTokens(deps.embedding.count, request.question);
    if (tokens > MAX_EMBEDDING_TOKENS || countUnicodeCharacters(request.question) > MAX_EMBEDDING_CHARACTERS)
      throw new RagFailure('INPUT_TOO_LONG');
    await context.revalidate();
    await deps.store.reserveEmbedding(ownerId, signal);
    const produced = await deps.embedding.embed([request.question], 'search_query', signal);
    if (produced.length !== 1) throw new IndexFailure('INVALID_PROVIDER_OUTPUT');
    validateVector(produced[0]);
    await context.revalidate();
    const keys = await deps.artifacts.query(produced[0], ownerId, manifest.version,
      request.scope.type === 'note' ? request.scope.noteId : null, signal);
    const byKey = new Map(scoped.map(d => [d.vectorKey, d]));
    const vector: Ranked[] = keys.map((key, index) => {
      const d = byKey.get(key);
      if (!d) throw new RagFailure('SOURCE_CHANGED');
      assertChunkAuthority(d.chunk, context);
      return { chunk: d.chunk, rank: index + 1 };
    });
    const candidates = rrf(vector, keyword);
    const bySource = new Map(scoped.map(d => [sourceKey(d.chunk), d]));
    await context.revalidate();
    const floats = await deps.artifacts.getVectors(candidates.map(c => bySource.get(sourceKey(c.chunk))!.vectorKey), signal);
    const vectors = new Map(candidates.map(c => {
      const d = bySource.get(sourceKey(c.chunk))!;
      const value = floats.get(d.vectorKey);
      if (!value) throw new RagFailure('INDEX_NOT_READY');
      return [sourceKey(c.chunk), value] as const;
    }));
    const anchors = mmr(candidates, vectors);
    const neighbors: Chunk[] = scoped.filter(d => anchors.some(a => a.noteId === d.chunk.noteId
      && a.revision === d.chunk.revision && a.sectionId === d.chunk.sectionId
      && Math.abs(a.ordinal - d.chunk.ordinal) === 1)).map(d => d.chunk);
    for (const chunk of [...anchors, ...neighbors]) assertChunkAuthority(chunk, context);
    await context.revalidate();
    return { provenance: 'internal-retrieval-probe', manifestVersion: manifest.version,
      checksum: manifest.checksum, vectorKeys: keys, keywordChunkIds: keyword.map(k => k.chunk.chunkId),
      anchors, neighbors };
  };
}
