import { mmr } from '../amplify/rag/retrieval';
import { sourceKey, type Candidate, type Chunk } from '../amplify/rag/types';

const mk = (id: string): Chunk => ({ ownerId: 'a', noteId: id, revision: 1, sectionId: 'body', chunkId: 'c', ordinal: 0, title: id, startOffset: 0, endOffset: 4, text: 'text' });
const A = mk('A'); const B = mk('B');
const candidates: Candidate[] = [
  { chunk: A, score: 0.032, vectorRank: 1, vectorDistance: 0.2 },
  { chunk: B, score: 0.031, vectorRank: 2, vectorDistance: 0.8 },
];
const vec = (x: number, y: number) => Array.from({length:768}, (_, i) => i===0?x:i===1?y:0);
const vectors = new Map([[sourceKey(A), vec(0.8, 0.6)], [sourceKey(B), vec(0.2, Math.sqrt(0.96))]]);
console.log(mmr(candidates, vectors).map(c => c.noteId));
