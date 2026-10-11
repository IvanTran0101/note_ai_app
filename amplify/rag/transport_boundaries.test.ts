import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseRequest } from './contract';
import { createRagHandler } from './handler';
import type { APIGatewayProxyEventV2WithJWTAuthorizer as Event } from 'aws-lambda';
import type { RagResponse } from './types';

test('duplicate keys cannot bypass the strict request contract, including escaped names', () => {
  for (const body of [
    '{"wireVersion":1,"question":"old","question":"new","scope":{"type":"account"}}',
    '{"wireVersion":1,"question":"old","\\u0071uestion":"new","scope":{"type":"account"}}',
    '{"wireVersion":1,"question":"q","scope":{"type":"account","type":"account"}}',
  ]) assert.throws(() => parseRequest(body));
});
test('identifier Unicode is validated after JSON escape decoding', () => {
  assert.throws(() => parseRequest('{"wireVersion":1,"question":"q","scope":{"type":"note","noteId":"\\ud800"}}'));
});
test('literal braces, colons and escaped quotes in a question remain valid JSON data', () => {
  const question = 'What does {"question":"q", "question":"r"} mean? [S1]';
  const request = parseRequest(JSON.stringify({ wireVersion: 1, question, scope: { type: 'account' } }));
  assert.equal(request.question, question);
});

const body = JSON.stringify({ wireVersion: 1, question: 'q', scope: { type: 'account' } });
const event = (text = body, isBase64Encoded = false): Event => ({ rawPath: '/ai/rag/query',
  headers: { 'content-type': 'application/json' }, body: text, isBase64Encoded,
  requestContext: { http: { method: 'POST' }, authorizer: { jwt: { claims: { sub: 'actor-a', token_use: 'access' } } } },
} as unknown as Event);

test('the HTTP boundary rejects source-field leaks even if an injected query is broken', async () => {
  const handler = createRagHandler(async (_, __, id) => ({ wireVersion: 1, requestId: id, status: 'ANSWERED',
    answer: 'alpha [S1]', sources: [{ sourceId: 'S1', noteId: 'n', revision: 1, title: 't',
      startOffset: 0, endOffset: 5, quote: 'alpha', ownerId: 'unexpected-owner', key: 'unexpected-private-key' }],
  } as unknown as RagResponse));
  const response = await handler(event());
  assert.equal(response.statusCode, 502);
  assert.equal(response.body.includes('unexpected-'), false);
});
test('base64 padding bits must be canonical, not merely decodable', async () => {
  let paddedBody = body;
  while (Buffer.byteLength(paddedBody) % 3 !== 1) paddedBody += ' ';
  const raw = Buffer.from(paddedBody).toString('base64');
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const position = raw.length - 3;
  const malformed = raw.slice(0, position) + alphabet[alphabet.indexOf(raw[position]) + 1] + raw.slice(position + 1);
  assert.deepEqual(Buffer.from(malformed, 'base64'), Buffer.from(raw, 'base64'));
  let calls = 0;
  const handler = createRagHandler(async (_, __, id) => { calls++; return {
    wireVersion: 1, requestId: id, status: 'NOT_ENOUGH_CONTEXT', reason: 'INSUFFICIENT_EVIDENCE', answer: null, sources: [],
  }; });
  assert.equal((await handler(event(malformed, true))).statusCode, 400);
  assert.equal(calls, 0);
});
