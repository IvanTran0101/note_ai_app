/**
 * Keyword slice tests — contract C05 (independent BM25 Top-20, keyword-only match, tenant
 * isolation by caller-supplied eligible corpus) and the documented analyzer v1 identity.
 * Runner: node_modules/.bin/tsx --test amplify/rag/keyword.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import notesFixture from '../../test/fixtures/rag/notes.json';
import { chunkNote } from './chunking';
import {
  ANALYZER_VERSION, BM25_B, BM25_DOCUMENT, BM25_K1, BM25_TOP_K, QUERY_POLICY_VERSION,
  analyze, bm25, queryTerms,
} from './keyword';
import { POLICY_IDENTITY_FIELDS } from './indexing/snapshot';
import { RagFailure, type CanonicalNote, type Chunk, type Counter, type ErrorCode } from './types';

const words: Counter = (text) => text.split(/\s+/).filter((part) => part.length > 0).length;

const noteFromFixture = (key: string): CanonicalNote => {
  const raw = notesFixture.notes.find((entry) => entry.key === key);
  assert.ok(raw, `fixture note ${key} must exist`);
  return {
    ownerId: raw.ownerId,
    noteId: raw.noteId,
    revision: raw.revision,
    title: raw.title,
    content: raw.content,
    synced: raw.synced,
    protected: raw.protected,
    deleted: raw.deleted,
    available: raw.available,
  };
};

const chunkOf = (key: string): Chunk => {
  const chunks = chunkNote(noteFromFixture(key), words);
  assert.equal(chunks.length, 1, `fixture note ${key} must produce one chunk`);
  return chunks[0];
};

/** Hand-built chunk: text must be the exact slice of its own content for assertChunk. */
const manualChunk = (content: string, chunkId: string, noteId = 'n-manual', ordinal = 0): Chunk => ({
  ownerId: 'actor-a',
  noteId,
  revision: 1,
  sectionId: 'body',
  chunkId,
  ordinal,
  title: 'Manual',
  startOffset: 0,
  endOffset: content.length,
  text: content,
});

const failsWith = (code: ErrorCode) => (error: unknown): boolean =>
  error instanceof RagFailure && error.code === code;

test('analyzer v1 is NFKC + Unicode lowercase + letter/number runs', () => {
  assert.equal(ANALYZER_VERSION, 'rag-analyzer.v1');
  assert.deepEqual(analyze('SLGH031 chạy bao lâu khi lên cót đầy?'), [
    'slgh031',
    'chạy',
    'bao',
    'lâu',
    'khi',
    'lên',
    'cót',
    'đầy',
  ]);
  assert.deepEqual(analyze('80-hour power reserve'), ['80', 'hour', 'power', 'reserve']);
  assert.deepEqual(analyze('８０ giờ'), ['80', 'giờ'], 'NFKC folds full-width digits');
  assert.deepEqual(analyze('CAFÉ ﬁle'), ['café', 'file'], 'NFKC folds the fi ligature');
  assert.deepEqual(analyze('!!! ... ---'), []);
  assert.deepEqual(analyze(''), []);
  assert.deepEqual(analyze('aa aa'), ['aa', 'aa'], 'duplicates are kept for term frequency');
});

test('queryTerms removes only explicit VI/EN fillers from query scoring', () => {
  assert.equal(QUERY_POLICY_VERSION, 'rag-query-policy.v1');
  assert.deepEqual(
    queryTerms('SLGH031 chạy bao lâu khi lên cót đầy?'),
    ['slgh031', 'chạy', 'bao', 'lâu', 'lên', 'cót', 'đầy'],
    'khi is a filler; the model name, question word and content terms remain',
  );
  assert.deepEqual(
    queryTerms('Khi nào diễn ra cuộc họp và ai đến?'),
    ['họp', 'đến'],
    'Vietnamese question/function fillers are removed, content words are not',
  );
  assert.deepEqual(
    queryTerms('When does the Nimbus N1 have an 80-hour power reserve?'),
    ['nimbus', 'n1', 'have', '80', 'hour', 'power', 'reserve'],
    'English question fillers and articles are removed; the model/number stay',
  );
  assert.deepEqual(queryTerms('khi ra nào diễn cuộc và'), []);
  assert.deepEqual(queryTerms('the a an of to and is did'), []);
  assert.deepEqual(queryTerms(''), [], 'an empty meaningful query has no terms');
  assert.deepEqual(queryTerms('!!! ...'), []);
});

