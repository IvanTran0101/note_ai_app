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
import { type FsLike, nodeFs, type AnyRecord, TEST_API_KEY, PROVIDER_CANARY, passed, fail, show, assertEqual, nodeAssert, assertDeepEqual, assertOk, assertExcludes, check, wirePath, wireCases, textEncoder, expectFailure, type FetchCall, createFetchMock, jsonResponse, providerPayload } from './test_support';

const rawFromFixture = (testCase: AnyRecord): AnyRecord => {
  const provider = testCase.provider as AnyRecord;
  const payload: AnyRecord = {
    choices: [{ message: { content: provider.text }, finish_reason: provider.finish_reason }],
  };
  const usage = provider.usage as AnyRecord | undefined;
  if (usage !== undefined) {
    const mapped: AnyRecord = {};
    if ('inputTokens' in usage) {
      mapped.prompt_tokens = usage.inputTokens;
    }
    if ('outputTokens' in usage) {
      mapped.completion_tokens = usage.outputTokens;
    }
    if ('cachedTokens' in usage) {
      // The fixture's `cachedTokens` is carried as an official DeepSeek extra so
      // the runtime's "ignore official extras" rule is exercised, not bypassed.
      mapped.prompt_cache_hit_tokens = usage.cachedTokens;
      mapped.total_tokens = 1295;
    }
    payload.usage = mapped;
  }
  return payload;
};

