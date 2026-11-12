/**
 * Indexing jobs slice tests — C21/C23 stream normalization and the canonical fingerprint.
 * Runner: node --import tsx --test amplify/rag/indexing/jobs.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CONSENT_VERSION } from '../contract';
import { JOB_POLICY_VERSION, IndexFailure } from './types';
import type { IndexNote, IndexState, Job } from './types';
import { classifyRecord, fingerprint, jobsFromStream, markersOf, parseJob, sameMarkers } from './jobs';

const av = (value: string) => ({ S: value });
const num = (value: number) => ({ N: String(value) });

const record = (options: Readonly<{
  eventName?: string;
  ownerId?: string;
  sortKey?: string;
  revision?: number | null;
  eventId?: string;
  newImage?: Record<string, unknown> | null;
  text?: boolean;
}> = {}): Record<string, unknown> => {
  const revision = options.revision === undefined
    ? num(1)
    : options.revision === null ? undefined : num(options.revision);
  const newImage = options.newImage === null
    ? undefined
    : options.newImage ?? {
      revision,
      ...(options.text === false ? {} : { title: av('secret title'), content: av('secret body') }),
    };
  return {
    eventID: options.eventId ?? 'evt-1',
    eventName: options.eventName ?? 'INSERT',
    dynamodb: {
      Keys: {
        ownerId: av(options.ownerId ?? 'OWNER#u1'),
        noteId: av(options.sortKey ?? 'NOTE#n1'),
      },
      NewImage: newImage,
      SequenceNumber: '100',
    },
  };
};

const note = (over: Partial<IndexNote> = {}): IndexNote => ({
  ownerId: 'u1', noteId: 'n1', revision: 1, title: 'T', content: 'body one',
  synced: true, protected: false, deleted: false, available: true, protectionRevision: 0, ...over,
});

const state = (over: Partial<IndexState> = {}): IndexState => ({
  ownerId: 'u1', accountEpoch: 1,
  consent: { accepted: true, version: CONSENT_VERSION, generation: 2 },
  notes: [note()], manifest: null, ...over,
});

const noteJob = (over: Partial<Job> = {}): Job => ({
  jobVersion: 1, kind: 'RECONCILE_NOTE', ownerId: 'u1', noteId: 'n1',
  sourceRevisionHint: 1, policyVersion: JOB_POLICY_VERSION, eventId: 'evt-1', ...over,
});

const rejectsJob = (value: unknown): void => {
  assert.throws(() => parseJob(value), (error: unknown) =>
    error instanceof IndexFailure && error.code === 'INVALID_JOB' && error.retryable === false);
};

test('parseJob accepts the exact note and account job shapes', () => {
  assert.deepEqual(parseJob(noteJob()), noteJob());
  const account = parseJob({
    jobVersion: 1, kind: 'RECONCILE_ACCOUNT', ownerId: 'u1', noteId: null,
    sourceRevisionHint: null, policyVersion: JOB_POLICY_VERSION, eventId: 'evt-2',
  });
  assert.deepEqual(account, {
    jobVersion: 1, kind: 'RECONCILE_ACCOUNT', ownerId: 'u1', noteId: null,
    sourceRevisionHint: null, policyVersion: JOB_POLICY_VERSION, eventId: 'evt-2',
  });
  assert.ok(Object.isFrozen(account));
});

test('parseJob fails closed on shape, identifier and safe-integer violations', () => {
  rejectsJob({ ...noteJob(), extra: 1 });
  rejectsJob({ jobVersion: 1, kind: 'RECONCILE_NOTE', ownerId: 'u1' });
  for (const jobVersion of [2, '1', 1.5, true, null]) rejectsJob({ ...noteJob(), jobVersion });
  rejectsJob({ ...noteJob(), kind: 'REBUILD' });
  for (const ownerId of ['', '   ', 'u\u0000', 'a'.repeat(129), 7, null]) {
    rejectsJob({ ...noteJob(), ownerId });
  }
  rejectsJob({ ...noteJob(), noteId: null });
  rejectsJob({ ...noteJob(), noteId: 'n\u0007' });
  rejectsJob({ ...noteJob({ kind: 'RECONCILE_ACCOUNT', noteId: null }), noteId: 'n1', sourceRevisionHint: null });
  for (const hint of [0, -1, 1.5, '1', true]) rejectsJob({ ...noteJob(), sourceRevisionHint: hint });
  rejectsJob({ ...noteJob({ kind: 'RECONCILE_ACCOUNT', noteId: null }), sourceRevisionHint: 3 });
  rejectsJob({ ...noteJob(), policyVersion: 'rag-index.v2' });
  rejectsJob({ ...noteJob(), eventId: '' });
  rejectsJob(null);
  rejectsJob('job');
});

test('jobsFromStream normalizes a note row without trusting NewImage text or flags', () => {
  const jobs = jobsFromStream({ Records: [record({ revision: 4 })] } as never);
  assert.deepEqual(jobs, [noteJob({ sourceRevisionHint: 4 })]);
  assert.equal(JSON.stringify(jobs).includes('secret'), false);
  assert.equal(Object.keys(jobs[0] as object).length, 7);
});

test('note and protection rows for one note coalesce; REMOVE drops the revision hint', () => {
  const jobs = jobsFromStream({
    Records: [
      record({ sortKey: 'NOTE#n1', eventName: 'MODIFY', revision: 2 }),
      record({ sortKey: 'PROTECTION#n1', eventName: 'MODIFY', revision: 2, eventId: 'evt-2' }),
      record({ sortKey: 'NOTE#n1', eventName: 'REMOVE', newImage: null, eventId: 'evt-3' }),
    ],
  } as never);
  assert.deepEqual(jobs, [noteJob({ sourceRevisionHint: 2 })]);
  assert.deepEqual(
    jobsFromStream({ Records: [record({ eventName: 'REMOVE', newImage: null })] } as never),
    [noteJob({ sourceRevisionHint: null })],
  );
});

test('consent rows become one account job and supersede that owner note jobs', () => {
  const jobs = jobsFromStream({
    Records: [
      record({ sortKey: 'NOTE#n1' }),
      record({ sortKey: 'RAG#CONSENT', eventId: 'evt-9', newImage: { ownerId: av('u2') } }),
      record({ sortKey: 'PROTECTION#n2', eventId: 'evt-8' }),
    ],
  } as never);
  assert.deepEqual(jobs, [{
    jobVersion: 1, kind: 'RECONCILE_ACCOUNT', ownerId: 'u1', noteId: null,
    sourceRevisionHint: null, policyVersion: JOB_POLICY_VERSION, eventId: 'evt-9',
  }]);
});

test('owner partition comes from the key only, never from a projected actor attribute', () => {
  const jobs = jobsFromStream({
    Records: [record({
      newImage: { revision: num(3), canonicalOwnerId: av('u2'), ownerId: av('u2'), actorId: av('u9') },
    })],
  } as never);
  assert.equal(jobs[0]?.ownerId, 'u1');
  const consent = jobsFromStream({
    Records: [record({ sortKey: 'RAG#CONSENT', newImage: { ownerId: av('u2'), actorId: av('u2') } })],
  } as never);
  assert.equal(consent[0]?.ownerId, 'u1');
});

test('worker, status, manifest, feed and relay rows are excluded', () => {
  const ignored = [
    'META#SYNC', 'MUTATION#m1', 'CHANGE#4', 'EVENT#e1', 'SHARED#n1',
    'RAG#MANIFEST#v1', 'RAG#LEASE#t1', 'RAG#STATUS', 'RAG#SNAPSHOT#v1', 'FOO#1',
  ];
  const jobs = jobsFromStream({ Records: ignored.map((sortKey) => record({ sortKey })) } as never);
  assert.deepEqual(jobs, []);
  assert.deepEqual(jobsFromStream({} as never), []);
  assert.deepEqual(jobsFromStream(undefined as never), []);
});

test('relevant but malformed rows are classified malformed, never normalized', () => {
  const bad = [
    record({ ownerId: 'u1' }),
    record({ ownerId: 'OWNER#' }),
    record({ ownerId: 'OWNER#u\u0001' }),
    record({ sortKey: 'NOTE#' }),
    record({ eventName: 'OOPS' }),
    record({ eventId: '' }),
    record({ newImage: { revision: av('1') } }),
    record({ newImage: { revision: num(0) } }),
    record({ newImage: { revision: { BOOL: true } } }),
  ];
  for (const entry of bad) {
    assert.deepEqual(classifyRecord(entry), { kind: 'MALFORMED' });
    assert.deepEqual(jobsFromStream({ Records: [entry] } as never), []);
  }
  assert.deepEqual(classifyRecord(record({ sortKey: 'META#SYNC' })), { kind: 'EXCLUDED' });
  // A missing revision is a non-authoritative hint, not a corrupt row: the worker reconciles
  // the latest canonical state either way.
  assert.deepEqual(
    jobsFromStream({ Records: [record({ newImage: {} })] } as never),
    [noteJob({ sourceRevisionHint: null })],
  );
});

test('fingerprint is a stable digest of identity, revision, protection, consent and policy', () => {
  const base = fingerprint(state());
  assert.match(base, /^[0-9a-f]{64}$/);
  assert.equal(fingerprint(state()), base);
  assert.equal(fingerprint(state({ notes: [note(), note({ noteId: 'n0' })] })),
    fingerprint(state({ notes: [note({ noteId: 'n0' }), note()] })), 'note order is canonical');
  assert.equal(base.includes('body one'), false);

  const variants: IndexState[] = [
    state({ notes: [note({ revision: 2 })] }),
    state({ notes: [note({ title: 'T2' })] }),
    state({ notes: [note({ content: 'body two' })] }),
    state({ notes: [note({ protected: true, protectionRevision: 1 })] }),
    state({ notes: [note({ synced: false })] }),
    state({ notes: [note({ deleted: true })] }),
    state({ notes: [note({ available: false })] }),
    state({ accountEpoch: 2 }),
    state({ consent: { accepted: false, version: CONSENT_VERSION, generation: 2 } }),
    state({ consent: { accepted: true, version: CONSENT_VERSION, generation: 3 } }),
    state({ notes: [note(), note({ noteId: 'n2' })] }),
  ];
  for (const variant of variants) assert.notEqual(fingerprint(variant), base);
});

test('fingerprint fails closed on foreign or incoherent canonical state', () => {
  const broken: unknown[] = [
    state({ notes: [note({ ownerId: 'u2' })] }),
    state({ notes: [note(), note()] }),
    state({ accountEpoch: -1 }),
    state({ consent: { accepted: true, version: CONSENT_VERSION, generation: -1 } }),
    state({ notes: [note({ revision: 0 })] }),
    state({ notes: [note({ protectionRevision: -1 })] }),
    { ...state(), ownerId: '  ' },
  ];
  for (const value of broken) {
    assert.throws(() => fingerprint(value as IndexState), (error: unknown) =>
      error instanceof IndexFailure && error.code === 'INVALID_STATE' && error.retryable === false);
  }
});

test('every fingerprint-relevant canonical change is marker-visible (equivalence canary)', () => {
  // The scripted canonical writers from the marker invariant: each step changes exactly one
  // fingerprint input, and every fingerprint input must move a freshness marker with it.
  const steps: readonly Readonly<{ name: string; before: IndexState; after: IndexState }>[] = [
    {
      name: 'note revision bump',
      before: state(),
      after: state({ notes: [note({ revision: 2 })] }),
    },
    {
      name: 'note delete',
      before: state(),
      after: state({ notes: [note({ deleted: true })] }),
    },
    {
      name: 'protection enable',
      before: state(),
      after: state({ notes: [note({ protected: true, protectionRevision: 1 })] }),
    },
    {
      name: 'protection disable',
      before: state({ notes: [note({ protected: true, protectionRevision: 1 })] }),
      after: state({ notes: [note({ protected: false, protectionRevision: 2 })] }),
    },
    {
      name: 'consent generation bump',
      before: state(),
      after: state({ consent: { accepted: true, version: CONSENT_VERSION, generation: 3 } }),
    },
    {
      name: 'account epoch bump',
      before: state(),
      after: state({ accountEpoch: 2 }),
    },
  ];
  for (const step of steps) {
    assert.equal(sameMarkers(markersOf(step.before), markersOf(step.after)), false, step.name);
    assert.notEqual(fingerprint(step.after), fingerprint(step.before), step.name);
  }
  // The unchanged account is marker-stable, and a text-only rewrite shows up through revision.
  assert.equal(sameMarkers(markersOf(state()), markersOf(state())), true);
  assert.equal(fingerprint(state()), fingerprint(state()));
});