test('queryTerms never removes negations, numbers or distinctive content tokens', () => {
  assert.deepEqual(
    queryTerms('không xử lý file đính kèm'),
    ['không', 'xử', 'lý', 'file', 'đính', 'kèm'],
  );
  assert.deepEqual(queryTerms('chưa có bảo hành'), ['chưa', 'có', 'bảo', 'hành']);
  assert.deepEqual(queryTerms('not without the 14-day limit'), ['not', 'without', '14', 'day', 'limit']);
  assert.deepEqual(queryTerms('no never'), ['no', 'never']);
  assert.deepEqual(queryTerms('Hoa Sen 2026-07-01'), ['hoa', 'sen', '2026', '07', '01']);
  assert.deepEqual(queryTerms('SLGH031 Caliber 9SA5'), ['slgh031', 'caliber', '9sa5']);

  const raw = '  Khi nào Hoa Sen ra mắt?  ';
  assert.deepEqual(queryTerms(raw), ['hoa', 'sen', 'mắt']);
  assert.equal(raw, '  Khi nào Hoa Sen ra mắt?  ', 'the raw question is never edited');
  assert.throws(() => queryTerms(null as unknown as string), failsWith('INVALID_INPUT'));
});

test('query policy version is not part of the index policy identity', () => {
  assert.equal(QUERY_POLICY_VERSION, 'rag-query-policy.v1');
  assert.deepEqual(POLICY_IDENTITY_FIELDS.lexical, {
    analyzer: ANALYZER_VERSION,
    k1: BM25_K1,
    b: BM25_B,
  });
  assert.ok(
    !JSON.stringify(POLICY_IDENTITY_FIELDS).includes(QUERY_POLICY_VERSION),
    'query-only term selection must not force a re-embed or invalidate an index generation',
  );
});

test('BM25 finds a keyword-only chunk (no vector branch involved)', () => {
  const corpus = [chunkOf('a-watch'), chunkOf('a-meeting'), chunkOf('a-condition'), chunkOf('a-negation')];
  const ranked = bm25('SLGH031 chạy bao lâu khi lên cót đầy?', corpus);
  assert.ok(ranked.length > 0);
  assert.equal(ranked[0].rank, 1);
  assert.equal(ranked[0].chunk.noteId, 'n-watch');
  assert.ok(ranked.every((entry) => entry.rank >= 1 && Number.isSafeInteger(entry.rank)));
  assert.deepEqual(
    ranked.map((entry) => entry.rank),
    ranked.map((_entry, index) => index + 1),
    'ranks are dense and start at 1',
  );
});

test('BM25 attaches a positive finite bm25Score to every returned entry', () => {
  const corpus = ['a-watch', 'a-meeting', 'a-condition', 'a-negation'].map((key) => chunkOf(key));
  const ranked = bm25('SLGH031 chạy bao lâu khi lên cót đầy?', corpus);
  assert.ok(ranked.length > 0);
  for (const entry of ranked) {
    assert.equal(typeof entry.bm25Score, 'number');
    assert.ok(Number.isFinite(entry.bm25Score));
    assert.ok((entry.bm25Score ?? 0) > 0);
  }
  const scores = ranked.map((entry) => entry.bm25Score ?? 0);
  assert.deepEqual([...scores].sort((left, right) => right - left), scores, 'score order matches rank order');
  // A question made only of fillers never falls back to common-word boosts.
  assert.deepEqual(bm25('khi ra nào diễn cuộc và', corpus), []);
  assert.deepEqual(bm25('the a an of to and is did', corpus), []);
});

test('query-only khi/ra fillers do not boost unrelated notes while distinctive names remain', () => {
  const watch = {
    ...manualChunk('Đồng hồ chạy khi lên cót đầy.', 'body-0', 'n-watch'),
    title: 'Đồng hồ',
  };
  const meeting = {
    ...manualChunk('Buổi họp diễn ra tại phòng B203.', 'body-1', 'n-meeting'),
    title: 'Buổi họp',
  };
  const hoaSen = {
    ...manualChunk('Hoa Sen là biểu tượng của Việt Nam.', 'body-2', 'n-hoa-sen'),
    title: 'Hoa Sen',
  };
  const corpus = [watch, meeting, hoaSen];

  // "khi", "nào", "diễn" and "ra" are fillers, so the unrelated watch/meeting chunks cannot
  // enter the keyword branch through those shared words.
  assert.deepEqual(
    bm25('Hoa Sen khi nào diễn ra?', corpus).map((entry) => entry.chunk.noteId),
    ['n-hoa-sen'],
  );
  assert.deepEqual(
    bm25('Hoa Sen', corpus).map((entry) => entry.chunk.noteId),
    ['n-hoa-sen'],
    'the distinctive name tokens remain scorable',
  );
  assert.deepEqual(bm25('khi ra', corpus), [], 'filler-only query yields an empty keyword branch');
});

