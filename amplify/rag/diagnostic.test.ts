/**
 * Pipeline diagnostic tests: one frozen allowlisted metadata event per admitted query, the two
 * Noul scores, refusal/error semantics, privacy and callback-failure isolation.
 *
 * Synthetic fixtures only; no cloud, provider key or network call.
 *
 * Runner: node --import tsx --test amplify/rag/diagnostic.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chunkNote } from './chunking';
import { EVIDENCE_MAX_TOKENS } from './context';
import { countSyntheticTokens, createMockRuntime, MOCK_MANIFEST_VERSION } from './mock';
import type { MockRuntime } from './mock';
import { createQuery } from './pipeline';
import type { PipelineDeps, RagQueryDiagnostic } from './pipeline';
import {
  chunkRef, indexRef, noteRef, ownerRef, traceBranchCandidates, traceFusedCandidates, traceRelevance,
} from './query_diagnostics';
import { RELEVANCE_POLICY_VERSION } from './relevance';
import type { RelevanceDecision, RelevanceRejectionReason } from './relevance';
import { RagFailure } from './types';
import type { Chunk, RagRequest, RagResponse, Ranked, Scope } from './types';

const QUESTION = 'SLGH031 chạy bao lâu khi lên cót đầy?';
const ACCOUNT: Scope = { type: 'account' };
const SAFE_REASONS: ReadonlySet<string> = new Set([
  'target_mismatch',
  'no_query_overlap',
  'weak_lexical',
  'outside_vector_boundary',
  'non_positive_semantic',
]);
const EVENT_KEYS = [
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
] as const;

type Mutable<T> = { -readonly [K in keyof T]: T[K] };
const asMutable = <T>(value: T): Mutable<T> => value as Mutable<T>;

const request = (question = QUESTION, scope: Scope = ACCOUNT): RagRequest => ({
  wireVersion: 1,
  question,
  scope,
});

const run = (
  deps: PipelineDeps,
  requestId: string,
  req: RagRequest = request(),
  actor = 'actor-a',
): Promise<RagResponse> => createQuery(deps)(actor, req, requestId);

const capture = (runtime: MockRuntime): Readonly<{ deps: PipelineDeps; events: RagQueryDiagnostic[] }> => {
  const events: RagQueryDiagnostic[] = [];
  return {
    events,
    deps: { ...runtime.deps, onDiagnostic: (event) => { events.push(event); } },
  };
};

const assertEvent = (event: RagQueryDiagnostic | undefined): RagQueryDiagnostic => {
  assert.ok(event);
  assert.deepEqual(Object.keys(event).sort(), [...EVENT_KEYS].sort());
  assert.equal(event.stage, 'rag-query-diagnostic');
  assert.ok(Object.isFrozen(event));
  return event;
};

const assertNullScores = (event: RagQueryDiagnostic): void => {
  assert.equal(event.answerabilityNoul, null);
  assert.equal(event.conflictNoul, null);
};

/** Before a non-empty fused union exists, the gate has not run and exposes only safe defaults. */
const assertGateNotRun = (event: RagQueryDiagnostic): void => {
  assert.equal(event.relevancePolicyVersion, RELEVANCE_POLICY_VERSION);
  assert.equal(event.relevantCandidateCount, 0);
  assert.deepEqual(event.rejectedChunkRefs, []);
  assert.deepEqual(event.rejectedChunkReasons, []);
  assert.equal(event.relevanceMode, null);
};

const countsOf = (event: RagQueryDiagnostic): readonly number[] => [
  event.vectorCandidateCount,
  event.keywordCandidateCount,
  event.fusedCandidateCount,
  event.selectedChunkCount,
  event.evidenceSourceCount,
];

const assertDeepFrozen = (value: unknown): void => {
  if (value === null || typeof value !== 'object') return;
  assert.ok(Object.isFrozen(value));
  for (const child of Object.values(value as Record<string, unknown>)) assertDeepFrozen(child);
};

const attempt = (operation: () => void): void => {
  try {
    operation();
  } catch {
    // Frozen-value mutation is expected to throw; the assertions below prove it had no effect.
  }
};

