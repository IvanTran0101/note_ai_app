/** Production composition with mocked SDK/fetch; no credentials or network. */
import { DynamoDBDocumentClient, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import { handler } from './lambda';
import { assertEqual, assertExcludes, eventFor, jsonResponse, providerPayload, requestBody } from './test_support';

declare const process: { env: Record<string, string | undefined>; exitCode: number; };

const main = async (): Promise<void> => {
  const originalSend = DynamoDBDocumentClient.prototype.send;
  const originalFetch = globalThis.fetch;
  const originalError = console.error;
  let sdkCalls = 0;
  const authorizations: string[] = [];
  const logs: unknown[] = [];
  DynamoDBDocumentClient.prototype.send = (async (command: unknown, options?: { abortSignal?: AbortSignal; }) => {
    assertEqual(command instanceof UpdateCommand, true, 'only quota update');
    assertEqual(options?.abortSignal instanceof AbortSignal, true, 'SDK abort bound');
    sdkCalls += 1;
    return {};
  }) as unknown as DynamoDBDocumentClient['send'];
  globalThis.fetch = (async (_url, init) => {
    authorizations.push(new Headers(init?.headers).get('authorization') ?? '');
    return jsonResponse(providerPayload('direct'));
  }) as typeof fetch;
  console.error = (...args) => { logs.push(args); };
  process.env.SUMMARY_QUOTA_TABLE_NAME = 'synthetic-quota-table';
  const invoke = async () => {
    const response = await handler(eventFor({ body: JSON.stringify(requestBody('direct', ['synthetic note'])) }), {} as never, () => {});
    if (typeof response !== 'object' || response === null) throw new Error('Expected structured Lambda response');
    return response;
  };
  try {
    delete process.env.DEEPSEEK_API_KEY;
    assertEqual((await invoke())?.statusCode, 500, 'missing key');
    process.env.DEEPSEEK_API_KEY = '<value will be resolved during runtime>';
    assertEqual((await invoke())?.statusCode, 500, 'unresolved Amplify secret');
    assertEqual(sdkCalls, 0, 'unconfigured does not consume quota');
    assertEqual(authorizations.length, 0, 'unconfigured does not fetch');
    process.env.DEEPSEEK_API_KEY = 'synthetic-key-A';
    assertEqual((await invoke())?.statusCode, 200, 'recovery after missing key');
    process.env.DEEPSEEK_API_KEY = 'synthetic-key-B';
    assertEqual((await invoke())?.statusCode, 200, 'rotated key');
    assertEqual(authorizations[0], 'Bearer synthetic-key-A', 'initial key');
    assertEqual(authorizations[1], 'Bearer synthetic-key-B', 'current key, not cached');
    delete process.env.DEEPSEEK_API_KEY;
    assertEqual((await invoke())?.statusCode, 500, 'missing key after prior success fails closed');
    assertEqual(sdkCalls, 2, 'no stale provider/quota call');
    process.env.DEEPSEEK_API_KEY = 'synthetic-key-C';
    assertEqual((await invoke())?.statusCode, 200, 'later recovery');
    assertEqual(sdkCalls, 3, 'one quota per configured invocation');
    for (const key of ['synthetic-key-A', 'synthetic-key-B', 'synthetic-key-C']) assertExcludes(JSON.stringify(logs), key, 'no secret logs');
    console.log('Lambda mock composition passed: missing/placeholder/rotation/recovery, 0 live SDK/fetch calls.');
  } finally {
    DynamoDBDocumentClient.prototype.send = originalSend;
    globalThis.fetch = originalFetch;
    console.error = originalError;
  }
};
main().catch(error => { console.error(error); process.exitCode = 1; });
