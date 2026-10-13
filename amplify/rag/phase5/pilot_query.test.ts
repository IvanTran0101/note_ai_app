/**
 * Phase 5 pilot query tests: the trusted config/actor gate before composition, the canonical
 * pipeline reached through the guarded index store, the atomic lease/Cohere debits, fail-closed
 * config/consent/index moves, the single reservation per provider and the independent bounded
 * lease release. Synthetic in-process index/providers only; no AWS, network or model call.
 *
 * Runner: node --import tsx --test amplify/rag/phase5/pilot_query.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chunkNote } from '../chunking';
import { CONSENT_VERSION } from '../contract';
import { countSyntheticTokens } from '../mock';
import { policy, RagFailure, sourceKey } from '../types';
import type { Counter, GenerateInput, JevInput, Providers, RagRequest, RagResponse } from '../types';
import { fingerprint } from '../indexing/jobs';
import { checksum, embeddingInputDigest, policyIdentity, sha256Hex } from '../indexing/snapshot';
import type { Artifacts, Document, IndexDeps, IndexState, IndexStore, Manifest, Snapshot } from '../indexing/types';
import { readLiveApproval } from '../live_policy';
import type { LiveApproval } from '../live_policy';
import type { PilotBudget, QueryLease } from './pilot_budget';
import { createPilotQuery } from './pilot_query';
import { RUNTIME_CASE_HASH, RUNTIME_CONFIG_VERSION, RUNTIME_CORPUS_KIND, parseRuntimeConfig } from './runtime_config';
import type { RuntimeConfig } from './runtime_config';

const ACTOR = '00000001-0000-4000-8000-000000000001';
const OTHER = '00000009-0000-4000-8000-000000000009';
const TITLE = 'Tieu de n-a';
const CONTENT = Array.from({ length: 220 }, (_, index) => `doan ${index} noi ve alpha beta gamma cua a`).join('. ');
const REQUEST: RagRequest = { wireVersion: 1, question: 'alpha beta gamma', scope: { type: 'account' } };

const vector1024 = (seed: number): readonly number[] =>
  Object.freeze(Array.from({ length: policy.embedding.dimensions }, (_, index) => (index === seed % 8 ? 1 : 0)));

const isCode = (code: string) => (error: unknown): boolean =>
  error instanceof RagFailure && error.code === code;

const rawConfig = (
  patch: { generation?: number; enabled?: boolean; owners?: readonly string[] } = {},
): RuntimeConfig => {
  const owners = patch.owners ?? [ACTOR];
  return parseRuntimeConfig({
    version: RUNTIME_CONFIG_VERSION,
    generation: patch.generation ?? 1,
    policy: { enabled: patch.enabled ?? true, owners, model: 'jev-1.13.0',
      thresholds: { answerabilityMin: 0.85, conflictMax: 0.1 } },
    corpus: { kind: RUNTIME_CORPUS_KIND, caseHash: RUNTIME_CASE_HASH,
      owners: Object.fromEntries(owners.map((owner) =>
        [owner, [{ noteId: 'n-a', inputDigest: embeddingInputDigest(TITLE, CONTENT) }]])) },
  });
};

const approval: LiveApproval = readLiveApproval(Object.freeze({
  model: 'jev-1.13.0',
  thresholds: Object.freeze({ answerabilityMin: 0.85, conflictMax: 0.1 }),
  fixtureVersion: 'fix-1', calibrationVersion: 'cal-1',
}));

const note = () => Object.freeze({
  ownerId: ACTOR, noteId: 'n-a', revision: 7, title: TITLE, content: CONTENT,
  synced: true, protected: false, deleted: false, available: true, protectionRevision: 0,
});

type Fixture = Readonly<{
  deps: IndexDeps;
  counts: { loads: number; reads: number; queries: number; embeds: number; underlyingReserve: number };
  documents: readonly Document[];
}>;

const fixture = (overrides: { manifest?: 'ready' | 'tampered' | 'none'; consent?: boolean } = {}): Fixture => {
  const counts = { loads: 0, reads: 0, queries: 0, embeds: 0, underlyingReserve: 0 };
  const baseNote = note();
  const documents: readonly Document[] = Object.freeze(
    chunkNote(baseNote, countSyntheticTokens).map((chunk) => Object.freeze({
      chunk, vectorKey: sha256Hex(`vector\u0000${sourceKey(chunk)}`),
      embeddingDigest: sha256Hex(`digest\u0000${sourceKey(chunk)}`),
    })),
  );
  const base: IndexState = {
    ownerId: ACTOR, accountEpoch: 3,
    consent: Object.freeze({ accepted: overrides.consent ?? true, version: CONSENT_VERSION, generation: 2 }),
    notes: Object.freeze([baseNote]), manifest: null,
  };
  const version = 'v1';
  const snapshot: Snapshot = Object.freeze({
    schemaVersion: 1, ownerId: ACTOR, version, consentGeneration: 2, accountEpoch: 3,
    policyIdentity: policyIdentity(), documents,
  });
  const readyManifest: Manifest = Object.freeze({
    ownerId: ACTOR, generation: 1, version,
    fingerprint: overrides.manifest === 'tampered' ? sha256Hex('tampered') : fingerprint(base),
    consentGeneration: 2, accountEpoch: 3, status: 'READY',
    snapshotKey: 'snap', checksum: checksum(snapshot), policyIdentity: policyIdentity(),
  });
  const state: IndexState = Object.freeze({
    ...base, manifest: overrides.manifest === 'none' ? null : readyManifest,
  });
  const store: IndexStore = {
    async load() { counts.loads += 1; return state; },
    async acquire() { return null; },
    async publish() { return false; },
    async finish() {},
    async reserveEmbedding() { counts.underlyingReserve += 1; },
  };
  const artifacts: Artifacts = {
    async read() { counts.reads += 1; return snapshot; },
    async put() { return { key: 'k', checksum: sha256Hex('put') }; },
    async putVectors() {},
    async getVectors(keys) { return new Map(keys.map((key, index) => [key, vector1024(index)] as const)); },
    async query(_vector, ownerId, _version, noteId) {
      counts.queries += 1;
      return documents
        .filter((document) => document.chunk.ownerId === ownerId && (noteId === null || document.chunk.noteId === noteId))
        .map((document) => document.vectorKey);
    },
    async cleanup() {},
  };
  const embedding = {
    count: countSyntheticTokens as Counter,
    async embed(texts: readonly string[]) { counts.embeds += 1; return texts.map((_text, index) => vector1024(index)); },
  };
  return Object.freeze({ deps: { store, artifacts, embedding }, counts, documents });
};

const jevEnvelope = (input: JevInput): unknown => ({
  model: 'jev-1.13.0',
  answers: {
    answerable_from_evidence: { type: 'noul', noul: 0.96 },
    has_unresolved_conflict: { type: 'noul', noul: 0.03 },
  },
  usage: { input_tokens: countSyntheticTokens(JSON.stringify(input)), output_tokens: 10 },
});

const generateEnvelope = (input: GenerateInput): unknown => {
  const first = input.evidence.sources[0];
  if (first === undefined) throw new RagFailure('EVIDENCE_VALIDATION_UNAVAILABLE');
  // Short answer that cites the approved label; the quote is not echoed back.
  return { answer: `Theo nguồn [${first.sourceId}]`, sources: [{ ...first }] };
};

type Calls = {
  readConfig: number;
  loadIndex: number;
  acquireQuery: number;
  release: number;
  reserve: string[];
  acquireCohere: number;
  rawJev: number;
  rawGenerate: number;
};

const setup = (options: {
  index?: Fixture;
  owners?: readonly string[];
  enabled?: boolean;
  config?: (call: number) => RuntimeConfig;
  reserveFailure?: 'jev' | 'deepseek';
  acquireFailure?: boolean;
  releaseHangs?: boolean;
  /** Withdraws the config (next generation) while the named async reservation is in flight. */
  mutateOn?: 'cohere' | 'jev' | 'deepseek';
} = {}) => {
  const index = options.index ?? fixture();
  const calls: Calls = {
    readConfig: 0, loadIndex: 0, acquireQuery: 0, release: 0, reserve: [], acquireCohere: 0, rawJev: 0, rawGenerate: 0,
  };
  let generation = 1;
  const readConfig = async (): Promise<RuntimeConfig> => {
    calls.readConfig += 1;
    if (options.config !== undefined) return options.config(calls.readConfig);
    return rawConfig({ owners: options.owners, enabled: options.enabled, generation });
  };
  const budget: PilotBudget = {
    async reserve(provider) {
      if (options.reserveFailure === provider) throw new RagFailure('RATE_LIMITED');
      if (options.mutateOn === provider) generation += 1;
      calls.reserve.push(provider);
    },
    async acquireQuery(actor, requestId): Promise<QueryLease> {
      if (options.acquireFailure === true) throw new RagFailure('RATE_LIMITED');
      calls.acquireQuery += 1;
      return Object.freeze({ actor, token: `lease-${calls.acquireQuery}`, expiresAt: 28_000 });
    },
    async release() {
      calls.release += 1;
      if (options.releaseHangs === true) await new Promise<never>(() => {});
    },
    async acquireCohere() {
      calls.acquireCohere += 1;
      if (options.mutateOn === 'cohere') generation += 1;
    },
    async read() { return Object.freeze({ queryCalls: 0, jevCalls: 0, deepseekCalls: 0, cohereCalls: 0, reservedUsdMicros: 0 }); },
  };
  const rawProviders: Providers = {
    async jev(input) { calls.rawJev += 1; return jevEnvelope(input); },
    async generate(input) { calls.rawGenerate += 1; return generateEnvelope(input); },
  };
  const query = createPilotQuery({
    readConfig,
    readApproval: async () => approval,
    loadIndex: () => { calls.loadIndex += 1; return index.deps; },
    budget,
    rawProviders,
    counters: { evidence: countSyntheticTokens, jev: countSyntheticTokens, output: countSyntheticTokens },
  });
  return { query, calls, index };
};

