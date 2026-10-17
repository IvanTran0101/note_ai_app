/**
 * Phase 3 AWS JSON transport: one SigV4-signed HTTPS POST per call, no SDK client, no retry.
 *
 * The port is deliberately narrow. The caller names a service and one whitelisted operation
 * path; it can never supply an endpoint, host or signing region. The region is validated at
 * construction, so a malformed value cannot reach the hostname, and the operation set is
 * closed: Bedrock is only `InvokeModel` for the policy embedding model, S3 Vectors is only the
 * four vector-bucket operations the indexing artifacts use.
 *
 * Credentials come from the AWS default provider chain (or are injected in tests) and are only
 * ever placed into signature headers. Failures collapse to an `IndexFailure` code plus a
 * retryable flag: only a timeout, HTTP 429 and HTTP 5xx may be retried. Provider response
 * bodies and credentials are never copied into an error, so no error can echo canonical text
 * or a secret — the caller only ever sees a code.
 *
 * Fixed endpoints (no caller input):
 *  - bedrock   -> https://bedrock-runtime.<region>.amazonaws.com
 *  - s3vectors -> https://s3vectors.<region>.api.aws
 */
import { Sha256 } from '@aws-crypto/sha256-js';
import { defaultProvider } from '@aws-sdk/credential-provider-node';
import { SignatureV4 } from '@smithy/signature-v4';
import legacyPolicy from '../../../docs/rag/policy_v1.json';
import { IndexFailure } from './types';

export type AwsService = 'bedrock' | 's3vectors';

/** The credential shape SigV4 needs; the SDK chain or an explicit test identity both fit. */
export type AwsCredentials = Readonly<{
  accessKeyId: string;
  secretAccessKey: string;
  sessionToken?: string;
}>;
export type AwsCredentialSource = AwsCredentials | (() => Promise<AwsCredentials>);

/** Exactly what the transport sends: fetch must be called once with this shape. */
export type AwsFetchInit = Readonly<{
  method: 'POST';
  headers: Readonly<Record<string, string>>;
  body: string;
  signal: AbortSignal;
}>;
export type AwsFetch = (url: string, init: AwsFetchInit) => Promise<Response>;

export type AwsJsonOptions = Readonly<{
  fetch?: AwsFetch;
  credentials?: AwsCredentialSource;
}>;

/** One signed JSON-protocol call. A retry belongs to the caller, never to this port. */
export type AwsJson = (
  service: AwsService,
  path: string,
  body: unknown,
  signal: AbortSignal,
  /**
   * Optional captured revalidation. Credential resolution and signing are awaited first, then
   * this callback runs, then the deadline is checked again, and only then does the transport
   * fetch. A callback failure (a typed SOURCE_CHANGED/CONSENT refusal) passes through untouched:
   * it is never remapped to UNAUTHORIZED by the credential/signing catch.
   */
  beforeDispatch?: () => Promise<void>,
) => Promise<unknown>;

/**
 * The only Bedrock operation this code may invoke; embedding.ts reuses the constant. Frozen to
 * the legacy policy_v1 Cohere model: the active EmbeddingGemma runtime is self-hosted HTTP and
 * must never widen or retarget this signed Bedrock whitelist.
 */
export const BEDROCK_INVOKE_MODEL_PATH =
  `/model/${encodeURIComponent(legacyPolicy.embedding.model)}/invoke`;

/** Operation whitelist: (service, exact path) pairs. Nothing else is signable or sendable. */
const OPERATIONS: Readonly<Record<AwsService, ReadonlySet<string>>> = Object.freeze({
  bedrock: new Set([BEDROCK_INVOKE_MODEL_PATH]),
  s3vectors: new Set(['/PutVectors', '/GetVectors', '/QueryVectors', '/DeleteVectors']),
});

const SIGNING_SERVICE: Readonly<Record<AwsService, string>> = Object.freeze({
  bedrock: 'bedrock',
  s3vectors: 's3vectors',
});

const HOSTS: Readonly<Record<AwsService, (region: string) => string>> = Object.freeze({
  bedrock: (region: string) => `bedrock-runtime.${region}.amazonaws.com`,
  s3vectors: (region: string) => `s3vectors.${region}.api.aws`,
});

/** Standard AWS region shape; dots/slashes/colons cannot pass, so the host stays fixed. */
const REGION = /^[a-z]{2,8}(?:-[a-z]+)+-\d{1,2}$/;
const MAX_REGION_LENGTH = 32;

export const isAwsRegion = (region: unknown): region is string =>
  typeof region === 'string' && region.length <= MAX_REGION_LENGTH && REGION.test(region);

const invalidInput: () => never = () => {
  throw new IndexFailure('INVALID_INPUT', false);
};

const invalidState: () => never = () => {
  throw new IndexFailure('INVALID_STATE', false);
};

/**
 * Failure taxonomy for an HTTP status. `aborted` wins: a caller deadline that fired is a
 * timeout even if the transport also reported a status. Everything unknown is terminal.
 */
