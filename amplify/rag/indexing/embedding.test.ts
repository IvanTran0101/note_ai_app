/**
 * Embedding port tests — policy-fixed Cohere request, counter bounds, one-query rule, provider
 * output validation and no budget side effect. All IO is injected; no provider is contacted.
 * Runner: node --import tsx --test amplify/rag/indexing/embedding.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { RagFailure, type Counter } from '../types';
import { IndexFailure } from './types';
import { BEDROCK_INVOKE_MODEL_PATH, type AwsJson } from './aws_http';
import {
  EMBED_BATCH_LIMIT, EMBEDDING_MODEL, EMBEDDING_PATH, EMBEDDING_TRUNCATE, createEmbedding,
} from './embedding';

const SIGNAL = new AbortController().signal;

type Call = Readonly<{ service: string; path: string; body: Record<string, unknown>; signal: AbortSignal }>;

const recorder = (
  reply: (body: Record<string, unknown>, calls: number) => unknown,
): Readonly<{ calls: Call[]; request: AwsJson }> => {
  const calls: Call[] = [];
  const request: AwsJson = async (service, path, body, signal) => {
    calls.push({ service, path, body: body as Record<string, unknown>, signal });
    return reply(body as Record<string, unknown>, calls.length);
  };
  return { calls, request };
};

/** The policy embedding is 1024-dimensional and non-zero; `vector(0.5)` stays non-zero. */
const vector = (head = 1): number[] => {
  const values = new Array<number>(1024).fill(0);
  values[0] = head;
  return values;
};

const counter = (text: string): number => text.length;

const failureOf = async (run: () => Promise<unknown>): Promise<IndexFailure> => {
  try {
    await run();
  } catch (error) {
    assert.ok(error instanceof IndexFailure, `expected IndexFailure, got ${String(error)}`);
    return error;
  }
  throw new Error('expected the call to fail');
};

test('document batches send the policy request once and return frozen 1024-dim vectors', async () => {
  const io = recorder(() => ({ embeddings: [vector(), vector(0.5)] }));
  const embedding = createEmbedding('us-east-1', counter, io.request);
  assert.equal(embedding.count, counter);
  assert.equal(EMBEDDING_MODEL, 'cohere.embed-multilingual-v3');
  assert.equal(EMBEDDING_PATH, '/model/cohere.embed-multilingual-v3/invoke');
  assert.equal(EMBEDDING_PATH, BEDROCK_INVOKE_MODEL_PATH, 'the port whitelists this exact path');
  assert.equal(EMBEDDING_TRUNCATE, 'NONE');
  assert.equal(EMBED_BATCH_LIMIT, 96);

  const produced = await embedding.embed(['alpha', 'beta'], 'search_document', SIGNAL);
  assert.equal(io.calls.length, 1);
  assert.deepEqual(io.calls[0].body, {
    texts: ['alpha', 'beta'], input_type: 'search_document', truncate: 'NONE',
  });
  assert.equal(io.calls[0].service, 'bedrock');
  assert.equal(io.calls[0].path, EMBEDDING_PATH);
  assert.equal(io.calls[0].signal, SIGNAL);
  assert.equal(produced.length, 2);
  assert.deepEqual([...produced[0]], vector());
  assert.equal(produced[0].length, 1024);
  assert.ok(Object.isFrozen(produced) && Object.isFrozen(produced[0]));
});

test('a query embeds exactly one text with the query input type', async () => {
  const io = recorder(() => ({ embeddings: [vector()] }));
  const embedding = createEmbedding('us-east-1', counter, io.request);
  await embedding.embed(['question?'], 'search_query', SIGNAL);
  assert.deepEqual(io.calls[0].body, {
    texts: ['question?'], input_type: 'search_query', truncate: 'NONE',
  });

  for (const texts of [['q1', 'q2'], [] as string[], new Array<string>(2).fill('q')]) {
    const error = await failureOf(() => embedding.embed(texts, 'search_query', SIGNAL));
    assert.equal(error.code, 'INVALID_INPUT');
  }
  const purpose = await failureOf(() =>
    embedding.embed(['x'], 'search_document ' as 'search_document', SIGNAL));
  assert.equal(purpose.code, 'INVALID_INPUT');
  assert.equal(io.calls.length, 1);
});

test('batch count bounds are 1..96 and are checked before any provider call', async () => {
  const io = recorder(() => ({ embeddings: [] }));
  const embedding = createEmbedding('us-east-1', () => 1, io.request);
  for (const texts of [[], new Array<string>(97).fill('x'), 'not-an-array' as unknown as string[]]) {
    const error = await failureOf(() =>
      embedding.embed(texts, 'search_document', SIGNAL));
    assert.equal(error.code, 'INVALID_INPUT');
  }
  assert.equal(io.calls.length, 0);

  const full = new Array<string>(EMBED_BATCH_LIMIT).fill('x');
  io.calls.length = 0;
  const many = recorder(() => ({ embeddings: full.map(() => vector()) }));
  await createEmbedding('us-east-1', () => 1, many.request).embed(full, 'search_document', SIGNAL);
  assert.equal(many.calls.length, 1);
});

