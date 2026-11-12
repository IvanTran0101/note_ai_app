/**
 * Worker Lambda dispatch shell tests. The handler must resolve its mode before any runtime
 * composition: an unknown `RAG_PILOT_PHASE5` value fails closed, and an absent value keeps the
 * legacy private composition (only the mode decision is exercised here; the private and pilot
 * handlers themselves are covered by entrypoints.test.ts and phase5/pilot_worker.test.ts).
 *
 * Runner: node --import tsx --test amplify/rag/indexing/worker_lambda.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { IndexFailure, WORKER_MS } from './types';
import { WORKER_MARGIN_MS } from './stream';
import { handler, invocationDeadlineFrom } from './worker_lambda';

const withMode = async (value: string | undefined): Promise<void> => {
  const previous = process.env['RAG_PILOT_PHASE5'];
  if (value === undefined) delete process.env['RAG_PILOT_PHASE5'];
  else process.env['RAG_PILOT_PHASE5'] = value;
  try {
    await assert.rejects(
      handler({ operation: 'unknown' }),
      (error: unknown) => error instanceof IndexFailure && error.code === 'INVALID_STATE',
    );
  } finally {
    if (previous === undefined) delete process.env['RAG_PILOT_PHASE5'];
    else process.env['RAG_PILOT_PHASE5'] = previous;
  }
};

test('an unknown pilot mode fails closed before any runtime composition', async () => {
  for (const value of ['pilot', 'SYNTHETIC-ONLY', '', 'true']) await withMode(value);
});

test('the invocation deadline is captured from the trusted context on the frozen clock', () => {
  const now = () => 1_000;
  // No context keeps the fixed 110s worker budget (the 120s cap less the 10s cutoff margin).
  assert.equal(invocationDeadlineFrom(undefined, now), 1_000 + WORKER_MS - WORKER_MARGIN_MS);
  // A shorter Lambda context tightens the budget by the same 10s cutoff margin.
  assert.equal(
    invocationDeadlineFrom({ getRemainingTimeInMillis: () => 30_000 }, now),
    1_000 + 30_000 - WORKER_MARGIN_MS,
  );
  // A 20s context is margin-deducted once, not capped-then-margined twice.
  assert.equal(
    invocationDeadlineFrom({ getRemainingTimeInMillis: () => 20_000 }, now),
    1_000 + 20_000 - WORKER_MARGIN_MS,
  );
  // A larger context is still capped by the fixed budget and its margin.
  assert.equal(
    invocationDeadlineFrom({ getRemainingTimeInMillis: () => 900_000 }, now),
    1_000 + WORKER_MS - WORKER_MARGIN_MS,
  );
});

test('a context reporting a non-finite or non-positive remaining fails closed', () => {
  for (const remaining of [0, -1, Number.NaN, Number.POSITIVE_INFINITY, 'soon']) {
    assert.throws(
      () => invocationDeadlineFrom({ getRemainingTimeInMillis: () => remaining }),
      (error: unknown) => error instanceof IndexFailure && error.code === 'INVALID_STATE',
    );
  }
});

test('a context without a usable remaining accessor keeps the fixed budget', () => {
  assert.equal(invocationDeadlineFrom({}, () => 2_000), 2_000 + WORKER_MS - WORKER_MARGIN_MS);
  assert.equal(
    invocationDeadlineFrom({ getRemainingTimeInMillis: 3 }, () => 2_000),
    2_000 + WORKER_MS - WORKER_MARGIN_MS,
  );
});

test('a trusted context already inside the cutoff margin times out before composition', async () => {
  // The context's remaining is at/below the 10s margin, so the captured deadline is now: the
  // handler must refuse with a retryable TIMEOUT instead of starting the cold tokenizer path.
  for (const remaining of [1, 5_000, WORKER_MARGIN_MS]) {
    await assert.rejects(
      handler({ operation: 'unknown' }, { getRemainingTimeInMillis: () => remaining } as never),
      (error: unknown) => error instanceof IndexFailure && error.code === 'TIMEOUT' && error.retryable,
    );
  }
});

test('an invalid mode still fails closed with a context present (deadline captured first)', async () => {
  const previous = process.env['RAG_PILOT_PHASE5'];
  process.env['RAG_PILOT_PHASE5'] = 'pilot';
  try {
    await assert.rejects(
      handler({ operation: 'unknown' }, { getRemainingTimeInMillis: () => 30_000 } as never),
      (error: unknown) => error instanceof IndexFailure && error.code === 'INVALID_STATE',
    );
  } finally {
    if (previous === undefined) delete process.env['RAG_PILOT_PHASE5'];
    else process.env['RAG_PILOT_PHASE5'] = previous;
  }
});
