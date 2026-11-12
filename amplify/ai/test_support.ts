import type {
  APIGatewayProxyEventV2WithJWTAuthorizer,
  APIGatewayProxyStructuredResultV2,
} from 'aws-lambda';
import { fileURLToPath } from 'node:url';
import {
  DEFAULT_MAX_RESPONSE_BYTES,
  DEFAULT_PROVIDER_TIMEOUT_MS,
  createDeepSeekProvider,
} from './deepseek_client';
import {
  CONSENT_VERSION,
  MAX_BODY_BYTES_UTF8,
  MAX_INPUT_TOKENS_PER_CALL,
  SummaryFailure,
  buildSummaryMessages,
  estimateSummaryInputTokens,
  maxOutputTokensForStage,
  parseSummaryBody,
  type QuotaDecision,
  type SummaryRequest,
  type SummaryResult,
  type SummaryStage,
} from './summary_contract';
import { DEFAULT_QUOTA_TIMEOUT_MS, createSummaryHandler } from './summary_handler';

export type FsLike = Readonly<{
  existsSync: (path: string) => boolean;
  readFileSync: (path: string, encoding: string) => string;
}>;

declare const process: {
  on(event: string, listener: (reason: unknown) => void): unknown;
  getBuiltinModule?: (id: string) => unknown;
  exitCode: number;
};

export const nodeFs = process.getBuiltinModule?.('node:fs') as FsLike | undefined;

export type AnyRecord = Record<string, any>;

export const TEST_API_KEY = 'sk-test-not-a-real-key-0000';

export const NOTE_CANARY = 'CANARY-NOTE-TEXT-do-not-leak';

export const PROVIDER_CANARY = 'CANARY-PROVIDER-BODY-do-not-leak';

export let passed = 0;

export const fail = (label: string, detail: string): never => {
  throw new Error(`${label}: ${detail}`);
};

export const show = (value: unknown): string => {
  try {
    return JSON.stringify(value) ?? String(value);
  } catch {
    return String(value);
  }
};

export const isPlainObject = (value: unknown): value is AnyRecord =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

export const assertEqual = (actual: unknown, expected: unknown, label: string): void => {
  if (!Object.is(actual, expected)) {
    fail(label, `expected ${show(expected)}, got ${show(actual)}`);
  }
};

export const nodeAssert = process.getBuiltinModule?.('node:assert/strict') as { deepStrictEqual(actual: unknown, expected: unknown, label?: string): void; };

export const assertDeepEqual = (actual: unknown, expected: unknown, label: string): void => nodeAssert.deepStrictEqual(actual, expected, label);

export const assertOk = (value: unknown, label: string): void => {
  if (!value) {
    fail(label, `expected a truthy value, got ${show(value)}`);
  }
};

export const assertIncludes = (haystack: string, needle: string, label: string): void => {
  if (!haystack.includes(needle)) {
    fail(label, `expected to contain ${show(needle)}`);
  }
};

export const assertExcludes = (haystack: string, needle: string, label: string): void => {
  if (haystack.includes(needle)) {
    fail(label, `expected not to contain ${show(needle)}`);
  }
};

export const assertLessThan = (actual: number, bound: number, label: string): void => {
  if (!(actual < bound)) {
    fail(label, `expected ${actual} < ${bound}`);
  }
};