test('all four Jev verdicts emit one frozen diagnostic with both Noul scores', async () => {
  const cases = [
    { scenario: 'allow', outcome: 'ANSWERED', reason: null, stage: null, scores: [0.96, 0.03] },
    {
      scenario: 'insufficient',
      outcome: 'NOT_ENOUGH_CONTEXT',
      reason: 'INSUFFICIENT_EVIDENCE',
      stage: 'jev',
      scores: [0.03, 0.03],
    },
    {
      scenario: 'conflict',
      outcome: 'NOT_ENOUGH_CONTEXT',
      reason: 'UNRESOLVED_CONFLICT',
      stage: 'jev',
      scores: [0.96, 0.97],
    },
    {
      scenario: 'uncertain',
      outcome: 'NOT_ENOUGH_CONTEXT',
      reason: 'UNCERTAIN',
      stage: 'jev',
      scores: [0.5, 0.03],
    },
  ] as const;

  for (const expected of cases) {
    const runtime = createMockRuntime({ scenario: expected.scenario });
    const captured = capture(runtime);
    const response = await run(captured.deps, `req-${expected.scenario}`);

    assert.equal(captured.events.length, 1, expected.scenario);
    const event = assertEvent(captured.events[0]);
    assert.equal(event.requestId, `req-${expected.scenario}`);
    assert.equal(event.scopeType, 'account');
    assert.equal(event.outcome, expected.outcome);
    assert.equal(event.reason, expected.reason);
    assert.equal(event.abstentionStage, expected.stage);
    assert.equal(event.answerabilityNoul, expected.scores[0]);
    assert.equal(event.conflictNoul, expected.scores[1]);
    for (const count of countsOf(event)) assert.ok(count > 0, `${expected.scenario} counts`);

    if (expected.outcome === 'ANSWERED') {
      assert.equal(response.status, 'ANSWERED');
    } else {
      assert.equal(response.status, 'NOT_ENOUGH_CONTEXT');
      if (response.status === 'NOT_ENOUGH_CONTEXT') assert.equal(response.reason, expected.reason);
    }
  }
});

test('the trace maps validated branches, MMR anchors and final evidence 1:1', async () => {
  const runtime = createMockRuntime();
  const captured = capture(runtime);
  const response = await run(captured.deps, 'req-trace-map');
  assert.equal(response.status, 'ANSWERED');

  const event = assertEvent(captured.events[0]);
  assert.match(event.ownerRef, /^[0-9a-f]{64}$/);
  assert.match(event.indexRef, /^[0-9a-f]{64}$/);
  assert.equal(event.ownerRef, ownerRef('actor-a'));
  assert.equal(event.indexRef, indexRef('actor-a', MOCK_MANIFEST_VERSION));

  assert.equal(event.vectorCandidates.length, event.vectorCandidateCount);
  assert.equal(event.keywordCandidates.length, event.keywordCandidateCount);
  assert.equal(event.fusedCandidates.length, event.fusedCandidateCount);
  assert.equal(event.selectedChunkRefs.length, event.selectedChunkCount);
  assert.equal(event.evidenceSources.length, event.evidenceSourceCount);
  assert.ok(event.vectorCandidates.length > 0);
  assert.ok(event.keywordCandidates.length > 0);
  assert.ok(event.fusedCandidates.length > 0);
  assert.ok(event.selectedChunkRefs.length > 0);
  assert.ok(event.evidenceSources.length > 0);

  for (const entry of [...event.vectorCandidates, ...event.keywordCandidates]) {
    assert.deepEqual(Object.keys(entry).sort(), ['bm25Score', 'chunkRef', 'rank', 'vectorDistance']);
    assert.match(entry.chunkRef, /^[0-9a-f]{64}$/);
    assert.ok(Number.isSafeInteger(entry.rank) && entry.rank >= 1);
    assert.ok(
      entry.vectorDistance === null ||
        (Number.isFinite(entry.vectorDistance) && entry.vectorDistance >= 0 && entry.vectorDistance <= 2),
    );
    assert.ok(entry.bm25Score === null || (Number.isFinite(entry.bm25Score) && entry.bm25Score > 0));
  }
  for (const entry of event.fusedCandidates) {
    assert.deepEqual(Object.keys(entry).sort(), [
      'bm25Rank', 'bm25Score', 'chunkRef', 'score', 'vectorDistance', 'vectorRank',
    ]);
    assert.match(entry.chunkRef, /^[0-9a-f]{64}$/);
    assert.ok(Number.isFinite(entry.score));
    assert.ok(entry.vectorRank === null || (Number.isSafeInteger(entry.vectorRank) && entry.vectorRank >= 1));
    assert.ok(entry.bm25Rank === null || (Number.isSafeInteger(entry.bm25Rank) && entry.bm25Rank >= 1));
    assert.ok(
      entry.vectorDistance === null ||
        (Number.isFinite(entry.vectorDistance) && entry.vectorDistance >= 0 && entry.vectorDistance <= 2),
    );
    assert.ok(entry.bm25Score === null || (Number.isFinite(entry.bm25Score) && entry.bm25Score > 0));
  }

  const fusedRefs = new Set(event.fusedCandidates.map((entry) => entry.chunkRef));
  assert.equal(new Set(event.selectedChunkRefs).size, event.selectedChunkRefs.length);
  for (const ref of event.selectedChunkRefs) {
    assert.match(ref, /^[0-9a-f]{64}$/);
    assert.ok(fusedRefs.has(ref), 'every MMR anchor is one validated fused candidate');
  }

  // Ordered relevance metadata: version, retained count, hashed rejects and safe enum reasons.
  assert.equal(event.relevancePolicyVersion, RELEVANCE_POLICY_VERSION);
  assert.ok(event.relevantCandidateCount > 0);
  assert.ok(event.relevantCandidateCount <= event.fusedCandidateCount);
  assert.equal(event.rejectedChunkRefs.length, event.rejectedChunkReasons.length);
  assert.equal(event.relevantCandidateCount + event.rejectedChunkRefs.length, event.fusedCandidateCount);
  assert.ok(event.relevanceMode === 'scored' || event.relevanceMode === 'mixed' || event.relevanceMode === 'legacy-rank-only');
  const rejectedRefs = new Set(event.rejectedChunkRefs);
  assert.equal(rejectedRefs.size, event.rejectedChunkRefs.length);
  for (const ref of event.rejectedChunkRefs) {
    assert.match(ref, /^[0-9a-f]{64}$/);
    assert.ok(fusedRefs.has(ref), 'every rejected ref is one validated fused candidate');
    assert.ok(!event.selectedChunkRefs.includes(ref), 'a rejected candidate never becomes an anchor');
  }
  for (const reason of event.rejectedChunkReasons) {
    assert.ok(SAFE_REASONS.has(reason), `unexpected relevance reason ${reason}`);
  }

  for (const source of event.evidenceSources) {
    assert.deepEqual(Object.keys(source).sort(), [
      'endOffset',
      'noteRef',
      'revision',
      'sourceId',
      'startOffset',
    ]);
    assert.match(source.sourceId, /^S[1-9]\d*$/);
    assert.match(source.noteRef, /^[0-9a-f]{64}$/);
    assert.ok(Number.isSafeInteger(source.revision) && source.revision >= 1);
    assert.ok(Number.isSafeInteger(source.startOffset) && source.startOffset >= 0);
    assert.ok(Number.isSafeInteger(source.endOffset) && source.endOffset > source.startOffset);
  }

  // The first released evidence source maps to the same final span and note reference.
  if (response.status === 'ANSWERED') {
    const released = response.sources[0];
    assert.ok(released);
    const traced = event.evidenceSources.find((source) => source.sourceId === released.sourceId);
    assert.ok(traced);
    assert.equal(traced.noteRef, noteRef('actor-a', released.noteId));
    assert.equal(traced.revision, released.revision);
    assert.equal(traced.startOffset, released.startOffset);
    assert.equal(traced.endOffset, released.endOffset);
  }
});