export function failureForStatus(status: number, aborted = false): IndexFailure {
  if (aborted) return new IndexFailure('TIMEOUT', true);
  if (status === 408) return new IndexFailure('TIMEOUT', true);
  if (status === 429) return new IndexFailure('RATE_LIMITED', true);
  if (status >= 500) return new IndexFailure('PROVIDER_UNAVAILABLE', true);
  if (status === 401 || status === 403) return new IndexFailure('UNAUTHORIZED', false);
  if (status === 404 || status === 409) return new IndexFailure('INDEX_NOT_READY', false);
  if (status >= 400) return new IndexFailure('INVALID_INPUT', false);
  return new IndexFailure('PROVIDER_UNAVAILABLE', false);
}

/** Circular/unserializable bodies are refused before any signature or network work. */
const serialize = (body: unknown): string => {
  let text: string | undefined;
  try {
    text = JSON.stringify(body);
  } catch {
    invalidInput();
  }
  if (typeof text !== 'string' || text.length === 0) invalidInput();
  return text;
};

const requireSignal = (signal: unknown): AbortSignal => {
  if (!(signal instanceof AbortSignal)) invalidInput();
  return signal;
};

const requireOptions = (options: unknown): AwsJsonOptions => {
  if (options === undefined) return {};
  if (typeof options !== 'object' || options === null || Array.isArray(options)) invalidState();
  const candidate = options as AwsJsonOptions;
  if (candidate.fetch !== undefined && typeof candidate.fetch !== 'function') invalidState();
  const credentials = candidate.credentials;
  if (
    credentials !== undefined && typeof credentials !== 'function' &&
    (typeof credentials !== 'object' || credentials === null)
  ) {
    invalidState();
  }
  return candidate;
};

/**
 * Build the one-call JSON port for a region. Construction validates configuration; every call
 * re-validates its service, path, body and signal, signs once and fetches exactly once.
 */
export function createAwsJson(region: string, options?: AwsJsonOptions): AwsJson {
  if (!isAwsRegion(region)) invalidState();
  const resolved = requireOptions(options);
  const transport: AwsFetch = resolved.fetch ?? fetch;
  const credentials = resolved.credentials ?? defaultProvider();
  // Bedrock is a normal SigV4 service (path escaped once for the URL, once for the canonical
  // request); S3 Vectors is S3-family single-encoding. Every whitelisted path segment is a
  // plain ASCII token, so the two rules coincide on the operations reachable from here.
  const signers: Readonly<Record<AwsService, SignatureV4>> = Object.freeze({
    bedrock: new SignatureV4({
      service: SIGNING_SERVICE.bedrock, region, sha256: Sha256, credentials, uriEscapePath: true,
    }),
    s3vectors: new SignatureV4({
      service: SIGNING_SERVICE.s3vectors, region, sha256: Sha256, credentials, uriEscapePath: false,
    }),
  });

  return async (service, path, body, signal, beforeDispatch) => {
    if (service !== 'bedrock' && service !== 's3vectors') invalidInput();
    if (typeof path !== 'string' || !OPERATIONS[service].has(path)) invalidInput();
    const deadline = requireSignal(signal);
    if (deadline.aborted) throw new IndexFailure('TIMEOUT', true);
    const payload = serialize(body);
    const host = HOSTS[service](region);

    let request;
    try {
      request = await signers[service].sign({
        method: 'POST',
        protocol: 'https:',
        hostname: host,
        path,
        headers: { host, 'content-type': 'application/json' },
        body: payload,
      });
    } catch {
      // Credential resolution or signing failed: a configuration/access problem, not a replay.
      if (deadline.aborted) throw new IndexFailure('TIMEOUT', true);
      throw new IndexFailure('UNAUTHORIZED', false);
    }

    // Signing is async (credential resolution included): the captured revalidation runs here,
    // after the signature exists and immediately before the fetch, so a withdrawal during that
    // window is refused with its own typed code rather than mapped to an access failure.
    if (deadline.aborted) throw new IndexFailure('TIMEOUT', true);
    if (typeof beforeDispatch === 'function') await beforeDispatch();
    if (deadline.aborted) throw new IndexFailure('TIMEOUT', true);

    let response: Response;
    try {
      response = await transport(`https://${host}${path}`, {
        method: 'POST',
        headers: request.headers,
        body: payload,
        signal: deadline,
      });
    } catch {
      if (deadline.aborted) throw new IndexFailure('TIMEOUT', true);
      throw new IndexFailure('PROVIDER_UNAVAILABLE', false);
    }
    if (!response.ok) throw failureForStatus(response.status, deadline.aborted);

    let text: string;
    try {
      text = await response.text();
    } catch {
      if (deadline.aborted) throw new IndexFailure('TIMEOUT', true);
      throw new IndexFailure('PROVIDER_UNAVAILABLE', false);
    }
    if (text.length === 0) return {};
    try {
      return JSON.parse(text) as unknown;
    } catch {
      // The raw payload is never surfaced: it may contain canonical text or a provider secret.
      throw new IndexFailure('INVALID_PROVIDER_OUTPUT', false);
    }
  };
}
