import type { APIGatewayProxyStructuredResultV2 } from 'aws-lambda';
import type { SummaryErrorCode, SummaryStage } from './summary_contract';
const isNonBlankString = (v: unknown): v is string => typeof v === 'string' && v.trim().length > 0;

export const STATUS_BY_CODE: Readonly<Record<SummaryErrorCode, number>> = {
  invalidInput: 400,
  inputTooLong: 413,
  unauthorized: 401,
  consentRequired: 403,
  noteLocked: 403,
  noteChanged: 409,
  rateLimited: 429,
  providerUnavailable: 502,
  invalidOutput: 502,
  timeout: 504,
  unexpected: 500,
};

export type Outcome = Readonly<{
  statusCode: number;
  code?: SummaryErrorCode;
  stage?: SummaryStage;
  summary?: string;
  usage?: Readonly<{ inputTokens: number; outputTokens: number; }>;
  retryAfterSeconds?: number;
}>;

export const defaultRequestId = (): string => {
  const cryptoApi = globalThis.crypto;
  if (cryptoApi !== undefined && typeof cryptoApi.randomUUID === 'function') {
    return cryptoApi.randomUUID();
  }
  return `req-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
};

/** One request's response: a success envelope or the contract's error envelope. */
export const toResponse = (outcome: Outcome, requestId: string): APIGatewayProxyStructuredResultV2 => {
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (outcome.retryAfterSeconds !== undefined) {
    headers['retry-after'] = String(outcome.retryAfterSeconds);
  }
  const body =
    outcome.code === undefined
      ? { summary: outcome.summary, requestId, usage: outcome.usage }
      : { error: { code: outcome.code }, requestId };
  return { statusCode: outcome.statusCode, headers, body: JSON.stringify(body) };
};

export const logOutcome = (outcome: Outcome, requestId: string, latencyMs: number): void => {
  if (outcome.code === undefined) {
    console.info('summary request', {
      requestId,
      stage: outcome.stage,
      latencyMs,
      inputTokens: outcome.usage?.inputTokens,
      outputTokens: outcome.usage?.outputTokens,
    });
    return;
  }
  console.warn('summary request failed', {
    requestId,
    stage: outcome.stage,
    latencyMs,
    code: outcome.code,
  });
};