test('reference helpers are deterministic, domain-separated and owner/revision sensitive', () => {
  const base: Chunk = {
    ownerId: 'actor-a',
    noteId: 'n-a',
    revision: 1,
    sectionId: 'body',
    chunkId: 'body-0',
    ordinal: 0,
    title: 'synthetic',
    startOffset: 0,
    endOffset: 1,
    text: 'x',
  };

  assert.match(ownerRef('actor-a'), /^[0-9a-f]{64}$/);
  assert.equal(ownerRef('actor-a'), ownerRef('actor-a'));
  assert.notEqual(ownerRef('actor-a'), ownerRef('actor-b'));

  assert.equal(indexRef('actor-a', 'v1'), indexRef('actor-a', 'v1'));
  assert.notEqual(indexRef('actor-a', 'v1'), indexRef('actor-a', 'v2'));
  assert.notEqual(indexRef('actor-a', 'v1'), indexRef('actor-b', 'v1'));

  assert.equal(chunkRef(base), chunkRef({ ...base }));
  assert.notEqual(chunkRef(base), chunkRef({ ...base, revision: 2 }));
  assert.notEqual(chunkRef(base), chunkRef({ ...base, ownerId: 'actor-b' }));
  assert.notEqual(chunkRef(base), chunkRef({ ...base, chunkId: 'body-1' }));

  assert.equal(noteRef('actor-a', 'n-a'), noteRef('actor-a', 'n-a'));
  assert.notEqual(noteRef('actor-a', 'n-a'), noteRef('actor-b', 'n-a'));

  // Domain separation: the same raw-ish input never reuses another domain's digest.
  assert.notEqual(ownerRef('x'), noteRef('x', ''));
  assert.notEqual(ownerRef('x'), indexRef('x', ''));
  assert.notEqual(noteRef('x', 'y'), chunkRef({ ...base, ownerId: 'x', noteId: 'y' }));
});

