import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createPhase4Budget, PHASE4_BUDGET_KEY } from './budget';

test('budget reserves once before egress, atomic shared dollar cap and fixed provider limit', async () => {
  const calls: any[] = [];
  const budget = createPhase4Budget('ap-southeast-1', 'T', { send: async (command, options) => { calls.push([command.input, options]); return {}; } });
  const signal = new AbortController().signal;
  await budget.reserve('deepseek', 8000, signal);
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0][0].Key, PHASE4_BUDGET_KEY);
  assert.equal(calls[0][0].ExpressionAttributeValues[':limit'], 24);
  assert.equal(calls[0][0].ExpressionAttributeValues[':cost'], 3629);
  assert.equal(calls[0][1].abortSignal, signal);
  assert.match(calls[0][0].ConditionExpression, /#calls < :limit/);
  assert.match(calls[0][0].ConditionExpression, /#usd <= :remaining/);
});

test('exhausted or unavailable budget fails closed and does not retry', async () => {
  let calls = 0;
  const budget = createPhase4Budget('ap-southeast-1', 'T', { send: async () => { calls++; throw { name: 'ConditionalCheckFailedException' }; } });
  await assert.rejects(budget.reserve('jev', 1000, new AbortController().signal), { code: 'RATE_LIMITED' });
  assert.equal(calls, 1);
  await assert.rejects(budget.reserve('jev', NaN, new AbortController().signal), { code: 'LIVE_POLICY_NOT_CONFIGURED' });
  assert.equal(calls, 1);
});

test('aborted reservation has zero writes; malformed counter is not reported as zero', async () => {
  let calls = 0;
  const budget = createPhase4Budget('ap-southeast-1', 'T', { send: async () => { calls++; return { Item: { jevCalls: -1 } }; } });
  await assert.rejects(budget.reserve('jev', 1, AbortSignal.abort()), { code: 'TIMEOUT' });
  assert.equal(calls, 0);
  await assert.rejects(budget.read(new AbortController().signal), { code: 'PROVIDER_UNAVAILABLE' });
});
