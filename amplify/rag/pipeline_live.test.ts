/**
 * Phase 4 live-pipeline tests: the private approval gate runs before any egress, only the
 * `rag-smoke-` actor may use an approved live config, the retrieval phase stays inside the 26s
 * deadline, and an approved request still runs the unchanged P2 pipeline (quota, evidence, Jev,
 * generation, release). Mock mode ignores approval values entirely.
 *
 * Runner: node --import tsx --test amplify/rag/pipeline_live.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chunkNote } from './chunking';
import { CONSENT_VERSION } from './contract';
import { countSyntheticTokens, createMockRuntime } from './mock';
import { createQuery } from './pipeline';
import type { PipelineDeps } from './pipeline';
import { policy, sourceKey } from './types';
import type {
  CanonicalNote, CanonicalState, Counters, Evidence, GenerateInput, JevInput,
  RagRequest, RagResponse, RetrievalDeps, RuntimeConfig,
} from './types';

const LIVE_MODEL = 'jev-1.13.0';
const SMOKE_ACTOR = 'rag-smoke-a';
const QUESTION = 'alpha beta gamma';
const THRESHOLDS = Object.freeze({ answerabilityMin: 0.9, conflictMax: 0.1 });

const liveConfig = (patch: Partial<RuntimeConfig> = {}): RuntimeConfig =>
  Object.freeze({
    mode: 'live',
    model: LIVE_MODEL,
    thresholds: THRESHOLDS,
    jevMaxTokens: 32_768,
    requestTimeoutMs: policy.technicalDefaults.wire.requestTimeoutMs,
    ...patch,
  });

const approval = (patch: Record<string, unknown> = {}): unknown =>
  Object.freeze({
    model: LIVE_MODEL,
    thresholds: THRESHOLDS,
    fixtureVersion: 'rag-phase4-fixtures.v1',
    calibrationVersion: 'rag-phase4-confirmation-2026-10-12.v1',
    ...patch,
  });

const note = (): CanonicalNote =>
  Object.freeze({
    ownerId: SMOKE_ACTOR,
    noteId: 'n-live',
    revision: 4,
    title: 'Ghi chu live',
    content: Array.from({ length: 220 }, (_, index) => `doan ${index} noi ve alpha beta gamma`).join('. '),
    synced: true,
    protected: false,
    deleted: false,
    available: true,
  });

const state = (actor: string, notes: readonly CanonicalNote[]): CanonicalState =>
  Object.freeze({
    actorId: actor,
    sessionGeneration: 3,
    consent: Object.freeze({ accepted: true, version: CONSENT_VERSION, generation: 2 }),
    indexReady: true,
    manifestVersion: 'v1',
    notes: Object.freeze(notes),
  });

type LiveCounts = {
  authority: number; quota: number; embed: number; vector: number; keyword: number;
  getVectors: number; neighbors: number; jev: number; generate: number;
};

type LiveHarness = Readonly<{ deps: PipelineDeps; counts: LiveCounts; evidence: { value: Evidence | null } }>;

/** The smallest complete live composition: authorized state, one anchor chunk and stub providers. */
const liveHarness = (patch: Partial<PipelineDeps> = {}): LiveHarness => {
  const counts: LiveCounts = {
    authority: 0, quota: 0, embed: 0, vector: 0, keyword: 0, getVectors: 0, neighbors: 0, jev: 0, generate: 0,
  };
  const counters: Counters = Object.freeze({
    embedding: countSyntheticTokens, evidence: countSyntheticTokens,
    jev: countSyntheticTokens, output: countSyntheticTokens,
  });
  const notes = [note()];
  const anchor = chunkNote(notes[0]!, countSyntheticTokens)[0]!;
  const vector = Array.from({ length: policy.embedding.dimensions }, (_, index) => (index === 0 ? 1 : 0));
  const evidence = { value: null as Evidence | null };

  const retrieval: RetrievalDeps = {
    embedQuery: async (_question, signal) => {
      counts.embed += 1;
      if (signal.aborted) throw new Error('aborted');
      return vector;
    },
    vectorSearch: async () => {
      counts.vector += 1;
      return [{ chunk: anchor, rank: 1 }];
    },
    keywordSearch: async () => {
      counts.keyword += 1;
      return [];
    },
    getVectors: async (chunks) => {
      counts.getVectors += 1;
      return new Map(chunks.map((chunk) => [sourceKey(chunk), vector] as const));
    },
    neighbors: async () => {
      counts.neighbors += 1;
      return [];
    },
  };

  const deps: PipelineDeps = {
    authority: {
      read: async (actor) => {
        counts.authority += 1;
        if (actor !== SMOKE_ACTOR) throw new Error('unauthorized');
        return state(actor, notes);
      },
    },
    retrieval,
    providers: {
      jev: async (input: JevInput) => {
        counts.jev += 1;
        assert.equal(input.model, LIVE_MODEL);
        return {
          model: LIVE_MODEL,
          answers: {
            answerable_from_evidence: { type: 'noul', noul: 0.96 },
            has_unresolved_conflict: { type: 'noul', noul: 0.03 },
          },
          usage: { input_tokens: 12, output_tokens: 4 },
        };
      },
      generate: async (input: GenerateInput) => {
        counts.generate += 1;
        evidence.value = input.evidence;
        const first = input.evidence.sources[0]!;
        return { answer: `Theo nguồn: ${first.quote} [${first.sourceId}]`, sources: [{ ...first }] };
      },
    },
    counters,
    config: liveConfig(),
    consumeQuota: async () => {
      counts.quota += 1;
      return true;
    },
    liveApproval: approval(),
    ...patch,
  };
  return Object.freeze({ deps, counts, evidence });
};

