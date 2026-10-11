/**
 * RAG v1 HTTP handler for API Gateway HTTP API with a Cognito JWT authorizer.
 *
 * Contract: docs/contracts/rag_api_v1.md §1/§2/§4/§7. Policy: docs/rag/policy_v1.json
 * `technicalDefaults.wire` + `technicalDefaults.errorHttpStatus` + `safety`.
 *
 * Transport and policy only: the verified access-token `sub` (claims supplied by the API
 * Gateway authorizer - no header or body value can supply an identity), a bounded and
 * UTF-8 checked body, `parseRequest`, one injected query, and a bounded response envelope.
 * Unexpected failures and oversized provider output become safe error envelopes; no JWT,
 * content, provider message or stack is ever logged or echoed.
 */
import { randomUUID } from 'node:crypto';
import type { APIGatewayProxyEventV2WithJWTAuthorizer } from 'aws-lambda';
import {
  ABSTENTION_REASONS,
  REQUEST_MAX_BYTES,
  RESPONSE_MAX_BYTES,
  WIRE_VERSION,
  MAX_GENERATED_SOURCES,
  isValidIdentifier,
  isValidSource,
  isValidUnicode,
  parseRequest,
} from './contract';
import { policy, RagFailure } from './types';
import type { ErrorCode, RagRequest, RagResponse } from './types';

export type RagQuery = (actor: string, request: RagRequest, requestId: string) => Promise<RagResponse>;
export type RagHttpResponse = Readonly<{
  statusCode: number;
  headers: Readonly<Record<string, string>>;
  body: string;
}>;
export type RagHandler = (event: APIGatewayProxyEventV2WithJWTAuthorizer) => Promise<RagHttpResponse>;

const RAG_PATH: string = policy.technicalDefaults.wire.route;
const ERROR_STATUS = policy.technicalDefaults.errorHttpStatus as Readonly<Record<string, number>>;
const JSON_HEADERS = Object.freeze({
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store',
});
/** Base64 expands three bytes to four characters; used for the pre-decode size check. */
const MAX_BASE64_CHARS = Math.ceil(REQUEST_MAX_BYTES / 3) * 4 + 4;
const CANONICAL_BASE64 = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;
const ANSWERED_KEYS = ['wireVersion', 'requestId', 'status', 'answer', 'sources'] as const;
const ABSTENTION_KEYS = ['wireVersion', 'requestId', 'status', 'reason', 'answer', 'sources'] as const;
const ERROR_KEYS = ['wireVersion', 'requestId', 'status', 'code'] as const;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const hasExactKeys = (value: Record<string, unknown>, required: readonly string[]): boolean =>
  Object.keys(value).length === required.length &&
  required.every((key) => Object.prototype.hasOwnProperty.call(value, key));

const methodOf = (event: APIGatewayProxyEventV2WithJWTAuthorizer): string =>
  event.requestContext?.http?.method?.toUpperCase() ?? '';

const headerOf = (event: APIGatewayProxyEventV2WithJWTAuthorizer, name: string): string | undefined => {
  const headers = event.headers;
  if (headers === null || headers === undefined) return undefined;
  const wanted = name.toLowerCase();
  for (const [key, value] of Object.entries(headers)) {
    if (key.toLowerCase() === wanted && typeof value === 'string') return value;
  }
  return undefined;
};

/** `application/json` with an optional UTF-8 charset; anything else is not this API's body. */
const isJsonUtf8 = (value: string | undefined): boolean => {
  if (value === undefined) return false;
  const [mediaType, ...parameters] = value.split(';').map((part) => part.trim().toLowerCase());
  if (mediaType !== 'application/json') return false;
  return parameters.every((parameter) => {
    if (parameter.length === 0) return true;
    const [name, rawCharset] = parameter.split('=').map((part) => part.trim());
    const charset = (rawCharset ?? '').replace(/^"|"$/g, '');
    return name === 'charset' && (charset === 'utf-8' || charset === 'utf8');
  });
};

/** Only the authorizer claims count: `sub` on a Cognito access token, never the Authorization header. */
const accessTokenActor = (event: APIGatewayProxyEventV2WithJWTAuthorizer): string => {
  const claims = event.requestContext?.authorizer?.jwt?.claims;
  if (!isRecord(claims)) throw new RagFailure('UNAUTHORIZED');
  const sub = claims['sub'];
  if (claims['token_use'] !== 'access' || !isValidIdentifier(sub)) throw new RagFailure('UNAUTHORIZED');
  return sub;
};

