/**
 * Indexing stream slice tests — partial batch reporting, coalescing, self-trigger filtering,
 * terminal vs retryable classification and the manual/backfill path.
 * Runner: node --import tsx --test amplify/rag/indexing/stream.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { JOB_POLICY_VERSION, IndexFailure } from './types';
import type { Job, JobResult } from './types';
import { createStreamHandler, runManualJob } from './stream';

const av = (value: string) => ({ S: value });

const record = (options: Readonly<{
  ownerId?: string;
  sortKey?: string;
  sequence: string;
  eventName?: string;
  eventId?: string;
  revision?: number;
}>): Record<string, unknown> => ({
  eventID: options.eventId ?? `evt-${options.sequence}`,
  eventName: options.eventName ?? 'INSERT',
  dynamodb: {
    Keys: {
      ownerId: av(options.ownerId ?? 'OWNER#u1'),
      noteId: av(options.sortKey ?? 'NOTE#n1'),
    },
    NewImage: { revision: { N: String(options.revision ?? 1) }, title: av('secret title') },
    SequenceNumber: options.sequence,
  },
});

const job = (ownerId: string, noteId: string | null, kind: Job['kind'] = 'RECONCILE_NOTE'): Job => ({
  jobVersion: 1, kind, ownerId, noteId, sourceRevisionHint: noteId === null ? null : 1,
  policyVersion: JOB_POLICY_VERSION, eventId: `evt-${ownerId}-${noteId ?? 'account'}`,
});

const rig = (handler: (job: Job) => Promise<JobResult>) => {
  const calls: Job[] = [];
  const logs: Record<string, string | number>[] = [];
  const worker = async (value: Job): Promise<JobResult> => {
    calls.push(value);
    return handler(value);
  };
  const handle = createStreamHandler(worker, (metadata) => logs.push({ ...metadata }));
  return { calls, logs, handle, worker };
};

const accept = async (): Promise<JobResult> => ({ status: 'SUCCEEDED', code: 'READY' });

test('a fully successful batch acknowledges every record', async () => {
  const rigged = rig(accept);
  const result = await rigged.handle({ Records: [record({ sequence: '1' })] } as never);
  assert.deepEqual(result, { batchItemFailures: [] });
  assert.equal(rigged.calls.length, 1);
  assert.equal(rigged.calls[0]?.ownerId, 'u1');
});

test('duplicate owner/note records coalesce and report the earliest sequence numerically', async () => {
  const rigged = rig(async () => {
    throw new IndexFailure('PORT_FAILURE', true);
  });
  const result = await rigged.handle({
    Records: [
      record({ sequence: '100' }),
      record({ sequence: '99', eventName: 'MODIFY', revision: 2 }),
      record({ sortKey: 'PROTECTION#n1', sequence: '101', eventName: 'MODIFY' }),
    ],
  } as never);
  assert.equal(rigged.calls.length, 1, 'one worker call for one owner/note');
  assert.deepEqual(result, { batchItemFailures: [{ itemIdentifier: '99' }] });
});

test('only the failing group is reported from a partial batch', async () => {
  const rigged = rig(async (value) => {
    if (value.ownerId === 'u1') throw new IndexFailure('SOURCE_CHANGED', false);
    if (value.ownerId === 'u2') throw new IndexFailure('PORT_FAILURE', true);
    return accept();
  });
  const result = await rigged.handle({
    Records: [
      record({ sequence: '10' }),
      record({ ownerId: 'OWNER#u2', sequence: '20' }),
      record({ sequence: '30' }),
      record({ ownerId: 'OWNER#u3', sequence: '40' }),
    ],
  } as never);
  assert.equal(rigged.calls.length, 3);
  assert.deepEqual(result, { batchItemFailures: [{ itemIdentifier: '20' }] });
  assert.ok(rigged.logs.some((entry) => entry['code'] === 'SOURCE_CHANGED'));
});

test('an account job absorbs the owner note records for failure mapping', async () => {
  const rigged = rig(async () => {
    throw new IndexFailure('BUDGET_EXHAUSTED', true);
  });
  const result = await rigged.handle({
    Records: [
      record({ sequence: '5', sortKey: 'NOTE#n1' }),
      record({ sequence: '7', sortKey: 'RAG#CONSENT' }),
    ],
  } as never);
  assert.equal(rigged.calls.length, 1);
  assert.equal(rigged.calls[0]?.kind, 'RECONCILE_ACCOUNT');
  assert.equal(rigged.calls[0]?.noteId, null);
  assert.deepEqual(result, { batchItemFailures: [{ itemIdentifier: '5' }] });
});

test('worker-owned and foreign rows are acknowledged without any worker call', async () => {
  const rigged = rig(accept);
  const result = await rigged.handle({
    Records: [
      'META#SYNC', 'CHANGE#1', 'EVENT#e1', 'MUTATION#m1', 'SHARED#n1',
      'RAG#MANIFEST#lease-1', 'RAG#LEASE#lease-1', 'RAG#STATUS', 'RAG#SNAPSHOT#lease-1',
    ].map((sortKey, index) => record({ sortKey, sequence: String(index + 1) })),
  } as never);
  assert.deepEqual(result, { batchItemFailures: [] });
  assert.equal(rigged.calls.length, 0);
  assert.equal(rigged.logs.length, 0);
});

test('a malformed relevant row is a terminal typed failure, not a replay', async () => {
  const rigged = rig(accept);
  const result = await rigged.handle({
    Records: [
      record({ ownerId: 'u1', sequence: '1' }),
      record({ sequence: '2', eventId: '' }),
    ],
  } as never);
  assert.deepEqual(result, { batchItemFailures: [] });
  assert.equal(rigged.calls.length, 0);
  assert.deepEqual(rigged.logs, [
    { event: 'index.stream.rejected', code: 'INVALID_JOB', sequenceNumber: '1' },
    { event: 'index.stream.rejected', code: 'INVALID_JOB', sequenceNumber: '2' },
  ]);
});

test('FAILED worker results stay terminal and are acknowledged with typed metadata only', async () => {
  const rigged = rig(async (value) => (value.ownerId === 'u1'
    ? { status: 'FAILED', code: 'INPUT_TOO_LONG' }
    : { status: 'FAILED', code: 'CLEANUP_FAILED' }));
  const result = await rigged.handle({
    Records: [record({ sequence: '1' }), record({ ownerId: 'OWNER#u2', sequence: '2' })],
  } as never);
  assert.deepEqual(result, { batchItemFailures: [] });
  assert.deepEqual(rigged.logs, [{
    event: 'index.stream.terminal', code: 'INPUT_TOO_LONG', ownerId: 'u1', noteId: 'n1',
  }, {
    event: 'index.stream.terminal', code: 'CLEANUP_FAILED', ownerId: 'u2', noteId: 'n1',
  }]);
  assert.equal(JSON.stringify(rigged.logs).includes('secret'), false);
});

test('SOURCE_CHANGED and PUBLISH_REJECTED replay the earliest sequence with the exact code', async () => {
  for (const code of ['SOURCE_CHANGED', 'PUBLISH_REJECTED'] as const) {
    const rigged = rig(async () => ({ status: 'SUPERSEDED', code }));
    const result = await rigged.handle({
      Records: [
        record({ sequence: '100' }),
        record({ sequence: '99', eventName: 'MODIFY', revision: 2 }),
        record({ sortKey: 'PROTECTION#n1', sequence: '101', eventName: 'MODIFY' }),
      ],
    } as never);
    assert.equal(rigged.calls.length, 1, `${code}: one worker call`);
    assert.deepEqual(result, { batchItemFailures: [{ itemIdentifier: '99' }] }, code);
    assert.deepEqual(rigged.logs, [{
      event: 'index.stream.replay', code, ownerId: 'u1', sequenceNumber: '99',
    }], code);
  }
});

test('ALREADY_DONE is acknowledged, never replayed and never logged as terminal', async () => {
  const rigged = rig(async () => ({ status: 'SUPERSEDED', code: 'ALREADY_DONE' }));
  const result = await rigged.handle({ Records: [record({ sequence: '21' })] } as never);
  assert.deepEqual(result, { batchItemFailures: [] });
  assert.equal(rigged.calls.length, 1);
  assert.deepEqual(rigged.logs, []);
});

test('a replayed SOURCE_CHANGED converges on the next invocation', async () => {
  let attempt = 0;
  const rigged = rig(async () => {
    attempt += 1;
    return attempt === 1
      ? { status: 'SUPERSEDED', code: 'SOURCE_CHANGED' }
      : { status: 'SUCCEEDED', code: 'READY' };
  });
  const event = { Records: [record({ sequence: '30' })] } as never;
  assert.deepEqual(await rigged.handle(event), { batchItemFailures: [{ itemIdentifier: '30' }] });
  assert.deepEqual(await rigged.handle(event), { batchItemFailures: [] });
  assert.equal(rigged.calls.length, 2);
});

test('a non-retryable thrown failure is acknowledged; an unknown failure replays', async () => {
  const terminal = rig(async () => {
    throw new IndexFailure('INVALID_STATE', false);
  });
  assert.deepEqual(await terminal.handle({ Records: [record({ sequence: '4' })] } as never),
    { batchItemFailures: [] });
  assert.equal(terminal.logs[0]?.['code'], 'INVALID_STATE');

  const unknown = rig(async () => {
    throw new Error('socket closed');
  });
  const result = await unknown.handle({ Records: [record({ sequence: '8' })] } as never);
  assert.deepEqual(result, { batchItemFailures: [{ itemIdentifier: '8' }] });
  assert.equal(unknown.logs[0]?.['code'], 'PORT_FAILURE');
});

test('a failing job without a sequence number is acknowledged and logged', async () => {
  const rigged = rig(async () => {
    throw new IndexFailure('PORT_FAILURE', true);
  });
  const withoutSequence = record({ sequence: '1' });
  delete ((withoutSequence['dynamodb'] as Record<string, unknown>)['SequenceNumber']);
  const result = await rigged.handle({ Records: [withoutSequence] } as never);
  assert.deepEqual(result, { batchItemFailures: [] });
  assert.equal(rigged.logs[0]?.['event'], 'index.stream.unmapped');
});

test('an empty or malformed event acknowledges nothing and calls nobody', async () => {
  const rigged = rig(accept);
  for (const event of [null, {}, { Records: [] }, undefined]) {
    assert.deepEqual(await rigged.handle(event as never), { batchItemFailures: [] });
  }
  assert.equal(rigged.calls.length, 0);
});

test('the manual/backfill path funnels the raw value through the same worker', async () => {
  const rigged = rig(accept);
  const logs: Record<string, string | number>[] = [];
  const result = await runManualJob(rigged.worker, job('u1', 'n1'), (metadata) => logs.push({ ...metadata }));
  assert.equal(result.status, 'SUCCEEDED');
  assert.equal(rigged.calls.length, 1);
  assert.deepEqual(logs, []);

  const failing = rig(async () => {
    throw new IndexFailure('TIMEOUT', true);
  });
  await assert.rejects(runManualJob(failing.worker, job('u1', 'n1'), undefined), (error: unknown) =>
    error instanceof IndexFailure && error.code === 'TIMEOUT' && error.retryable === true);

  const broken = rig(async () => {
    throw new Error('boom');
  });
  await assert.rejects(runManualJob(broken.worker, job('u1', 'n1'), undefined), (error: unknown) =>
    error instanceof IndexFailure && error.code === 'PORT_FAILURE' && error.retryable === true);
});

 test('a busy lease replays instead of dropping a newer event', async () => {
  const r = rig(async () => ({ status: 'SUPERSEDED', code: 'LEASE_BUSY' }));
  assert.deepEqual(await r.handle({ Records: [record({ sequence: '12' })] } as never),
    { batchItemFailures: [{ itemIdentifier: '12' }] });
});

test('one invocation shares the 120-second budget across all jobs', async () => {
  const original = Date.now;
  let now = 0;
  Date.now = () => now;
  try {
    const budgets: number[] = [];
    const handler = createStreamHandler(async (_job, budget) => {
      budgets.push(budget!); now += 110_001;
      return { status: 'SUCCEEDED', code: 'READY' };
    });
    const result = await handler({ Records: [record({sequence:'1'}),
      record({ownerId:'OWNER#u2',sequence:'2'})] } as never);
    assert.deepEqual(budgets,[110_000]);
    assert.deepEqual(result,{batchItemFailures:[{itemIdentifier:'2'}]});
  } finally { Date.now = original; }
});

test('an explicit trusted deadline is shared across jobs, never reset per job', async () => {
  const original = Date.now;
  let now = 0;
  Date.now = () => now;
  try {
    const budgets: number[] = [];
    const handler = createStreamHandler(async (_job, budget) => {
      budgets.push(budget!); now += 10_001;
      return { status: 'SUCCEEDED', code: 'READY' };
    });
    const result = await handler({ Records: [record({sequence:'1'}),
      record({ownerId:'OWNER#u2',sequence:'2'})] } as never, 10_000);
    assert.deepEqual(budgets,[10_000]);
    assert.deepEqual(result,{batchItemFailures:[{itemIdentifier:'2'}]});
  } finally { Date.now = original; }
});

test('an explicit deadline can never extend the fixed 110-second worker cap', async () => {
  const original = Date.now;
  Date.now = () => 0;
  try {
    const budgets: number[] = [];
    const handler = createStreamHandler(async (_job, budget) => {
      budgets.push(budget!);
      return { status: 'SUCCEEDED', code: 'READY' };
    });
    await handler({ Records: [record({ sequence: '1' })] } as never, 5_000_000);
    assert.deepEqual(budgets, [110_000]);
  } finally { Date.now = original; }
});

test('a non-finite explicit deadline fails closed before any worker call', async () => {
  let calls = 0;
  const handler = createStreamHandler(async () => {
    calls += 1;
    return { status: 'SUCCEEDED', code: 'READY' };
  });
  await assert.rejects(
    handler({ Records: [record({ sequence: '1' })] } as never, Number.NaN),
    (error: unknown) => error instanceof IndexFailure && error.code === 'INVALID_STATE',
  );
  assert.equal(calls, 0);
});

test('manual backfill forwards the remaining budget only for a trusted deadline', async () => {
  const original = Date.now;
  Date.now = () => 0;
  try {
    const seen: Array<number | undefined> = [];
    const worker = async (_value: unknown, remainingMs?: number): Promise<JobResult> => {
      seen.push(remainingMs);
      return { status: 'SUCCEEDED', code: 'READY' };
    };
    await runManualJob(worker, job('u1', 'n1'), undefined, 7_000);
    await runManualJob(worker, job('u1', 'n1'), undefined);
    assert.deepEqual(seen, [7_000, undefined]);
  } finally { Date.now = original; }
});
