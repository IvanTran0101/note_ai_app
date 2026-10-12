import { test } from 'node:test';
import assert from 'node:assert/strict';
import { RequestDeadline } from './deadline';

test('enclosing handler cancellation aborts a nested query and prevents later stages', async () => {
  const parent = new AbortController();
  const nested = new RequestDeadline(26_000, Date.now, parent.signal);
  let later = false;
  const pending = nested.within(() => new Promise<void>(() => {})).then(() => { later = true; });
  parent.abort();
  await assert.rejects(pending, { code: 'TIMEOUT' });
  assert.equal(nested.signal.aborted, true);
  assert.equal(later, false);
  nested.close();
});

test('already expired enclosing handler produces no query work', async () => {
  const nested = new RequestDeadline(26_000, Date.now, AbortSignal.abort());
  let called = false;
  await assert.rejects(nested.within(async () => { called = true; }), { code: 'TIMEOUT' });
  assert.equal(called, false);
  nested.close();
});