test('the same owner and manifest stay stable; another owner or revision diverges', async () => {
  const first = capture(createMockRuntime());
  const second = capture(createMockRuntime());
  await run(first.deps, 'req-stable-a');
  await run(second.deps, 'req-stable-b');
  const firstEvent = assertEvent(first.events[0]);
  const secondEvent = assertEvent(second.events[0]);
  assert.equal(firstEvent.ownerRef, secondEvent.ownerRef);
  assert.equal(firstEvent.indexRef, secondEvent.indexRef);
  assert.deepEqual(firstEvent.selectedChunkRefs, secondEvent.selectedChunkRefs);

  const other = capture(createMockRuntime());
  await run(other.deps, 'req-stable-other', request(), 'actor-b');
  const otherEvent = assertEvent(other.events[0]);
  assert.notEqual(otherEvent.ownerRef, firstEvent.ownerRef);
  assert.notEqual(otherEvent.indexRef, firstEvent.indexRef);
  assert.notDeepEqual(otherEvent.selectedChunkRefs, firstEvent.selectedChunkRefs);
});

test('the event and every nested trace value are deeply frozen', async () => {
  const runtime = createMockRuntime();
  let seen: RagQueryDiagnostic | undefined;
  const deps: PipelineDeps = {
    ...runtime.deps,
    onDiagnostic: (event) => {
      seen = event;
      attempt(() => (event.vectorCandidates as unknown as { chunkRef: string; rank: number }[]).push({
        chunkRef: 'mutable', rank: 1,
      }));
      attempt(() => { (event.vectorCandidates[0] as unknown as { rank: number }).rank = 999; });
      attempt(() => (event.selectedChunkRefs as unknown as string[]).push('mutable'));
      attempt(() => { (event.evidenceSources[0] as unknown as { revision: number }).revision = 999; });
    },
  };
  const response = await run(deps, 'req-deep-frozen');
  assert.equal(response.status, 'ANSWERED');
  const event = assertEvent(seen);
  assertDeepFrozen(event);
  assert.ok(event.vectorCandidates.length > 0);
  assert.notEqual(event.vectorCandidates[0]?.rank, 999);
  assert.ok(!event.selectedChunkRefs.includes('mutable'));
  assert.notEqual(event.evidenceSources[0]?.revision, 999);
});

test('a throwing onDiagnostic getter is swallowed and cannot change the response', async () => {
  const runtime = createMockRuntime();
  const deps = { ...runtime.deps };
  Object.defineProperty(deps, 'onDiagnostic', {
    get() {
      throw new Error('getter-secret');
    },
  });
  const response = await run(deps as PipelineDeps, 'req-getter');
  assert.equal(response.status, 'ANSWERED');
});

test('an empty eligible scope abstains at scope with null scores and zero counts', async () => {
  const runtime = createMockRuntime();
  const state = runtime.store.states.get('actor-a');
  assert.ok(state);
  runtime.store.states.set('actor-a', { ...state, notes: [] });

  const captured = capture(runtime);
  const response = await run(captured.deps, 'req-empty-scope');
  assert.equal(response.status, 'NOT_ENOUGH_CONTEXT');
  if (response.status === 'NOT_ENOUGH_CONTEXT') assert.equal(response.reason, 'INSUFFICIENT_EVIDENCE');

  assert.equal(captured.events.length, 1);
  const event = assertEvent(captured.events[0]);
  assert.equal(event.outcome, 'NOT_ENOUGH_CONTEXT');
  assert.equal(event.reason, 'INSUFFICIENT_EVIDENCE');
  assert.equal(event.abstentionStage, 'scope');
  assertNullScores(event);
  assertGateNotRun(event);
  assert.deepEqual(countsOf(event), [0, 0, 0, 0, 0]);
  assert.equal(event.ownerRef, ownerRef('actor-a'));
  assert.equal(event.indexRef, indexRef('actor-a', MOCK_MANIFEST_VERSION));
  assert.deepEqual(event.vectorCandidates, []);
  assert.deepEqual(event.keywordCandidates, []);
  assert.deepEqual(event.fusedCandidates, []);
  assert.deepEqual(event.selectedChunkRefs, []);
  assert.deepEqual(event.evidenceSources, []);
  assert.equal(runtime.counts.embedding, 0);
  assert.equal(runtime.counts.jev, 0);
});