export const check = async (name: string, run: () => Promise<void> | void): Promise<void> => {
  try {
    await run();
    passed += 1;
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
};

export const wirePath = fileURLToPath(new URL('./wire_cases.json', import.meta.url));

if (nodeFs === undefined || !nodeFs.existsSync(wirePath)) throw new Error("Required wire fixtures unavailable");
export const wireCases = JSON.parse(nodeFs.readFileSync(wirePath, 'utf8')) as AnyRecord;

export const ERROR_CODES: ReadonlySet<string> = new Set([
  'invalidInput',
  'inputTooLong',
  'unauthorized',
  'consentRequired',
  'rateLimited',
  'providerUnavailable',
  'invalidOutput',
  'timeout',
  'unexpected',
  'noteChanged',
  'noteLocked',
]);

export const textEncoder = new TextEncoder();

export const requestBody = (stage: unknown, inputs: unknown): AnyRecord => ({
  stage,
  inputs,
  note: { ownerId: 'account-test', noteId: 'synthetic-note', contentRevision: 1, protectionRevision: 0, runId: 'a'.repeat(32), sectionIndex: 0, sourceStart: null, sourceEnd: null },
  consent: { accepted: true, version: CONSENT_VERSION },
});

export const parseBody = (response: APIGatewayProxyStructuredResultV2): AnyRecord =>
  JSON.parse(String(response.body)) as AnyRecord;

export const isTokenCount = (value: unknown): boolean =>
  typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;

export const envelopeProblem = (value: unknown): string | undefined => {
  if (!isPlainObject(value)) {
    return 'not a JSON object';
  }
  if (typeof value.requestId !== 'string' || value.requestId.trim().length === 0) {
    return 'requestId is missing or blank';
  }
  const keys = Object.keys(value).sort().join(',');
  if ('error' in value) {
    const error = value.error;
    if (!isPlainObject(error)) {
      return 'error is not an object';
    }
    if (typeof error.code !== 'string' || !ERROR_CODES.has(error.code)) {
      return 'error code is unknown';
    }
    return keys === 'error,requestId' ? undefined : 'error envelope has unexpected fields';
  }
  if (keys !== 'requestId,summary,usage') {
    return 'success envelope has unexpected fields';
  }
  if (typeof value.summary !== 'string' || value.summary.trim().length === 0) {
    return 'summary is missing or blank';
  }
  if (!isPlainObject(value.usage)) {
    return 'usage is missing';
  }
  if (Object.keys(value.usage).sort().join(',') !== 'inputTokens,outputTokens') {
    return 'usage has unexpected fields';
  }
  if (!isTokenCount(value.usage.inputTokens) || !isTokenCount(value.usage.outputTokens)) {
    return 'usage is not a pair of whole token counts';
  }
  return undefined;
};

export const expectFailure = async (
  run: () => Promise<unknown>,
  code: string,
  label: string,
): Promise<SummaryFailure> => {
  let caught: unknown;
  try {
    await run();
  } catch (error) {
    caught = error;
  }
  if (!(caught instanceof SummaryFailure)) {
    fail(label, `expected SummaryFailure, got ${show(caught)}`);
  }
  const failure = caught as SummaryFailure;
  assertEqual(failure.code, code, `${label}: error code`);
  assertExcludes(failure.message, TEST_API_KEY, `${label}: key in message`);
  return failure;
};

export const expectHandlerFailure = async (
  response: APIGatewayProxyStructuredResultV2,
  status: number,
  code: string,
  label: string,
): Promise<APIGatewayProxyStructuredResultV2> => {
  assertEqual(response.statusCode, status, `${label}: status`);
  const body = parseBody(response);
  assertEqual(body.error?.code, code, `${label}: error code`);
  assertEqual(envelopeProblem(body), undefined, `${label}: error envelope shape`);
  return response;
};

export type FetchCall = Readonly<{ url: string; init: RequestInit; }>;

export const createFetchMock = (
  respond: (call: FetchCall) => Response | Promise<Response>,
): Readonly<{ fetchImpl: typeof fetch; calls: FetchCall[]; }> => {
  const calls: FetchCall[] = [];
  const fetchImpl = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const call: FetchCall = { url: String(input), init: init ?? {} };
    calls.push(call);
    return await respond(call);
  }) as unknown as typeof fetch;
  return { fetchImpl, calls };
};

export const jsonResponse = (
  payload: unknown,
  status = 200,
  headers: Record<string, string> = {},
): Response =>
  new Response(JSON.stringify(payload), {
    status,
    headers: { 'content-type': 'application/json', ...headers },
  });

export const providerPayload = (stage: SummaryStage, overrides: AnyRecord = {}): AnyRecord => ({
  id: 'chatcmpl-test',
  object: 'chat.completion',
  created: 1,
  model: 'deepseek-flash',
  choices: [
    {
      index: 0,
      message: { role: 'assistant', content: overrides.content ?? `Tóm tắt ${stage}.` },
      finish_reason: overrides.finishReason ?? 'stop',
    },
  ],
  usage: overrides.usage ?? { prompt_tokens: 1200, completion_tokens: 20, total_tokens: 1220 },
});

export const hangingStream = (): ReadableStream<Uint8Array> => new ReadableStream<Uint8Array>({ start() { } });

