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
import { type AnyRecord, TEST_API_KEY, NOTE_CANARY, PROVIDER_CANARY, passed, fail, show, isPlainObject, assertEqual, nodeAssert, assertDeepEqual, assertIncludes, assertExcludes, assertLessThan, check, ERROR_CODES, requestBody, parseBody, isTokenCount, envelopeProblem, expectHandlerFailure, type FetchCall, createFetchMock, jsonResponse, providerPayload, hangingStream, type EventOptions, eventFor, type HandlerResponse, type Harness, buildHandler, realHandlerWithFetch } from './test_support';

const waitMs = async (ms: number): Promise<void> =>
  await new Promise<void>((resolve) => {
    setTimeout(resolve, ms);
  });

export const runHandlerChecks = async (context: { capturedLogs: string[]; liveFetchCalls: () => number; unhandled: unknown[] ;}): Promise<void> => {
  await check('handler success: mapped envelope, one quota call, one provider call', async () => {
    const { harness, fetch } = realHandlerWithFetch(() => jsonResponse(providerPayload('direct')));
    const response = await harness.handler(
      eventFor({ body: JSON.stringify(requestBody('direct', ['Ghi chú: họp nhóm 9h.'])) }),
    );

    assertEqual(response.statusCode, 200, 'status');
    const body = parseBody(response);
    assertEqual(envelopeProblem(body), undefined, 'success envelope shape');
    assertEqual(body.summary, 'Tóm tắt direct.', 'summary mapped');
    assertDeepEqual(body.usage, { inputTokens: 1200, outputTokens: 20 }, 'usage mapped');
    assertEqual(body.requestId, 'req-test', 'server request id');
    assertEqual(harness.quotaCalls.length, 1, 'one quota call');
    assertEqual(harness.quotaCalls[0]?.accountId, 'account-1', 'quota keyed by verified sub');
    assertEqual(harness.quotaCalls[0]?.nowMs, 1000, 'quota receives the server clock');
    assertEqual(harness.providerRequests.length, 1, 'one generation');
    assertEqual(fetch.calls.length, 1, 'one provider fetch');
    assertDeepEqual(
      harness.providerRequests[0],
      { stage: 'direct', inputs: ['Ghi chú: họp nhóm 9h.'] },
      'validated request reached the provider',
    );
  });

  await check('handler quota: refusal is 429 with bounded Retry-After, never a provider call', async () => {
    const refused = buildHandler({ quota: { allowed: false, retryAfterSeconds: 30 } });
    const response = await refused.handler(eventFor({ body: JSON.stringify(requestBody('direct', ['x'])) }));
    await expectHandlerFailure(response, 429, 'rateLimited', 'quota refusal');
    assertEqual(response.headers?.['retry-after'], '30', 'Retry-After header');
    assertEqual(refused.providerRequests.length, 0, 'quota refusal blocks generation');

    const onProvider = realHandlerWithFetch(
      () => new Response(PROVIDER_CANARY, { status: 429, headers: { 'retry-after': '12' } }),
    );
    const providerLimited = await onProvider.harness.handler(
      eventFor({ body: JSON.stringify(requestBody('section', ['x'])) }),
    );
    await expectHandlerFailure(providerLimited, 429, 'rateLimited', 'provider rate limit');
    assertEqual(providerLimited.headers?.['retry-after'], '12', 'provider Retry-After forwarded');
    assertEqual(onProvider.fetch.calls.length, 1, 'no retry after a rate limit');

    const absurd = buildHandler({ quota: { allowed: false, retryAfterSeconds: 10 ** 9 } });
    const absurdResponse = await absurd.handler(eventFor({ body: JSON.stringify(requestBody('direct', ['x'])) }));
    await expectHandlerFailure(absurdResponse, 429, 'rateLimited', 'absurd retry hint');
    assertEqual(absurdResponse.headers?.['retry-after'], '3600', 'retry hint clamped');
  });

  await check('handler quota failures fail closed within the quota deadline', async () => {
    const throwing = buildHandler({
      quota: async () => {
        throw new SummaryFailure('unexpected', 'quota storage failed');
      },
    });
    await expectHandlerFailure(
      await throwing.handler(eventFor({ body: JSON.stringify(requestBody('direct', ['x'])) })),
      500,
      'unexpected',
      'quota throws SummaryFailure',
    );
    assertEqual(throwing.providerRequests.length, 0, 'quota failure blocks generation');

    const plainThrow = buildHandler({
      quota: async () => {
        throw new Error(`dynamo tcp error ${PROVIDER_CANARY}`);
      },
    });
    const plainResponse = await plainThrow.handler(
      eventFor({ body: JSON.stringify(requestBody('direct', ['x'])) }),
    );
    await expectHandlerFailure(plainResponse, 500, 'unexpected', 'quota throws plain Error');
    assertExcludes(show(plainResponse), PROVIDER_CANARY, 'storage error text not echoed');
    assertEqual(plainThrow.providerRequests.length, 0, 'storage error blocks generation');

    const hanging = buildHandler({
      quota: () => new Promise<QuotaDecision>(() => undefined),
      quotaTimeoutMs: 40,
    });
    const startedAt = Date.now();
    const hangingResponse = await hanging.handler(
      eventFor({ body: JSON.stringify(requestBody('direct', ['x'])) }),
    );
    await expectHandlerFailure(hangingResponse, 500, 'unexpected', 'quota hangs');
    assertLessThan(Date.now() - startedAt, 2000, 'quota deadline settles promptly');
    assertEqual(hanging.providerRequests.length, 0, 'quota timeout fails closed');
  });

  await check('handler provider failures map to the contract statuses', async () => {
    const timeout = realHandlerWithFetch(() => new Response(hangingStream(), { status: 200 }), {
      providerTimeoutMs: 40,
    });
    const timeoutResponse = await timeout.harness.handler(
      eventFor({ body: JSON.stringify(requestBody('direct', [NOTE_CANARY])) }),
    );
    await expectHandlerFailure(timeoutResponse, 504, 'timeout', 'provider timeout');
    assertExcludes(show(timeoutResponse), NOTE_CANARY, 'note text not echoed on timeout');
    assertEqual(timeout.fetch.calls.length, 1, 'timeout does not retry');

    const upstream = realHandlerWithFetch(() => new Response(PROVIDER_CANARY, { status: 502 }));
    const upstreamResponse = await upstream.harness.handler(
      eventFor({ body: JSON.stringify(requestBody('section', [NOTE_CANARY])) }),
    );
    await expectHandlerFailure(upstreamResponse, 502, 'providerUnavailable', 'provider 5xx');
    assertExcludes(show(upstreamResponse), PROVIDER_CANARY, 'provider body not echoed');
    assertEqual(upstream.fetch.calls.length, 1, '5xx does not retry');

    const truncated = realHandlerWithFetch(
      () => jsonResponse(providerPayload('direct', { finishReason: 'length' })),
    );
    await expectHandlerFailure(
      await truncated.harness.handler(eventFor({ body: JSON.stringify(requestBody('direct', ['x'])) })),
      502,
      'invalidOutput',
      'non-stop finish reason',
    );

    const overBudget = realHandlerWithFetch(() =>
      jsonResponse(providerPayload('section', { usage: { prompt_tokens: 100, completion_tokens: 129 } })),
    );
    await expectHandlerFailure(
      await overBudget.harness.handler(eventFor({ body: JSON.stringify(requestBody('section', ['x'])) })),
      502,
      'invalidOutput',
      'over-budget section output',
    );
  });

  await check('handler re-validates the generated result before a 200', async () => {
    const scenarios: ReadonlyArray<readonly [string, unknown]> = [
      ['blank summary', { summary: '   ', usage: { inputTokens: 1, outputTokens: 1 } }],
      ['summary wrong type', { summary: 7, usage: { inputTokens: 1, outputTokens: 1 } }],
      ['usage missing', { summary: 'ok' }],
      ['usage bool', { summary: 'ok', usage: { inputTokens: true, outputTokens: 1 } }],
      ['usage negative', { summary: 'ok', usage: { inputTokens: -1, outputTokens: 1 } }],
    ];
    for (const [label, generated] of scenarios) {
      const harness = buildHandler({ generate: async () => generated as SummaryResult });
      const response = await harness.handler(
        eventFor({ body: JSON.stringify(requestBody('direct', ['x'])) }),
      );
      await expectHandlerFailure(response, 502, 'invalidOutput', label);
    }
  });

  await check('handler request ids are per request and logs carry metadata only', async () => {
    let counter = 0;
    const { harness } = realHandlerWithFetch(() => jsonResponse(providerPayload('direct')), {
      requestId: () => `req-${(counter += 1)}`,
    });
    const first = parseBody(
      await harness.handler(eventFor({ body: JSON.stringify(requestBody('direct', ['x'])) })),
    );
    const second = parseBody(
      await harness.handler(eventFor({ body: JSON.stringify(requestBody('direct', ['x'])) })),
    );
    assertEqual(first.requestId, 'req-1', 'first id');
    assertEqual(second.requestId, 'req-2', 'second id');

    const noise = show(context.capturedLogs);
    assertExcludes(noise, TEST_API_KEY, 'no key in logs');
    assertExcludes(noise, NOTE_CANARY, 'no note text in logs');
    assertExcludes(noise, 'Tóm tắt direct.', 'no summary text in logs');
    assertExcludes(noise, 'account-1', 'no account id in logs');
    assertIncludes(noise, 'req-1', 'metadata logging happened');
  });

  await check('handler never calls the live global fetch and reports no unhandled rejections', async () => {
    assertEqual(context.liveFetchCalls(), 0, 'live fetch trap');
    await waitMs(25);
    assertDeepEqual(context.unhandled, [], 'context.unhandled rejections');
  });
};