const request: RagRequest = { wireVersion: 1, question: QUESTION, scope: { type: 'account' } };
const run = (deps: PipelineDeps, actor = SMOKE_ACTOR, id = 'live-1'): Promise<RagResponse> =>
  createQuery(deps)(actor, request, id);
const codeOf = (response: RagResponse): string => {
  if (response.status !== 'ERROR') assert.fail(`expected ERROR, got ${response.status}`);
  return response.code;
};

test('an approved live request runs the unchanged pipeline end to end', async () => {
  const harness = liveHarness();
  const response = await run(harness.deps);
  if (response.status !== 'ANSWERED') assert.fail(`expected ANSWERED, got ${response.status}`);
  assert.ok(response.sources.length > 0);
  assert.ok(response.sources[0]!.quote.length > 0);
  // One authorization read plus the eight per-stage revalidations the P2 pipeline always makes.
  assert.deepEqual(harness.counts, {
    authority: 9, quota: 1, embed: 1, vector: 1, keyword: 1, getVectors: 1, neighbors: 1, jev: 1, generate: 1,
  });
  assert.ok(harness.evidence.value !== null);
  assert.deepEqual(harness.evidence.value.sources.map((source) => source.sourceId), response.sources.map((s) => s.sourceId));
});

test('without an approval live mode is refused before any port call', async () => {
  const harness = liveHarness({ liveApproval: undefined });
  assert.equal(codeOf(await run(harness.deps)), 'LIVE_POLICY_NOT_CONFIGURED');
  assert.deepEqual(harness.counts, {
    authority: 0, quota: 0, embed: 0, vector: 0, keyword: 0, getVectors: 0, neighbors: 0, jev: 0, generate: 0,
  });
});

