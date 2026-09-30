import { createDeepSeekProvider } from './deepseek_client';
import { type SummaryResult } from './summary_contract';
import {
  assertEqual, assertExcludes, buildHandler, check, createFetchMock,
  eventFor, expectFailure, expectHandlerFailure, jsonResponse, providerPayload,
  requestBody, TEST_API_KEY
} from './test_support';

export const runBoundaryChecks = async (context: { capturedLogs: string[]; }): Promise<void> => {
  await check('actual provider usage input 16000/16001 and section output 128/129', async () => {
    for (const [input, output, accepted] of [[16000, 128, true], [16001, 128, false], [100, 129, false]] as const) {
      const mock = createFetchMock(() => jsonResponse(providerPayload('section', {
        usage: { prompt_tokens: input, completion_tokens: output, total_tokens: input + output },
      })));
      const generate = createDeepSeekProvider({ apiKey: TEST_API_KEY, fetchImpl: mock.fetchImpl });
      if (accepted) assertEqual((await generate({ stage: 'section', inputs: ['x'] })).usage.inputTokens, input, 'boundary accepted');
      else await expectFailure(() => generate({ stage: 'section', inputs: ['x'] }), 'invalidOutput', 'actual usage cap');
      assertEqual(mock.calls.length, 1, 'post-call check never retries');
    }
  });
  await check('handler provider port cannot return over-cap usage', async () => {
    for (const usage of [{ inputTokens: 16001, outputTokens: 1 }, { inputTokens: 1, outputTokens: 129 }]) {
      const mock = buildHandler({ generate: async () => ({ summary: 'ok', usage }) as SummaryResult });
      const response = await mock.handler(eventFor({ body: JSON.stringify(requestBody('section', ['x'])) }));
      await expectHandlerFailure(response, 502, 'invalidOutput', 'injected usage cap');
      assertEqual(mock.providerRequests.length, 1, 'single generation');
    }
  });
  await check('mutable unknown error name is never logged or returned', async () => {
    const canary = 'PRIVATE-ERROR-NAME-CANARY';
    const mock = buildHandler({ requestId: () => { const error = new Error('private'); error.name = canary; throw error; } });
    const response = await mock.handler(eventFor({ body: JSON.stringify(requestBody('direct', ['x'])) }));
    await expectHandlerFailure(response, 500, 'unexpected', 'ID-factory error');
    assertExcludes(JSON.stringify(context.capturedLogs), canary, 'safe logs');
    assertExcludes(String(response.body), canary, 'safe public error');
  });
  await check('missing readable provider body fails without arrayBuffer allocation', async () => {
    let fullReads = 0;
    const mock = createFetchMock(() => ({
      status: 200, headers: new Headers(), body: null,
      arrayBuffer: async () => { fullReads += 1; return new ArrayBuffer(1024 * 1024); },
    }) as unknown as Response);
    const generate = createDeepSeekProvider({ apiKey: TEST_API_KEY, fetchImpl: mock.fetchImpl });
    await expectFailure(() => generate({ stage: 'direct', inputs: ['x'] }), 'invalidOutput', 'missing body');
    assertEqual(fullReads, 0, 'no unbounded fallback');
  });
};