const decodeBase64Body = (raw: string): string => {
  if (raw.length > MAX_BASE64_CHARS) throw new RagFailure('INPUT_TOO_LONG');
  if (!CANONICAL_BASE64.test(raw)) throw new RagFailure('INVALID_INPUT');
  const bytes = Buffer.from(raw, 'base64');
  if (bytes.byteLength > REQUEST_MAX_BYTES) throw new RagFailure('INPUT_TOO_LONG');
  if (bytes.toString('base64') !== raw) throw new RagFailure('INVALID_INPUT');
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    throw new RagFailure('INVALID_INPUT');
  }
};

const readRawBody = (event: APIGatewayProxyEventV2WithJWTAuthorizer): string => {
  const raw = event.body;
  if (typeof raw !== 'string' || raw.length === 0) throw new RagFailure('INVALID_INPUT');
  if (event.isBase64Encoded === true) return decodeBase64Body(raw);
  if (new TextEncoder().encode(raw).byteLength > REQUEST_MAX_BYTES) throw new RagFailure('INPUT_TOO_LONG');
  return raw;
};

const errorEnvelope = (requestId: string, code: ErrorCode): RagHttpResponse => {
  const envelope: RagResponse = { wireVersion: WIRE_VERSION, requestId, status: 'ERROR', code };
  return Object.freeze({
    statusCode: ERROR_STATUS[code] ?? 503,
    headers: JSON_HEADERS,
    body: JSON.stringify(envelope),
  });
};

/** Re-checks the injected query result so a broken adapter cannot become a 200. */
const assertRagResponse = (value: unknown, requestId: string): RagResponse => {
  function invalid(): never {
    throw new RagFailure('INVALID_PROVIDER_OUTPUT');
  }
  if (!isRecord(value) || value['wireVersion'] !== WIRE_VERSION || value['requestId'] !== requestId) invalid();
  const status = value['status'];
  if (status === 'ERROR') {
    const code = value['code'];
    if (!hasExactKeys(value, ERROR_KEYS)) invalid();
    if (typeof code !== 'string' || !Object.prototype.hasOwnProperty.call(ERROR_STATUS, code)) invalid();
  } else if (status === 'NOT_ENOUGH_CONTEXT') {
    if (!hasExactKeys(value, ABSTENTION_KEYS)) invalid();
    if (value['answer'] !== null || !Array.isArray(value['sources']) || value['sources'].length !== 0) invalid();
    if (!(ABSTENTION_REASONS as readonly string[]).includes(value['reason'] as string)) invalid();
  } else if (status === 'ANSWERED') {
    if (!hasExactKeys(value, ANSWERED_KEYS)) invalid();
    const answer = value['answer'];
    const sources = value['sources'];
    if (typeof answer !== 'string' || !answer.trim() || !isValidUnicode(answer)) invalid();
    if (!Array.isArray(sources) || sources.length === 0 || sources.length > MAX_GENERATED_SOURCES) invalid();
    const labels = new Set<string>();
    for (const source of sources) {
      if (!isValidSource(source) || labels.has(source.sourceId)) invalid();
      labels.add(source.sourceId);
    }
    const referenced = new Set(Array.from(answer.matchAll(/\[(S[0-9]+)\]/g), match => match[1]));
    if (referenced.size !== labels.size || [...referenced].some(label => !labels.has(label))) invalid();
  } else {
    invalid();
  }
  return value as unknown as RagResponse;
};

const respond = (requestId: string, response: RagResponse): RagHttpResponse => {
  const body = JSON.stringify(response);
  if (new TextEncoder().encode(body).byteLength > RESPONSE_MAX_BYTES) {
    return errorEnvelope(requestId, 'INVALID_PROVIDER_OUTPUT');
  }
  const statusCode = response.status === 'ERROR' ? ERROR_STATUS[response.code] ?? 503 : 200;
  return Object.freeze({ statusCode, headers: JSON_HEADERS, body });
};

const safeRequestId = (factory: () => string): string => {
  try {
    const candidate = factory();
    if (isValidIdentifier(candidate)) return candidate;
  } catch {
    // fall through to a server-generated correlation id
  }
  return randomUUID();
};

/**
 * Builds the Lambda handler around one injected query. `requestId` defaults to a random UUID
 * and is only a correlation value, never an idempotency or billing key.
 */
export function createRagHandler(query: RagQuery, requestId: () => string = randomUUID): RagHandler {
  return async (event) => {
    const id = safeRequestId(requestId);
    try {
      if (event.rawPath !== RAG_PATH || methodOf(event) !== 'POST') throw new RagFailure('INVALID_INPUT');
      const actor = accessTokenActor(event);
      if (!isJsonUtf8(headerOf(event, 'content-type'))) throw new RagFailure('INVALID_INPUT');
      const request = parseRequest(readRawBody(event));
      return respond(id, assertRagResponse(await query(actor, request, id), id));
    } catch (error) {
      return errorEnvelope(id, error instanceof RagFailure ? error.code : 'PROVIDER_UNAVAILABLE');
    }
  };
}
