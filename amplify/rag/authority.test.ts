import { test } from 'node:test';
import assert from 'node:assert/strict';
import { assertChunkAuthority, beginContext } from './authority';
import { CONSENT_VERSION } from './contract';
import { RagFailure } from './types';
import type { AuthorityStore, CanonicalNote, CanonicalState, Chunk, RagRequest, Scope } from './types';

const note = (over: Partial<CanonicalNote> = {}): CanonicalNote => ({
  ownerId: 'actor-a',
  noteId: 'n-watch',
  revision: 1,
  title: 'SLGH031',
  content: 'alpha beta gamma',
  synced: true,
  protected: false,
  deleted: false,
  available: true,
  ...over,
});

const state = (over: Partial<CanonicalState> = {}): CanonicalState => ({
  actorId: 'actor-a',
  sessionGeneration: 1,
  consent: { accepted: true, version: CONSENT_VERSION, generation: 1 },
  indexReady: true,
  manifestVersion: 'm-1',
  notes: [note()],
  ...over,
});

const request = (scope: Scope): RagRequest => ({ wireVersion: 1, question: 'q?', scope });
const account = request({ type: 'account' });
const signalOf = (): AbortSignal => new AbortController().signal;

const storeOf = (initial: CanonicalState) => {
  let current = initial;
  const store: AuthorityStore = { read: async () => current };
  return {
    store,
    set: (next: CanonicalState): void => {
      current = next;
    },
  };
};

const codeOf = async (run: () => unknown): Promise<string> => {
  try {
    await run();
  } catch (error) {
    if (error instanceof RagFailure) return error.code;
    throw error;
  }
  throw new Error('expected a RagFailure');
};

const chunkFor = (host: CanonicalNote, over: Partial<Chunk> = {}): Chunk => {
  const endOffset = Math.min(5, host.content.length);
  return {
    ownerId: host.ownerId,
    noteId: host.noteId,
    revision: host.revision,
    sectionId: 'body',
    chunkId: 'c1',
    ordinal: 0,
    title: host.title,
    startOffset: 0,
    endOffset,
    text: host.content.slice(0, endOffset),
    ...over,
  };
};

test('beginContext keeps only own synced available unprotected text notes with revision >= 1', async () => {
  const eligible = note({ noteId: 'n-own' });
  const notes = [
    eligible,
    note({ noteId: 'n-watch', ownerId: 'actor-b', title: 'actor-b title', content: 'actor-b secret' }),
    note({ noteId: 'n-protected', protected: true }),
    note({ noteId: 'n-deleted', deleted: true }),
    note({ noteId: 'n-local', synced: false }),
    note({ noteId: 'n-unavailable', available: false }),
    note({ noteId: 'n-shared', incomingShared: true }),
    note({ noteId: 'n-old', revision: 0 }),
  ];
  const context = await beginContext('actor-a', account, storeOf(state({ notes })).store, signalOf());
  assert.deepEqual(context.notes.map((entry) => entry.noteId), ['n-own']);
  assert.deepEqual(context.state.notes, context.notes);
  assert.equal(context.actor, 'actor-a');
  assert.deepEqual(context.request, account);
});

test('a mutable direct caller cannot change the authorized scope or the provider snapshot', async () => {
  const mutable = {
    wireVersion: 1 as const,
    question: 'q?',
    scope: { type: 'note' as const, noteId: 'n-watch' },
  };
  const context = await beginContext(
    'actor-a',
    mutable,
    storeOf(state({ notes: [note(), note({ noteId: 'n-other' })] })).store,
    signalOf(),
  );
  mutable.scope.noteId = 'n-other';
  assert.equal(context.request.scope.type === 'note' && context.request.scope.noteId, 'n-watch');
  assert.deepEqual(context.notes.map((entry) => entry.noteId), ['n-watch']);
  assert.ok(Object.isFrozen(context.request));
  assert.ok(Object.isFrozen(context.request.scope));
});

test('actor-a and actor-b never see each other through a shared noteId', async () => {
  const aNote = note({ content: 'actor-a content' });
  const bNote = note({ ownerId: 'actor-b', title: 'actor-b title', content: 'actor-b content' });
  const both = state({ notes: [aNote, bNote] });

  const forA = await beginContext('actor-a', account, storeOf(both).store, signalOf());
  assert.deepEqual(forA.notes.map((entry) => entry.content), ['actor-a content']);
  const forB = await beginContext('actor-b', account, storeOf(state({ actorId: 'actor-b', notes: [aNote, bNote] })).store, signalOf());
  assert.deepEqual(forB.notes.map((entry) => entry.content), ['actor-b content']);

  const scopedA = await beginContext(
    'actor-a',
    request({ type: 'note', noteId: 'n-watch' }),
    storeOf(both).store,
    signalOf(),
  );
  assert.equal(scopedA.notes.length, 1);
  assert.equal(scopedA.notes[0]?.ownerId, 'actor-a');
  assert.equal(scopedA.notes[0]?.title, 'SLGH031');
});

