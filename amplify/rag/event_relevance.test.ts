/**
 * Synthetic event-relevance regressions for the canonical pipeline:
 * authority -> vector/BM25 -> RRF -> relevance shortlist -> getVectors/MMR -> evidence -> JEV.
 * Main: a multipart watercolour-workshop question must use exactly its schedule and fee notes;
 * same-generic-word/different-date, different meeting and unrelated goal/watch/person notes are
 * noise. Extras: renamed event, different date, fee conflict, long lower-BM25 correction,
 * independent-topic conjunction, cross-language fallback, fail-closed validation.
 * All data is synthetic; BM25 is real over that corpus.
 * Runner: node --import tsx --test amplify/rag/event_relevance.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SECTION_BODY } from './chunking';
import { CONSENT_VERSION } from './contract';
import { bm25 } from './keyword';
import { countSyntheticTokens } from './mock';
import { createQuery, type PipelineDeps } from './pipeline';
import { policy, RagFailure, sourceKey } from './types';
import type {
  CanonicalNote, CanonicalState, Chunk, GenerateInput, JevInput, RagResponse, Ranked,
  RuntimeConfig,
} from './types';

const OWNER = 'actor-event';
const MODEL = 'synthetic-event-jev';
const CONFIG: RuntimeConfig = Object.freeze({
  mode: 'mock', model: MODEL, thresholds: Object.freeze({ answerabilityMin: 0.9, conflictMax: 0.1 }),
  jevMaxTokens: 32_768, requestTimeoutMs: 26_000,
});
const EVENT_QUESTION = 'Workshop vẽ màu nước ngày 25/10/2026 diễn ra khi nào, ở đâu và lệ phí bao nhiêu?';
const FEE_QUESTION = 'Workshop vẽ màu nước ngày 25/10/2026 có lệ phí bao nhiêu?';
const POTTERY_QUESTION = 'Lớp làm gốm ngày 02/11/2026 diễn ra khi nào, ở đâu và học phí bao nhiêu?';
const CORRECTION_QUESTION = 'Workshop vẽ màu nước ngày 25/10/2026 diễn ra ở đâu và lệ phí bao nhiêu?';
const TOPICS_QUESTION = 'Hạn chót báo cáo quý 3 và lịch họp Hoa Sen là khi nào?';
const CROSS_LANGUAGE_QUESTION = 'When does the lotus group meet, and what is the fee?';

/** Unit vector on the 768-d circle whose cosine with the query vector is `cosine`. */
const unitVector = (cosine: number): readonly number[] => {
  const first = Math.max(-1, Math.min(1, cosine));
  return Object.freeze(Array.from({ length: policy.embedding.dimensions }, (_value, index) =>
    index === 0 ? first : index === 1 ? Math.sqrt(1 - first * first) : 0));
};
const chunkOf = (noteId: string, title: string, text: string): Chunk =>
  ({ ownerId: OWNER, noteId, revision: 1, sectionId: SECTION_BODY, chunkId: 'body-0', ordinal: 0,
    title, startOffset: 0, endOffset: text.length, text });
const noteOf = (chunk: Chunk): CanonicalNote =>
  ({ ownerId: chunk.ownerId, noteId: chunk.noteId, revision: chunk.revision, title: chunk.title,
    content: chunk.text, synced: true, protected: false, deleted: false, available: true });
const ranked = (chunk: Chunk, rank: number, signals: Readonly<{ vectorDistance?: number }> = {}): Ranked =>
  ({ chunk, rank, ...signals });
const jevEnvelope = (input: JevInput, support: number, conflict: number): unknown => ({
  model: MODEL,
  answers: { answerable_from_evidence: { type: 'noul', noul: support },
    has_unresolved_conflict: { type: 'noul', noul: conflict } },
  usage: { input_tokens: countSyntheticTokens(JSON.stringify(input)), output_tokens: 4 },
});

