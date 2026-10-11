import { test } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { request } from 'node:http';
import { createMockServer } from './mock_server';

test('actual loopback HTTP mock returns cited evidence, rejects auth/UTF8 and avoids forbidden calls', async () => {
  const { server, runtime } = createMockServer();
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address();
  assert.ok(address && typeof address === 'object');
  const url = `http://127.0.0.1:${address.port}/ai/rag/query`;
  const body = JSON.stringify({ wireVersion: 1, question: 'SLGH031?', scope: { type: 'note', noteId: 'n-watch' } });
  try {
    const reply = await fetch(url, { method: 'POST', headers: {
      authorization: 'Bearer rag-mock-actor-a', 'content-type': 'application/json',
    }, body });
    assert.equal(reply.status, 200);
    const output = await reply.json() as { status: string; answer: string; sources: { noteId: string; quote: string }[] };
    assert.equal(output.status, 'ANSWERED');
    assert.match(output.answer, /\[S1\]/);
    assert.ok(output.sources.every(s => s.noteId === 'n-watch' && !s.quote.includes('999')));
    const calls = runtime.counts.generation;
    const noAuth = await fetch(url, { method: 'POST', headers: { 'content-type': 'application/json' }, body });
    assert.equal(noAuth.status, 401);
    const crossSite = await fetch(url, { method: 'POST', headers: {
      origin: 'https://example.invalid', 'content-type': 'application/json', authorization: 'Bearer rag-mock-actor-a',
    }, body });
    assert.equal(crossSite.status, 403);
    const malformed = await new Promise<number>((resolve, reject) => {
      const req = request(url, { method: 'POST', headers: { 'content-type': 'application/json' } }, res => {
        res.resume(); res.on('end', () => resolve(res.statusCode!));
      });
      req.on('error', reject); req.end(Buffer.from([0xc3, 0x28]));
    });
    assert.equal(malformed, 400);
    assert.equal(runtime.counts.generation, calls);
  } finally {
    server.closeAllConnections();
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
});