test('note scope is denied when no eligible own note matches', async () => {
  const denied: readonly CanonicalNote[][] = [
    [note({ noteId: 'n-other' })],
    [note({ ownerId: 'actor-b' })],
    [note({ protected: true })],
    [note({ deleted: true })],
    [note({ synced: false })],
    [note({ revision: 0 })],
    [],
  ];
  for (const notes of denied) {
    assert.equal(
      await codeOf(() =>
        beginContext('actor-a', request({ type: 'note', noteId: 'n-watch' }), storeOf(state({ notes })).store, signalOf()),
      ),
      'SCOPE_DENIED',
    );
  }
});

test('the snapshot and notes are cloned and frozen so no provider can mutate canonical state', async () => {
  const original = note();
  const context = await beginContext('actor-a', account, storeOf(state({ notes: [original] })).store, signalOf());
  (original as { title: string }).title = 'mutated after begin';
  (original as { content: string }).content = 'mutated after begin';

  assert.equal(context.notes[0]?.title, 'SLGH031');
  assert.equal(context.notes[0]?.content, 'alpha beta gamma');
  assert.ok(Object.isFrozen(context));
  assert.ok(Object.isFrozen(context.state));
  assert.ok(Object.isFrozen(context.notes));
  assert.ok(Object.isFrozen(context.notes[0]));
  try {
    (context.state.notes[0] as { title: string }).title = 'provider write';
    (context.notes[0] as { content: string }).content = 'provider write';
  } catch {
    // strict mode refuses the write outright; sloppy mode silently ignores it
  }
  assert.equal(context.state.notes[0]?.title, 'SLGH031');
  assert.equal(context.notes[0]?.content, 'alpha beta gamma');
});

test('beginContext refuses invalid consent, session, index and actor before trusting a note', async () => {
  const cases: readonly [string, CanonicalState, string][] = [
    ['consent off', state({ consent: { accepted: false, version: CONSENT_VERSION, generation: 1 } }), 'CONSENT_REQUIRED'],
    ['consent version', state({ consent: { accepted: true, version: 'summary-consent.v1', generation: 1 } }), 'CONSENT_REQUIRED'],
    ['consent generation fraction', state({ consent: { accepted: true, version: CONSENT_VERSION, generation: 1.5 } }), 'CONSENT_REQUIRED'],
    ['consent generation negative', state({ consent: { accepted: true, version: CONSENT_VERSION, generation: -1 } }), 'CONSENT_REQUIRED'],
    ['consent missing', state({ consent: undefined as unknown as CanonicalState['consent'] }), 'CONSENT_REQUIRED'],
    ['session negative', state({ sessionGeneration: -1 }), 'SOURCE_CHANGED'],
    ['session fraction', state({ sessionGeneration: 1.5 }), 'SOURCE_CHANGED'],
    ['index not ready', state({ indexReady: false }), 'INDEX_NOT_READY'],
    ['manifest blank', state({ manifestVersion: '   ' }), 'INDEX_NOT_READY'],
    ['manifest missing', state({ manifestVersion: undefined as unknown as string }), 'INDEX_NOT_READY'],
    ['state for another actor', state({ actorId: 'actor-b' }), 'UNAUTHORIZED'],
    [
      'foreign state with consent off',
      state({ actorId: 'actor-b', consent: { accepted: false, version: CONSENT_VERSION, generation: 1 } }),
      'UNAUTHORIZED',
    ],
  ];
  for (const [name, value, code] of cases) {
    assert.equal(await codeOf(() => beginContext('actor-a', account, storeOf(value).store, signalOf())), code, name);
  }
  for (const actor of ['', ' actor-a', 'actor-a ', 'a'.repeat(129), 'bad\u0000actor']) {
    assert.equal(await codeOf(() => beginContext(actor, account, storeOf(state()).store, signalOf())), 'UNAUTHORIZED', actor);
  }
});

