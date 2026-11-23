import type {
  APIGatewayProxyEventV2WithJWTAuthorizer,
  APIGatewayProxyStructuredResultV2,
} from 'aws-lambda';
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
import { TEST_API_KEY, passed, fail, show, assertEqual, assertExcludes, assertLessThan, check, textEncoder, expectFailure, type FetchCall, createFetchMock, hangingStream } from './test_support';

const streamWithPrefixThenHang = (prefix: string): ReadableStream<Uint8Array> =>
  new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(textEncoder.encode(prefix));
    },
  });

export const runProviderIoChecks = async (context: { capturedLogs: string[]; liveFetchCalls: () => number; unhandled: unknown[] ;}): Promise<void> => {
  await check('provider bounds response bytes while reading and cancels early', async () => {
    let pulls = 0;
    const stream = new ReadableStream<Uint8Array>({
      pull(controller) {
        pulls += 1;
        if (pulls > 6) {
          controller.close();
          return;
        }
        controller.enqueue(new Uint8Array(40000).fill(0x61));
      },
    });
    const { fetchImpl } = createFetchMock(() => new Response(stream, { status: 200 }));
    const provider = createDeepSeekProvider({ apiKey: TEST_API_KEY, fetchImpl, timeoutMs: 500 });
    await expectFailure(
      async () => provider({ stage: 'direct', inputs: ['x'] }),
      'invalidOutput',
      'over-size body',
    );
    assertLessThan(pulls, 6, `reader must stop at the byte bound (pulls=${pulls})`);

    // Declared Content-Length is refused before any read, not trusted as the bound.
    const declared = {
      status: 200,
      headers: new Headers({ 'content-length': '70000' }),
      body: null,
      arrayBuffer: async () => {
        throw new Error('body must not be read');
      },
    } as unknown as Response;
    const declaredMock = createFetchMock(() => declared);
    const declaredProvider = createDeepSeekProvider({
      apiKey: TEST_API_KEY,
      fetchImpl: declaredMock.fetchImpl,
      timeoutMs: 500,
    });
    await expectFailure(
      async () => declaredProvider({ stage: 'direct', inputs: ['x'] }),
      'invalidOutput',
      'declared over-size body',
    );
  });

  await check('provider deadline settles even when the mock ignores AbortSignal', async () => {
    const { fetchImpl, calls } = createFetchMock(() => new Response(hangingStream(), { status: 200 }));
    const provider = createDeepSeekProvider({ apiKey: TEST_API_KEY, fetchImpl, timeoutMs: 40 });
    const startedAt = Date.now();
    await expectFailure(async () => provider({ stage: 'direct', inputs: ['x'] }), 'timeout', 'hanging body');
    assertLessThan(Date.now() - startedAt, 2000, 'deadline settles promptly');
    assertEqual(calls.length, 1, 'no retry after a deadline');
    assertEqual((calls[0].init.signal as AbortSignal).aborted, true, 'deadline aborted the request');

    const partial = createFetchMock(
      () => new Response(streamWithPrefixThenHang('{"choices":'), { status: 200 }),
    );
    const partialProvider = createDeepSeekProvider({
      apiKey: TEST_API_KEY,
      fetchImpl: partial.fetchImpl,
      timeoutMs: 40,
    });
    await expectFailure(
      async () => partialProvider({ stage: 'direct', inputs: ['x'] }),
      'timeout',
      'stalled mid-body',
    );
  });
};
