import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadDeepSeekCounter, jevInputUpperBound } from './token_fit';

test('separate input bound preserves UTF8 and rejects invalid unicode', () => {
  assert.equal(jevInputUpperBound('hello'), 517);
  assert.equal(jevInputUpperBound('Tiếng Việt'), Buffer.byteLength('Tiếng Việt') + 512);
  assert.throws(() => jevInputUpperBound('\ud800'), { code: 'EVIDENCE_VALIDATION_UNAVAILABLE' });
  assert.throws(() => loadDeepSeekCounter('/nonexistent'), { code: 'LIVE_POLICY_NOT_CONFIGURED' });
});

test('official DeepSeek artifact has pinned VI/EN raw-text goldens', () => {
  const counter = loadDeepSeekCounter('output/rag/deepseek-tokenizer');
  assert.equal(counter('Hello!'), 2);
  assert.equal(counter('Thời lượng pin là 80 giờ.'), 10);
  assert.equal(counter('The battery lasts 80 hours.'), 7);
});