const run = (s: ReturnType<typeof setup>): Promise<RagResponse> => s.query(ACTOR, REQUEST, 'req-1');

test('a listed enabled actor runs the canonical pipeline and releases the one lease in finally', async () => {
  const s = setup();
  const response = await run(s);
  assert.equal(response.status, 'ANSWERED');
  assert.equal(s.calls.acquireQuery, 1);
  assert.equal(s.calls.release, 1);
  assert.deepEqual(s.calls.reserve, ['jev', 'deepseek']);
  assert.equal(s.calls.rawJev, 1);
  assert.equal(s.calls.rawGenerate, 1);
  // Cohere goes only through the guarded store -> budget.acquireCohere, never the old counter.
  assert.equal(s.calls.acquireCohere, 1);
  assert.equal(s.index.counts.underlyingReserve, 0);
  assert.equal(s.index.counts.embeds, 1);
});

test('a non-pilot or disabled config is refused before the index factory and every provider', async () => {
  for (const s of [setup({ owners: [OTHER] }), setup({ enabled: false })]) {
    const response = await run(s);
    assert.equal(response.status, 'ERROR');
    assert.equal((response as { code: string }).code, 'LIVE_POLICY_NOT_CONFIGURED');
    assert.equal(s.calls.loadIndex, 0);
    assert.equal(s.calls.rawJev, 0);
    assert.equal(s.calls.acquireQuery, 0);
  }
});

