/**
 * The IAM-only embedding canary module: exact event shape, fixed synthetic text, count/reserve
 * ordering, metadata-only output and bounded error mapping. No AWS, provider or environment call.
 *
 * Runner: node --import tsx --test amplify/rag/phase5/embedding_canary.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { IndexFailure } from '../indexing/types';
import { RagFailure } from '../types';
import {
  EMBEDDING_CANARY_KIND, canaryFailure, isEmbeddingCanaryEvent, runEmbeddingCanary,
} from './embedding_canary';
import type { EmbeddingCanaryDeps } from './embedding_canary';
import type { PilotBudget } from './pilot_budget';

const VECTOR = Object.freeze(Array.from({ length: 768 }, (_, index) => (index === 0 ? 1 : 0)));

test('only the exact one-key canary payload is accepted', () => {
  assert.equal(isEmbeddingCanaryEvent({ kind: EMBEDDING_CANARY_KIND }), true);
  assert.equal(isEmbeddingCanaryEvent({ kind: EMBEDDING_CANARY_KIND, text: 'note body' }), false);
  assert.equal(isEmbeddingCanaryEvent({ kind: 'embedding-canary.v2' }), false);
  assert.equal(isEmbeddingCanaryEvent({}), false);
  assert.equal(isEmbeddingCanaryEvent(null), false);
});

test('the runner counts both tokenizers, reserves before one fixed-text embed and returns metadata only', async () => {
  const order: string[] = [];
  const budget: PilotBudget = {
    async reserve() { throw new Error('the canary must not reserve a query provider'); },
    async acquireQuery() { throw new Error('the canary must not acquire a query lease'); },
    async release() { throw new Error('the canary must not release a query lease'); },
    async acquireEmbedding() { order.push('reserve'); },
    async acquireCohere() { throw new Error('the canary must not use the legacy path'); },
    async read() { throw new Error('the canary must not read counters'); },
  };
  let clock = 100;
  const deps: EmbeddingCanaryDeps = {
    embedding: {
      count(text) { order.push(`count:embedding:${text}`); return 14; },
      async embed(texts, purpose) {
        order.push(`embed:${purpose}:${texts[0]}`);
        return [VECTOR];
      },
    },
    budget,
    countOutput(text) { order.push(`count:deepseek:${text}`); return 9; },
    now: () => { clock += 5; return clock; },
  };

  const result = await runEmbeddingCanary(deps, new AbortController().signal) as Record<string, unknown>;

  const text = 'NoteFlow synthetic embedding canary. No user note content.';
  assert.deepEqual(order, [
    `count:embedding:${text}`, `count:deepseek:${text}`, 'reserve', `embed:search_query:${text}`,
  ]);
  assert.deepEqual(result, {
    status: 'OK',
    canary: EMBEDDING_CANARY_KIND,
    profile: { model: 'embeddinggemma2', dimensions: 768 },
    dimensions: 768,
    norm: 1,
    finite: true,
    timing: { totalMs: 5 },
    tokenizerCounts: { embedding: 14, deepseek: 9 },
  });
  assert.ok(!('vector' in result) && !('vectors' in result));
});

test('a bad tokenizer count never reserves or embeds; an invalid vector is rejected after the dispatch', async () => {
  const dispatches: string[] = [];
  const budget: PilotBudget = {
    async reserve() {},
    async acquireQuery() { throw new Error('unused'); },
    async release() {},
    async acquireEmbedding() { dispatches.push('reserve'); },
    async acquireCohere() {},
    async read() { throw new Error('unused'); },
  };
  const deps = (count: number, vector: readonly number[]): EmbeddingCanaryDeps => ({
    embedding: {
      count: () => count,
      async embed() { dispatches.push('embed'); return [vector]; },
    },
    budget,
    countOutput: () => 9,
    now: Date.now,
  });

  await assert.rejects(() => runEmbeddingCanary(deps(-1, VECTOR), new AbortController().signal),
    (error: unknown) => error instanceof IndexFailure && error.code === 'INVALID_STATE');
  assert.deepEqual(dispatches, [], 'no reservation or adapter dispatch before a valid count');

  await assert.rejects(() => runEmbeddingCanary(deps(14, Object.freeze([1, 0])), new AbortController().signal),
    (error: unknown) => error instanceof IndexFailure && error.code === 'INVALID_PROVIDER_OUTPUT');
  assert.deepEqual(dispatches, ['reserve', 'embed'], 'the provider output is validated after the one dispatch');
});

test('the safe mapping exposes a known code and never an unknown or raw error', () => {
  assert.deepEqual(canaryFailure(new RagFailure('SCOPE_DENIED')), {
    status: 'ERROR', canary: EMBEDDING_CANARY_KIND, code: 'SCOPE_DENIED',
  });
  assert.deepEqual(canaryFailure(new IndexFailure('INVALID_PROVIDER_OUTPUT')), {
    status: 'ERROR', canary: EMBEDDING_CANARY_KIND, code: 'INVALID_PROVIDER_OUTPUT',
  });
  assert.deepEqual(canaryFailure(new IndexFailure('NOT_A_WIRE_CODE')), {
    status: 'ERROR', canary: EMBEDDING_CANARY_KIND, code: 'PROVIDER_UNAVAILABLE',
  });
  assert.deepEqual(canaryFailure(new Error('raw provider detail')), {
    status: 'ERROR', canary: EMBEDDING_CANARY_KIND, code: 'PROVIDER_UNAVAILABLE',
  });
});
