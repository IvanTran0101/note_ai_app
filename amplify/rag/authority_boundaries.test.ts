import { test } from 'node:test';
import assert from 'node:assert/strict';
import { beginContext } from './authority';
import { CONSENT_VERSION, parseRequest } from './contract';
import type { CanonicalNote, CanonicalState } from './types';

const note: CanonicalNote = { ownerId: 'actor-a', noteId: 'n', revision: 1,
  title: 'Title', content: 'alpha', synced: true, protected: false, deleted: false, available: true };
const state: CanonicalState = { actorId: 'actor-a', sessionGeneration: 1,
  consent: { accepted: true, version: CONSENT_VERSION, generation: 1 }, indexReady: true,
  manifestVersion: 'mock-1', notes: [note, { ...note, ownerId: 'actor-b' },
    { ...note, noteId: 'protected', protected: true }, { ...note, noteId: 'other-own' }] };

test('provider-facing request context contains only authorized scoped notes', async () => {
  const request = parseRequest(JSON.stringify({ wireVersion: 1, question: 'q', scope: { type: 'note', noteId: 'n' } }));
  const context = await beginContext('actor-a', request, { async read() { return state; } }, new AbortController().signal);
  assert.deepEqual(context.state.notes, context.notes);
  assert.equal(context.state.notes.length, 1);
  assert.equal(context.state.notes[0].ownerId, 'actor-a');
  assert.equal(Object.isFrozen(context.state.notes[0]), true);
});
test('a mutable direct caller cannot change request scope after authorization', async () => {
  const request = { wireVersion: 1 as const, question: 'q', scope: { type: 'note' as const, noteId: 'n' } };
  const context = await beginContext('actor-a', request, { async read() { return state; } }, new AbortController().signal);
  request.scope.noteId = 'other-own';
  assert.equal(context.request.scope.type === 'note' && context.request.scope.noteId, 'n');
});
test('the request is captured before the first awaited authority read', async () => {
  const request = { wireVersion: 1 as const, question: 'q', scope: { type: 'note' as const, noteId: 'n' } };
  const context = await beginContext('actor-a', request, { async read() {
    request.scope.noteId = 'other-own';
    return state;
  } }, new AbortController().signal);
  assert.equal(context.request.scope.type === 'note' && context.request.scope.noteId, 'n');
});