test('an empty vector and keyword union abstains at retrieval with null scores', async () => {
  const runtime = createMockRuntime();
  asMutable(runtime.deps.retrieval).vectorSearch = async (): Promise<readonly Ranked[]> => [];
  asMutable(runtime.deps.retrieval).keywordSearch = async (): Promise<readonly Ranked[]> => [];

  const captured = capture(runtime);
  const response = await run(captured.deps, 'req-empty-retrieval');
  assert.equal(response.status, 'NOT_ENOUGH_CONTEXT');
  if (response.status === 'NOT_ENOUGH_CONTEXT') assert.equal(response.reason, 'INSUFFICIENT_EVIDENCE');

  assert.equal(captured.events.length, 1);
  const event = assertEvent(captured.events[0]);
  assert.equal(event.outcome, 'NOT_ENOUGH_CONTEXT');
  assert.equal(event.reason, 'INSUFFICIENT_EVIDENCE');
  assert.equal(event.abstentionStage, 'retrieval');
  assertNullScores(event);
  assertGateNotRun(event);
  assert.deepEqual(countsOf(event), [0, 0, 0, 0, 0]);
  assert.equal(event.ownerRef, ownerRef('actor-a'));
  assert.equal(event.indexRef, indexRef('actor-a', MOCK_MANIFEST_VERSION));
  assert.deepEqual(event.vectorCandidates, []);
  assert.deepEqual(event.keywordCandidates, []);
  assert.deepEqual(event.fusedCandidates, []);
  assert.deepEqual(event.selectedChunkRefs, []);
  assert.deepEqual(event.evidenceSources, []);
  assert.equal(runtime.counts.getVectors, 0);
  assert.equal(runtime.counts.jev, 0);
});

test('an all-rejected shortlist abstains at relevance before getVectors or Jev', async () => {
  const runtime = createMockRuntime();
  const state = runtime.store.states.get('actor-a');
  assert.ok(state);
  const note = state.notes.find((entry) => entry.noteId === 'n-watch');
  assert.ok(note);
  const chunk = chunkNote(note, countSyntheticTokens)[0];
  assert.ok(chunk);
  // One valid own chunk, but its only signal is a negative cosine (distance >= 1) and the keyword
  // branch is empty: the ordered gate must reject it rather than pass it into MMR/context.
  asMutable(runtime.deps.retrieval).vectorSearch = async (): Promise<readonly Ranked[]> => [
    { chunk, rank: 1, vectorDistance: 1.25 },
  ];
  asMutable(runtime.deps.retrieval).keywordSearch = async (): Promise<readonly Ranked[]> => [];

  const captured = capture(runtime);
  const response = await run(captured.deps, 'req-relevance-empty');
  assert.equal(response.status, 'NOT_ENOUGH_CONTEXT');
  if (response.status === 'NOT_ENOUGH_CONTEXT') assert.equal(response.reason, 'INSUFFICIENT_EVIDENCE');

  assert.equal(captured.events.length, 1);
  const event = assertEvent(captured.events[0]);
  assert.equal(event.outcome, 'NOT_ENOUGH_CONTEXT');
  assert.equal(event.reason, 'INSUFFICIENT_EVIDENCE');
  assert.equal(event.abstentionStage, 'relevance');
  assertNullScores(event);
  assert.equal(event.fusedCandidateCount, 1);
  assert.equal(event.relevantCandidateCount, 0);
  assert.equal(event.selectedChunkCount, 0);
  assert.equal(event.relevanceMode, 'scored');
  assert.deepEqual(event.rejectedChunkRefs, [chunkRef(chunk)]);
  assert.deepEqual(event.rejectedChunkReasons, ['non_positive_semantic']);
  assert.deepEqual(event.selectedChunkRefs, []);
  assert.deepEqual(event.evidenceSources, []);
  assert.equal(runtime.counts.getVectors, 0);
  assert.equal(runtime.counts.neighbors, 0);
  assert.equal(runtime.counts.jev, 0);
  assert.equal(runtime.counts.generation, 0);
  // The gate metadata is a one-way ref plus a fixed reason; no title/text/question leaks.
  assert.match(event.rejectedChunkRefs[0], /^[0-9a-f]{64}$/);
  const serialized = JSON.stringify(event);
  for (const secret of [note.title, chunk.text, QUESTION]) assert.ok(!serialized.includes(secret), secret);
});

