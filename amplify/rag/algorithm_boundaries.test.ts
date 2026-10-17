import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chunkNote } from './chunking';
import { buildEvidence } from './context';
import { EMBEDDING_DIMENSIONS, mmr, rrf } from './retrieval';
import { sourceKey, type Chunk, type CanonicalNote } from './types';

const note: CanonicalNote = { ownerId: 'actor-a', noteId: 'n', revision: 1,
  title: 'Title', content: 'alpha', synced: true, protected: false, deleted: false, available: true };
const chunk = (id: string): Chunk => ({ ownerId: 'actor-a', noteId: 'n', revision: 1,
  sectionId: 'body', chunkId: id, ordinal: 0, title: 'Title', text: 'alpha', startOffset: 0, endOffset: 5 });

test('chunking rejects invalid Unicode instead of silently replacing a surrogate on egress', () => {
  assert.throws(() => chunkNote({ ...note, content: 'bad\uD800' }, s => s.length));
});
test('canonical span validation cannot bisect a valid emoji', () => {
  const emoji = { ...note, content: '🧠' };
  const half = { ...chunk('c'), text: emoji.content.slice(0, 1), endOffset: 1 };
  assert.throws(() => buildEvidence([half], [], [emoji], s => s.length));
});
test('MMR cosine remains correct for tiny but nonzero valid vectors', () => {
  const a = chunk('a'), b = chunk('b'), c = chunk('c');
  const axis = (index: number) => Array.from({ length: EMBEDDING_DIMENSIONS }, (_, i) => i === index ? 1e-300 : 0);
  const vectors = new Map([[sourceKey(a), axis(0)], [sourceKey(b), axis(0)], [sourceKey(c), axis(1)]]);
  const anchors = mmr([{ chunk: a, score: 1 }, { chunk: b, score: .9 }, { chunk: c, score: .8 }], vectors);
  assert.deepEqual(anchors.slice(0, 2).map(c => c.chunkId), ['a', 'c']);
});
test('RRF rejects a rank outside the configured Top-20 branch', () => {
  assert.throws(() => rrf([{ chunk: chunk('a'), rank: 21 }], []));
});
test('an expansion duplicate cannot contradict an existing anchor identity', () => {
  const a = chunk('a');
  assert.throws(() => buildEvidence([a], [{ ...a, text: 'other' }], [note], s => s.length));
});