test('the injected counter bounds both the 2048-character and 512-token caps', async () => {
  const seen: string[] = [];
  const tokens = (text: string): number => {
    seen.push(text);
    return text.length;
  };
  const io = recorder(() => ({ embeddings: [vector()] }));
  const embedding = createEmbedding('us-east-1', tokens, io.request);

  const atTokenCap = 'b'.repeat(512);
  await embedding.embed([atTokenCap], 'search_document', SIGNAL);
  assert.deepEqual(seen, [atTokenCap]);

  const overToken = await failureOf(() => embedding.embed(['c'.repeat(513)], 'search_document', SIGNAL));
  assert.equal(overToken.code, 'INPUT_TOO_LONG');
  assert.equal(overToken.retryable, false);

  // Character cap is a separate bound, measured in code points with a tiny token count.
  const charIo = recorder(() => ({ embeddings: [vector()] }));
  const charOnly = createEmbedding('us-east-1', () => 0, charIo.request);
  const atCharCap = 'a'.repeat(2048);
  await charOnly.embed([atCharCap], 'search_document', SIGNAL);
  const charOver = await failureOf(() => charOnly.embed(['a'.repeat(2049)], 'search_document', SIGNAL));
  assert.equal(charOver.code, 'INPUT_TOO_LONG');
  // 2048 astral characters are 4096 UTF-16 units but exactly 2048 code points -> accepted.
  await charOnly.embed(['😀'.repeat(2048)], 'search_document', SIGNAL);
  const astralOver = await failureOf(() => charOnly.embed(['😀'.repeat(2049)], 'search_document', SIGNAL));
  assert.equal(astralOver.code, 'INPUT_TOO_LONG');
  assert.equal(io.calls.length, 1);
  assert.equal(charIo.calls.length, 2);
  assert.equal(seen.length, 2);
});

test('bad texts and a broken counter fail closed without a provider call', async () => {
  const io = recorder(() => ({ embeddings: [vector()] }));
  const embedding = createEmbedding('us-east-1', counter, io.request);
  for (const text of [42, '', '\ud800', null]) {
    const error = await failureOf(() =>
      embedding.embed([text as unknown as string], 'search_document', SIGNAL));
    assert.equal(error.code, 'INVALID_INPUT');
  }
  assert.equal(io.calls.length, 0);

  for (const broken of [() => -1, () => Number.NaN, () => { throw new Error('tokenizer'); }]) {
    const guarded = createEmbedding('us-east-1', broken as Counter, io.request);
    await assert.rejects(
      () => guarded.embed(['x'], 'search_document', SIGNAL),
      (error: unknown) =>
        error instanceof RagFailure && error.code === 'EVIDENCE_VALIDATION_UNAVAILABLE',
    );
  }
  assert.equal(io.calls.length, 0);
});

test('provider payloads must be one finite non-zero 1024-dim vector per input text', async () => {
  const bad: readonly (readonly [string, unknown])[] = [
    ['missing envelope', null],
    ['missing embeddings', { id: 'x' }],
    ['embeddings not an array', { embeddings: {} }],
    ['truncated cardinality', { embeddings: [vector()] }],
    ['wrong dimensions', { embeddings: [new Array<number>(512).fill(1)] }],
    ['non-number component', { embeddings: [vector().map((value, index) => (index === 3 ? 'x' : value))] }],
    ['non-finite component', { embeddings: [vector().map((value, index) => (index === 3 ? Number.NaN : value))] }],
    ['zero vector', { embeddings: [new Array<number>(1024).fill(0)] }],
  ];
  for (const [label, reply] of bad) {
    const io = recorder(() => reply);
    const embedding = createEmbedding('us-east-1', counter, io.request);
    const error = await failureOf(() => embedding.embed(['a', 'b'], 'search_document', SIGNAL));
    assert.deepEqual([error.code, error.retryable], ['INVALID_PROVIDER_OUTPUT', false], label);
    assert.equal(io.calls.length, 1, label);
  }
});

test('provider failures propagate unchanged and are never retried inside the port', async () => {
  const failures = [
    new IndexFailure('RATE_LIMITED', true),
    new IndexFailure('TIMEOUT', true),
    new IndexFailure('UNAUTHORIZED', false),
  ];
  for (const failure of failures) {
    let calls = 0;
    const request: AwsJson = async () => {
      calls += 1;
      throw failure;
    };
    const embedding = createEmbedding('us-east-1', counter, request);
    await assert.rejects(
      () => embedding.embed(['a'], 'search_document', SIGNAL),
      (error: unknown) => error === failure,
    );
    assert.equal(calls, 1);
  }
});

test('the embedding port exposes no budget hook — the worker reserves before calling', () => {
  const io = recorder(() => ({ embeddings: [vector()] }));
  const embedding = createEmbedding('us-east-1', counter, io.request);
  assert.deepEqual(Object.keys(embedding), ['count', 'embed']);
  assert.equal('reserveEmbedding' in embedding, false);
  assert.equal('reserve' in embedding, false);
});

test('construction validates region, counter and injected request', () => {
  const io = recorder(() => ({ embeddings: [] }));
  const invalid: readonly (() => unknown)[] = [
    () => createEmbedding('not-a-region', counter, io.request),
    () => createEmbedding('us-east-1', 'counter' as unknown as Counter, io.request),
    () => createEmbedding('us-east-1', counter, 'request' as unknown as AwsJson),
  ];
  for (const build of invalid) {
    assert.throws(build, (error: unknown) =>
      error instanceof IndexFailure && error.code === 'INVALID_STATE' && error.retryable === false);
  }
  // A valid region with no injected request builds the real signed port without any IO.
  assert.equal(createEmbedding('ap-southeast-1', counter).count, counter);
});