test('evidence collapsing to zero sources abstains at evidence without fabricated scores', async () => {
  const runtime = createMockRuntime();
  const captured = capture(runtime);
  // Valid anchors, but every non-empty serialization is over budget, so buildEvidence drops them
  // all and returns the legitimate empty bundle. The diagnostic must not invent scores for it.
  const overBudget: PipelineDeps = {
    ...captured.deps,
    counters: {
      ...captured.deps.counters,
      evidence: (text) => (text.length === 0 ? 0 : EVIDENCE_MAX_TOKENS + 1),
    },
  };
  const response = await run(overBudget, 'req-empty-evidence');
  assert.equal(response.status, 'NOT_ENOUGH_CONTEXT');
  if (response.status === 'NOT_ENOUGH_CONTEXT') assert.equal(response.reason, 'INSUFFICIENT_EVIDENCE');

  assert.equal(captured.events.length, 1);
  const event = assertEvent(captured.events[0]);
  assert.equal(event.outcome, 'NOT_ENOUGH_CONTEXT');
  assert.equal(event.reason, 'INSUFFICIENT_EVIDENCE');
  assert.equal(event.abstentionStage, 'evidence');
  assertNullScores(event);
  assert.ok(event.fusedCandidateCount > 0);
  assert.ok(event.selectedChunkCount > 0);
  assert.equal(event.evidenceSourceCount, 0);
  assert.ok(event.fusedCandidates.length > 0);
  assert.ok(event.selectedChunkRefs.length > 0);
  assert.deepEqual(event.evidenceSources, []);
  assert.equal(runtime.counts.getVectors, 1);
  assert.equal(runtime.counts.neighbors, 1);
  assert.equal(runtime.counts.jev, 0);
});

test('a malformed Jev response is ERROR with null scores and no abstention stage', async () => {
  const runtime = createMockRuntime({ scenario: 'malformed' });
  const captured = capture(runtime);
  const response = await run(captured.deps, 'req-malformed');
  assert.equal(response.status, 'ERROR');
  if (response.status === 'ERROR') assert.equal(response.code, 'EVIDENCE_VALIDATION_UNAVAILABLE');

  assert.equal(captured.events.length, 1);
  const event = assertEvent(captured.events[0]);
  assert.equal(event.outcome, 'ERROR');
  assert.equal(event.reason, 'EVIDENCE_VALIDATION_UNAVAILABLE');
  assert.equal(event.abstentionStage, null);
  assertNullScores(event);
  assert.ok(event.selectedChunkCount > 0);
  assert.ok(event.evidenceSourceCount > 0);
  assert.ok(event.selectedChunkRefs.length > 0);
  assert.ok(event.evidenceSources.length > 0);
  assert.equal(runtime.counts.generation, 0);
});

test('a post-Jev generation failure is ERROR with the available scores, never ALLOW', async () => {
  const runtime = createMockRuntime();
  asMutable(runtime.deps.providers).generate = async () => {
    runtime.counts.generation += 1;
    throw new Error('synthetic-provider-secret');
  };
  const captured = capture(runtime);
  const response = await run(captured.deps, 'req-generation-error');
  assert.equal(response.status, 'ERROR');
  if (response.status === 'ERROR') assert.equal(response.code, 'PROVIDER_UNAVAILABLE');

  assert.equal(captured.events.length, 1);
  const event = assertEvent(captured.events[0]);
  assert.equal(event.outcome, 'ERROR');
  assert.equal(event.reason, 'PROVIDER_UNAVAILABLE');
  assert.equal(event.abstentionStage, null);
  assert.equal(event.answerabilityNoul, 0.96);
  assert.equal(event.conflictNoul, 0.03);
  assert.ok(event.selectedChunkCount > 0);
  assert.ok(event.evidenceSourceCount > 0);
  assert.ok(event.selectedChunkRefs.length > 0);
  assert.ok(event.evidenceSources.length > 0);
  assert.equal(runtime.counts.generation, 1);
  assert.ok(!JSON.stringify(event).includes('synthetic-provider-secret'));
});

test('a throwing diagnostic sink is swallowed and cannot change the response', async () => {
  for (const scenario of ['allow', 'insufficient'] as const) {
    const runtime = createMockRuntime({ scenario });
    let calls = 0;
    const deps: PipelineDeps = {
      ...runtime.deps,
      onDiagnostic: () => {
        calls += 1;
        throw new Error('logger-secret');
      },
    };
    const response = await run(deps, `req-throwing-${scenario}`);
    assert.equal(calls, 1, scenario);
    if (scenario === 'allow') {
      assert.equal(response.status, 'ANSWERED');
    } else {
      assert.equal(response.status, 'NOT_ENOUGH_CONTEXT');
      if (response.status === 'NOT_ENOUGH_CONTEXT') assert.equal(response.reason, 'INSUFFICIENT_EVIDENCE');
    }
  }
});