test('a smoke actor is not a pilot and never falls back to the smoke seam', async () => {
  const s = setup();
  const response = await s.query('rag-smoke-a', REQUEST, 'req-1');
  assert.equal(response.status, 'ERROR');
  assert.equal((response as { code: string }).code, 'LIVE_POLICY_NOT_CONFIGURED');
  assert.equal(s.calls.loadIndex, 0);
});

test('a non-ready canonical index is INDEX_NOT_READY with zero retrieval/provider calls', async () => {
  for (const manifest of ['tampered', 'none'] as const) {
    const s = setup({ index: fixture({ manifest }) });
    const response = await run(s);
    assert.equal(response.status, 'ERROR');
    assert.equal((response as { code: string }).code, 'INDEX_NOT_READY');
    assert.equal(s.calls.acquireQuery, 0);
    assert.equal(s.index.counts.embeds, 0);
    assert.equal(s.calls.rawJev, 0);
  }
});

test('a revoked consent is CONSENT_REQUIRED before any provider', async () => {
  const s = setup({ index: fixture({ consent: false }) });
  const response = await run(s);
  assert.equal(response.status, 'ERROR');
  assert.equal((response as { code: string }).code, 'CONSENT_REQUIRED');
  assert.equal(s.calls.rawJev, 0);
  assert.equal(s.calls.acquireQuery, 0);
});

test('a config change after the trusted read is SOURCE_CHANGED with zero paid work', async () => {
  const s = setup({ config: (call) => rawConfig({ generation: call === 1 ? 1 : 2 }) });
  const response = await run(s);
  assert.equal(response.status, 'ERROR');
  assert.equal((response as { code: string }).code, 'SOURCE_CHANGED');
  assert.equal(s.calls.acquireQuery, 0);
  assert.equal(s.calls.rawJev, 0);
});

test('a quota refusal stops before embedding and every provider, and releases nothing', async () => {
  const s = setup({ acquireFailure: true });
  const response = await run(s);
  assert.equal(response.status, 'ERROR');
  assert.equal((response as { code: string }).code, 'RATE_LIMITED');
  assert.equal(s.calls.rawJev, 0);
  assert.equal(s.calls.acquireCohere, 0);
  assert.equal(s.calls.release, 0);
});

