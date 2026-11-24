import assert from 'node:assert/strict';
import {test} from 'node:test';
import {SummaryRequestDeadline} from './summary_deadline';
import {SummaryFailure} from './summary_contract';
const timeout = (e: unknown) => e instanceof SummaryFailure && e.code === 'timeout';
test('deadline rejects a late operation result and reserves authorized release time', async () => {
  let now = 0;
  const d = new SummaryRequestDeadline(26000, () => now);
  assert.equal(d.providerBudget(), 15000);
  now = 16000;
  assert.equal(d.providerBudget(), 1000);
  now = 17000;
  assert.throws(() => d.providerBudget(), timeout);
  now = 0;
  await assert.rejects(d.within(async () => {now = 26000; return 'late';}), timeout);
});
test('a hung authority cannot hold the request beyond the deadline', async () => {
  const d = new SummaryRequestDeadline(1000);
  await assert.rejects(d.within(() => new Promise<never>(() => {})), timeout);
});
test('invalid configured deadlines fail closed', () => {
  for (const n of [0, 999, 26001, NaN, 2000.5]) {
    assert.throws(() => new SummaryRequestDeadline(n), SummaryFailure);
  }
});
