// Active profile: EmbeddingGemma-2 Q8/768. policy_v1.json stays untouched for rollback.
import policy from '../../docs/rag/policy_v2.json';
export { policy };
export type ErrorCode = keyof typeof policy.technicalDefaults.errorHttpStatus;
export class RagFailure extends Error {
  constructor(public readonly code: ErrorCode) { super(code); }
}
export type Scope = Readonly<{ type: 'account' }> | Readonly<{ type: 'note'; noteId: string }>;
export type RagRequest = Readonly<{ wireVersion: 1; question: string; scope: Scope }>;
export type CanonicalNote = Readonly<{
  ownerId: string; noteId: string; revision: number; title: string; content: string;
  synced: boolean; protected: boolean; deleted: boolean; available: boolean;
  incomingShared?: boolean;
}>;
export type Chunk = Readonly<{
  ownerId: string; noteId: string; revision: number; sectionId: string; chunkId: string;
  ordinal: number; title: string; startOffset: number; endOffset: number; text: string;
}>;
/**
 * Optional raw ranking signals. `vectorDistance` is a cosine distance in [0,2] and `bm25Score`
 * is a positive finite BM25 score. They are carried for diagnostics/ranking policy only: the
 * fused `score` and all RRF/MMR decisions never read them, and a legacy branch entry without
 * them stays valid (absence is `undefined`, never a fabricated number).
 */
export type Ranked = Readonly<{
  chunk: Chunk; rank: number; vectorDistance?: number; bm25Score?: number;
}>;
export type Candidate = Readonly<{
  chunk: Chunk; score: number; vectorRank?: number; bm25Rank?: number;
  vectorDistance?: number; bm25Score?: number;
}>;
export type Source = Readonly<{
  sourceId: string; noteId: string; revision: number; title: string;
  startOffset: number; endOffset: number; quote: string;
}>;
export type Evidence = Readonly<{ sources: readonly Source[]; text: string }>;
export type Counter = (text: string) => number;
export type Counters = Readonly<{ embedding: Counter; evidence: Counter; jev: Counter; output: Counter }>;
export type Verdict = 'ALLOW' | 'INSUFFICIENT_EVIDENCE' | 'UNRESOLVED_CONFLICT' | 'UNCERTAIN';
export type RagResponse =
  | Readonly<{ wireVersion: 1; requestId: string; status: 'ANSWERED'; answer: string; sources: readonly Source[] }>
  | Readonly<{ wireVersion: 1; requestId: string; status: 'NOT_ENOUGH_CONTEXT'; reason: Exclude<Verdict, 'ALLOW'>; answer: null; sources: readonly [] }>
  | Readonly<{ wireVersion: 1; requestId: string; status: 'ERROR'; code: ErrorCode }>;
export type CanonicalState = Readonly<{
  actorId: string; sessionGeneration: number;
  consent: Readonly<{ accepted: boolean; version: string; generation: number }>;
  indexReady: boolean; manifestVersion: string; notes: readonly CanonicalNote[];
}>;
export type AuthorityStore = Readonly<{ read(actor: string, signal: AbortSignal): Promise<CanonicalState> }>;
export type RequestContext = Readonly<{
  actor: string; request: RagRequest; state: CanonicalState; notes: readonly CanonicalNote[];
  signal: AbortSignal; revalidate(): Promise<void>;
}>;
export type RetrievalDeps = Readonly<{
  /**
   * `beforeDispatch` is the pipeline's captured `RequestContext.revalidate`. It must be awaited
   * after the reservation and immediately before the paid provider call, so a permit/consent/
   * source change that lands during an async reservation can never be followed by egress.
   * It is optional so every existing direct caller keeps its two-argument signature.
   */
  embedQuery(question: string, signal: AbortSignal, beforeDispatch?: () => Promise<void>): Promise<readonly number[]>;
  vectorSearch(vector: readonly number[], context: RequestContext): Promise<readonly Ranked[]>;
  keywordSearch(question: string, context: RequestContext): Promise<readonly Ranked[]>;
  getVectors(chunks: readonly Chunk[], context: RequestContext): Promise<ReadonlyMap<string, readonly number[]>>;
  neighbors(anchors: readonly Chunk[], context: RequestContext): Promise<readonly Chunk[]>;
}>;
export type JevInput = Readonly<{
  model: string; questionSetVersion: string;
  questions: typeof policy.jev.questions;
  state: Readonly<{ question: string; evidence: string }>;
}>;
export type GenerateInput = Readonly<{ question: string; evidence: Evidence; maxOutputTokens: number }>;
export type Providers = Readonly<{
  /**
   * `beforeDispatch` is the pipeline's captured `RequestContext.revalidate`. A quota-reserving
   * wrapper must await it after the reservation and immediately before the raw paid call, so a
   * permit/consent/source change during the reservation never reaches the provider. Optional so
   * every existing two-argument implementation and direct caller is unchanged.
   */
  jev(input: JevInput, signal: AbortSignal, beforeDispatch?: () => Promise<void>): Promise<unknown>;
  generate(input: GenerateInput, signal: AbortSignal, beforeDispatch?: () => Promise<void>): Promise<unknown>;
}>;
export type RuntimeConfig = Readonly<{
  mode: 'mock' | 'live'; model: string | null;
  thresholds: Readonly<{ answerabilityMin: number; conflictMax: number }> | null;
  jevMaxTokens: number; requestTimeoutMs: number;
}>;
export const sourceKey = (c: Pick<Chunk, 'ownerId' | 'noteId' | 'revision' | 'sectionId' | 'chunkId'>): string =>
  JSON.stringify([c.ownerId, c.noteId, c.revision, c.sectionId, c.chunkId]);