test('concurrent requests keep independent diagnostic state', async () => {
  const runtime = createMockRuntime();
  const events: RagQueryDiagnostic[] = [];
  const deps: PipelineDeps = {
    ...runtime.deps,
    onDiagnostic: (event) => { events.push(event); },
  };
  const query = createQuery(deps);
  const [answered, tooLong] = await Promise.all([
    query('actor-a', request(), 'req-concurrent-ok'),
    query('actor-a', request('a'.repeat(3000)), 'req-concurrent-long'),
  ]);

  assert.equal(answered.status, 'ANSWERED');
  assert.equal(tooLong.status, 'ERROR');
  if (tooLong.status === 'ERROR') assert.equal(tooLong.code, 'INPUT_TOO_LONG');
  assert.equal(events.length, 2);

  const byId = new Map(events.map((event) => [event.requestId, event]));
  const ok = byId.get('req-concurrent-ok');
  const long = byId.get('req-concurrent-long');
  assert.ok(ok);
  assert.ok(long);
  assert.equal(ok.outcome, 'ANSWERED');
  assert.equal(ok.reason, null);
  assert.ok(ok.vectorCandidateCount > 0);
  assert.equal(typeof ok.answerabilityNoul, 'number');
  assert.equal(ok.ownerRef, ownerRef('actor-a'));
  assert.ok(ok.vectorCandidates.length > 0);
  assert.ok(ok.selectedChunkRefs.length > 0);
  assert.ok(ok.evidenceSources.length > 0);
  assert.equal(long.outcome, 'ERROR');
  assert.equal(long.reason, 'INPUT_TOO_LONG');
  assert.equal(long.abstentionStage, null);
  assert.equal(long.ownerRef, ownerRef('actor-a'));
  assertNullScores(long);
  assert.deepEqual(countsOf(long), [0, 0, 0, 0, 0]);
  assert.deepEqual(long.vectorCandidates, []);
  assert.deepEqual(long.keywordCandidates, []);
  assert.deepEqual(long.fusedCandidates, []);
  assert.deepEqual(long.selectedChunkRefs, []);
  assert.deepEqual(long.evidenceSources, []);
});

test('the event is allowlisted and never leaks synthetic secrets, text or identity', async () => {
  const secretQuestion = `${QUESTION} sk-live-secret-question`;
  const runtime = createMockRuntime();
  const captured = capture(runtime);
  await run(captured.deps, 'req-privacy', request(secretQuestion, { type: 'note', noteId: 'n-watch' }));

  assert.equal(captured.events.length, 1);
  const event = assertEvent(captured.events[0]);
  assert.equal(event.scopeType, 'note');
  for (const forbidden of ['actor', 'question', 'noteId', 'title', 'quote', 'evidence', 'error', 'apiKey', 'payload', 'sources']) {
    assert.ok(!(forbidden in event), forbidden);
  }
  const serialized = JSON.stringify(event);
  for (const secret of [
    'actor-a',
    secretQuestion,
    'SLGH031',
    'n-watch',
    'Caliber 9SA5',
    'sk-live-secret-question',
    MOCK_MANIFEST_VERSION,
  ]) {
    assert.ok(!serialized.includes(secret), secret);
  }

  // Every raw chunk identity/title/text shipped to the index is absent from the JSON event.
  const index = runtime.index.get('actor-a');
  assert.ok(index);
  const snapshot = JSON.parse(index.encodeLexicalSnapshot()) as {
    documents: readonly { chunk: Chunk }[];
  };
  for (const document of snapshot.documents) {
    for (const raw of [
      document.chunk.ownerId,
      document.chunk.noteId,
      document.chunk.sectionId,
      document.chunk.chunkId,
      document.chunk.title,
      document.chunk.text,
    ]) {
      assert.ok(!serialized.includes(raw), `raw source value leaked: ${raw}`);
    }
  }
});

test('config rejection before the pipeline stays unlogged', async () => {
  const runtime = createMockRuntime();
  const events: RagQueryDiagnostic[] = [];
  const deps: PipelineDeps = {
    ...runtime.deps,
    config: { ...runtime.deps.config, mode: 'live' },
    onDiagnostic: (event) => { events.push(event); },
  };
  const response = await run(deps, 'req-live-unlogged');
  assert.equal(response.status, 'ERROR');
  if (response.status === 'ERROR') assert.equal(response.code, 'LIVE_POLICY_NOT_CONFIGURED');
  assert.equal(events.length, 0);
});

test('a malformed requestId is rejected before any diagnostic', async () => {
  const runtime = createMockRuntime();
  const captured = capture(runtime);
  await assert.rejects(
    () => run(captured.deps, ' req-invalid'),
    (error: unknown) => error instanceof RagFailure && error.code === 'INVALID_INPUT',
  );
  assert.equal(captured.events.length, 0);
});


