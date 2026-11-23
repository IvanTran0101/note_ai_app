import { policy, RagFailure, sourceKey } from './types';
import type { CanonicalNote, CanonicalState, Chunk, Counter, Ranked, RequestContext } from './types';
import { CONSENT_VERSION, isValidIdentifier } from './contract';
import { assertChunk, chunkNote, embeddingText } from './chunking';
import { ANALYZER_VERSION, bm25, compareSourceKey } from './keyword';
import { validateVector, sameChunk } from './retrieval';
import { isEligibleNote as isIndexable } from './authority';
import { dot, unitVector, embedSearchQuery, embedSearchDocument } from './mock_embedding';
export { embedSearchQuery, embedSearchDocument } from './mock_embedding';

export const SNAPSHOT_VERSION = 1;
export const LEXICAL_CODEC = 'rag-lexical-snapshot.v1';
export const INDEX_MODEL: string = policy.embedding.model;
export const INDEX_DIMENSIONS: number = policy.embedding.dimensions;
export const INDEX_CHUNKING_POLICY: string = JSON.stringify({
  contract: policy.contractVersion, chunking: policy.chunking,
  text: policy.technicalDefaults.embeddingText, offset: policy.technicalDefaults.offsetUnit,
});
export const INDEX_ANALYZER_VERSION: string = ANALYZER_VERSION;
export const INDEX_PROVENANCE = 'synthetic-lexical-toy-hash-not-a-provider-model';
export const QUERY_INPUT_TYPE: string = policy.embedding.queryInputType;
export const DOCUMENT_INPUT_TYPE: string = policy.embedding.documentInputType;
const VECTOR_TOP_K: number = policy.retrieval.vectorTopK;

export type IndexMetadata = Readonly<{
  snapshotVersion: number;
  model: string;
  dimensions: number;
  chunkingPolicy: string;
  analyzerVersion: string;
  manifestVersion: string;
  consentGeneration: number;
  ownerId: string;
}>;

export type IndexedDocument = Readonly<{ sourceKey: string; chunk: Chunk }>;

export type LexicalSnapshot = Readonly<{
  codec: typeof LEXICAL_CODEC;
  metadata: IndexMetadata;
  documents: readonly IndexedDocument[];
}>;

export type MockIndex = Readonly<{
  metadata: IndexMetadata;
  encodeLexicalSnapshot(): string;
  vectorSearch(vector: readonly number[], context: RequestContext): Promise<readonly Ranked[]>;
  keywordSearch(question: string, context: RequestContext): Promise<readonly Ranked[]>;
  getVectors(chunks: readonly Chunk[], context: RequestContext): Promise<ReadonlyMap<string, readonly number[]>>;
  neighbors(anchors: readonly Chunk[], context: RequestContext): Promise<readonly Chunk[]>;
}>;

const SNAPSHOT_KEYS = ['codec', 'metadata', 'documents'] as const;
const METADATA_KEYS = [
  'snapshotVersion',
  'model',
  'dimensions',
  'chunkingPolicy',
  'analyzerVersion',
  'manifestVersion',
  'consentGeneration',
  'ownerId',
] as const;
const DOCUMENT_KEYS = ['sourceKey', 'chunk'] as const;
const CHUNK_KEYS = [
  'ownerId',
  'noteId',
  'revision',
  'sectionId',
  'chunkId',
  'ordinal',
  'title',
  'startOffset',
  'endOffset',
  'text',
] as const;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const hasExactKeys = (value: Record<string, unknown>, required: readonly string[]): boolean =>
  Object.keys(value).length === required.length &&
  required.every((key) => Object.prototype.hasOwnProperty.call(value, key));

const assertStaticMetadata = (metadata: unknown): IndexMetadata => {
  if (!isRecord(metadata) || !hasExactKeys(metadata, METADATA_KEYS)) throw new RagFailure('INDEX_NOT_READY');
  if (metadata['snapshotVersion'] !== SNAPSHOT_VERSION) throw new RagFailure('INDEX_NOT_READY');
  if (metadata['model'] !== INDEX_MODEL) throw new RagFailure('INDEX_NOT_READY');
  if (metadata['dimensions'] !== INDEX_DIMENSIONS) throw new RagFailure('INDEX_NOT_READY');
  if (metadata['chunkingPolicy'] !== INDEX_CHUNKING_POLICY) throw new RagFailure('INDEX_NOT_READY');
  if (metadata['analyzerVersion'] !== INDEX_ANALYZER_VERSION) throw new RagFailure('INDEX_NOT_READY');
  if (!isValidIdentifier(metadata['manifestVersion']) || !isValidIdentifier(metadata['ownerId'])) {
    throw new RagFailure('INDEX_NOT_READY');
  }
  const consentGeneration = metadata['consentGeneration'];
  if (!Number.isSafeInteger(consentGeneration) || (consentGeneration as number) < 0) {
    throw new RagFailure('INDEX_NOT_READY');
  }
  return Object.freeze({
    snapshotVersion: SNAPSHOT_VERSION,
    model: INDEX_MODEL,
    dimensions: INDEX_DIMENSIONS,
    chunkingPolicy: INDEX_CHUNKING_POLICY,
    analyzerVersion: INDEX_ANALYZER_VERSION,
    manifestVersion: metadata['manifestVersion'],
    consentGeneration: consentGeneration as number,
    ownerId: metadata['ownerId'],
  });
};

