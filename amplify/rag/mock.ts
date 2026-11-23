// Synthetic composition only: explicit fixture consent and scripted provider outcomes.
import notesFixture from '../../test/fixtures/rag/notes.json';
import { CONSENT_VERSION } from './contract';
import { countUnicodeCharacters } from './chunking';
import { createRagHandler } from './handler';
import type { RagHandler } from './handler';
import { buildLexicalSnapshot, createMockIndex, embedSearchQuery } from './mock_index';
import type { MockIndex } from './mock_index';
import { createQuery } from './pipeline';
import type { PipelineDeps } from './pipeline';
import { policy, RagFailure } from './types';
import type {
  CanonicalNote,
  CanonicalState,
  Counter,
  Counters,
  GenerateInput,
  JevInput,
  Providers,
  RetrievalDeps,
  RuntimeConfig,
} from './types';

export const MOCK_MODEL = 'jev-fixture';
export const MOCK_MANIFEST_VERSION = 'mock-1';
export const MOCK_SESSION_GENERATION = 1;
export const MOCK_CONSENT_GENERATION = 1;
export const MOCK_JEV_MAX_TOKENS = 32_768;
/** Named provenance for the helpers that stand in for real tokenizers/models. */
export const SYNTHETIC_COUNTER_PROVENANCE = 'synthetic-ceil-codepoints/4-not-a-model-tokenizer';
export const SYNTHETIC_THRESHOLD_PROVENANCE: string = policy.mockOnly.provenance;
export const SYNTHETIC_SCENARIOS = ['allow', 'insufficient', 'conflict', 'uncertain', 'malformed', 'timeout', 'invalid-output'] as const;

export type MockScenario = (typeof SYNTHETIC_SCENARIOS)[number];
export type MockRuntimeOptions = Readonly<{ scenario?: MockScenario }>;
export type MockCounts = {
  embedding: number;
  vector: number;
  keyword: number;
  getVectors: number;
  neighbors: number;
  jev: number;
  generation: number;
};
export type MockAuthorityStore = Readonly<{
  /** Exposed for test mutation only; `read` always returns a fresh clone. */
  states: Map<string, CanonicalState>;
  read(actor: string, signal: AbortSignal): Promise<CanonicalState>;
}>;
export type MockRuntime = Readonly<{
  handler: RagHandler;
  deps: PipelineDeps;
  counts: MockCounts;
  store: MockAuthorityStore;
  index: ReadonlyMap<string, MockIndex>;
}>;

// shortcut: ceil(codepoints/4) is a fixture counter; use verified provider counters before live.
export const countSyntheticTokens: Counter = (text) =>
  typeof text === 'string' ? Math.ceil(countUnicodeCharacters(text) / 4) : Number.NaN;

/** Fixture Jev probabilities (policy.mockOnly, provenance = synthetic-fixture-values-not-calibrated). */
const JEV_PROBABILITIES: Readonly<Record<'allow' | 'insufficient' | 'conflict' | 'uncertain', readonly [number, number]>> = {
  allow: [0.96, 0.03],
  insufficient: [0.03, 0.03],
  conflict: [0.96, 0.97],
  uncertain: [0.5, 0.03],
};

const FIXTURE_NOTES: readonly CanonicalNote[] = Object.freeze(
  notesFixture.notes.map((note) =>
    Object.freeze({
      ownerId: note.ownerId,
      noteId: note.noteId,
      revision: note.revision,
      title: note.title,
      content: note.content,
      synced: note.synced,
      protected: note.protected,
      deleted: note.deleted,
      available: note.available,
    }),
  ),
);

const assertLive = (signal: AbortSignal): void => {
  if (signal.aborted) throw new RagFailure('TIMEOUT');
};

/** One shared fixture projection per actor: the authority and scope filters still decide access. */
const syntheticState = (actor: string): CanonicalState =>
  Object.freeze({
    actorId: actor,
    sessionGeneration: MOCK_SESSION_GENERATION,
    consent: Object.freeze({ accepted: true, version: CONSENT_VERSION, generation: MOCK_CONSENT_GENERATION }),
    indexReady: true,
    manifestVersion: MOCK_MANIFEST_VERSION,
    notes: FIXTURE_NOTES,
  });

const MOCK_CONFIG: RuntimeConfig = Object.freeze({
  mode: 'mock',
  model: MOCK_MODEL,
  thresholds: Object.freeze({
    answerabilityMin: policy.mockOnly.thresholds.answerabilityMin,
    conflictMax: policy.mockOnly.thresholds.conflictMax,
  }),
  jevMaxTokens: MOCK_JEV_MAX_TOKENS,
  requestTimeoutMs: policy.technicalDefaults.wire.requestTimeoutMs,
});

const jevEnvelope = (support: number, conflict: number, input: JevInput): unknown => ({
  model: MOCK_MODEL,
  answers: {
    answerable_from_evidence: { type: 'noul', noul: support },
    has_unresolved_conflict: { type: 'noul', noul: conflict },
  },
  usage: {
    input_tokens: countSyntheticTokens(JSON.stringify(input)),
    output_tokens: countSyntheticTokens(`${support}/${conflict}`),
  },
});

