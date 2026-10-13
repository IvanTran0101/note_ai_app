/**
 * Phase 5.1 consent endpoint handler: `GET`/`PUT /ai/rag/consent` (plan 5.1A/5.1C).
 *
 * Contract: docs/rag/phase5_api_consent_contract.md. Transport and policy only: the actor is
 * the verified Cognito access-token `sub` from the API Gateway authorizer (no header or body
 * value can supply an identity), the PUT body is exactly
 * `{accepted, version, expectedGeneration}` with no owner field, and the response is exactly
 * `{wireVersion, requestId, consent:{accepted, version, generation}}` or the same error
 * envelope `createRagHandler` uses.
 *
 * Permission is injected as `assertActor(actor)`: this module never decides who is a pilot and
 * never accepts a caller-supplied owner or allowlist. A missing `assertActor` is a build-time
 * refusal (LIVE_POLICY_NOT_CONFIGURED), never an allow. The endpoint deliberately does not
 * depend on query admission, so a pilot owner can always revoke a grant.
 *
 * `accessTokenActor`, the base64/UTF-8 body guard and the header check mirror the private
 * helpers of `../handler`; the root may export them there and delete this copy once the two
 * handlers share one transport module. The duplicate-key scan is not copied: it is the exported
 * `assertNoDuplicateKeys` of `../contract`, the same scanner the query body already runs.
 */
import { randomUUID } from 'node:crypto';
import type { APIGatewayProxyEventV2WithJWTAuthorizer } from 'aws-lambda';
import {
  CONSENT_VERSION, REQUEST_MAX_BYTES, WIRE_VERSION, assertNoDuplicateKeys, isValidIdentifier, isValidUnicode,
} from '../contract';
import { isSafeInteger } from '../chunking';
import { RequestDeadline } from '../deadline';
import { policy, RagFailure } from '../types';
import type { ErrorCode } from '../types';
import type { RagHttpResponse } from '../handler';
import type { ConsentGrant, ConsentStore, ConsentWrite } from './consent_store';

export const CONSENT_PATH = '/ai/rag/consent';

export type ConsentHandlerDeps = Readonly<{
  store: ConsentStore;
  /** Server-side permission for this exact actor. Must throw a RagFailure when refused. */
  assertActor: (actor: string) => void;
  requestId?: () => string;
  /**
   * Optional enclosing request deadline. When supplied, the consent deadline is parented to it,
   * so a total budget that started before a permission/config read still bounds this handler.
   * Omitting it preserves the original 26s-only behavior.
   */
  signal?: AbortSignal;
}>;
export type ConsentHandler = (event: APIGatewayProxyEventV2WithJWTAuthorizer) => Promise<RagHttpResponse>;

const ERROR_STATUS = policy.technicalDefaults.errorHttpStatus as Readonly<Record<string, number>>;
const REQUEST_TIMEOUT_MS: number = policy.technicalDefaults.wire.requestTimeoutMs;
const JSON_HEADERS = Object.freeze({
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store',
});
const PUT_KEYS = ['accepted', 'version', 'expectedGeneration'] as const;
/** Base64 expands three bytes to four characters; used for the pre-decode size check. */
const MAX_BASE64_CHARS = Math.ceil(REQUEST_MAX_BYTES / 3) * 4 + 4;
const CANONICAL_BASE64 = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;
const encoder = new TextEncoder();

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
  if (encoder.encode(raw).byteLength > REQUEST_MAX_BYTES) throw new RagFailure('INPUT_TOO_LONG');
  if (!isValidUnicode(raw)) throw new RagFailure('INVALID_INPUT');
  return raw;
};

/**
 * Exact PUT body: no owner, no unknown key, the one consent version and a safe expected
 * generation. The shared contract scanner runs before `JSON.parse`, so a duplicated
 * `accepted`/`version`/`expectedGeneration` (raw or escaped) is INVALID_INPUT instead of the
 * silently-last duplicate `JSON.parse` would otherwise hand to the store.
 */
const parseConsentWrite = (body: string): ConsentWrite => {
  assertNoDuplicateKeys(body);
  let value: unknown;
  try {
    value = JSON.parse(body);
  } catch {
    throw new RagFailure('INVALID_INPUT');
  }
  if (!isRecord(value) || !hasExactKeys(value, PUT_KEYS)) throw new RagFailure('INVALID_INPUT');
  const accepted = value['accepted'];
  const version = value['version'];
  const expected = value['expectedGeneration'];
  if (typeof accepted !== 'boolean' || version !== CONSENT_VERSION) throw new RagFailure('INVALID_INPUT');
  if (!isSafeInteger(expected) || expected < 0 || expected >= Number.MAX_SAFE_INTEGER) {
    throw new RagFailure('INVALID_INPUT');
  }
  return Object.freeze({ accepted, version, expectedGeneration: expected });
};

const errorEnvelope = (requestId: string, code: ErrorCode): RagHttpResponse =>
  Object.freeze({
    statusCode: ERROR_STATUS[code] ?? 503,
    headers: JSON_HEADERS,
    body: JSON.stringify({ wireVersion: WIRE_VERSION, requestId, status: 'ERROR', code }),
  });

/** Rebuilds the envelope from the validated grant only, so the wire shape stays exact. */
const respond = (requestId: string, consent: ConsentGrant): RagHttpResponse =>
  Object.freeze({
    statusCode: 200,
    headers: JSON_HEADERS,
    body: JSON.stringify({
      wireVersion: WIRE_VERSION,
      requestId,
      consent: { accepted: consent.accepted, version: consent.version, generation: consent.generation },
    }),
  });

const safeRequestId = (factory: () => string): string => {
  try {
    const candidate = factory();
    if (isValidIdentifier(candidate)) return candidate;
  } catch {
    // fall through to a server-generated correlation id
  }
  return randomUUID();
};

export function createConsentHandler(deps: ConsentHandlerDeps): ConsentHandler {
  if (
    !isRecord(deps) ||
    !isRecord(deps['store']) ||
    typeof deps['store']['read'] !== 'function' ||
    typeof deps['store']['write'] !== 'function' ||
    typeof deps['assertActor'] !== 'function'
  ) {
    throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
  const { store, assertActor } = deps;
  const parent = deps.signal;
  if (parent !== undefined && !(parent instanceof AbortSignal)) {
    throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
  const nextId: () => string = deps.requestId ?? randomUUID;

  return async (event) => {
    const id = safeRequestId(nextId);
    // The deadline starts before any store read/write; an enclosing signal (when supplied) can
    // only shorten it, so a total budget that began at admission still covers this endpoint.
    const deadline = new RequestDeadline(REQUEST_TIMEOUT_MS, Date.now, parent);
    try {
      // Wrong path: API Gateway normally answers 404 before the Lambda; this defensive guard
      // keeps the same meaning if the integration is ever widened.
      if (event.rawPath !== CONSENT_PATH) throw new RagFailure('SCOPE_DENIED');
      const actor = accessTokenActor(event);
      assertActor(actor);
      const method = methodOf(event);
      if (method === 'GET') return respond(id, await deadline.within(() => store.read(actor, deadline.signal)));
      if (method !== 'PUT') throw new RagFailure('INVALID_INPUT');
      if (!isJsonUtf8(headerOf(event, 'content-type'))) throw new RagFailure('INVALID_INPUT');
      const next = parseConsentWrite(readRawBody(event));
      return respond(id, await deadline.within(() => store.write(actor, next, deadline.signal)));
    } catch (error) {
      return errorEnvelope(id, error instanceof RagFailure ? error.code : 'PROVIDER_UNAVAILABLE');
    } finally {
      deadline.close();
    }
  };
}