test('a refused JEV reservation stops before the single raw JEV call', async () => {
  const s = setup({ reserveFailure: 'jev' });
  const response = await run(s);
  assert.equal(response.status, 'ERROR');
  assert.equal((response as { code: string }).code, 'RATE_LIMITED');
  assert.equal(s.calls.rawJev, 0);
  assert.equal(s.calls.rawGenerate, 0);
  assert.equal(s.calls.release, 1);
});

test('a provider failure still releases the captured lease exactly once', async () => {
  const s = setup();
  const query = createPilotQuery({
    readConfig: async () => rawConfig(),
    readApproval: async () => approval,
    loadIndex: () => s.index.deps,
    budget: {
      async reserve() {},
      async acquireQuery(actor): Promise<QueryLease> { return { actor, token: 't', expiresAt: 1 }; },
      async release() { s.calls.release += 1; },
      async acquireCohere() {},
      async read() { return { queryCalls: 0, jevCalls: 0, deepseekCalls: 0, cohereCalls: 0, reservedUsdMicros: 0 }; },
    },
    rawProviders: {
      jev: async () => { throw new RagFailure('TIMEOUT'); },
      generate: async () => { throw new RagFailure('PROVIDER_UNAVAILABLE'); },
    },
    counters: { evidence: countSyntheticTokens, jev: countSyntheticTokens, output: countSyntheticTokens },
  });
  const response = await query(ACTOR, REQUEST, 'req-1');
  assert.equal(response.status, 'ERROR');
  assert.equal((response as { code: string }).code, 'TIMEOUT');
  assert.equal(s.calls.release, 1);
});

test('a hung release port cannot hold the request past the independent release budget', async () => {
  const s = setup({ releaseHangs: true });
  const started = Date.now();
  const response = await run(s);
  const elapsed = Date.now() - started;
  assert.equal(response.status, 'ANSWERED');
  assert.equal(s.calls.release, 1);
  assert.ok(elapsed < 2_500, `release must be bounded, took ${elapsed}ms`);
});

test('each invocation captures a fresh config, index and lease', async () => {
  const s = setup();
  await run(s);
  await run(s);
  assert.equal(s.calls.acquireQuery, 2);
  assert.equal(s.calls.release, 2);
  assert.ok(s.calls.readConfig >= 2);
  assert.equal(s.calls.loadIndex, 2);
});

test('the builder refuses malformed dependencies without any call', () => {
  assert.throws(() => createPilotQuery({} as never), isCode('LIVE_POLICY_NOT_CONFIGURED'));
});

/**
 * Group 3 race regression: the config is withdrawn while an async reservation is in flight. The
 * reservation still counts, but the captured context is re-validated after it and immediately
 * before the raw paid call, so the corresponding provider is never invoked.
 */
test('a config withdrawal during the Cohere reservation blocks the paid embed', async () => {
  const s = setup({ mutateOn: 'cohere' });
  const response = await run(s);
  assert.equal(response.status, 'ERROR');
  assert.equal((response as { code: string }).code, 'SOURCE_CHANGED');
  assert.equal(s.calls.acquireCohere, 1, 'the reservation is still consumed');
  assert.equal(s.index.counts.embeds, 0, 'no paid embed after the permit moved');
  assert.equal(s.calls.rawJev, 0);
  assert.equal(s.calls.rawGenerate, 0);
  assert.equal(s.calls.release, 1);
});

test('a config withdrawal during the JEV reservation blocks the raw JEV call', async () => {
  const s = setup({ mutateOn: 'jev' });
  const response = await run(s);
  assert.equal(response.status, 'ERROR');
  assert.equal((response as { code: string }).code, 'SOURCE_CHANGED');
  assert.deepEqual(s.calls.reserve, ['jev'], 'the JEV reservation is still consumed');
  assert.equal(s.calls.rawJev, 0, 'no raw JEV call after the permit moved');
  assert.equal(s.calls.rawGenerate, 0);
  assert.equal(s.calls.release, 1);
});

test('a config withdrawal during the DeepSeek reservation blocks the raw generate call', async () => {
  const s = setup({ mutateOn: 'deepseek' });
  const response = await run(s);
  assert.equal(response.status, 'ERROR');
  assert.equal((response as { code: string }).code, 'SOURCE_CHANGED');
  assert.deepEqual(s.calls.reserve, ['jev', 'deepseek'], 'the DeepSeek reservation is still consumed');
  assert.equal(s.calls.rawJev, 1, 'the earlier JEV call is legitimate');
  assert.equal(s.calls.rawGenerate, 0, 'no raw generate call after the permit moved');
  assert.equal(s.calls.release, 1);
});