export type EventOptions = Readonly<{
  method?: string;
  path?: string;
  claims?: AnyRecord | null;
  authorizer?: 'jwt' | 'absent';
  body?: string | null;
  base64?: boolean;
}>;

export const eventFor = (options: EventOptions = {}): APIGatewayProxyEventV2WithJWTAuthorizer => {
  const claims =
    options.claims === undefined ? { sub: 'account-1', token_use: 'access' } : options.claims;
  const authorizer =
    options.authorizer === 'absent' || claims === null ? undefined : { jwt: { claims, scopes: null } };
  const path = options.path ?? '/ai/summary';
  return {
    version: '2.0',
    routeKey: '$default',
    rawPath: path,
    rawQueryString: '',
    headers: { 'content-type': 'application/json' },
    requestContext: {
      accountId: '123456789012',
      apiId: 'api-test',
      domainName: 'api-test.execute-api.local',
      domainPrefix: 'api-test',
      http: {
        method: options.method ?? 'POST',
        path,
        protocol: 'HTTP/1.1',
        sourceIp: '127.0.0.1',
        userAgent: 'tsx',
      },
      requestId: 'gateway-request',
      routeKey: '$default',
      stage: '$default',
      time: '01/Jan/2026:00:00:00 +0000',
      timeEpoch: 0,
      authorizer,
    },
    body: options.body ?? null,
    isBase64Encoded: options.base64 ?? false,
  } as unknown as APIGatewayProxyEventV2WithJWTAuthorizer;
};

export type HandlerResponse = APIGatewayProxyStructuredResultV2;

export type Harness = Readonly<{
  handler: (event: APIGatewayProxyEventV2WithJWTAuthorizer) => Promise<HandlerResponse>;
  providerRequests: SummaryRequest[];
  quotaCalls: Readonly<{ accountId: string; nowMs: number; }>[];
}>;

export const buildHandler = (
  options: Readonly<{
    fetchImpl?: typeof fetch;
    providerTimeoutMs?: number;
    generate?: (request: SummaryRequest) => Promise<SummaryResult>;
    quota?: (() => Promise<QuotaDecision>) | QuotaDecision;
    quotaTimeoutMs?: number;
    requestId?: () => string;
  }> = {},
): Harness => {
  const providerRequests: SummaryRequest[] = [];
  const quotaCalls: { accountId: string; nowMs: number; }[] = [];

  let generate: (request: SummaryRequest) => Promise<SummaryResult>;
  if (options.generate !== undefined) {
    generate = options.generate;
  } else {
    const fetchImpl = options.fetchImpl;
    if (fetchImpl === undefined) {
      // No provider expected on this path: calling one fails the check instead
      // of silently needing a mock that is never used.
      generate = async () => fail('harness', 'the provider must not be called on this path');
    } else {
      generate = createDeepSeekProvider({
        apiKey: TEST_API_KEY,
        fetchImpl,
        timeoutMs: options.providerTimeoutMs ?? 500,
      });
    }
  }

  // Transport/provider unit tests isolate authority; real canonical checks remain in summary_security.test.ts.
  const handler = createSummaryHandler({
    security: { async begin() { return { async revalidate() {}, async complete() {} }; } },
    generate: async (request) => {
      providerRequests.push(request);
      return await generate(request);
    },
    consumeQuota: async (accountId, nowMs) => {
      quotaCalls.push({ accountId, nowMs });
      if (typeof options.quota === 'function') {
        return await options.quota();
      }
      return options.quota ?? { allowed: true };
    },
    now: () => 1000,
    requestId: options.requestId ?? (() => 'req-test'),
    quotaTimeoutMs: options.quotaTimeoutMs,
  });

  return { handler, providerRequests, quotaCalls };
};

export const realHandlerWithFetch = (
  respond: (call: FetchCall) => Response | Promise<Response>,
  options: Readonly<{
    providerTimeoutMs?: number;
    quota?: (() => Promise<QuotaDecision>) | QuotaDecision;
    quotaTimeoutMs?: number;
    requestId?: () => string;
  }> = {},
): Readonly<{ harness: Harness; fetch: ReturnType<typeof createFetchMock>; }> => {
  const mock = createFetchMock(respond);
  const harness = buildHandler({ fetchImpl: mock.fetchImpl, ...options });
  return { harness, fetch: mock };
};