type Entry = Readonly<{ chunk: Chunk; distance: number }>;
type HarnessOptions = Readonly<{
  entries: readonly Entry[];
  notes?: readonly CanonicalNote[]; // canonical notes when they differ (fail-closed cases)
  support?: number; conflict?: number;
}>;
type Harness = Readonly<{
  calls: Readonly<{ embedQuery: number; vectorSearch: number; keywordSearch: number;
    getVectors: readonly Chunk[][]; neighbors: readonly Chunk[][];
    jev: readonly JevInput[]; generate: readonly GenerateInput[] }>;
  run(question: string): Promise<RagResponse>;
}>;

/**
 * Bounded local copy of the retrieval-quality harness pattern; the existing test file is not
 * changed or exported. Vector order is distance order and the lexical branch defaults to real
 * BM25. `cosine = 1 - vectorDistance` keeps the synthetic vectors physically consistent.
 */
const createHarness = (options: HarnessOptions): Harness => {
  let embedCalls = 0;
  let vectorCalls = 0;
  let keywordCalls = 0;
  let sequence = 0;
  const fetched: Chunk[][] = [];
  const neighborCalls: Chunk[][] = [];
  const jevCalls: JevInput[] = [];
  const generateCalls: GenerateInput[] = [];
  const chunks = options.entries.map((entry) => entry.chunk);
  const notes = options.notes ?? chunks.map(noteOf);
  const state: CanonicalState = Object.freeze({
    actorId: OWNER, sessionGeneration: 1,
    consent: Object.freeze({ accepted: true, version: CONSENT_VERSION, generation: 1 }),
    indexReady: true, manifestVersion: 'event-1', notes: Object.freeze([...notes]),
  });
  const vectors = new Map(options.entries.map((entry) =>
    [sourceKey(entry.chunk), unitVector(1 - entry.distance)]));
  const branch = Object.freeze([...options.entries]
    .sort((left, right) => left.distance - right.distance ||
      (sourceKey(left.chunk) < sourceKey(right.chunk) ? -1 : 1))
    .map((entry, index) => ranked(entry.chunk, index + 1, { vectorDistance: entry.distance })));
  const deps: PipelineDeps = {
    authority: Object.freeze({
      read: async (actor: string): Promise<CanonicalState> => {
        if (actor !== OWNER) throw new RagFailure('UNAUTHORIZED');
        return state;
      },
    }),
    retrieval: {
      embedQuery: async () => { embedCalls += 1; return unitVector(1); },
      vectorSearch: async () => { vectorCalls += 1; return branch; },
      keywordSearch: async (question) => { keywordCalls += 1; return bm25(question, chunks); },
      getVectors: async (requested) => {
        fetched.push([...requested]);
        return new Map(requested.map((chunk) => {
          const vector = vectors.get(sourceKey(chunk));
          if (vector === undefined) throw new RagFailure('INDEX_NOT_READY');
          return [sourceKey(chunk), vector];
        }));
      },
      neighbors: async (anchors) => { neighborCalls.push([...anchors]); return Object.freeze([]); },
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
    counters: { embedding: countSyntheticTokens, evidence: countSyntheticTokens,
      jev: countSyntheticTokens, output: countSyntheticTokens },
    config: CONFIG,
    consumeQuota: async () => true,
  };
  const query = createQuery(deps);
  return {
    calls: {
      get embedQuery() { return embedCalls; },
      get vectorSearch() { return vectorCalls; },
      get keywordSearch() { return keywordCalls; },
      getVectors: fetched, neighbors: neighborCalls, jev: jevCalls, generate: generateCalls,
    },
    run: (question: string) => {
      sequence += 1;
      return query(OWNER, { wireVersion: 1, question, scope: { type: 'account' } }, `event-${sequence}`);
    },
  };
};

const noteIds = (chunks: readonly Chunk[]): readonly string[] => chunks.map((chunk) => chunk.noteId);
const assertAnswered = (response: RagResponse): void => {
  if (response.status !== 'ANSWERED') assert.fail(`expected ANSWERED, got ${response.status}: ${
    response.status === 'ERROR' ? response.code : response.reason}`);
};
const errorCode = (response: RagResponse): string =>
  response.status === 'ERROR' ? response.code : assert.fail(`expected ERROR, got ${response.status}`);
const assertRetrievalOnce = (harness: Harness): void => {
  assert.equal(harness.calls.embedQuery, 1);
  assert.equal(harness.calls.vectorSearch, 1);
  assert.equal(harness.calls.keywordSearch, 1);
  assert.equal(harness.calls.getVectors.length, 1);
  assert.equal(harness.calls.neighbors.length, 1);
  assert.equal(harness.calls.jev.length, 1);
};

const demo = chunkOf('n-ws-demo', 'DEMO Lịch workshop',
  'Workshop vẽ màu nước diễn ra lúc 09:00 ngày 25/10/2026 tại phòng A2.');
const fee = chunkOf('n-ws-fee', 'Workshop vẽ màu nước - lệ phí',
  'Workshop vẽ màu nước ngày 25/10/2026 có lệ phí 150.000đ/người đã bao gồm dụng cụ.');
const trucBac = chunkOf('n-ws-truc-bac', 'Workshop vẽ màu nước Trúc Bạc',
  'Workshop vẽ màu nước Trúc Bạc diễn ra lúc 14:00 ngày 29/11/2026 tại phòng sinh hoạt cộng đồng. ' +
  'Lệ phí 100.000đ/người, đăng ký muộn 150.000đ/người; đã bao gồm dụng cụ vẽ.');
const hoaSen = chunkOf('n-hoa-sen', 'Hoa Sen',
  'Họp nhóm Hoa Sen lúc 14:00 ngày 12/11/2026 tại phòng B1. ' +
  'Nội dung chuẩn bị báo cáo quý 3 và phân công công việc.');
const goals = chunkOf('n-goals', 'Mục tiêu quý 4',
  'Mục tiêu quý 4: hoàn thành doanh thu, cập nhật OKR và theo dõi tiến độ công việc hàng tuần.');
const watch = chunkOf('n-watch', 'Watch',
  'Mua đồng hồ mới trước sinh nhật Daniel. Ngân sách dự kiến khoảng 5 triệu đồng.');
const daniel = chunkOf('n-daniel', 'Daniel',
  'Daniel thích uống cà phê sữa đá và đọc sách vào cuối tuần.');
const noise: readonly Entry[] = [
  { chunk: goals, distance: 0.95 }, { chunk: daniel, distance: 0.98 }, { chunk: watch, distance: 1.05 },
];
const farNoise: readonly Entry[] = [
  { chunk: goals, distance: 1.02 }, { chunk: daniel, distance: 1.08 }, { chunk: watch, distance: 1.15 },
];

test('two relevant event notes are the only evidence for a multipart event question', async () => {
  const entries: readonly Entry[] = [
    { chunk: demo, distance: 0.18 }, { chunk: fee, distance: 0.26 },
    { chunk: trucBac, distance: 0.42 }, { chunk: hoaSen, distance: 0.72 }, ...noise,
  ];
  // Real BM25 over the whole account, not a hand-written score list.
  const keyword = bm25(EVENT_QUESTION, entries.map((entry) => entry.chunk));
  const scores = new Map(keyword.map((entry) => [entry.chunk.noteId, entry.bm25Score ?? 0]));
  assert.ok((scores.get('n-ws-fee') ?? 0) > 0);
  assert.ok((scores.get('n-ws-demo') ?? 0) > 0);
  assert.ok((scores.get('n-ws-fee') ?? 0) > (scores.get('n-hoa-sen') ?? 0));

  const harness = createHarness({ entries });
  assertAnswered(await harness.run(EVENT_QUESTION));
  const evidence = harness.calls.jev[0]?.state.evidence ?? '';
  assert.match(evidence, /09:00/);
  assert.match(evidence, /phòng A2/);
  assert.match(evidence, /150\.000/);
  for (const unrelated of ['Trúc Bạc', '29/11/2026', '100.000', 'Hoa Sen', '12/11/2026',
    'Daniel', 'đồng hồ', 'OKR']) {
    assert.ok(!evidence.includes(unrelated), `unrelated noise reached JEV: ${unrelated}`);
  }
  const anchors = noteIds(harness.calls.neighbors[0] ?? []);
  assert.deepEqual([...anchors].sort(), ['n-ws-demo', 'n-ws-fee']);
  assert.deepEqual([...noteIds(harness.calls.getVectors[0] ?? [])].sort(),
    ['n-ws-demo', 'n-ws-fee']);
  assertRetrievalOnce(harness);
  assert.equal(harness.calls.generate.length, 1);
});

test('a renamed event is selected by its own facts, not the literal watercolor name', async () => {
  const potterySchedule = chunkOf('n-pottery-schedule', 'Lịch lớp gốm',
    'Lớp làm gốm diễn ra lúc 13:30 ngày 02/11/2026 tại xưởng gốm Hoa Đất.');
  const potteryFee = chunkOf('n-pottery-fee', 'Học phí lớp gốm',
    'Lớp làm gốm ngày 02/11/2026 có học phí 250.000đ/người, đã bao gồm đất sét và men.');
  const entries: readonly Entry[] = [
    { chunk: potterySchedule, distance: 0.17 }, { chunk: potteryFee, distance: 0.24 },
    { chunk: demo, distance: 0.4 }, { chunk: fee, distance: 0.45 }, ...noise,
  ];
  const harness = createHarness({ entries });
  assertAnswered(await harness.run(POTTERY_QUESTION));
  const evidence = harness.calls.jev[0]?.state.evidence ?? '';
  assert.match(evidence, /13:30/);
  assert.match(evidence, /xưởng gốm Hoa Đất/);
  assert.match(evidence, /250\.000/);
  assert.ok(!evidence.includes('Workshop vẽ màu nước'), 'the differently named event leaked in');
  assert.ok(!evidence.includes('phòng A2'));
  assert.ok(!evidence.includes('150.000'));
  const anchors = noteIds(harness.calls.neighbors[0] ?? []);
  assert.ok(anchors.includes('n-pottery-schedule'));
  assert.ok(anchors.includes('n-pottery-fee'));
  assert.ok(!anchors.includes('n-ws-demo'));
  assert.ok(!anchors.includes('n-ws-fee'));
  assertRetrievalOnce(harness);
  assert.equal(harness.calls.generate.length, 1);
});

test('the same generic workshop words on a different full date do not enter evidence', async () => {
  const day25Schedule = chunkOf('n-day25-schedule', 'Lịch workshop 25/10',
    'Workshop vẽ màu nước diễn ra lúc 09:00 ngày 25/10/2026 tại phòng A2.');
  const day25Fee = chunkOf('n-day25-fee', 'Lệ phí workshop 25/10',
    'Workshop vẽ màu nước ngày 25/10/2026 có lệ phí 150.000đ/người đã bao gồm dụng cụ.');
  const day27Schedule = chunkOf('n-day27-schedule', 'Lịch workshop 27/10',
    'Workshop vẽ màu nước diễn ra lúc 08:00 ngày 27/10/2026 tại phòng C3.');
  const day27Fee = chunkOf('n-day27-fee', 'Lệ phí workshop 27/10',
    'Workshop vẽ màu nước ngày 27/10/2026 có lệ phí 120.000đ/người đã bao gồm dụng cụ.');
  const entries: readonly Entry[] = [
    { chunk: day25Schedule, distance: 0.18 }, { chunk: day25Fee, distance: 0.26 },
    { chunk: day27Schedule, distance: 0.38 }, { chunk: day27Fee, distance: 0.44 },
  ];
  const harness = createHarness({ entries });
  assertAnswered(await harness.run(EVENT_QUESTION));
  const evidence = harness.calls.jev[0]?.state.evidence ?? '';
  assert.match(evidence, /09:00/);
  assert.match(evidence, /phòng A2/);
  assert.match(evidence, /150\.000/);
  assert.ok(!evidence.includes('27/10/2026'), 'a different full date reached JEV');
  assert.ok(!evidence.includes('phòng C3'));
  assert.ok(!evidence.includes('120.000'));
  const anchors = noteIds(harness.calls.neighbors[0] ?? []);
  assert.ok(anchors.includes('n-day25-schedule'));
  assert.ok(anchors.includes('n-day25-fee'));
  assert.ok(!anchors.includes('n-day27-schedule'));
  assert.ok(!anchors.includes('n-day27-fee'));
  const fetched = noteIds(harness.calls.getVectors[0] ?? []);
  assert.ok(!fetched.includes('n-day27-schedule'));
  assert.ok(!fetched.includes('n-day27-fee'));
  assertRetrievalOnce(harness);
  assert.equal(harness.calls.generate.length, 1);
});

test('conflicting same-event fees both reach JEV and no answer is generated', async () => {
  const schedule = chunkOf('n-conflict-schedule', 'Lịch workshop',
    'Workshop vẽ màu nước ngày 25/10/2026 diễn ra lúc 09:00 tại phòng A2.');
  const fee150 = chunkOf('n-conflict-fee-150', 'Lệ phí workshop 150k',
    'Workshop vẽ màu nước ngày 25/10/2026 có lệ phí 150.000đ/người, đã bao gồm dụng cụ.');
  const fee200 = chunkOf('n-conflict-fee-200', 'Lệ phí workshop 200k',
    'Workshop vẽ màu nước ngày 25/10/2026 có lệ phí 200.000đ/người, đã bao gồm dụng cụ.');
  const harness = createHarness({
    entries: [{ chunk: schedule, distance: 0.18 }, { chunk: fee150, distance: 0.24 },
      { chunk: fee200, distance: 0.27 }, ...noise],
    support: 0.96, conflict: 0.97,
  });
  const response = await harness.run(FEE_QUESTION);
  if (response.status !== 'NOT_ENOUGH_CONTEXT') assert.fail(`expected abstention, got ${response.status}`);
  assert.equal(response.reason, 'UNRESOLVED_CONFLICT');
  const evidence = harness.calls.jev[0]?.state.evidence ?? '';
  assert.match(evidence, /150\.000/);
  assert.match(evidence, /200\.000/);
  const anchors = noteIds(harness.calls.neighbors[0] ?? []);
  assert.ok(anchors.includes('n-conflict-fee-150'));
  assert.ok(anchors.includes('n-conflict-fee-200'));
  assertRetrievalOnce(harness);
  assert.equal(harness.calls.generate.length, 0);
});

test('a long correction with lower raw BM25 survives with the primary fact', async () => {
  const primary = chunkOf('n-correct-primary', 'Lịch workshop 25/10',
    'Workshop vẽ màu nước ngày 25/10/2026 diễn ra lúc 09:00 tại phòng A2. Lệ phí 150.000đ/người.');
  const correctionText = 'Đính chính workshop vẽ màu nước ngày 25/10/2026: địa điểm chuyển sang ' +
    'phòng B4, lệ phí giữ nguyên 150.000đ/người. ' +
    'Ghi chú cập nhật từ ban tổ chức về phòng học và dụng cụ. '.repeat(16);
  const correction = chunkOf('n-correct-update', 'Đính chính workshop 25/10', correctionText);
  const entries: readonly Entry[] = [
    { chunk: primary, distance: 0.18 }, { chunk: correction, distance: 0.3 }, ...noise,
  ];
  const keyword = bm25(CORRECTION_QUESTION, entries.map((entry) => entry.chunk));
  const scores = new Map(keyword.map((entry) => [entry.chunk.noteId, entry.bm25Score ?? 0]));
  assert.ok((scores.get('n-correct-update') ?? 0) < (scores.get('n-correct-primary') ?? 0));
  const harness = createHarness({ entries });
  assertAnswered(await harness.run(CORRECTION_QUESTION));
  const evidence = harness.calls.jev[0]?.state.evidence ?? '';
  assert.match(evidence, /09:00/);
  assert.match(evidence, /phòng A2/);
  assert.match(evidence, /phòng B4/);
  assert.match(evidence, /150\.000/);
  const anchors = noteIds(harness.calls.neighbors[0] ?? []);
  assert.ok(anchors.includes('n-correct-primary'));
  assert.ok(anchors.includes('n-correct-update'));
  assert.ok(!anchors.includes('n-goals'));
  assertRetrievalOnce(harness);
  assert.equal(harness.calls.generate.length, 1);
});

test('a genuine independent-topic conjunction retains both requested sources', async () => {
  const reportDeadline = chunkOf('n-report-deadline', 'Hạn chót báo cáo quý 3',
    'Báo cáo quý 3 phải nộp trước 17:00 ngày 30/09/2026 cho phòng tài chính.');
  const hoaSenMeeting = chunkOf('n-hoa-sen-meeting', 'Lịch họp Hoa Sen',
    'Họp nhóm Hoa Sen lúc 14:00 ngày 12/11/2026 tại phòng B1.');
  const harness = createHarness({
    entries: [{ chunk: reportDeadline, distance: 0.2 }, { chunk: hoaSenMeeting, distance: 0.42 },
      ...noise],
  });
  assertAnswered(await harness.run(TOPICS_QUESTION));
  const evidence = harness.calls.jev[0]?.state.evidence ?? '';
  assert.match(evidence, /17:00/);
  assert.match(evidence, /30\/09\/2026/);
  assert.match(evidence, /14:00/);
  assert.match(evidence, /12\/11\/2026/);
  assert.ok(!evidence.includes('OKR'));
  assert.ok(!evidence.includes('đồng hồ'));
  assert.ok(!evidence.includes('Daniel'));
  const anchors = noteIds(harness.calls.neighbors[0] ?? []);
  assert.ok(anchors.includes('n-report-deadline'));
  assert.ok(anchors.includes('n-hoa-sen-meeting'));
  assert.ok(!anchors.includes('n-goals'));
  assertRetrievalOnce(harness);
  assert.equal(harness.calls.generate.length, 1);
});

test('a cross-language query with no lexical overlap uses the vector-only fallback', async () => {
  const hoaSenSchedule = chunkOf('n-lotus-schedule', 'Hoa Sen',
    'Hoa Sen họp lúc 14:00 ngày 12/11/2026 tại phòng B1.');
  const hoaSenFee = chunkOf('n-lotus-fee', 'Hoa Sen - lệ phí',
    'Hoa Sen thu lệ phí 150.000đ/người cho buổi họp ngày 12/11/2026.');
  const entries: readonly Entry[] = [
    { chunk: hoaSenSchedule, distance: 0.22 }, { chunk: hoaSenFee, distance: 0.3 }, ...farNoise,
  ];
  // Real BM25 proves this is genuinely lexical-empty; the vector branch supplies both factors.
  assert.equal(bm25(CROSS_LANGUAGE_QUESTION, entries.map((entry) => entry.chunk)).length, 0);
  const harness = createHarness({ entries });
  assertAnswered(await harness.run(CROSS_LANGUAGE_QUESTION));
  const evidence = harness.calls.jev[0]?.state.evidence ?? '';
  assert.match(evidence, /14:00/);
  assert.match(evidence, /150\.000/);
  assert.ok(!evidence.includes('OKR'));
  assert.ok(!evidence.includes('Daniel'));
  const anchors = noteIds(harness.calls.neighbors[0] ?? []);
  assert.ok(anchors.includes('n-lotus-schedule'));
  assert.ok(anchors.includes('n-lotus-fee'));
  assert.ok(!anchors.includes('n-goals'));
  assertRetrievalOnce(harness);
  assert.equal(harness.calls.generate.length, 1);
});

test('foreign, stale and malformed branches fail closed before the gate, vectors or JEV', async () => {
  const own = chunkOf('n-validation', 'Validation', 'alpha beta');
  const ownNotes = Object.freeze([noteOf(own)]);
  const cases = [
    { name: 'foreign', entries: [{ chunk: { ...own, ownerId: 'actor-foreign' }, distance: 0.1 }],
      code: 'SCOPE_DENIED' },
    { name: 'stale', entries: [{ chunk: { ...own, revision: 2 }, distance: 0.1 }],
      code: 'SOURCE_CHANGED' },
    { name: 'malformed', entries: [{ chunk: own, distance: 2.5 }], code: 'INVALID_INPUT' },
  ] as const;  for (const item of cases) {
    const harness = createHarness({ entries: item.entries, notes: ownNotes });
    assert.equal(errorCode(await harness.run('alpha beta?')), item.code, item.name);
    assert.equal(harness.calls.getVectors.length, 0, `${item.name} reached getVectors`);
    assert.equal(harness.calls.jev.length, 0, `${item.name} reached JEV`);
    assert.equal(harness.calls.generate.length, 0, `${item.name} reached generation`);
  }
});