test('an invalid, mutable or mismatched approval is refused before any port call', async () => {
  const cases: readonly unknown[] = [
    {}, // missing everything
    approval({ model: 'jev-9.9.9' }), // model not pinned by the config
    approval({ thresholds: Object.freeze({ answerabilityMin: 0.95, conflictMax: 0.1 }) }),
    approval({ thresholds: Object.freeze({ answerabilityMin: 0.9, conflictMax: 0.05 }) }),
    approval({ fixtureVersion: '' }),
    approval({ calibrationVersion: '  ' }),
    approval({ retrievalStageMs: 7_000 }),
    { ...(approval() as Record<string, unknown>) }, // mutable copy
  ];
  for (const candidate of cases) {
    const harness = liveHarness({ liveApproval: candidate });
    assert.equal(codeOf(await run(harness.deps)), 'LIVE_POLICY_NOT_CONFIGURED');
    assert.equal(harness.counts.authority + harness.counts.quota + harness.counts.embed, 0, 'no egress');
  }
});

test('a non-smoke actor is refused even with a valid approval', async () => {
  const harness = liveHarness();
  assert.equal(codeOf(await run(harness.deps, 'actor-a')), 'LIVE_POLICY_NOT_CONFIGURED');
  assert.equal(harness.counts.authority, 0);
  assert.equal(harness.counts.jev, 0);
});

test('the retrieval phase bound stops a hanging retrieval without touching Jev', async () => {
  const started = Date.now();
  const hanging: RetrievalDeps = {
    ...liveHarness().deps.retrieval,
    embedQuery: (_question, signal) =>
      new Promise<readonly number[]>((_resolve, reject) => {
        signal.addEventListener('abort', () => reject(new Error('aborted')), { once: true });
      }),
  };
  const harness = liveHarness({ retrieval: hanging, liveApproval: approval({ retrievalStageMs: 25 }) });
  assert.equal(codeOf(await run(harness.deps)), 'TIMEOUT');
  assert.ok(Date.now() - started < 5_000, 'the retrieval bound is far below the total deadline');
  assert.equal(harness.counts.jev, 0);
  assert.equal(harness.counts.generate, 0);
});

test('a retrieval bound at or above the request deadline can never be approved', async () => {
  const harness = liveHarness({
    config: liveConfig({ requestTimeoutMs: 5_000 }),
    liveApproval: approval(),
  });
  assert.equal(codeOf(await run(harness.deps)), 'LIVE_POLICY_NOT_CONFIGURED');
  assert.equal(harness.counts.authority, 0);
});

test('quota stays mandatory in live mode: a denial stops retrieval before the first embedding', async () => {
  const harness = liveHarness({ consumeQuota: async () => false });
  assert.equal(codeOf(await run(harness.deps)), 'RATE_LIMITED');
  assert.equal(harness.counts.authority, 1);
  assert.equal(harness.counts.embed, 0);
  assert.equal(harness.counts.jev, 0);
});

test('mock mode ignores any liveApproval value and still answers', async () => {
  const runtime = createMockRuntime();
  const mockRequest: RagRequest = {
    wireVersion: 1,
    question: 'SLGH031 chạy bao lâu khi lên cót đầy?',
    scope: { type: 'account' },
  };
  const response = await createQuery({ ...runtime.deps, liveApproval: { not: 'an approval' } })(
    'actor-a',
    mockRequest,
    'mock-1',
  );
  assert.equal(response.status, 'ANSWERED');
  assert.equal(runtime.counts.jev, 1);
  assert.equal(runtime.counts.generation, 1);
});

test('an empty eligible scope abstains in live mode without any embedding egress', async () => {
  const empty = state(SMOKE_ACTOR, []);
  const harness = liveHarness({
    authority: { read: async (actor) => (actor === SMOKE_ACTOR ? empty : Promise.reject(new Error('unauthorized'))) },
  });
  const response = await run(harness.deps);
  if (response.status !== 'NOT_ENOUGH_CONTEXT') assert.fail('empty scope must abstain');
  assert.equal(response.reason, 'INSUFFICIENT_EVIDENCE');
  assert.equal(harness.counts.embed, 0);
  assert.equal(harness.counts.vector, 0);
  assert.equal(harness.counts.jev, 0);
});