test('BM25 returns positive matches only and ranks them by score', () => {
  const corpus = [
    manualChunk('alpha alpha alpha', 'body-0', 'n-a'),
    manualChunk('alpha alpha', 'body-1', 'n-b'),
    manualChunk('alpha', 'body-2', 'n-c'),
    manualChunk('beta gamma delta', 'body-3', 'n-d'),
  ];
  const ranked = bm25('alpha', corpus);
  assert.equal(ranked.length, 3, 'the chunk without the term is not returned');
  assert.deepEqual(
    ranked.map((entry) => entry.chunk.noteId),
    ['n-a', 'n-b', 'n-c'],
  );
});

test('BM25 applies IDF: a rare term outranks a common one', () => {
  const common = Array.from({ length: 10 }, (_value, index) => manualChunk(`beta ${index}`, `body-${index}`, `n-c${index}`));
  const rare = manualChunk('alpha', 'body-r', 'n-rare');
  const ranked = bm25('alpha beta', [rare, ...common]);
  assert.equal(ranked[0].chunk.noteId, 'n-rare');
});

test('BM25 normalizes by document length', () => {
  const short = manualChunk('alpha', 'body-0', 'n-short');
  const long = manualChunk(`alpha ${'filler '.repeat(40)}`, 'body-1', 'n-long');
  const ranked = bm25('alpha', [short, long]);
  assert.equal(ranked[0].chunk.noteId, 'n-short');
});

test('BM25 caps at the configured Top-20 with stable source-key ties', () => {
  const many = Array.from({ length: 25 }, (_value, index) =>
    manualChunk('alpha', `body-${String(index).padStart(2, '0')}`, 'n-many'),
  );
  const ranked = bm25('alpha', many);
  assert.equal(BM25_TOP_K, 20);
  assert.equal(ranked.length, 20);
  assert.deepEqual(
    ranked.map((entry) => entry.chunk.chunkId),
    many
      .slice(0, 20)
      .map((chunk) => chunk.chunkId)
      .sort(),
  );

  const tied = [manualChunk('alpha', 'body-1', 'n-tie'), manualChunk('alpha', 'body-0', 'n-tie')];
  const tiedRanked = bm25('alpha', tied);
  assert.equal(tiedRanked[0].chunk.chunkId, 'body-0', 'ties break by ascending source key');
});

test('the caller-supplied eligible corpus is exactly what is searched', () => {
  const eligible = [chunkOf('a-watch'), chunkOf('a-meeting')];
  const ranked = bm25('SLGH031', eligible);
  assert.equal(ranked.length, 1);
  assert.equal(ranked[0].chunk.ownerId, 'actor-a');
  assert.ok(
    ranked.every((entry) => entry.chunk.ownerId === 'actor-a'),
    'a foreign note is only reachable if the caller puts it in the corpus',
  );
  assert.deepEqual(bm25('SLGH031', []), []);
  assert.deepEqual(bm25(' ', eligible), [], 'a question without tokens matches nothing');
});

test('BM25 never dedupes by content hash: distinct sources with equal text both rank', () => {
  const sameText = 'alpha beta gamma';
  const ranked = bm25('alpha', [
    manualChunk(sameText, 'body-0', 'n-left'),
    manualChunk(sameText, 'body-0', 'n-right'),
  ]);
  assert.equal(ranked.length, 2, 'identity, not text, decides whether two documents are the same');
  assert.deepEqual(
    ranked.map((entry) => entry.chunk.noteId),
    ['n-left', 'n-right'],
  );
});

test('BM25 uses the fixed fixture parameters', () => {
  const corpus = [chunkOf('a-watch')];
  assert.equal(BM25_K1, 1.2);
  assert.equal(BM25_B, 0.75);
  assert.equal(bm25('SLGH031', corpus).length, 1);
});

test('BM25 analyzes raw title-newline-content, never the embedding frame', () => {
  assert.equal(BM25_DOCUMENT, 'title-newline-content-span');
  const chunk = manualChunk('alpha beta', 'body-0', 'n-frame');
  // These words occur only in the `title: ... | text: ...` embedding frame, not in the
  // title/content themselves, so lexical retrieval must not see them.
  assert.deepEqual(bm25('title', [chunk]), []);
  assert.deepEqual(bm25('text', [chunk]), []);
  assert.equal(bm25('manual', [chunk]).length, 1, 'the title remains lexical input');
  assert.equal(bm25('alpha', [chunk]).length, 1, 'the content span remains lexical input');
});

test('BM25 fails closed on a malformed corpus', () => {
  const valid = chunkOf('a-watch');
  assert.throws(() => bm25('SLGH031', [valid, valid]), failsWith('INVALID_INPUT'), 'duplicate identity');
  const broken = { ...valid, endOffset: valid.endOffset + 1 }; // span no longer matches the slice
  assert.throws(() => bm25('SLGH031', [broken]), failsWith('INVALID_INPUT'));
  assert.throws(
    () => bm25('SLGH031', [null as unknown as Chunk]),
    failsWith('INVALID_INPUT'),
  );
});