export const runProviderChecks = async (context: { capturedLogs: string[]; liveFetchCalls: () => number; unhandled: unknown[] ;}): Promise<void> => {
  await check('provider request: one fetch to the fixed endpoint with frozen flags', async () => {
    const { fetchImpl, calls } = createFetchMock(() => jsonResponse(providerPayload('section')));
    const provider = createDeepSeekProvider({ apiKey: TEST_API_KEY, fetchImpl, timeoutMs: 500 });
    const request: SummaryRequest = { stage: 'section', inputs: ['một đoạn'] };
    const result = await provider(request);

    assertEqual(calls.length, 1, 'exactly one provider call');
    assertEqual(calls[0].url, 'https://api.deepseek.com/chat/completions', 'fixed HTTPS endpoint');
    assertEqual(calls[0].init.method, 'POST', 'POST');
    assertEqual(calls[0].init.redirect, 'error', 'redirects refused');
    assertOk(calls[0].init.signal instanceof AbortSignal, 'deadline signal attached');
    const headers = calls[0].init.headers as Record<string, string>;
    assertEqual(headers.authorization, `Bearer ${TEST_API_KEY}`, 'bearer auth header');
    assertEqual(headers['content-type'], 'application/json', 'json content type');

    const sent = JSON.parse(String(calls[0].init.body)) as AnyRecord;
    assertDeepEqual(
      Object.keys(sent).sort(),
      ['max_tokens', 'messages', 'model', 'stream', 'thinking'],
      'request carries no client-controlled fields',
    );
    assertEqual(sent.model, 'deepseek-flash', 'frozen model');
    assertEqual(sent.stream, false, 'streaming off');
    assertDeepEqual(sent.thinking, { type: 'disabled' }, 'thinking disabled');
    assertEqual(sent.max_tokens, maxOutputTokensForStage('section'), 'section output budget');
    assertDeepEqual(sent.messages, buildSummaryMessages(request), 'server-owned messages');
    assertDeepEqual(
      result,
      { summary: 'Tóm tắt section.', usage: { inputTokens: 1200, outputTokens: 20 } },
      'mapped result',
    );
    assertExcludes(show(result), TEST_API_KEY, 'key not in result');
    assertExcludes(show(context.capturedLogs), TEST_API_KEY, 'adapter never logs the key');
  });

  await check('provider fixtures map to raw DeepSeek JSON, official extra fields ignored', async () => {
    for (const testCase of wireCases.provider_cases as AnyRecord[]) {
      const payload = rawFromFixture(testCase);
      const { fetchImpl, calls } = createFetchMock(() => jsonResponse(payload));
      const provider = createDeepSeekProvider({ apiKey: TEST_API_KEY, fetchImpl, timeoutMs: 500 });
      const request: SummaryRequest = {
        stage: testCase.stage,
        inputs: testCase.stage === 'merge' ? ['một', 'hai'] : ['đoạn dữ liệu'],
      };

      if (testCase.id === 'provider.usage.extra_field.rejected') {
        // Documented deviation: the v0.3 fixture envelope treats any extra
        // usage field as a shape defect; the runtime validates the selected
        // fields and ignores official DeepSeek extras (total_tokens,
        // prompt_cache_hit_tokens, prompt_tokens_details), so it accepts this
        // case. Rejecting official extras would break on the real payload.
        const result = await provider(request);
        assertDeepEqual(
          result.usage,
          { inputTokens: 1200, outputTokens: 95 },
          `${testCase.id}: maps only the selected fields`,
        );
        assertEqual(calls.length, 1, `${testCase.id}: one call`);
        continue;
      }

      if (testCase.expect === 'accepted') {
        const result = await provider(request);
        const expectedSummary = String(testCase.normalized_summary ?? testCase.provider.text).trim();
        assertEqual(result.summary, expectedSummary, `${testCase.id}: summary`);
        assertDeepEqual(
          result.usage,
          {
            inputTokens: testCase.provider.usage.inputTokens,
            outputTokens: testCase.provider.usage.outputTokens,
          },
          `${testCase.id}: usage mapped from prompt/completion tokens`,
        );
      } else {
        await expectFailure(async () => provider(request), 'invalidOutput', testCase.id);
      }
      assertEqual(calls.length, 1, `${testCase.id}: no provider retry`);
    }
  });

  await check('provider refusals stay safe: malformed, truncated, non-stop, bad usage', async () => {
    const scenarios: ReadonlyArray<readonly [string, SummaryStage, Response]> = [
      ['not JSON', 'direct', new Response('{not json', { status: 200 })],
      ['truncated JSON', 'direct', new Response('{"choices":[{"message":{"content":"hi"', { status: 200 })],
      ['empty body', 'direct', new Response('', { status: 200 })],
      ['non-object JSON', 'direct', jsonResponse(['choices'])],
      ['no choices', 'direct', jsonResponse({ usage: { prompt_tokens: 1, completion_tokens: 1 } })],
      ['two choices', 'direct', jsonResponse({ choices: [{}, {}], usage: { prompt_tokens: 1, completion_tokens: 1 } })],
      [
        'finish_reason missing',
        'direct',
        jsonResponse({ choices: [{ message: { content: 'x' } }], usage: { prompt_tokens: 1, completion_tokens: 1 } }),
      ],
      ['finish_reason length', 'direct', jsonResponse(providerPayload('direct', { finishReason: 'length' }))],
      ['finish_reason filtered', 'section', jsonResponse(providerPayload('section', { finishReason: 'filtered' }))],
      ['finish_reason aborted', 'merge', jsonResponse(providerPayload('merge', { finishReason: 'aborted' }))],
      ['content whitespace', 'direct', jsonResponse(providerPayload('direct', { content: '   \n\t ' }))],
      ['content wrong type', 'direct', jsonResponse(providerPayload('direct', { content: 42 }))],
      [
        'usage missing',
        'direct',
        jsonResponse({ choices: [{ message: { content: 'x' }, finish_reason: 'stop' }] }),
      ],
      ['usage not object', 'direct', jsonResponse(providerPayload('direct', { usage: 'usage' }))],
      ['usage bool', 'direct', jsonResponse(providerPayload('direct', { usage: { prompt_tokens: true, completion_tokens: 20 } }))],
      ['usage negative', 'direct', jsonResponse(providerPayload('direct', { usage: { prompt_tokens: -1, completion_tokens: 20 } }))],
      ['usage string', 'direct', jsonResponse(providerPayload('direct', { usage: { prompt_tokens: 1, completion_tokens: '20' } }))],
      ['usage float', 'direct', jsonResponse(providerPayload('direct', { usage: { prompt_tokens: 1.5, completion_tokens: 2 } }))],
      [
        'section output over budget',
        'section',
        jsonResponse(providerPayload('section', { usage: { prompt_tokens: 9000, completion_tokens: 129 } })),
      ],
      [
        'direct output over budget',
        'direct',
        jsonResponse(providerPayload('direct', { usage: { prompt_tokens: 9000, completion_tokens: 257 } })),
      ],
    ];

    for (const [label, stage, response] of scenarios) {
      const { fetchImpl, calls } = createFetchMock(() => response);
      const provider = createDeepSeekProvider({ apiKey: TEST_API_KEY, fetchImpl, timeoutMs: 500 });
      const inputs = stage === 'merge' ? ['a', 'b'] : ['x'];
      await expectFailure(async () => provider({ stage, inputs }), 'invalidOutput', label);
      assertEqual(calls.length, 1, `${label}: one attempt, no retry`);
    }
  });

  await check('provider rejects invalid UTF-8 even when a lenient decode would parse', async () => {
    const json = JSON.stringify(providerPayload('direct', { content: 'AAA' }));
    const bytes = textEncoder.encode(json);
    bytes[json.indexOf('AAA')] = 0x80;
    const { fetchImpl } = createFetchMock(() => new Response(bytes, { status: 200 }));
    const provider = createDeepSeekProvider({ apiKey: TEST_API_KEY, fetchImpl, timeoutMs: 500 });
    await expectFailure(
      async () => provider({ stage: 'direct', inputs: ['x'] }),
      'invalidOutput',
      'invalid UTF-8',
    );
  });

  await check('provider HTTP failures map safely with bounded Retry-After', async () => {
    const scenarios: ReadonlyArray<readonly [string, number, Record<string, string>, string]> = [
      ['429 with seconds', 429, { 'retry-after': '17' }, 'rateLimited'],
      ['429 with HTTP-date', 429, { 'retry-after': 'Wed, 21 Oct 2026 07:28:00 GMT' }, 'rateLimited'],
      ['429 with zero', 429, { 'retry-after': '0' }, 'rateLimited'],
      ['429 with junk', 429, { 'retry-after': 'later' }, 'rateLimited'],
      ['500', 500, {}, 'providerUnavailable'],
      ['503', 503, {}, 'providerUnavailable'],
      ['401', 401, {}, 'providerUnavailable'],
      ['408', 408, {}, 'timeout'],
    ];
    for (const [label, status, headers, code] of scenarios) {
      const { fetchImpl, calls } = createFetchMock(() => new Response(PROVIDER_CANARY, { status, headers }));
      const provider = createDeepSeekProvider({ apiKey: TEST_API_KEY, fetchImpl, timeoutMs: 500 });
      const failure = await expectFailure(
        async () => provider({ stage: 'direct', inputs: ['x'] }),
        code,
        label,
      );
      assertEqual(calls.length, 1, `${label}: one attempt`);
      assertExcludes(failure.message, PROVIDER_CANARY, `${label}: provider body not in message`);
      assertExcludes(failure.message, TEST_API_KEY, `${label}: key not in message`);
      if (status === 429) {
        const retryAfter = failure.retryAfterSeconds;
        if (label === '429 with seconds') {
          assertEqual(retryAfter, 17, 'valid Retry-After is passed through');
        } else {
          assertEqual(retryAfter, undefined, `${label}: unusable Retry-After is dropped`);
        }
      }
    }

    // A very large Retry-After must be clamped, not echoed.
    const clampedMock = createFetchMock(
      () => new Response(PROVIDER_CANARY, { status: 429, headers: { 'retry-after': '999999' } }),
    );
    const clampedProvider = createDeepSeekProvider({
      apiKey: TEST_API_KEY,
      fetchImpl: clampedMock.fetchImpl,
      timeoutMs: 500,
    });
    const clamped = await expectFailure(
      async () => clampedProvider({ stage: 'direct', inputs: ['x'] }),
      'rateLimited',
      'clamped Retry-After',
    );
    assertEqual(clamped.retryAfterSeconds, 3600, 'Retry-After clamped to the bound');
  });

  await check('provider network failure and configuration bounds are safe', async () => {
    const networkMock = createFetchMock(() => {
      throw new Error(`ECONNREFUSED ${PROVIDER_CANARY}`);
    });
    const provider = createDeepSeekProvider({
      apiKey: TEST_API_KEY,
      fetchImpl: networkMock.fetchImpl,
      timeoutMs: 500,
    });
    const failure = await expectFailure(
      async () => provider({ stage: 'direct', inputs: ['x'] }),
      'providerUnavailable',
      'network failure',
    );
    assertExcludes(failure.message, PROVIDER_CANARY, 'raw network error not exposed');
    assertExcludes(failure.message, TEST_API_KEY, 'key not exposed');

    const neverCalled = createFetchMock(() => jsonResponse(providerPayload('direct')));
    const overBudget = createDeepSeekProvider({
      apiKey: TEST_API_KEY,
      fetchImpl: neverCalled.fetchImpl,
      timeoutMs: 500,
    });
    await expectFailure(
      async () => overBudget({ stage: 'direct', inputs: ['x'.repeat(MAX_INPUT_TOKENS_PER_CALL)] }),
      'inputTooLong',
      'provider-side estimate guard',
    );
    assertEqual(neverCalled.calls.length, 0, 'over-budget request never reaches the provider');

    const invalidConfigs: ReadonlyArray<readonly [string, AnyRecord]> = [
      ['blank key', { apiKey: '   ' }],
      ['zero timeout', { apiKey: TEST_API_KEY, timeoutMs: 0 }],
      ['negative body cap', { apiKey: TEST_API_KEY, maxResponseBytes: -1 }],
    ];
    for (const [label, options] of invalidConfigs) {
      await expectFailure(
        async () => Promise.resolve(createDeepSeekProvider(options as any)),
        'unexpected',
        label,
      );
    }
  });
};