const decodeDocument = (value: unknown): IndexedDocument => {
  if (!isRecord(value) || !hasExactKeys(value, DOCUMENT_KEYS)) throw new RagFailure('INDEX_NOT_READY');
  const key = value['sourceKey'];
  const chunkValue = value['chunk'];
  if (typeof key !== 'string' || !isRecord(chunkValue) || !hasExactKeys(chunkValue, CHUNK_KEYS)) {
    throw new RagFailure('INDEX_NOT_READY');
  }
  try {
    assertChunk(chunkValue);
  } catch {
    throw new RagFailure('INDEX_NOT_READY');
  }
  const chunk = chunkValue as unknown as Chunk;
  if (sourceKey(chunk) !== key) throw new RagFailure('INDEX_NOT_READY');
  return Object.freeze({ sourceKey: key, chunk: Object.freeze({ ...chunk }) });
};

const syntheticConsent = (state: CanonicalState): Readonly<{ accepted: boolean; generation: number }> => {
  const consent = state.consent as { accepted?: unknown; version?: unknown; generation?: unknown } | undefined;
  if (consent === null || typeof consent !== 'object') return { accepted: false, generation: 0 };
  const accepted = consent.accepted === true && consent.version === CONSENT_VERSION &&
    Number.isSafeInteger(consent.generation) && (consent.generation as number) >= 0;
  return { accepted, generation: accepted ? (consent.generation as number) : 0 };
};

export function buildLexicalSnapshot(actor: string, state: CanonicalState, counter: Counter): LexicalSnapshot {
  if (!isValidIdentifier(actor) || state === null || typeof state !== 'object') {
    throw new RagFailure('INDEX_NOT_READY');
  }
  if (state.actorId !== actor) throw new RagFailure('UNAUTHORIZED');
  const consent = syntheticConsent(state);
  const documents: IndexedDocument[] = [];
  const seen = new Set<string>();
  if (consent.accepted && Array.isArray(state.notes)) {
    for (const note of state.notes) {
      if (!isIndexable(note, actor)) continue;
      for (const chunk of chunkNote(note, counter)) {
        const key = sourceKey(chunk);
        if (seen.has(key)) throw new RagFailure('INDEX_NOT_READY');
        seen.add(key);
        documents.push(Object.freeze({ sourceKey: key, chunk: Object.freeze({ ...chunk }) }));
      }
    }
  }
  return Object.freeze({
    codec: LEXICAL_CODEC,
    metadata: Object.freeze({
      snapshotVersion: SNAPSHOT_VERSION,
      model: INDEX_MODEL,
      dimensions: INDEX_DIMENSIONS,
      chunkingPolicy: INDEX_CHUNKING_POLICY,
      analyzerVersion: INDEX_ANALYZER_VERSION,
      manifestVersion: state.manifestVersion,
      consentGeneration: consent.generation,
      ownerId: actor,
    }),
    documents: Object.freeze(documents),
  });
}

export function encodeLexicalSnapshot(snapshot: LexicalSnapshot): string {
  if (snapshot === null || typeof snapshot !== 'object') throw new RagFailure('INDEX_NOT_READY');
  const metadata = assertStaticMetadata(snapshot.metadata);
  if (snapshot.codec !== LEXICAL_CODEC || !Array.isArray(snapshot.documents)) throw new RagFailure('INDEX_NOT_READY');
  return JSON.stringify({
    codec: LEXICAL_CODEC,
    metadata,
    documents: snapshot.documents.map((document) => decodeDocument(document)),
  });
}

