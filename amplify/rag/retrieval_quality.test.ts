/**
 * Synthetic retrieval-quality regressions for the five ordered improvements:
 *  1. validated cosine distance / BM25 score preserved through fusion and diagnostics;
 *  2. query-only filler filtering (Hoa Sen vs "khi/ra" noise);
 *  3. relevance shortlist before getVectors/MMR;
 *  4. adaptive MMR utility, plus conservative explicit-multipart retention;
 *  5. expansion only from the selected, gate-qualified anchors.
 *
 * Also covers long same-entity corrections, a real same-event conflict reaching JEV, a
 * cross-language vector-only query, and foreign/stale/malformed branch data failing before JEV.
 * All chunks, vectors and notes are synthetic; no provider, cloud, secret or network is used.
 *
 * Runner: node --import tsx --test amplify/rag/retrieval_quality.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CONSENT_VERSION } from './contract';
import { bm25, queryTerms } from './keyword';
import { countSyntheticTokens } from './mock';
import { createQuery } from './pipeline';
import type { PipelineDeps, RagQueryDiagnostic } from './pipeline';
import { chunkRef } from './query_diagnostics';
import { isConjunctiveQuestion, selectRelevantCandidates } from './relevance';
import { mmr, rrf, MMR_MAX_ANCHORS } from './retrieval';
import { SECTION_BODY } from './chunking';
import { policy, RagFailure, sourceKey } from './types';
import type {
  Candidate,
  CanonicalNote,
  CanonicalState,
  Chunk,
  GenerateInput,
  JevInput,
  RagRequest,
  RagResponse,
  Ranked,
  RuntimeConfig,
  Scope,
} from './types';

const OWNER = 'actor-quality';
const MODEL = 'synthetic-quality-jev';
const CONFIG: RuntimeConfig = Object.freeze({
  mode: 'mock',
  model: MODEL,
  thresholds: Object.freeze({ answerabilityMin: 0.9, conflictMax: 0.1 }),
  jevMaxTokens: 32_768,
  requestTimeoutMs: 26_000,
});

const embedding = (first: number, second = 0, third = 0): readonly number[] =>
  Object.freeze(
    Array.from({ length: policy.embedding.dimensions }, (_value, index) =>
      index === 0 ? first : index === 1 ? second : index === 2 ? third : 0,
    ),
  );

const chunkOf = (noteId: string, title: string, text: string): Chunk => ({
  ownerId: OWNER,
  noteId,
  revision: 1,
  sectionId: SECTION_BODY,
  chunkId: 'body-0',
  ordinal: 0,
  title,
  startOffset: 0,
  endOffset: text.length,
  text,
});

const noteOf = (chunk: Chunk): CanonicalNote => ({
  ownerId: chunk.ownerId,
  noteId: chunk.noteId,
  revision: chunk.revision,
  title: chunk.title,
  content: chunk.text,
  synced: true,
  protected: false,
  deleted: false,
  available: true,
});

const ranked = (
  chunk: Chunk,
  rank: number,
  signals: Readonly<{ vectorDistance?: number; bm25Score?: number }> = {},
): Ranked => ({ chunk, rank, ...signals });

const request = (question: string, scope: Scope = { type: 'account' }): RagRequest => ({
  wireVersion: 1,
  question,
  scope,
});

const jevEnvelope = (input: JevInput, support: number, conflict: number): unknown => ({
  model: MODEL,
  answers: {
    answerable_from_evidence: { type: 'noul', noul: support },
    has_unresolved_conflict: { type: 'noul', noul: conflict },
  },
  usage: {
    input_tokens: countSyntheticTokens(JSON.stringify(input)),
    output_tokens: 4,
  },
});

type HarnessOptions = Readonly<{
  notes: readonly CanonicalNote[];
  vector: readonly Ranked[];
  keyword: readonly Ranked[];
  vectors: ReadonlyMap<string, readonly number[]>;
  support?: number;
  conflict?: number;
  neighborsFor?: (anchors: readonly Chunk[]) => readonly Chunk[];
}>;

type Harness = Readonly<{
  deps: PipelineDeps;
  calls: Readonly<{
    vectorSearch: number;
    keywordSearch: number;
    getVectors: readonly Chunk[][];
    neighbors: readonly Chunk[][];
    jev: readonly JevInput[];
    generate: readonly GenerateInput[];
  }>;
  diagnostics: readonly RagQueryDiagnostic[];
  run(question: string, scope?: Scope): Promise<RagResponse>;
}>;

const createHarness = (options: HarnessOptions): Harness => {
  let vectorSearchCalls = 0;
  let keywordSearchCalls = 0;
  const getVectorsCalls: Chunk[][] = [];
  const neighborCalls: Chunk[][] = [];
  const jevCalls: JevInput[] = [];
  const generateCalls: GenerateInput[] = [];
  const diagnostics: RagQueryDiagnostic[] = [];
  let sequence = 0;

  const state: CanonicalState = Object.freeze({
    actorId: OWNER,
    sessionGeneration: 1,
    consent: Object.freeze({ accepted: true, version: CONSENT_VERSION, generation: 1 }),
    indexReady: true,
    manifestVersion: 'quality-1',
    notes: Object.freeze([...options.notes]),
  });

  const deps: PipelineDeps = {
    authority: Object.freeze({
      read: async (actor: string): Promise<CanonicalState> => {
        if (actor !== OWNER) throw new RagFailure('UNAUTHORIZED');
        return state;
      },
    }),
    retrieval: {
      embedQuery: async () => embedding(1, 0, 0),
      vectorSearch: async () => {
        vectorSearchCalls += 1;
        return options.vector;
      },
      keywordSearch: async () => {
        keywordSearchCalls += 1;
        return options.keyword;
      },
      getVectors: async (chunks) => {
        getVectorsCalls.push([...chunks]);
        const vectors = new Map<string, readonly number[]>();
        for (const chunk of chunks) {
          const vector = options.vectors.get(sourceKey(chunk));
          if (vector === undefined) throw new RagFailure('INDEX_NOT_READY');
          vectors.set(sourceKey(chunk), vector);
        }
        return vectors;
      },
      neighbors: async (anchors) => {
        neighborCalls.push([...anchors]);
        return options.neighborsFor?.(anchors) ?? Object.freeze([]);
      },
    },
    providers: {
      jev: async (input) => {
        jevCalls.push(input);
        return jevEnvelope(input, options.support ?? 0.96, options.conflict ?? 0.03);
      },
      generate: async (input) => {
        generateCalls.push(input);
        const first = input.evidence.sources[0];
        if (first === undefined) throw new RagFailure('EVIDENCE_VALIDATION_UNAVAILABLE');
        return { answer: `Theo nguồn: ${first.quote} [${first.sourceId}]`, sources: [{ ...first }] };
      },
    },
    counters: {
      embedding: countSyntheticTokens,
      evidence: countSyntheticTokens,
      jev: countSyntheticTokens,
      output: countSyntheticTokens,
    },
    config: CONFIG,
    consumeQuota: async () => true,
    onDiagnostic: (event) => {
      diagnostics.push(event);
    },
  };

  const query = createQuery(deps);
  return Object.freeze({
    deps,
    calls: {
      get vectorSearch() {
        return vectorSearchCalls;
      },
      get keywordSearch() {
        return keywordSearchCalls;
      },
      getVectors: getVectorsCalls,
      neighbors: neighborCalls,
      jev: jevCalls,
      generate: generateCalls,
    },
    diagnostics,
    run: (question: string, scope: Scope = { type: 'account' }) => {
      sequence += 1;
      return query(OWNER, request(question, scope), `quality-${sequence}`);
    },
  });
};

const errorCode = (response: RagResponse): string => {
  if (response.status !== 'ERROR') assert.fail(`expected ERROR, got ${response.status}`);
  return response.code;
};

const noteIds = (chunks: readonly Chunk[]): readonly string[] =>
  chunks.map((chunk) => chunk.noteId);

test('ordered 1: validated vector distance and BM25 score survive fusion into diagnostics', async () => {
  const lexical = chunkOf('n-metric-a', 'Metric A', 'alpha beta gamma');
  const semantic = chunkOf('n-metric-b', 'Metric B', 'alpha beta');
  const harness = createHarness({
    notes: [noteOf(lexical), noteOf(semantic)],
    vector: [ranked(lexical, 1, { vectorDistance: 0.2 }), ranked(semantic, 2, { vectorDistance: 0.8 })],
    keyword: [ranked(lexical, 1, { bm25Score: 3 })],
    vectors: new Map([
      [sourceKey(lexical), embedding(1, 0, 0)],
      [sourceKey(semantic), embedding(0, 1, 0)],
    ]),
  });

  const response = await harness.run('alpha beta?');
  assert.equal(response.status, 'ANSWERED');
  assert.equal(harness.diagnostics.length, 1);
  const event = harness.diagnostics[0];
  assert.ok(event);

  const fusedByRef = new Map(event.fusedCandidates.map((entry) => [entry.chunkRef, entry]));
  const lexicalFused = fusedByRef.get(chunkRef(lexical));
  assert.ok(lexicalFused);
  assert.equal(lexicalFused.vectorDistance, 0.2);
  assert.equal(lexicalFused.bm25Score, 3);
  assert.equal(lexicalFused.vectorRank, 1);
  assert.equal(lexicalFused.bm25Rank, 1);
  assert.equal(lexicalFused.score, 1 / 61 + 1 / 61);

  const branchDistance = new Map(event.vectorCandidates.map((entry) => [entry.chunkRef, entry.vectorDistance]));
  assert.equal(branchDistance.get(chunkRef(lexical)), 0.2);
  assert.equal(branchDistance.get(chunkRef(semantic)), 0.8);
  const branchScore = new Map(event.keywordCandidates.map((entry) => [entry.chunkRef, entry.bm25Score]));
  assert.equal(branchScore.get(chunkRef(lexical)), 3);
  assert.equal(event.relevanceMode, 'scored');
});

test('ordered 2+3+5: filler-only noise is never lexical evidence and is filtered before vectors/MMR/neighbors', async () => {
  const hoaSen = chunkOf('n-hs', 'Hoa Sen', 'Hoa Sen mở cửa lúc 8 giờ');
  const noiseA = chunkOf('n-noise-a', 'Lịch khi ra', 'khi ra');
  const noiseB = chunkOf('n-noise-b', 'Khi nào ra', 'khi ra');
  const question = 'Hoa Sen mở cửa khi nào ra sao?';

  // Query-only filtering: the content terms remain; the question fillers do not score.
  assert.deepEqual(queryTerms(question), ['hoa', 'sen', 'mở', 'cửa']);
  const keyword = bm25(question, [hoaSen, noiseA, noiseB]);
  assert.deepEqual(noteIds(keyword.map((entry) => entry.chunk)), ['n-hs']);
  assert.ok((keyword[0]?.bm25Score ?? 0) > 0);

  const harness = createHarness({
    notes: [noteOf(hoaSen), noteOf(noiseA), noteOf(noiseB)],
    vector: [
      ranked(hoaSen, 1, { vectorDistance: 0.2 }),
      ranked(noiseA, 2, { vectorDistance: 0.3 }),
      ranked(noiseB, 3, { vectorDistance: 0.4 }),
    ],
    keyword,
    vectors: new Map([
      [sourceKey(hoaSen), embedding(1, 0, 0)],
      [sourceKey(noiseA), embedding(0, 1, 0)],
      [sourceKey(noiseB), embedding(0, 0, 1)],
    ]),
  });

  const response = await harness.run(question);
  assert.equal(response.status, 'ANSWERED');
  assert.equal(harness.calls.getVectors.length, 1);
  assert.deepEqual(noteIds(harness.calls.getVectors[0] ?? []), ['n-hs'], 'only the kept shortlist is fetched');
  assert.equal(harness.calls.neighbors.length, 1);
  assert.deepEqual(noteIds(harness.calls.neighbors[0] ?? []), ['n-hs'], 'expansion starts only from selected anchors');

  const event = harness.diagnostics[0];
  assert.ok(event);
  assert.equal(event.relevantCandidateCount, 1);
  assert.deepEqual(event.rejectedChunkReasons, ['outside_vector_boundary', 'outside_vector_boundary']);
  const jevInput = harness.calls.jev[0];
  assert.ok(jevInput);
  assert.ok(jevInput.state.evidence.includes('Hoa Sen mở cửa lúc 8 giờ'));
  assert.ok(!jevInput.state.evidence.includes('khi ra'), 'filler-only noise is not evidence');
});

test('ordered 4: adaptive MMR stops at non-positive utility; an explicit multipart query can retain both', () => {
  const a = chunkOf('n-geometry-a', 'A', 'first requested fact');
  const b = chunkOf('n-geometry-b', 'B', 'second requested fact');
  // Physically valid unit vectors for q=(1,0,0): cosine 0.8 and 0.2 -> distances 0.2 and 0.8.
  const vectors = new Map([
    [sourceKey(a), embedding(0.8, 0.6, 0)],
    [sourceKey(b), embedding(0.2, Math.sqrt(0.96), 0)],
  ]);
  const candidates: Candidate[] = [
    { chunk: a, score: 0.032, vectorRank: 1, vectorDistance: 0.2 },
    { chunk: b, score: 0.031, vectorRank: 2, vectorDistance: 0.8 },
  ];
  const question = 'Chính sách hoàn tiền và chính sách bảo hành?';

  assert.equal(isConjunctiveQuestion(question), true);
  // Default behavior: B has negative marginal utility after A and is dropped by the adaptive stop.
  assert.deepEqual(noteIds(mmr(candidates, vectors)), ['n-geometry-a']);
  // Pipeline hint for an explicit multi-part question: retain the second semantic part, still capped.
  const retained = mmr(candidates, vectors, {
    retainOnNonPositiveUtility: isConjunctiveQuestion(question),
  });
  assert.deepEqual(noteIds(retained), ['n-geometry-a', 'n-geometry-b']);
  assert.ok(retained.length <= MMR_MAX_ANCHORS);
});

test('explicit multipart cross-language query carries both vector-only sources through MMR to JEV', async () => {
  const returns = chunkOf('n-return', 'Refund policy', 'Refund policy: 30 days.');
  const warranty = chunkOf('n-warranty', 'Warranty policy', 'Warranty policy: 12 months.');
  const question = 'Chính sách hoàn tiền và chính sách bảo hành là gì?';
  assert.equal(isConjunctiveQuestion(question), true);

  // No lexical branch: both requested parts are semantic-only (cross-language).
  const harness = createHarness({
    notes: [noteOf(returns), noteOf(warranty)],
    vector: [
      ranked(returns, 1, { vectorDistance: 0.2 }),
      ranked(warranty, 2, { vectorDistance: 0.8 }),
    ],
    keyword: [],
    vectors: new Map([
      [sourceKey(returns), embedding(0.8, 0.6, 0)],
      [sourceKey(warranty), embedding(0.2, Math.sqrt(0.96), 0)],
    ]),
  });

  const response = await harness.run(question);
  assert.equal(response.status, 'ANSWERED');
  assert.equal(harness.calls.keywordSearch, 1);
  assert.equal(harness.calls.jev.length, 1);
  const evidence = harness.calls.jev[0]?.state.evidence ?? '';
  assert.ok(evidence.includes('Refund policy: 30 days.'), evidence);
  assert.ok(evidence.includes('Warranty policy: 12 months.'), evidence);
  assert.deepEqual(noteIds(harness.calls.getVectors[0] ?? []), ['n-return', 'n-warranty']);

  const event = harness.diagnostics[0];
  assert.ok(event);
  assert.equal(event.keywordCandidateCount, 0, 'the cross-language query has no lexical branch');
  assert.equal(event.vectorCandidateCount, 2);
  assert.equal(event.relevanceMode, 'scored');
  assert.equal(event.relevantCandidateCount, 2);
  assert.deepEqual(event.rejectedChunkReasons, []);
});

test('mixed lexical and semantic multipart evidence survives the closest-anchor boundary', async () => {
  const returns = chunkOf('n-return', 'Chính sách hoàn tiền', 'Refund policy: 30 days.');
  const warranty = chunkOf('n-warranty', 'Warranty policy', 'Warranty policy: 12 months.');
  const question = 'Chính sách hoàn tiền và chính sách bảo hành là gì?';
  assert.equal(isConjunctiveQuestion(question), true);

  // One strong lexical part must not exclude the weaker cross-language semantic part.
  const harness = createHarness({
    notes: [noteOf(returns), noteOf(warranty)],
    vector: [
      ranked(returns, 1, { vectorDistance: 0.2 }),
      ranked(warranty, 2, { vectorDistance: 0.8 }),
    ],
    keyword: [ranked(returns, 1, { bm25Score: 4 })],
    vectors: new Map([
      [sourceKey(returns), embedding(0.8, 0.6, 0)],
      [sourceKey(warranty), embedding(0.2, Math.sqrt(0.96), 0)],
    ]),
  });

  const response = await harness.run(question);
  assert.equal(response.status, 'ANSWERED');
  assert.equal(harness.calls.keywordSearch, 1);
  assert.equal(harness.calls.jev.length, 1);
  const evidence = harness.calls.jev[0]?.state.evidence ?? '';
  assert.ok(evidence.includes('Refund policy: 30 days.'), evidence);
  assert.ok(evidence.includes('Warranty policy: 12 months.'), evidence);
  assert.deepEqual(noteIds(harness.calls.getVectors[0] ?? []), ['n-return', 'n-warranty']);

  const event = harness.diagnostics[0];
  assert.ok(event);
  assert.equal(event.keywordCandidateCount, 1);
  assert.equal(event.vectorCandidateCount, 2);
  assert.equal(event.relevanceMode, 'scored');
  assert.equal(event.relevantCandidateCount, 2);
  assert.deepEqual(event.rejectedChunkReasons, []);
});

test('a long same-entity correction is retained with the primary fact', async () => {
  const primary = chunkOf('n-primary', 'SLGH031', 'Dự trữ năng lượng khoảng 80 giờ.');
  const correctionText = `Dự trữ năng lượng khoảng 100 giờ. ${'Ghi chú đính chính rất dài. '.repeat(20)}`;
  const correction = chunkOf('n-correction', 'SLGH031 — đính chính', correctionText);
  const question = 'SLGH031 dự trữ năng lượng bao lâu?';

  const harness = createHarness({
    notes: [noteOf(primary), noteOf(correction)],
    vector: [
      ranked(primary, 1, { vectorDistance: 0.2 }),
      ranked(correction, 9, { vectorDistance: 0.8 }),
    ],
    keyword: [
      ranked(primary, 1, { bm25Score: 4 }),
      // Long notes depress raw BM25; the relative coverage floor keeps the correction reliable.
      ranked(correction, 2, { bm25Score: 0.4 }),
    ],
    vectors: new Map([
      [sourceKey(primary), embedding(0.8, 0.6, 0)],
      [sourceKey(correction), embedding(0.2, Math.sqrt(0.96), 0)],
    ]),
  });

  const response = await harness.run(question);
  assert.equal(response.status, 'ANSWERED');
  assert.deepEqual(noteIds(harness.calls.getVectors[0] ?? []), ['n-primary', 'n-correction']);
  const evidence = harness.calls.jev[0]?.state.evidence ?? '';
  assert.ok(evidence.includes('80 giờ'), evidence);
  assert.ok(evidence.includes('100 giờ'), evidence);
  const event = harness.diagnostics[0];
  assert.ok(event);
  assert.deepEqual(event.rejectedChunkReasons, []);
  assert.deepEqual(noteIds(harness.calls.neighbors[0] ?? []), ['n-primary', 'n-correction']);
});

test('an actual same-event conflict reaches JEV instead of being merged or dropped', async () => {
  const fourteen = chunkOf('n-conflict-14', 'Hoa Sen', 'Hoa Sen mở cửa lúc 14:00.');
  const sixteen = chunkOf('n-conflict-16', 'Hoa Sen', 'Hoa Sen mở cửa lúc 16:00.');
  const question = 'Hoa Sen mở cửa lúc mấy giờ?';

  const harness = createHarness({
    notes: [noteOf(fourteen), noteOf(sixteen)],
    vector: [
      ranked(fourteen, 1, { vectorDistance: 0.2 }),
      ranked(sixteen, 2, { vectorDistance: 0.8 }),
    ],
    keyword: [
      ranked(fourteen, 1, { bm25Score: 3 }),
      // Weaker lexical evidence still clears the relative coverage floor; positive utility keeps
      // the contradictory second fact available to JEV instead of dropping it as redundant.
      ranked(sixteen, 2, { bm25Score: 1.2 }),
    ],
    vectors: new Map([
      [sourceKey(fourteen), embedding(0.8, 0.6, 0)],
      [sourceKey(sixteen), embedding(0.2, Math.sqrt(0.96), 0)],
    ]),
    support: 0.96,
    conflict: 0.97,
  });

  const response = await harness.run(question);
  assert.equal(response.status, 'NOT_ENOUGH_CONTEXT');
  if (response.status !== 'NOT_ENOUGH_CONTEXT') assert.fail('expected an abstention');
  assert.equal(response.reason, 'UNRESOLVED_CONFLICT');
  const evidence = harness.calls.jev[0]?.state.evidence ?? '';
  assert.ok(evidence.includes('14:00'), evidence);
  assert.ok(evidence.includes('16:00'), evidence);
  assert.equal(harness.calls.generate.length, 0);
  const event = harness.diagnostics[0];
  assert.ok(event);
  assert.equal(event.answerabilityNoul, 0.96);
  assert.equal(event.conflictNoul, 0.97);
});

test('foreign, stale and malformed branch data fail before the gate, getVectors or JEV', async () => {
  const own = chunkOf('n-validation', 'Validation', 'alpha beta');
  const base = {
    notes: [noteOf(own)],
    keyword: [] as readonly Ranked[],
    vectors: new Map([[sourceKey(own), embedding(1, 0, 0)]]),
  } as const;

  const foreign = createHarness({
    ...base,
    vector: [ranked({ ...own, ownerId: 'actor-foreign' }, 1, { vectorDistance: 0.1 })],
  });
  assert.equal(errorCode(await foreign.run('alpha beta?')), 'SCOPE_DENIED');

  const stale = createHarness({
    ...base,
    vector: [ranked({ ...own, revision: 2 }, 1, { vectorDistance: 0.1 })],
  });
  assert.equal(errorCode(await stale.run('alpha beta?')), 'SOURCE_CHANGED');

  const malformed = createHarness({
    ...base,
    vector: [ranked(own, 1, { vectorDistance: 2.5 })],
  });
  assert.equal(errorCode(await malformed.run('alpha beta?')), 'INVALID_INPUT');

  for (const harness of [foreign, stale, malformed]) {
    assert.equal(harness.calls.getVectors.length, 0, 'invalid branch data never reaches the shortlist');
    assert.equal(harness.calls.jev.length, 0, 'invalid branch data never reaches JEV');
    assert.equal(harness.calls.generate.length, 0);
  }
});

test('the gate shortlist keeps original ranks and scores, equivalent to pre-rank filtering', () => {
  const kept = chunkOf('n-kept', 'Kept', 'alpha');
  const dropped = chunkOf('n-dropped', 'Dropped', 'beta');
  const vector = [ranked(kept, 1, { vectorDistance: 0.2 }), ranked(dropped, 2, { vectorDistance: 1.5 })];
  const keyword = [ranked(kept, 1, { bm25Score: 2 })];
  const fused = rrf(vector, keyword);
  const decision = selectRelevantCandidates('alpha?', fused);

  assert.deepEqual(noteIds(decision.kept.map((candidate) => candidate.chunk)), ['n-kept']);
  const keptKeys = new Set(decision.kept.map((candidate) => sourceKey(candidate.chunk)));
  const filtered = rrf(
    vector.filter((entry) => keptKeys.has(sourceKey(entry.chunk))),
    keyword.filter((entry) => keptKeys.has(sourceKey(entry.chunk))),
  );
  assert.deepEqual(
    decision.kept.map((candidate) => [
      sourceKey(candidate.chunk),
      candidate.score,
      candidate.vectorRank,
      candidate.bm25Rank,
    ]),
    filtered.map((candidate) => [
      sourceKey(candidate.chunk),
      candidate.score,
      candidate.vectorRank,
      candidate.bm25Rank,
    ]),
  );
});