test('beginContext surfaces store failure as PROVIDER_UNAVAILABLE and abort as TIMEOUT', async () => {
  const failing: AuthorityStore = {
    read: async () => {
      throw new Error('canonical store down');
    },
  };
  assert.equal(await codeOf(() => beginContext('actor-a', account, failing, signalOf())), 'PROVIDER_UNAVAILABLE');
  const timingOut: AuthorityStore = {
    read: async () => {
      throw new RagFailure('TIMEOUT');
    },
  };
  assert.equal(await codeOf(() => beginContext('actor-a', account, timingOut, signalOf())), 'TIMEOUT');
  const empty: AuthorityStore = { read: async () => null as unknown as CanonicalState };
  assert.equal(await codeOf(() => beginContext('actor-a', account, empty, signalOf())), 'PROVIDER_UNAVAILABLE');
  assert.equal(
    await codeOf(() => beginContext('actor-a', account, storeOf(state()).store, AbortSignal.abort())),
    'TIMEOUT',
  );

  const controller = new AbortController();
  const slow: AuthorityStore = {
    read: async () => {
      controller.abort();
      return state();
    },
  };
  assert.equal(await codeOf(() => beginContext('actor-a', account, slow, controller.signal)), 'TIMEOUT');
});

test('revalidate blocks egress when consent, session, index or actor changed', async () => {
  const mutable = storeOf(state());
  const context = await beginContext('actor-a', account, mutable.store, signalOf());
  await context.revalidate();

  mutable.set(state({ consent: { accepted: false, version: CONSENT_VERSION, generation: 1 } }));
  assert.equal(await codeOf(() => context.revalidate()), 'CONSENT_REQUIRED');
  mutable.set(state({ consent: { accepted: true, version: CONSENT_VERSION, generation: 2 } }));
  assert.equal(await codeOf(() => context.revalidate()), 'CONSENT_REQUIRED');
  mutable.set(state({ sessionGeneration: 2 }));
  assert.equal(await codeOf(() => context.revalidate()), 'SOURCE_CHANGED');
  mutable.set(state({ indexReady: false }));
  assert.equal(await codeOf(() => context.revalidate()), 'INDEX_NOT_READY');
  mutable.set(state({ manifestVersion: 'm-2' }));
  assert.equal(await codeOf(() => context.revalidate()), 'INDEX_NOT_READY');
  mutable.set(state({ actorId: 'actor-b' }));
  assert.equal(await codeOf(() => context.revalidate()), 'UNAUTHORIZED');
  mutable.set(state({ actorId: 'actor-b', consent: { accepted: false, version: CONSENT_VERSION, generation: 1 } }));
  assert.equal(await codeOf(() => context.revalidate()), 'UNAUTHORIZED');
});

test('revalidate blocks egress when a snapshotted source note changes mid-run', async () => {
  const mutable = storeOf(state({ notes: [note()] }));
  const context = await beginContext('actor-a', account, mutable.store, signalOf());
  const changes: readonly [string, readonly CanonicalNote[]][] = [
    ['revision', [note({ revision: 2 })]],
    ['title', [note({ title: 'Changed title' })]],
    ['content', [note({ content: 'changed content' })]],
    ['deleted', [note({ deleted: true })]],
    ['protected', [note({ protected: true })]],
    ['unsynced', [note({ synced: false })]],
    ['unavailable', [note({ available: false })]],
    ['incoming shared', [note({ incomingShared: true })]],
    ['removed', []],
    ['foreign replacement', [note({ ownerId: 'actor-b' })]],
  ];
  for (const [name, notes] of changes) {
    mutable.set(state({ notes: [...notes] }));
    assert.equal(await codeOf(() => context.revalidate()), 'SOURCE_CHANGED', name);
  }
});

test('revalidate refuses an aborted signal and a store that fails after begin', async () => {
  const controller = new AbortController();
  const context = await beginContext('actor-a', account, storeOf(state()).store, controller.signal);
  controller.abort();
  assert.equal(await codeOf(() => context.revalidate()), 'TIMEOUT');

  let calls = 0;
  const flaky: AuthorityStore = {
    read: async () => {
      calls += 1;
      if (calls > 1) throw new Error('canonical store down');
      return state();
    },
  };
  const later = await beginContext('actor-a', account, flaky, signalOf());
  assert.equal(await codeOf(() => later.revalidate()), 'PROVIDER_UNAVAILABLE');
});

