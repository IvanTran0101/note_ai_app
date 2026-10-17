/**
 * Ordered relevance gate tests: the deterministic pre-MMR shortlist, query-relative vector
 * boundary, lexical reliability/coverage, explicit multi-part protection, conservative legacy
 * seams and metric privacy. Authored synthetic chunks only; no provider, cloud or network.
 *
 * Runner: node --import tsx --test amplify/rag/relevance.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { RELEVANCE_POLICY_VERSION, selectRelevantCandidates } from './relevance';
import { RagFailure, type Candidate, type Chunk } from './types';

let sequence = 0;

const makeChunk = (id: string, title: string, text: string): Chunk => {
  sequence += 1;
  return {
    ownerId: 'actor-a',
    noteId: id,
    revision: 1,
    sectionId: 'body',
    chunkId: `body-${sequence}`,
    ordinal: 0,
    title,
    startOffset: 0,
    endOffset: text.length,
    text,
  };
};

type CandidateOptions = Readonly<{
  score?: number;
  vectorRank?: number;
  bm25Rank?: number;
  vectorDistance?: number;
  bm25Score?: number;
}>;

const makeCandidate = (chunk: Chunk, options: CandidateOptions = {}): Candidate => {
  const candidate: {
    chunk: Chunk;
    score: number;
    vectorRank?: number;
    bm25Rank?: number;
    vectorDistance?: number;
    bm25Score?: number;
  } = { chunk, score: options.score ?? 0.5 };
  if (options.vectorRank !== undefined) candidate.vectorRank = options.vectorRank;
  if (options.bm25Rank !== undefined) candidate.bm25Rank = options.bm25Rank;
  if (options.vectorDistance !== undefined) candidate.vectorDistance = options.vectorDistance;
  if (options.bm25Score !== undefined) candidate.bm25Score = options.bm25Score;
  return candidate;
};

const ids = (candidates: readonly Candidate[]): readonly string[] =>
  candidates.map((candidate) => candidate.chunk.noteId);
const reasons = (decision: ReturnType<typeof selectRelevantCandidates>): readonly string[] =>
  decision.rejected.map((entry) => entry.reason);
const isInvalidInput = (error: unknown): boolean =>
  error instanceof RagFailure && error.code === 'INVALID_INPUT';

test('filler-only watch matches are never lexical anchors: the HS hit is the sole lexical anchor', () => {
  const hs = makeChunk('hs', 'Hoa Sen', 'Mở cửa 8:00');
  const watchA = makeChunk('watch-a', 'Lịch khi ra', 'khi ra');
  const watchB = makeChunk('watch-b', 'Khi nào ra', 'khi ra');
  const semantic = makeChunk('semantic', 'Bến xe', 'Địa chỉ bến xe');

  const decision = selectRelevantCandidates('Hoa Sen mở cửa khi nào ra sao?', [
    makeCandidate(hs, { score: 1, vectorRank: 1, bm25Rank: 1, vectorDistance: 0.2, bm25Score: 3 }),
    makeCandidate(watchA, { score: 0.9, vectorRank: 2, bm25Rank: 2, vectorDistance: 0.3, bm25Score: 2.9 }),
    makeCandidate(watchB, { score: 0.8, vectorRank: 3, bm25Rank: 3, vectorDistance: 0.4, bm25Score: 2.8 }),
    makeCandidate(semantic, { score: 0.5, vectorRank: 4, vectorDistance: 0.1 }),
  ]);

  assert.equal(decision.policyVersion, RELEVANCE_POLICY_VERSION);
  assert.equal(decision.mode, 'scored');
  assert.deepEqual(ids(decision.kept), ['hs', 'semantic']);
  assert.deepEqual(reasons(decision), ['no_query_overlap', 'no_query_overlap']);
});

test('two true facts about the asked entity (14 vs 16) are both retained although one is weaker', () => {
  const fourteen = makeChunk('hs-14', 'Hoa Sen 14', 'Gói 14 ngày');
  const sixteen = makeChunk('hs-16', 'Hoa Sen 16', 'Gói 16 ngày');
  const offBoundary = makeChunk('vector-only', 'Bảng giá', 'Bảng giá tham khảo');

  const decision = selectRelevantCandidates('Hoa Sen gói 14 hay 16 ngày?', [
    makeCandidate(fourteen, {
      score: 1, vectorRank: 1, bm25Rank: 1, vectorDistance: 0.1, bm25Score: 3,
    }),
    makeCandidate(sixteen, {
      score: 0.8, vectorRank: 2, bm25Rank: 2, vectorDistance: 1.4, bm25Score: 1.2,
    }),
    makeCandidate(offBoundary, { score: 0.4, vectorRank: 3, vectorDistance: 0.5 }),
  ]);

  assert.deepEqual(ids(decision.kept), ['hs-14', 'hs-16']);
  assert.deepEqual(reasons(decision), ['outside_vector_boundary']);
});

test('a long correction/conflict note about the same entity survives a weaker distance', () => {
  const primary = makeChunk('primary', 'SLGH031', 'Dự trữ năng lượng khoảng 80 giờ.');
  const correction = makeChunk(
    'correction',
    'SLGH031 — đính chính',
    `Dự trữ năng lượng khoảng 100 giờ. ${'Ghi chú đính chính rất dài. '.repeat(20)}`,
  );

  const decision = selectRelevantCandidates('SLGH031 dự trữ năng lượng bao lâu?', [
    makeCandidate(primary, {
      score: 1, vectorRank: 1, bm25Rank: 1, vectorDistance: 0.05, bm25Score: 4,
    }),
    makeCandidate(correction, {
      score: 0.7, vectorRank: 9, bm25Rank: 2, vectorDistance: 1.8, bm25Score: 0.4,
    }),
  ]);

  assert.deepEqual(ids(decision.kept), ['primary', 'correction']);
  assert.deepEqual(decision.rejected, []);
});

test('explicit multi-part questions retain every meaningful lexical hit for independent facts', () => {
  const hs = makeChunk(
    'hs',
    'Hoa Sen',
    'Giờ mở cửa 8:00, số điện thoại 0123, địa chỉ A',
  );
  const bhx = makeChunk('bhx', 'Bách Hóa Xanh', 'Bách Hóa Xanh');
  const unrelated = makeChunk('unrelated', 'Lịch họp', 'khi ra');
  const candidates = [
    makeCandidate(hs, { score: 1, vectorRank: 1, bm25Rank: 1, vectorDistance: 0.2, bm25Score: 5 }),
    makeCandidate(bhx, { score: 0.6, vectorRank: 2, bm25Rank: 2, vectorDistance: 1.5, bm25Score: 0.2 }),
    makeCandidate(unrelated, { score: 0.5, vectorRank: 3, bm25Rank: 3, vectorDistance: 0.3, bm25Score: 0.1 }),
  ];

  for (const question of [
    'Hoa Sen và Bách Hóa Xanh: giờ mở cửa, số điện thoại, địa chỉ?',
    'Hoa Sen vs Bách Hóa Xanh: giờ mở cửa, số điện thoại, địa chỉ?',
    'Hoa Sen versus Bách Hóa Xanh: giờ mở cửa, số điện thoại, địa chỉ?',
    'So sánh Hoa Sen với Bách Hóa Xanh: giờ mở cửa, số điện thoại, địa chỉ?',
    'Hoa Sen and Bách Hóa Xanh: giờ mở cửa, số điện thoại, địa chỉ?',
  ]) {
    const decision = selectRelevantCandidates(question, candidates);
    assert.deepEqual(ids(decision.kept), ['hs', 'bhx'], question);
    assert.deepEqual(reasons(decision), ['no_query_overlap'], question);
  }

  // Without the explicit conjunction, the same one-entity note is a weak lexical hit and the
  // gate may drop it; the conjunction is what protects the independent requested fact.
  const withoutConjunction = selectRelevantCandidates(
    'Hoa Sen Bách Hóa Xanh giờ mở cửa số điện thoại địa chỉ?',
    candidates,
  );
  assert.deepEqual(ids(withoutConjunction.kept), ['hs']);
  assert.deepEqual(reasons(withoutConjunction), ['weak_lexical', 'no_query_overlap']);
});

test('a conjunction plus a shared year/event word is not enough to keep an off-target source', () => {
  const target = makeChunk(
    'alpha-expo',
    'Alpha watercolour expo',
    'Alpha watercolour expo ngày 25/10/2026, lệ phí 150.000 đồng tại Hội trường A.',
  );
  const offTarget = makeChunk(
    'beta-expo',
    'Beta expo',
    'Beta expo ngày 29/11/2026, lệ phí 200.000 đồng.',
  );
  const decision = selectRelevantCandidates(
    'Alpha watercolour expo ngày 25/10/2026 diễn ra ở đâu và lệ phí bao nhiêu?',
    [
      makeCandidate(target, {
        score: 1, vectorRank: 1, bm25Rank: 1, vectorDistance: 0.2, bm25Score: 5,
      }),
      // Shares only generic event/date/fee words and a conjunction with the question.
      makeCandidate(offTarget, {
        score: 0.6, vectorRank: 2, bm25Rank: 2, vectorDistance: 0.8, bm25Score: 2,
      }),
    ],
  );

  assert.deepEqual(ids(decision.kept), ['alpha-expo']);
  assert.deepEqual(reasons(decision), ['target_mismatch']);
});

test('a semantically stronger vector-only candidate beats a weak lexical anchor boundary', () => {
  const lexicalAnchor = makeChunk('anchor', 'Hoa Sen', 'Mở cửa 8:00');
  const semantic = makeChunk('semantic', 'Bến xe', 'Địa chỉ bến xe');

  const decision = selectRelevantCandidates('Hoa Sen giờ mở cửa?', [
    makeCandidate(lexicalAnchor, {
      score: 1, vectorRank: 5, bm25Rank: 1, vectorDistance: 0.5, bm25Score: 2,
    }),
    makeCandidate(semantic, { score: 0.3, vectorRank: 1, vectorDistance: 0.05 }),
  ]);

  assert.deepEqual(ids(decision.kept), ['anchor', 'semantic']);
  assert.deepEqual(decision.rejected, []);
});

test('with no lexical anchor a known positive cosine is kept and unknown legacy distance stays conservative', () => {
  const candidates = [
    makeCandidate(makeChunk('d-01', 'A', 'nội dung a'), { vectorRank: 1, vectorDistance: 0.1 }),
    makeCandidate(makeChunk('d-04', 'B', 'nội dung b'), { vectorRank: 2, vectorDistance: 0.4 }),
    makeCandidate(makeChunk('d-095', 'C', 'nội dung c'), { vectorRank: 3, vectorDistance: 0.95 }),
    makeCandidate(makeChunk('d-1', 'D', 'nội dung d'), { vectorRank: 4, vectorDistance: 1 }),
    makeCandidate(makeChunk('d-12', 'E', 'nội dung e'), { vectorRank: 5, vectorDistance: 1.2 }),
    makeCandidate(makeChunk('legacy', 'F', 'nội dung f'), { vectorRank: 6 }),
  ];

  const decision = selectRelevantCandidates('Hoa Sen giờ mở cửa?', candidates);
  assert.equal(decision.mode, 'mixed');
  assert.deepEqual(ids(decision.kept), ['d-01', 'd-04', 'd-095', 'legacy']);
  assert.deepEqual(reasons(decision), ['non_positive_semantic', 'non_positive_semantic']);
});

test('empty or wholly negative-semantic shortlists abstain without inventing metrics', () => {
  const empty = selectRelevantCandidates('Hoa Sen?', []);
  assert.deepEqual(empty.kept, []);
  assert.deepEqual(empty.rejected, []);
  assert.equal(empty.mode, 'legacy-rank-only');

  const negative = selectRelevantCandidates('Hoa Sen?', [
    makeCandidate(makeChunk('neg-1', 'A', 'nội dung a'), { vectorRank: 1, vectorDistance: 1 }),
    makeCandidate(makeChunk('neg-2', 'B', 'nội dung b'), { vectorRank: 2, vectorDistance: 1.5 }),
  ]);
  assert.deepEqual(negative.kept, []);
  assert.deepEqual(reasons(negative), ['non_positive_semantic', 'non_positive_semantic']);
});

test('malformed metrics/ranks are errors, never silently filtered into an empty shortlist', () => {
  const chunk = makeChunk('bad', 'Hoa Sen', 'Mở cửa 8:00');
  for (const value of [-0.01, 2.01, Number.NaN, Number.POSITIVE_INFINITY, -Infinity, '0.5', null]) {
    assert.throws(
      () => selectRelevantCandidates('Hoa Sen?', [
        makeCandidate(chunk, { vectorRank: 1, vectorDistance: value as unknown as number }),
      ]),
      isInvalidInput,
      `vectorDistance ${String(value)}`,
    );
  }
  for (const value of [0, -1, Number.NaN, Number.POSITIVE_INFINITY, '1', null]) {
    assert.throws(
      () => selectRelevantCandidates('Hoa Sen?', [
        makeCandidate(chunk, { bm25Rank: 1, bm25Score: value as unknown as number }),
      ]),
      isInvalidInput,
      `bm25Score ${String(value)}`,
    );
  }
  for (const value of [0, 1.5, Number.NaN, '1']) {
    assert.throws(
      () => selectRelevantCandidates('Hoa Sen?', [
        makeCandidate(chunk, { vectorRank: value as unknown as number }),
      ]),
      isInvalidInput,
      `vectorRank ${String(value)}`,
    );
    assert.throws(
      () => selectRelevantCandidates('Hoa Sen?', [
        makeCandidate(chunk, { bm25Rank: value as unknown as number }),
      ]),
      isInvalidInput,
      `bm25Rank ${String(value)}`,
    );
  }
  // Duplicate source identities are ambiguous, not a shortlist decision.
  assert.throws(
    () => selectRelevantCandidates('Hoa Sen?', [
      makeCandidate(chunk, { vectorRank: 1, vectorDistance: 0.2 }),
      makeCandidate(chunk, { vectorRank: 2, vectorDistance: 0.3 }),
    ]),
    isInvalidInput,
  );
});

test('legacy all-rank-only candidates keep every validated entry and never fabricate metrics', () => {
  const decision = selectRelevantCandidates('Hoa Sen?', [
    makeCandidate(makeChunk('legacy-a', 'A', 'a'), { score: 1, vectorRank: 1, bm25Rank: 1 }),
    makeCandidate(makeChunk('legacy-b', 'B', 'b'), { score: 0.5, vectorRank: 2 }),
  ]);
  assert.equal(decision.mode, 'legacy-rank-only');
  assert.deepEqual(ids(decision.kept), ['legacy-a', 'legacy-b']);
  assert.deepEqual(decision.rejected, []);
});

test('gate rejections expose only hashed refs and safe reasons, never title/text/question', () => {
  const hs = makeChunk('private-hs', 'Hoa Sen private-title', 'Mở cửa private-text');
  const weak = makeChunk('private-weak', 'private-title weak', 'private-text weak');
  const question = 'Hoa Sen private-question mở cửa?';
  const decision = selectRelevantCandidates(question, [
    makeCandidate(hs, { score: 1, vectorRank: 1, bm25Rank: 1, vectorDistance: 0.2, bm25Score: 5 }),
    makeCandidate(weak, { score: 0.2, vectorRank: 2, bm25Rank: 2, vectorDistance: 0.3, bm25Score: 0.1 }),
  ]);

  assert.ok(decision.rejected.length > 0);
  for (const entry of decision.rejected) {
    assert.deepEqual(Object.keys(entry).sort(), ['chunkRef', 'reason']);
    assert.match(entry.chunkRef, /^[0-9a-f]{64}$/);
  }
  const serialized = JSON.stringify(decision.rejected);
  for (const secret of ['Hoa Sen private-title', 'private-text', 'private-question']) {
    assert.ok(!serialized.includes(secret), secret);
  }
  assert.ok(Object.isFrozen(decision.kept));
  assert.ok(Object.isFrozen(decision.rejected));
  assert.ok(Object.isFrozen(decision));
});


test('a closely named event variant cannot borrow the requested event date and fee words', () => {
  const schedule = makeChunk('water-schedule', 'Lịch workshop', 'Workshop vẽ màu nước ngày 25/10/2026 diễn ra lúc 09:00 tại phòng A2.');
  const fee = makeChunk('water-fee', 'Lệ phí workshop', 'Workshop vẽ màu nước ngày 25/10/2026 có lệ phí 150.000 đồng.');
  const oil = makeChunk('oil-fee', 'Lệ phí workshop', 'Workshop vẽ màu dầu ngày 25/10/2026 có lệ phí 250.000 đồng.');
  const decision = selectRelevantCandidates('Workshop vẽ màu nước ngày 25/10/2026 diễn ra khi nào, ở đâu và lệ phí bao nhiêu?', [
    makeCandidate(fee, { vectorRank: 1, bm25Rank: 1, vectorDistance: 0.1, bm25Score: 6 }),
    makeCandidate(schedule, { vectorRank: 2, bm25Rank: 2, vectorDistance: 0.2, bm25Score: 4 }),
    makeCandidate(oil, { vectorRank: 3, bm25Rank: 3, vectorDistance: 0.3, bm25Score: 3 }),
  ]);
  assert.deepEqual(new Set(ids(decision.kept)), new Set(['water-fee', 'water-schedule']));
});

test('alphanumeric identifiers are target names, not answer numbers to ignore', () => {
  const asked = makeChunk('asked-model', 'Grand Seiko SLGH031', 'Grand Seiko SLGH031 dự trữ năng lượng 80 giờ.');
  const other = makeChunk('other-model', 'Grand Seiko SLGH005', 'Grand Seiko SLGH005 dự trữ năng lượng 55 giờ.');
  const decision = selectRelevantCandidates('Grand Seiko SLGH031 dự trữ năng lượng bao lâu?', [
    makeCandidate(asked, { vectorRank: 1, bm25Rank: 1, vectorDistance: 0.1, bm25Score: 4 }),
    makeCandidate(other, { vectorRank: 2, bm25Rank: 2, vectorDistance: 0.2, bm25Score: 3 }),
  ]);
  assert.deepEqual(ids(decision.kept), ['asked-model']);
});


test('a date condition on one requested event does not erase a different requested topic', () => {
  const event = makeChunk('dated-event', 'Lệ phí workshop', 'Workshop vẽ màu nước ngày 25/10/2026 có lệ phí 150.000 đồng.');
  const report = makeChunk('dated-deadline', 'Hạn chót báo cáo', 'Hạn chót báo cáo là 30/09/2026 lúc 17:00.');
  const question = 'Workshop vẽ màu nước ngày 25/10/2026 có lệ phí bao nhiêu và hạn chót báo cáo là khi nào?';
  const decision = selectRelevantCandidates(question, [
    makeCandidate(event, { vectorRank: 1, bm25Rank: 1, vectorDistance: 0.1, bm25Score: 6 }),
    makeCandidate(report, { vectorRank: 2, bm25Rank: 2, vectorDistance: 0.3, bm25Score: 2 }),
  ]);
  assert.deepEqual(new Set(ids(decision.kept)), new Set(['dated-event', 'dated-deadline']));
});
