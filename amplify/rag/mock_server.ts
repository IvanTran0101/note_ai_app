import { createServer, type IncomingMessage } from 'node:http';
import { fileURLToPath } from 'node:url';
import type { APIGatewayProxyEventV2WithJWTAuthorizer as Event } from 'aws-lambda';
import { createMockRuntime } from './mock';
import { policy, RagFailure } from './types';

// This loopback demo accepts fixed synthetic credentials, never real Cognito JWTs.
export function createMockServer() {
  const runtime = createMockRuntime();
  const server = createServer(async (req, res) => {
    res.setHeader('cache-control', 'no-store');
    res.setHeader('content-type', 'application/json; charset=utf-8');
    const id = 'mock-transport';
    if (req.headers.origin || !/^(127\.0\.0\.1|localhost):\d+$/.test(req.headers.host ?? '')) {
      res.writeHead(403); res.end(JSON.stringify({ wireVersion: 1, requestId: id, status: 'ERROR', code: 'SCOPE_DENIED' }));
      return;
    }
    const auth = req.headers.authorization;
    const actor = auth === 'Bearer rag-mock-actor-a' ? 'actor-a'
      : auth === 'Bearer rag-mock-actor-b' ? 'actor-b' : undefined;
    try {
      const body = await readBody(req);
      const event = { rawPath: new URL(req.url ?? '/', 'http://127.0.0.1').pathname,
        headers: { 'content-type': req.headers['content-type'] ?? '' }, body,
        requestContext: { http: { method: req.method },
          ...(actor ? { authorizer: { jwt: { claims: { sub: actor, token_use: 'access' } } } } : {}) },
      } as unknown as Event;
      const result = await runtime.handler(event);
      res.writeHead(result.statusCode ?? 500);
      res.end(result.body);
    } catch (error) {
      const code = error instanceof RagFailure ? error.code : 'INVALID_INPUT';
      res.writeHead(policy.technicalDefaults.errorHttpStatus[code]);
      res.end(JSON.stringify({ wireVersion: 1, requestId: id, status: 'ERROR', code }));
    }
  });
  server.requestTimeout = policy.technicalDefaults.wire.requestTimeoutMs;
  return { server, runtime };
}

async function readBody(req: IncomingMessage): Promise<string> {
  const parts: Buffer[] = [];
  let bytes = 0;
  for await (const part of req) {
    const buffer = Buffer.isBuffer(part) ? part : Buffer.from(part);
    bytes += buffer.length;
    if (bytes > policy.technicalDefaults.wire.bodyMaxUtf8Bytes) throw new RagFailure('INPUT_TOO_LONG');
    parts.push(buffer);
  }
  return new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(parts));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { server } = createMockServer();
  server.listen(8797, '127.0.0.1', () => {
    console.log('RAG synthetic mock: http://127.0.0.1:8797/ai/rag/query — no cloud/provider calls');
  });
}