test('assertChunkAuthority accepts only an exact, current, surrogate-safe own-note span', async () => {
  const own = note();
  const context = await beginContext('actor-a', account, storeOf(state({ notes: [own] })).store, signalOf());
  assert.doesNotThrow(() => assertChunkAuthority(chunkFor(own), context));

  const rejected: readonly [string, Chunk, string][] = [
    ['foreign owner', chunkFor(own, { ownerId: 'actor-b' }), 'SCOPE_DENIED'],
    ['unknown note', chunkFor(own, { noteId: 'n-other' }), 'SCOPE_DENIED'],
    ['stale revision', chunkFor(own, { revision: 2 }), 'SOURCE_CHANGED'],
    ['stale title', chunkFor(own, { title: 'Changed title' }), 'SOURCE_CHANGED'],
    ['wrong section', chunkFor(own, { sectionId: 'section-1' }), 'SOURCE_CHANGED'],
    ['changed text', chunkFor(own, { text: 'XXXXX' }), 'SOURCE_CHANGED'],
    ['empty span', chunkFor(own, { startOffset: 0, endOffset: 0, text: '' }), 'INVALID_INPUT'],
    ['span past content', chunkFor(own, { endOffset: own.content.length + 1, text: `${own.content}x` }), 'SOURCE_CHANGED'],
    ['invalid ordinal', chunkFor(own, { ordinal: -1 }), 'INVALID_INPUT'],
    ['invalid chunk id', chunkFor(own, { chunkId: '   ' }), 'INVALID_INPUT'],
    ['invalid offsets', chunkFor(own, { startOffset: -1, endOffset: 3, text: 'alp' }), 'INVALID_INPUT'],
  ];
  for (const [name, chunk, code] of rejected) {
    assert.equal(await codeOf(() => assertChunkAuthority(chunk, context)), code, name);
  }
});

test('assertChunkAuthority refuses surrogate bisection and notes outside the request scope', async () => {
  const emoji = note({ noteId: 'n-emoji', title: 'Unicode', content: 'a🧠b' });
  const other = note({ noteId: 'n-other' });
  const context = await beginContext(
    'actor-a',
    account,
    storeOf(state({ notes: [emoji, other] })).store,
    signalOf(),
  );

  assert.doesNotThrow(() =>
    assertChunkAuthority(
      { ownerId: 'actor-a', noteId: 'n-emoji', revision: 1, sectionId: 'body', chunkId: 'c1', ordinal: 0,
        title: 'Unicode', startOffset: 1, endOffset: 3, text: '🧠' },
      context,
    ),
  );
  const bisectingStart: Chunk = {
    ownerId: 'actor-a', noteId: 'n-emoji', revision: 1, sectionId: 'body', chunkId: 'c2', ordinal: 0,
    title: 'Unicode', startOffset: 2, endOffset: 4, text: emoji.content.slice(2, 4),
  };
  // A span slice that bisects a pair cannot be well-formed, so it is structurally refused.
  assert.equal(await codeOf(() => assertChunkAuthority(bisectingStart, context)), 'INVALID_INPUT');
  const bisectingEnd: Chunk = { ...bisectingStart, startOffset: 0, endOffset: 2, text: emoji.content.slice(0, 2) };
  assert.equal(await codeOf(() => assertChunkAuthority(bisectingEnd, context)), 'INVALID_INPUT');
  // Well-formed substitute text still cannot counterfeit a bisecting span.
  const substituted: Chunk = { ...bisectingEnd, text: 'zz' };
  assert.equal(await codeOf(() => assertChunkAuthority(substituted, context)), 'SOURCE_CHANGED');

  const noteScoped = await beginContext(
    'actor-a',
    request({ type: 'note', noteId: 'n-emoji' }),
    storeOf(state({ notes: [emoji, other] })).store,
    signalOf(),
  );
  assert.deepEqual(noteScoped.notes.map((entry) => entry.noteId), ['n-emoji']);
  assert.equal(await codeOf(() => assertChunkAuthority(chunkFor(other), noteScoped)), 'SCOPE_DENIED');
  assert.doesNotThrow(() => assertChunkAuthority(chunkFor(emoji), noteScoped));
});

test('assertChunkAuthority reads the snapshot without mutating it', async () => {
  const own = note();
  const context = await beginContext('actor-a', account, storeOf(state({ notes: [own] })).store, signalOf());
  const before = JSON.stringify(context.state);
  assert.doesNotThrow(() => assertChunkAuthority(chunkFor(own), context));
  assert.equal(JSON.stringify(context.state), before);
  assert.equal(context.notes[0]?.content, 'alpha beta gamma');
});
