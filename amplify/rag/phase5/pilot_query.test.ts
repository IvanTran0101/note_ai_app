/**
 * Phase 5 pilot query tests: the trusted config/actor gate before composition, the canonical
 * pipeline reached through the guarded index store, the atomic lease/embedding debits, fail-closed
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
import type { RagQueryDiagnostic } from '../pipeline';
import { RELEVANCE_POLICY_VERSION } from '../relevance';
import { indexRef, ownerRef } from '../query_diagnostics';
import type { DiagnosticMetadata } from '../query_diagnostics';
import type { PilotBudget, QueryLease } from './pilot_budget';
import { PILOT_DEMO_THRESHOLDS } from './pilot_policy';
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
  patch: {
    generation?: number;
    enabled?: boolean;
    owners?: readonly string[];
    thresholds?: Readonly<{ answerabilityMin: number; conflictMax: number }>;
  } = {},
): RuntimeConfig => {
  const owners = patch.owners ?? [ACTOR];
  return parseRuntimeConfig({
    version: RUNTIME_CONFIG_VERSION,
    generation: patch.generation ?? 1,
    policy: { enabled: patch.enabled ?? true, owners, model: 'jev-1.13.0',
      thresholds: patch.thresholds ?? { answerabilityMin: 0.85, conflictMax: 0.1 } },
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

const fixture = (
  overrides: {
    manifest?: 'ready' | 'tampered' | 'none';
    consent?: boolean;
    embedFailure?: 'PROVIDER_UNAVAILABLE' | 'TIMEOUT';
  } = {},
): Fixture => {
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
    async embed(texts: readonly string[]) {
      if (overrides.embedFailure !== undefined) throw new RagFailure(overrides.embedFailure);
      counts.embeds += 1;
      return texts.map((_text, index) => vector1024(index));
    },
  };
  return Object.freeze({ deps: { store, artifacts, embedding }, counts, documents });
};

const jevEnvelope = (
  input: JevInput,
  scores: Readonly<{ support: number; conflict: number }> = { support: 0.96, conflict: 0.03 },
): unknown => ({
  model: 'jev-1.13.0',
  answers: {
    answerable_from_evidence: { type: 'noul', noul: scores.support },
    has_unresolved_conflict: { type: 'noul', noul: scores.conflict },
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
  acquireEmbedding: number;
  rawJev: number;
  rawGenerate: number;
};

const setup = (options: {
  index?: Fixture;
  owners?: readonly string[];
  enabled?: boolean;
  thresholds?: Readonly<{ answerabilityMin: number; conflictMax: number }>;
  jevScores?: Readonly<{ support: number; conflict: number }>;
  config?: (call: number) => RuntimeConfig;
  reserveFailure?: 'jev' | 'deepseek';
  acquireFailure?: boolean;
  releaseHangs?: boolean;
  /** Withdraws the config (next generation) while the named async reservation is in flight. */
  mutateOn?: 'cohere' | 'jev' | 'deepseek';
  /** Captures the same safe sink production wires to JSON console output. */
  log?: (metadata: DiagnosticMetadata) => void;
} = {}) => {
  const index = options.index ?? fixture();
  const calls: Calls = {
    readConfig: 0, loadIndex: 0, acquireQuery: 0, release: 0, reserve: [], acquireEmbedding: 0, rawJev: 0, rawGenerate: 0,
  };
  let generation = 1;
  const readConfig = async (): Promise<RuntimeConfig> => {
    calls.readConfig += 1;
    if (options.config !== undefined) return options.config(calls.readConfig);
    return rawConfig({
      owners: options.owners, enabled: options.enabled, generation, thresholds: options.thresholds,
    });
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
    async acquireEmbedding() {
      calls.acquireEmbedding += 1;
      if (options.mutateOn === 'cohere') generation += 1;
    },
    async acquireCohere() { /* deprecated: the active path never calls it */ },
    async read() { return Object.freeze({ queryCalls: 0, jevCalls: 0, deepseekCalls: 0, cohereCalls: 0, selfHostedEmbeddingCalls: 0, reservedUsdMicros: 0 }); },
  };
  const rawProviders: Providers = {
    async jev(input) { calls.rawJev += 1; return jevEnvelope(input, options.jevScores); },
    async generate(input) { calls.rawGenerate += 1; return generateEnvelope(input); },
  };
  const query = createPilotQuery({
    readConfig,
    readApproval: async () => approval,
    loadIndex: () => { calls.loadIndex += 1; return index.deps; },
    budget,
    rawProviders,
    counters: { evidence: countSyntheticTokens, jev: countSyntheticTokens, output: countSyntheticTokens },
    log: options.log,
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
  // Self-hosted embedding goes only through the guarded store -> budget.acquireEmbedding.
  assert.equal(s.calls.acquireEmbedding, 1);
  assert.equal(s.index.counts.underlyingReserve, 0);
  assert.equal(s.index.counts.embeds, 1);
});

test('the exact 0.5 demo pilot answers .66/.06 and refuses .49/.06 with the genuine .85 approval', async () => {
  // The approval remains the historical 0.85/0.1 calibration read from the real record.
  assert.deepEqual(approval.thresholds, { answerabilityMin: 0.85, conflictMax: 0.1 });
  assert.deepEqual(PILOT_DEMO_THRESHOLDS, { answerabilityMin: 0.5, conflictMax: 0.1 });

  const answered = setup({
    thresholds: PILOT_DEMO_THRESHOLDS,
    jevScores: { support: 0.66, conflict: 0.06 },
  });
  const answer = await run(answered);
  assert.equal(answer.status, 'ANSWERED');
  assert.equal(answered.calls.rawJev, 1);
  assert.equal(answered.calls.rawGenerate, 1);

  const refused = setup({
    thresholds: PILOT_DEMO_THRESHOLDS,
    jevScores: { support: 0.49, conflict: 0.06 },
  });
  const refusal = await run(refused);
  assert.equal(refusal.status, 'NOT_ENOUGH_CONTEXT');
  assert.equal((refusal as { reason: string }).reason, 'UNCERTAIN');
  assert.equal(refused.calls.rawJev, 1);
  assert.equal(refused.calls.rawGenerate, 0);
});

test('the pilot safe sink receives one typed allowlisted diagnostic event, including null pre-Jev scores', async () => {
  const events: DiagnosticMetadata[] = [];
  const s = setup({ log: (metadata) => { events.push(metadata); } });
  const response = await run(s);
  assert.equal(response.status, 'ANSWERED');

  const diagnostics = events.filter((event) => event['stage'] === 'rag-query-diagnostic');
  assert.equal(diagnostics.length, 1);
  const event = diagnostics[0] as unknown as RagQueryDiagnostic;
  assert.ok(event);
  assert.deepEqual(Object.keys(event).sort(), [
    'abstentionStage',
    'answerabilityNoul',
    'conflictNoul',
    'evidenceSourceCount',
    'evidenceSources',
    'fusedCandidateCount',
    'fusedCandidates',
    'indexRef',
    'keywordCandidateCount',
    'keywordCandidates',
    'outcome',
    'ownerRef',
    'reason',
    'rejectedChunkReasons',
    'rejectedChunkRefs',
    'relevanceMode',
    'relevancePolicyVersion',
    'relevantCandidateCount',
    'requestId',
    'scopeType',
    'selectedChunkCount',
    'selectedChunkRefs',
    'stage',
    'vectorCandidateCount',
    'vectorCandidates',
  ].sort());
  assert.equal(event['requestId'], 'req-1');
  assert.equal(event['scopeType'], 'account');
  assert.equal(event['outcome'], 'ANSWERED');
  assert.equal(event['reason'], null);
  assert.equal(event['abstentionStage'], null);
  assert.equal(typeof event['answerabilityNoul'], 'number');
  assert.equal(typeof event['conflictNoul'], 'number');
  assert.equal(event['ownerRef'], ownerRef(ACTOR));
  assert.equal(event['indexRef'], indexRef(ACTOR, 'v1'));

  // The sink receives typed arrays/objects, never pre-serialized JSON strings.
  assert.ok(Array.isArray(event['vectorCandidates']));
  assert.ok(Array.isArray(event['keywordCandidates']));
  assert.ok(Array.isArray(event['fusedCandidates']));
  assert.ok(Array.isArray(event['selectedChunkRefs']));
  assert.ok(Array.isArray(event['evidenceSources']));
  assert.ok(Array.isArray(event['rejectedChunkRefs']));
  assert.ok(Array.isArray(event['rejectedChunkReasons']));
  assert.equal(event['vectorCandidates'].length, event['vectorCandidateCount']);
  assert.equal(event['keywordCandidates'].length, event['keywordCandidateCount']);
  assert.equal(event['fusedCandidates'].length, event['fusedCandidateCount']);
  assert.equal(event['selectedChunkRefs'].length, event['selectedChunkCount']);
  assert.equal(event['evidenceSources'].length, event['evidenceSourceCount']);
  assert.equal(event['rejectedChunkRefs'].length, event['rejectedChunkReasons'].length);
  assert.equal(
    event['relevantCandidateCount'] + event['rejectedChunkRefs'].length,
    event['fusedCandidateCount'],
  );
  assert.equal(event['relevancePolicyVersion'], RELEVANCE_POLICY_VERSION);
  assert.ok(event['relevantCandidateCount'] > 0);
  assert.ok(
    event['relevanceMode'] === 'scored' ||
      event['relevanceMode'] === 'mixed' ||
      event['relevanceMode'] === 'legacy-rank-only',
  );
  assert.ok(event['vectorCandidates'].length > 0);
  assert.ok(event['selectedChunkRefs'].length > 0);
  assert.ok(event['evidenceSources'].length > 0);
  assert.ok(Object.isFrozen(event));
  assert.ok(Object.isFrozen(event['vectorCandidates']));
  assert.ok(Object.isFrozen(event['vectorCandidates'][0]));
  assert.ok(Object.isFrozen(event['selectedChunkRefs']));
  assert.ok(Object.isFrozen(event['rejectedChunkRefs']));
  assert.ok(Object.isFrozen(event['rejectedChunkReasons']));
  assert.ok(Object.isFrozen(event['evidenceSources']));
  assert.ok(Object.isFrozen(event['evidenceSources'][0]));

  // No raw actor, note identity, title, question, content or manifest version reaches the sink.
  const serialized = JSON.stringify(event);
  for (const secret of [ACTOR, 'n-a', TITLE, REQUEST.question, CONTENT, '"v1"']) {
    assert.ok(!serialized.includes(secret), secret);
  }

  // Pre-Jev refusal: the same sink carries null scores, never fabricated zeroes.
  const deniedEvents: DiagnosticMetadata[] = [];
  const denied = setup({ acquireFailure: true, log: (metadata) => { deniedEvents.push(metadata); } });
  const deniedResponse = await run(denied);
  assert.equal(deniedResponse.status, 'ERROR');
  assert.equal((deniedResponse as { code: string }).code, 'RATE_LIMITED');
  const deniedDiagnostics = deniedEvents.filter((entry) => entry['stage'] === 'rag-query-diagnostic');
  assert.equal(deniedDiagnostics.length, 1);
  const deniedEvent = deniedDiagnostics[0] as unknown as RagQueryDiagnostic;
  assert.ok(deniedEvent);
  assert.equal(deniedEvent['outcome'], 'ERROR');
  assert.equal(deniedEvent['reason'], 'RATE_LIMITED');
  assert.equal(deniedEvent['answerabilityNoul'], null);
  assert.equal(deniedEvent['conflictNoul'], null);
  assert.equal(deniedEvent['abstentionStage'], null);
  assert.equal(deniedEvent['ownerRef'], ownerRef(ACTOR));
  assert.equal(deniedEvent['indexRef'], indexRef(ACTOR, 'v1'));
  assert.deepEqual(deniedEvent['vectorCandidates'], []);
  assert.deepEqual(deniedEvent['keywordCandidates'], []);
  assert.deepEqual(deniedEvent['fusedCandidates'], []);
  assert.deepEqual(deniedEvent['selectedChunkRefs'], []);
  assert.deepEqual(deniedEvent['evidenceSources'], []);
  assert.equal(deniedEvent['relevancePolicyVersion'], RELEVANCE_POLICY_VERSION);
  assert.equal(deniedEvent['relevantCandidateCount'], 0);
  assert.deepEqual(deniedEvent['rejectedChunkRefs'], []);
  assert.deepEqual(deniedEvent['rejectedChunkReasons'], []);
  assert.equal(deniedEvent['relevanceMode'], null);
});

test('a throwing pilot log sink is swallowed and cannot change the query outcome', async () => {
  const s = setup({ log: () => { throw new Error('pilot-log-secret'); } });
  const response = await run(s);
  assert.equal(response.status, 'ANSWERED');
  assert.equal(s.calls.release, 1);
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
  assert.equal(s.calls.acquireEmbedding, 0);
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

test('an embedding outage is a bounded ERROR with its reservation kept, never an abstention', async () => {
  for (const embedFailure of ['PROVIDER_UNAVAILABLE', 'TIMEOUT'] as const) {
    const s = setup({ index: fixture({ embedFailure }) });
    const response = await run(s);
    assert.equal(response.status, 'ERROR', embedFailure);
    assert.equal((response as { code: string }).code, embedFailure);
    assert.notEqual(response.status, 'NOT_ENOUGH_CONTEXT');
    assert.equal(s.calls.acquireEmbedding, 1, 'the atomic reservation is never refunded');
    assert.equal(s.calls.rawJev, 0);
    assert.equal(s.calls.rawGenerate, 0);
    assert.equal(s.calls.release, 1);
  }
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
      async acquireEmbedding() {},
      async acquireCohere() { /* deprecated: the active path never calls it */ },
      async read() { return { queryCalls: 0, jevCalls: 0, deepseekCalls: 0, cohereCalls: 0, selfHostedEmbeddingCalls: 0, reservedUsdMicros: 0 }; },
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
  assert.equal(s.calls.acquireEmbedding, 1, 'the reservation is still consumed');
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
