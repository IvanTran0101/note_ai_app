import { test } from 'node:test';
import assert from 'node:assert/strict';
import { RequestDeadline } from './deadline';
import { RagFailure } from './types';

test('deadline aborts a hanging stage and prevents a later stage', async () => {
  const deadline = new RequestDeadline(10);
  let called = 0;
  try {
    await assert.rejects(deadline.within(() => new Promise(() => {})),
      (e: unknown) => e instanceof RagFailure && e.code === 'TIMEOUT');
    assert.equal(deadline.signal.aborted, true);
    await assert.rejects(deadline.within(async () => { called++; }), /TIMEOUT/);
    assert.equal(called, 0);
  } finally { deadline.close(); }
});
test('clock expiration after a resolving operation fails closed', async () => {
  let now = 0;
  const deadline = new RequestDeadline(100, () => now);
  try {
    await assert.rejects(deadline.within(async () => { now = 101; return 'late'; }), /TIMEOUT/);
  } finally { deadline.close(); }
});
test('close releases timer and cancellation, composition bounds are checked', () => {
  for (const duration of [0, -1, NaN, Infinity, 26_001, 1.5]) {
    assert.throws(() => new RequestDeadline(duration), /LIVE_POLICY_NOT_CONFIGURED/);
  }
  const deadline = new RequestDeadline(10);
  deadline.close();
  assert.equal(deadline.signal.aborted, true);
});