test('malformed branch ranks cannot leak raw strings before RRF rejects them', async () => {
  const runtime = createMockRuntime();
  const original = runtime.deps.retrieval.vectorSearch;
  asMutable(runtime.deps.retrieval).vectorSearch = async (...args) => {
    const entries = await original(...args);
    return entries.map(entry => ({ ...entry, rank: 'private-invalid-rank-do-not-log' as unknown as number }));
  };
  const captured = capture(runtime);
  const response = await run(captured.deps, 'req-invalid-rank');
  assert.equal(response.status, 'ERROR');
  assert.equal(captured.events.length, 1);
  assert.deepEqual(captured.events[0].vectorCandidates, []);
  assert.ok(!JSON.stringify(captured.events[0]).includes('private-invalid-rank-do-not-log'));
});

test('malformed raw score metadata cannot leak raw strings and never reaches the event', async () => {
  const runtime = createMockRuntime();
  const original = runtime.deps.retrieval.vectorSearch;
  asMutable(runtime.deps.retrieval).vectorSearch = async (...args) => {
    const entries = await original(...args);
    return entries.map(entry => ({
      ...entry,
      vectorDistance: 'private-invalid-distance-do-not-log' as unknown as number,
    }));
  };
  const captured = capture(runtime);
  const response = await run(captured.deps, 'req-invalid-distance');
  assert.equal(response.status, 'ERROR');
  assert.equal(captured.events.length, 1);
  assert.deepEqual(captured.events[0].vectorCandidates, []);
  assert.ok(!JSON.stringify(captured.events[0]).includes('private-invalid-distance-do-not-log'));
});

test('trace metric allowlists validate domains, freeze entries and fall back without leaking', () => {
  const chunk: Chunk = {
    ownerId: 'actor-a',
    noteId: 'n-a',
    revision: 1,
    sectionId: 'body',
    chunkId: 'body-0',
    ordinal: 0,
    title: 'synthetic',
    startOffset: 0,
    endOffset: 1,
    text: 'x',
  };
  const invalidBranch = traceBranchCandidates([
    { chunk, rank: 1, bm25Score: 'private-bm25-do-not-log' as unknown as number },
  ]);
  assert.deepEqual(invalidBranch, []);
  assert.ok(!JSON.stringify(invalidBranch).includes('private-bm25-do-not-log'));

  const invalidFused = traceFusedCandidates([
    { chunk, score: 1, vectorDistance: 'private-distance-do-not-log' as unknown as number },
  ]);
  assert.deepEqual(invalidFused, []);
  assert.ok(!JSON.stringify(invalidFused).includes('private-distance-do-not-log'));

  const fused = traceFusedCandidates([{ chunk, score: 1, vectorDistance: 0.5, bm25Score: 2 }]);
  assert.deepEqual(fused, [{
    chunkRef: chunkRef(chunk),
    score: 1,
    vectorRank: null,
    bm25Rank: null,
    vectorDistance: 0.5,
    bm25Score: 2,
  }]);
  assert.ok(Object.isFrozen(fused) && Object.isFrozen(fused[0]));
});

test('traceRelevance allowlists hashed refs and safe reasons and falls back on a hostile decision', () => {
  const chunk: Chunk = {
    ownerId: 'actor-a',
    noteId: 'n-a',
    revision: 1,
    sectionId: 'body',
    chunkId: 'body-0',
    ordinal: 0,
    title: 'synthetic',
    startOffset: 0,
    endOffset: 1,
    text: 'x',
  };
  const decision: RelevanceDecision = Object.freeze({
    policyVersion: RELEVANCE_POLICY_VERSION,
    kept: Object.freeze([{ chunk, score: 1 }]),
    rejected: Object.freeze([
      Object.freeze({ chunkRef: chunkRef(chunk), reason: 'weak_lexical' as RelevanceRejectionReason }),
    ]),
    mode: 'mixed' as const,
  });
  const traced = traceRelevance(decision);
  assert.deepEqual(traced, {
    relevantCandidateCount: 1,
    rejectedChunkRefs: [chunkRef(chunk)],
    rejectedChunkReasons: ['weak_lexical'],
    relevanceMode: 'mixed',
  });
  assert.ok(Object.isFrozen(traced));
  assert.ok(Object.isFrozen(traced.rejectedChunkRefs));
  assert.ok(Object.isFrozen(traced.rejectedChunkReasons));

  // A hostile decision getter fails closed to the empty allowlist, never leaking the error.
  const hostile = {
    ...decision,
    get kept(): never {
      throw new Error('private-kept-do-not-log');
    },
  } as unknown as RelevanceDecision;
  const fallback = traceRelevance(hostile);
  assert.deepEqual(fallback, {
    relevantCandidateCount: 0,
    rejectedChunkRefs: [],
    rejectedChunkReasons: [],
    relevanceMode: null,
  });
  assert.ok(!JSON.stringify(fallback).includes('private-kept-do-not-log'));
});
