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
import { type AnyRecord, TEST_API_KEY, passed, fail, show, isPlainObject, assertEqual, check, ERROR_CODES, textEncoder, requestBody, parseBody, isTokenCount, envelopeProblem, expectHandlerFailure, type FetchCall, createFetchMock, jsonResponse, providerPayload, type EventOptions, eventFor, type HandlerResponse, type Harness, buildHandler, realHandlerWithFetch } from './test_support';

const toBase64 = (bytes: Uint8Array): string => {
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
};

const base64Of = (text: string): string => toBase64(textEncoder.encode(text));

export const runHandlerTransportChecks = async (context: { capturedLogs: string[]; liveFetchCalls: () => number; unhandled: unknown[] ;}): Promise<void> => {
  await check('handler auth: access token with a subject required, zero other calls', async () => {
    const scenarios: ReadonlyArray<readonly [string, EventOptions]> = [
      ['authorizer absent', { authorizer: 'absent' }],
      ['claims null', { claims: null }],
      ['missing sub', { claims: { token_use: 'access' } }],
      ['blank sub', { claims: { sub: '   ', token_use: 'access' } }],
      ['non-string sub', { claims: { sub: 7, token_use: 'access' } }],
      ['id token', { claims: { sub: 'account-1', token_use: 'id' } }],
      ['missing token_use', { claims: { sub: 'account-1' } }],
      ['wrong token_use', { claims: { sub: 'account-1', token_use: 'refresh' } }],
    ];
    for (const [label, options] of scenarios) {
      const harness = buildHandler({ quota: { allowed: true } });
      const response = await harness.handler(
        eventFor({ ...options, body: JSON.stringify(requestBody('direct', ['x'])) }),
      );
      await expectHandlerFailure(response, 401, 'unauthorized', label);
      assertEqual(harness.quotaCalls.length, 0, `${label}: no quota`);
      assertEqual(harness.providerRequests.length, 0, `${label}: no provider`);
    }
  });

  await check('handler input refusals happen before quota and provider', async () => {
    const scenarios: ReadonlyArray<readonly [string, AnyRecord | string, number, string]> = [
      ['consent missing', { stage: 'direct', inputs: ['x'] }, 403, 'consentRequired'],
      [
        'consent false',
        { ...requestBody('direct', ['x']), consent: { accepted: false, version: CONSENT_VERSION } },
        403,
        'consentRequired',
      ],
      [
        'consent version',
        { ...requestBody('direct', ['x']), consent: { accepted: true, version: 'v2' } },
        403,
        'consentRequired',
      ],
      [
        'consent extra field',
        { ...requestBody('direct', ['x']), consent: { accepted: true, version: CONSENT_VERSION, extra: 1 } },
        400,
        'invalidInput',
      ],
      ['unknown field', { ...requestBody('section', ['x']), max_tokens: 10 }, 400, 'invalidInput'],
      ['stage unknown', requestBody('paragraph', ['x']), 400, 'invalidInput'],
      ['cardinality', requestBody('merge', ['only-one']), 400, 'invalidInput'],
      ['blank input', requestBody('section', ['  \n ']), 400, 'invalidInput'],
      ['malformed JSON', '{not json', 400, 'invalidInput'],
      ['JSON array body', JSON.stringify(['direct']), 400, 'invalidInput'],
      ['missing body', requestBody('direct', ['x']), 400, 'invalidInput'],
      ['too many tokens', requestBody('direct', ['x'.repeat(20000)]), 413, 'inputTooLong'],
    ];
    for (const [label, body, status, code] of scenarios) {
      const harness = buildHandler({ quota: { allowed: true } });
      const rawBody =
        label === 'missing body' ? null : typeof body === 'string' ? body : JSON.stringify(body);
      const response = await harness.handler(eventFor({ body: rawBody }));
      await expectHandlerFailure(response, status, code, label);
      assertEqual(harness.quotaCalls.length, 0, `${label}: no quota`);
      assertEqual(harness.providerRequests.length, 0, `${label}: no provider`);
    }

    const padded = JSON.stringify({
      ...requestBody('direct', ['']),
      inputs: ['a'.repeat(MAX_BODY_BYTES_UTF8)],
    });
    const overCap = buildHandler({ quota: { allowed: true } });
    await expectHandlerFailure(
      await overCap.handler(eventFor({ body: padded })),
      413,
      'inputTooLong',
      'raw body over cap',
    );
    assertEqual(overCap.quotaCalls.length, 0, 'over-cap body: no quota');
    assertEqual(overCap.providerRequests.length, 0, 'over-cap body: no provider');
  });

  await check('handler base64 bodies decode as UTF-8; malformed and over-cap refused', async () => {
    const unicode = 'Ghi chú tiếng Việt 🎯 có dấu.';
    const ok = realHandlerWithFetch(() => jsonResponse(providerPayload('direct')));
    const okResponse = await ok.harness.handler(
      eventFor({ body: base64Of(JSON.stringify(requestBody('direct', [unicode]))), base64: true }),
    );
    assertEqual(okResponse.statusCode, 200, 'base64 body accepted');
    assertEqual(
      ok.harness.providerRequests[0]?.inputs[0],
      unicode,
      'unicode preserved through base64',
    );
    assertEqual(ok.fetch.calls.length, 1, 'one provider call for the base64 request');

    const malformed = buildHandler({ quota: { allowed: true } });
    await expectHandlerFailure(
      await malformed.handler(eventFor({ body: '!!!not-base64!!!', base64: true })),
      400,
      'invalidInput',
      'malformed base64',
    );
    assertEqual(malformed.providerRequests.length, 0, 'malformed base64: no provider');

    const json = JSON.stringify(requestBody('direct', ['AAA']));
    const invalidUtf8 = textEncoder.encode(json);
    invalidUtf8[json.indexOf('AAA')] = 0x80;
    const badUtf8 = buildHandler({ quota: { allowed: true } });
    await expectHandlerFailure(
      await badUtf8.handler(eventFor({ body: toBase64(invalidUtf8), base64: true })),
      400,
      'invalidInput',
      'invalid UTF-8 base64',
    );
    assertEqual(badUtf8.providerRequests.length, 0, 'invalid UTF-8: no provider');

    const overCapBody = JSON.stringify({
      ...requestBody('direct', ['']),
      inputs: ['a'.repeat(MAX_BODY_BYTES_UTF8 + 1)],
    });
    const overCap = buildHandler({ quota: { allowed: true } });
    await expectHandlerFailure(
      await overCap.handler(eventFor({ body: base64Of(overCapBody), base64: true })),
      413,
      'inputTooLong',
      'base64 over cap',
    );
    assertEqual(overCap.providerRequests.length, 0, 'over-cap base64: no provider');
  });

  await check('handler routing: only POST /ai/summary, no calls for other requests', async () => {
    const scenarios: ReadonlyArray<readonly [string, EventOptions]> = [
      ['GET', { method: 'GET' }],
      ['PUT', { method: 'PUT' }],
      ['other path', { path: '/sync/health' }],
      ['root path', { path: '/' }],
    ];
    for (const [label, options] of scenarios) {
      const harness = buildHandler({ quota: { allowed: true } });
      const response = await harness.handler(
        eventFor({ ...options, body: JSON.stringify(requestBody('direct', ['x'])) }),
      );
      assertEqual(response.statusCode, 404, `${label}: status`);
      assertEqual(envelopeProblem(parseBody(response)), undefined, `${label}: envelope`);
      assertEqual(harness.quotaCalls.length, 0, `${label}: no quota`);
      assertEqual(harness.providerRequests.length, 0, `${label}: no provider`);
    }
  });
};