/** Malformed fixture: `noul` is a boolean, which the contract must refuse without generating. */
const malformedJevEnvelope = (input: JevInput): unknown => ({
  model: MOCK_MODEL,
  answers: {
    answerable_from_evidence: { type: 'noul', noul: true },
    has_unresolved_conflict: { type: 'noul', noul: false },
  },
  usage: {
    input_tokens: countSyntheticTokens(JSON.stringify(input)),
    output_tokens: countSyntheticTokens('malformed'),
  },
});

const hangingUntilAbort = (signal: AbortSignal): Promise<never> =>
  new Promise<never>((_resolve, reject) => {
    signal.addEventListener('abort', () => reject(new RagFailure('TIMEOUT')), { once: true });
  });

const generateEnvelope = (input: GenerateInput, scenario: MockScenario): unknown => {
  if (scenario === 'invalid-output') {
    // Invented source: not in the approved bundle, so citation validation must refuse it.
    return {
      answer: 'Câu trả lời bịa. [S1]',
      sources: [
        { sourceId: 'S1', noteId: 'n-invented', revision: 1, title: 'Invented', startOffset: 0, endOffset: 8, quote: 'invented' },
      ],
    };
  }
  const first = input.evidence.sources[0];
  if (first === undefined) throw new RagFailure('EVIDENCE_VALIDATION_UNAVAILABLE');
  // Quotes the approved source; this proves lineage only, never semantic accuracy.
  return { answer: `Theo nguồn: ${first.quote} [${first.sourceId}]`, sources: [{ ...first }] };
};

/**
 * Builds the synthetic runtime: fixture actor-a/actor-b canonical states, one RAM index per actor,
 * in-memory counters and the HTTP handler wired as `createRagHandler(createQuery(deps))`.
 * `deps` is intentionally not frozen so integration tests can replace provider/retrieval hooks.
 */
export function createMockRuntime(options: MockRuntimeOptions = {}): MockRuntime {
  const scenario: MockScenario = options.scenario ?? 'allow';
  const counts: MockCounts = { embedding: 0, vector: 0, keyword: 0, getVectors: 0, neighbors: 0, jev: 0, generation: 0 };
  const counters: Counters = Object.freeze({
    embedding: countSyntheticTokens,
    evidence: countSyntheticTokens,
    jev: countSyntheticTokens,
    output: countSyntheticTokens,
  });

  const states = new Map<string, CanonicalState>([
    ['actor-a', syntheticState('actor-a')],
    ['actor-b', syntheticState('actor-b')],
  ]);
  const store: MockAuthorityStore = {
    states,
    read: async (actor, signal) => {
      assertLive(signal);
      const state = states.get(actor);
      if (state === undefined) throw new RagFailure('UNAUTHORIZED');
      return structuredClone(state);
    },
  };

  const index = new Map<string, MockIndex>();
  for (const [actor, state] of states) {
    index.set(actor, createMockIndex(buildLexicalSnapshot(actor, state, counters.embedding)));
  }
  const indexFor = (actor: string): MockIndex => {
    const found = index.get(actor);
    if (found === undefined) throw new RagFailure('INDEX_NOT_READY');
    return found;
  };

  const retrieval: RetrievalDeps = {
    // policy.embedding.queryInputType = "search_query"; synthetic lexical hash, no provider call.
    embedQuery: async (question, signal) => {
      counts.embedding += 1;
      assertLive(signal);
      return embedSearchQuery(question);
    },
    vectorSearch: async (vector, context) => {
      counts.vector += 1;
      assertLive(context.signal);
      return indexFor(context.actor).vectorSearch(vector, context);
    },
    keywordSearch: async (question, context) => {
      counts.keyword += 1;
      assertLive(context.signal);
      return indexFor(context.actor).keywordSearch(question, context);
    },
    getVectors: async (chunks, context) => {
      counts.getVectors += 1;
      assertLive(context.signal);
      return indexFor(context.actor).getVectors(chunks, context);
    },
    neighbors: async (anchors, context) => {
      counts.neighbors += 1;
      assertLive(context.signal);
      return indexFor(context.actor).neighbors(anchors, context);
    },
  };

  const providers: Providers = {
    jev: async (input, signal) => {
      counts.jev += 1;
      assertLive(signal);
      if (scenario === 'timeout') return hangingUntilAbort(signal);
      if (scenario === 'malformed') return malformedJevEnvelope(input);
      const [support, conflict] = scenario === 'invalid-output' ? JEV_PROBABILITIES.allow : JEV_PROBABILITIES[scenario];
      return jevEnvelope(support, conflict, input);
    },
    generate: async (input, signal) => {
      counts.generation += 1;
      assertLive(signal);
      return generateEnvelope(input, scenario);
    },
  };

  const deps: PipelineDeps = {
    authority: store,
    retrieval,
    providers,
    counters,
    config: MOCK_CONFIG,
    // Synthetic in-process quota: always grants, never bills. Real quota is a Phase 3 port.
    consumeQuota: async (_actor, signal) => {
      assertLive(signal);
      return true;
    },
  };

  return Object.freeze({ handler: createRagHandler(createQuery(deps)), deps, counts, store, index });
}