export function decodeLexicalSnapshot(text: string): LexicalSnapshot {
  if (typeof text !== 'string' || text.length === 0) throw new RagFailure('INDEX_NOT_READY');
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    throw new RagFailure('INDEX_NOT_READY');
  }
  if (!isRecord(value) || !hasExactKeys(value, SNAPSHOT_KEYS) || value['codec'] !== LEXICAL_CODEC) {
    throw new RagFailure('INDEX_NOT_READY');
  }
  const metadata = assertStaticMetadata(value['metadata']);
  const rawDocuments = value['documents'];
  if (!Array.isArray(rawDocuments)) throw new RagFailure('INDEX_NOT_READY');
  const documents: IndexedDocument[] = [];
  const seen = new Set<string>();
  for (const entry of rawDocuments) {
    const document = decodeDocument(entry);
    if (seen.has(document.sourceKey)) throw new RagFailure('INDEX_NOT_READY');
    seen.add(document.sourceKey);
    documents.push(document);
  }
  return Object.freeze({ codec: LEXICAL_CODEC, metadata, documents: Object.freeze(documents) });
}

const ordinalKey = (chunk: Chunk): string =>
  JSON.stringify([chunk.ownerId, chunk.noteId, chunk.revision, chunk.sectionId, chunk.ordinal]);

type CoherentCorpus = Readonly<{ chunks: readonly Chunk[]; vectors: ReadonlyMap<string, readonly number[]> }>;

const coherentCorpus = (
  metadata: IndexMetadata,
  documents: readonly IndexedDocument[],
  vectors: ReadonlyMap<string, readonly number[]>,
  context: RequestContext,
): CoherentCorpus => {
  assertStaticMetadata(metadata);
  if (metadata.ownerId !== context.actor) throw new RagFailure('SCOPE_DENIED');
  if (metadata.manifestVersion !== context.state.manifestVersion) throw new RagFailure('INDEX_NOT_READY');
  const consent = context.state.consent as { accepted?: unknown; generation?: unknown } | undefined;
  if (
    consent === null ||
    typeof consent !== 'object' ||
    consent.accepted !== true ||
    metadata.consentGeneration !== consent.generation
  ) {
    throw new RagFailure('INDEX_NOT_READY');
  }
  if (!Array.isArray(context.notes)) throw new RagFailure('INDEX_NOT_READY');

  const scoped = new Map<string, CanonicalNote>();
  for (const note of context.notes) {
    if (note === null || typeof note !== 'object' || typeof note.noteId !== 'string') {
      throw new RagFailure('INDEX_NOT_READY');
    }
    scoped.set(note.noteId, note);
  }

  const chunks: Chunk[] = [];
  const withArtifacts = new Set<string>();
  const seen = new Set<string>();
  for (const document of documents) {
    const note = scoped.get(document.chunk.noteId);
    if (note === undefined) continue;
    if (document.chunk.ownerId !== context.actor) throw new RagFailure('SCOPE_DENIED');
    if (document.chunk.revision !== note.revision || document.chunk.title !== note.title) {
      throw new RagFailure('INDEX_NOT_READY');
    }
    if (
      document.chunk.endOffset > note.content.length ||
      note.content.slice(document.chunk.startOffset, document.chunk.endOffset) !== document.chunk.text
    ) {
      throw new RagFailure('INDEX_NOT_READY');
    }
    const key = document.sourceKey;
    if (seen.has(key) || vectors.get(key) === undefined) throw new RagFailure('INDEX_NOT_READY');
    seen.add(key);
    withArtifacts.add(note.noteId);
    chunks.push(document.chunk);
  }
  // A scoped note that produced no artifact is an incoherent index, not "no evidence".
  for (const note of scoped.values()) {
    if (note.content.trim() && !withArtifacts.has(note.noteId)) throw new RagFailure('INDEX_NOT_READY');
  }
  return { chunks: Object.freeze(chunks), vectors };
};

export function createMockIndex(snapshot: LexicalSnapshot): MockIndex {
  if (snapshot === null || typeof snapshot !== 'object') throw new RagFailure('INDEX_NOT_READY');
  const metadata = assertStaticMetadata(snapshot.metadata);
  if (snapshot.codec !== LEXICAL_CODEC || !Array.isArray(snapshot.documents)) throw new RagFailure('INDEX_NOT_READY');
  const documents: IndexedDocument[] = [];
  const vectors = new Map<string, readonly number[]>();
  for (const entry of snapshot.documents) {
    const document = decodeDocument(entry);
    if (vectors.has(document.sourceKey)) throw new RagFailure('INDEX_NOT_READY');
    documents.push(document);
    vectors.set(document.sourceKey, embedSearchDocument(embeddingText(document.chunk)));
  }
  const frozenDocuments: readonly IndexedDocument[] = Object.freeze(documents);
  const stored: ReadonlyMap<string, readonly number[]> = vectors;

  const vectorSearch = async (vector: readonly number[], context: RequestContext): Promise<readonly Ranked[]> => {
    const corpus = coherentCorpus(metadata, frozenDocuments, stored, context);
    // Cosine as a dot product of unit vectors: validate and normalize the incoming query vector,
    // never re-embed it. Vectors that are not the active finite dims are INDEX_NOT_READY upstream too.
    const query = unitVector(vector);
    const scored: { chunk: Chunk; score: number }[] = [];
    for (const chunk of corpus.chunks) {
      const storedVector = corpus.vectors.get(sourceKey(chunk));
      if (storedVector === undefined) throw new RagFailure('INDEX_NOT_READY');
      // Lexical-toy vectors are orthogonal (0) for token-disjoint text; 0 is not a match.
      const score = dot(query, storedVector);
      if (score > 0) scored.push({ chunk, score });
    }
    scored.sort((left, right) => right.score - left.score || compareSourceKey(left.chunk, right.chunk));
    const ranked = scored
      .slice(0, VECTOR_TOP_K)
      .map((entry, index) => Object.freeze({ chunk: entry.chunk, rank: index + 1 }));
    return Object.freeze(ranked);
  };

  const keywordSearch = async (question: string, context: RequestContext): Promise<readonly Ranked[]> => {
    const corpus = coherentCorpus(metadata, frozenDocuments, stored, context);
    // Independent BM25 over the same coherent corpus (analyzer v1), Top-20 with positive matches.
    return Object.freeze(bm25(question, corpus.chunks).map((entry) => Object.freeze({ ...entry })));
  };

  const getVectors = async (
    chunks: readonly Chunk[],
    context: RequestContext,
  ): Promise<ReadonlyMap<string, readonly number[]>> => {
    const corpus = coherentCorpus(metadata, frozenDocuments, stored, context);
    const available = new Map<string, readonly number[]>();
    for (const chunk of corpus.chunks) {
      const key = sourceKey(chunk);
      const vector = corpus.vectors.get(key);
      if (vector === undefined) throw new RagFailure('INDEX_NOT_READY');
      available.set(key, vector);
    }
    const result = new Map<string, readonly number[]>();
    if (!Array.isArray(chunks)) throw new RagFailure('INDEX_NOT_READY');
    for (const chunk of chunks) {
      try {
        assertChunk(chunk);
      } catch {
        throw new RagFailure('INDEX_NOT_READY');
      }
      const key = sourceKey(chunk);
      const vector = available.get(key);
      if (vector === undefined) throw new RagFailure('INDEX_NOT_READY');
      validateVector(vector);
      result.set(key, vector);
    }
    return result;
  };

  const neighbors = async (anchors: readonly Chunk[], context: RequestContext): Promise<readonly Chunk[]> => {
    const corpus = coherentCorpus(metadata, frozenDocuments, stored, context);
    if (!Array.isArray(anchors)) throw new RagFailure('INDEX_NOT_READY');
    const byOrdinal = new Map<string, Chunk>();
    const byKey = new Map<string, Chunk>();
    for (const chunk of corpus.chunks) {
      byOrdinal.set(ordinalKey(chunk), chunk);
      byKey.set(sourceKey(chunk), chunk);
    }
    const anchorKeys = new Set<string>();
    for (const anchor of anchors) {
      try {
        assertChunk(anchor);
      } catch {
        throw new RagFailure('INDEX_NOT_READY');
      }
      const key = sourceKey(anchor);
      const storedAnchor = byKey.get(key);
      if (storedAnchor === undefined || !sameChunk(storedAnchor, anchor)) throw new RagFailure('INDEX_NOT_READY');
      anchorKeys.add(key);
    }
    // Exactly +/-1 ordinal inside the same note/revision/section; no recursion, no forced fill.
    const result: Chunk[] = [];
    const seen = new Set<string>();
    for (const anchor of anchors) {
      for (const delta of [-1, 1]) {
        const candidate = byOrdinal.get(ordinalKey({ ...anchor, ordinal: anchor.ordinal + delta }));
        if (candidate === undefined) continue;
        const key = sourceKey(candidate);
        if (anchorKeys.has(key) || seen.has(key)) continue;
        seen.add(key);
        result.push(candidate);
      }
    }
    return Object.freeze(result);
  };

  return Object.freeze({
    metadata,
    encodeLexicalSnapshot: () =>
      encodeLexicalSnapshot(Object.freeze({ codec: LEXICAL_CODEC, metadata, documents: frozenDocuments })),
    vectorSearch,
    keywordSearch,
    getVectors,
    neighbors,
  });
}
