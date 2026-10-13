/**
 * Phase 5 HTTP production entry (plan 5.1B/5.1E): the real Lambda handler behind
 * `POST /ai/rag/query` and `GET|PUT /ai/rag/consent`.
 *
 * The API Gateway HTTP API JWT authorizer validates the Cognito access token before the Lambda
 * runs; inside, the actor is only `requestContext.authorizer.jwt.claims.sub` with
 * `token_use === 'access'` (enforced by the injected `createRagHandler`/`createConsentHandler`).
 * No path, method, query parameter or body field can select a private operation: an HTTP request
 * is routed only to the two canonical handlers, and a non-HTTP invocation (the IAM-invoked Phase 4
 * synthetic harness) is forwarded unchanged to the existing `private_lambda.handler` **before any
 * Phase 5 composition**.
 *
 * Routing is first and setup is lazy:
 *  - non-HTTP -> the private Phase 4 handler, with zero Phase 5 setup (no tokenizer, key or table
 *    requirement);
 *  - consent -> the notes-table consent store plus the state-table config reader, no
 *    tokenizer/provider/key requirement;
 *  - query   -> one request deadline started **before** the cold counter/provider composition,
 *    which is cached once per process and shared by every request.
 *
 * `createPilotHttpHandler` is the injectable boundary: tests assemble it with mock query/consent
 * handlers and assert routing/envelopes without any AWS, environment or model call. The default
 * entry never resolves, prints or persists a secret value.
 */
import { randomUUID } from 'node:crypto';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import type { APIGatewayProxyEventV2WithJWTAuthorizer } from 'aws-lambda';
import { RequestDeadline } from '../deadline';
import { isValidIdentifier } from '../contract';
import { createRagHandler } from '../handler';
import type { RagHttpResponse, RagQuery } from '../handler';
import { runtime } from '../indexing/runtime';
import type { IndexDeps } from '../indexing/types';
import { createDeepSeekProvider } from '../providers/deepseek';
import { createJevProvider, type ProviderUsage } from '../providers/jev';
import { jevInputUpperBound, loadDeepSeekCounter } from '../token_fit';
import { policy, RagFailure } from '../types';
import type { Counter, ErrorCode, Providers } from '../types';
import type { LiveApproval } from '../live_policy';
import { handler as privateHandler, readPublishedApproval } from '../private_lambda';
import { CONSENT_PATH, createConsentHandler } from './consent_handler';
import type { ConsentHandler } from './consent_handler';
import { createConsentStore } from './consent_store';
import type { ConsentGuard } from './consent_store';
import { isPilotOwner } from './pilot_policy';
import { createPilotBudget } from './pilot_budget';
import type { PilotBudget, PilotBudgetPort } from './pilot_budget';
import { createPilotQuery } from './pilot_query';
import { RUNTIME_CONFIG_KEY, createRuntimeConfigReader, sameRuntimeConfig } from './runtime_config';

export type PilotHttpDeps = Readonly<{
  /** The pilot query runner (`createPilotQuery(...)`), wrapped by `createRagHandler`. */
  query: RagQuery;
  /**
   * Builds the consent handler under the request's outer deadline. The factory runs inside that
   * deadline, so a permission/config read during construction is covered by the total budget.
   */
  consent: (signal: AbortSignal) => Promise<ConsentHandler> | ConsentHandler;
  /** Non-HTTP invocations (IAM private Phase 4) are forwarded here; never reachable over HTTP. */
  privateHandler?: (event: unknown) => Promise<unknown>;
  requestId?: () => string;
  /** Test seam; the default composition uses `Date.now`. */
  now?: () => number;
}>;
export type PilotHttpHandler = (event: unknown) => Promise<unknown>;

/**
 * Small test seam for the default production composition. It substitutes the shared SDK client
 * and the heavy cold factories — the routing, table selection and lazy ordering are the same
 * production code path, not an environment/test bypass.
 */
export type PilotProductionSeam = Readonly<{
  /** Builds the one document client shared by config, approval, budget and consent ports. */
  client?: (region: string) => PilotBudgetPort;
  /** Loads the indexed authority/embedding deps; default is the cached `runtime()`. */
  loadIndex?: () => IndexDeps;
  /** Loads the DeepSeek output counter; default reads the pinned tokenizer directory. */
  countOutput?: (directory: string) => Counter;
  /** Replaces the Phase 4 published-approval read; default is the real reader on the state table. */
  readApproval?: (signal: AbortSignal) => Promise<LiveApproval>;
  /** Replaces the raw JEV/DeepSeek ports; default builds them from the environment API keys. */
  rawProviders?: Providers;
  privateHandler?: (event: unknown) => Promise<unknown>;
  requestId?: () => string;
  now?: () => number;
}>;

const RAG_PATH: string = policy.technicalDefaults.wire.route;
const REQUEST_TIMEOUT_MS: number = policy.technicalDefaults.wire.requestTimeoutMs;
const ERROR_STATUS = policy.technicalDefaults.errorHttpStatus as Readonly<Record<string, number>>;
const JSON_HEADERS = Object.freeze({
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store',
});

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const isHttpEvent = (value: unknown): value is APIGatewayProxyEventV2WithJWTAuthorizer =>
  isRecord(value) &&
  typeof value['rawPath'] === 'string' &&
  isRecord(value['requestContext']) &&
  isRecord(value['requestContext']['http']);

const errorEnvelope = (requestId: string, code: ErrorCode): RagHttpResponse =>
  Object.freeze({
    statusCode: ERROR_STATUS[code] ?? 503,
    headers: JSON_HEADERS,
    body: JSON.stringify({ wireVersion: 1, requestId, status: 'ERROR', code }),
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

/**
 * The one router. HTTP events reach only the canonical query/consent handlers; every other
 * invocation is the IAM private Phase 4 harness. An unknown HTTP path is refused with the same
 * bounded envelope and never reaches a handler or a provider.
 */
export function createPilotHttpHandler(deps: PilotHttpDeps): PilotHttpHandler {
  if (
    !isRecord(deps) ||
    typeof deps['query'] !== 'function' ||
    typeof deps['consent'] !== 'function' ||
    (deps['privateHandler'] !== undefined && typeof deps['privateHandler'] !== 'function')
  ) {
    throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
  const nextId: () => string = deps.requestId ?? randomUUID;
  const now: () => number = deps.now ?? Date.now;
  const queryHandler = createRagHandler(deps.query, nextId);

  return async function handle(event: unknown): Promise<unknown> {
    const id = safeRequestId(nextId);
    if (!isHttpEvent(event)) {
      const forward = deps.privateHandler;
      if (forward === undefined) return { status: 'ERROR', code: 'LIVE_POLICY_NOT_CONFIGURED' };
      return forward(event);
    }
    if (event.rawPath !== RAG_PATH && event.rawPath !== CONSENT_PATH) {
      return errorEnvelope(id, 'SCOPE_DENIED');
    }
    if (event.rawPath === CONSENT_PATH) {
      const deadline = new RequestDeadline(REQUEST_TIMEOUT_MS, now);
      try {
        const consent = await deadline.within(() => Promise.resolve(deps.consent(deadline.signal)));
        return await deadline.within(() => consent(event));
      } catch (error) {
        return errorEnvelope(id, error instanceof RagFailure ? error.code : 'PROVIDER_UNAVAILABLE');
      } finally {
        deadline.close();
      }
    }
    return queryHandler(event);
  };
}

const required = (name: string): string => {
  const value = process.env[name];
  if (!value || value.includes('<value will be resolved')) throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  return value;
};

const defaultClient = (region: string): PilotBudgetPort =>
  DynamoDBDocumentClient.from(new DynamoDBClient({ region, maxAttempts: 1 }));

/**
 * Builds the real HTTP dependencies. Only the region and the two table names are read here; the
 * DeepSeek counter, provider ports and budget are composed lazily inside the query path, so a
 * consent or unknown-path request never needs a tokenizer or an API key.
 */
export function composeProduction(seam: PilotProductionSeam = {}): PilotHttpDeps {
  const region = required('RAG_REGION');
  const stateTable = required('RAG_STATE_TABLE');
  const notesTable = required('RAG_NOTES_TABLE');
  const client: PilotBudgetPort = (seam.client ?? defaultClient)(region);
  const configReader = createRuntimeConfigReader({ region, stateTable, client });
  const readConfig = (signal: AbortSignal) => configReader.read(signal);
  const readApproval = seam.readApproval ??
    ((signal: AbortSignal) =>
      readPublishedApproval(client as unknown as Parameters<typeof readPublishedApproval>[0], stateTable, signal));
  let index: IndexDeps | undefined;
  const loadIndex = (): IndexDeps => (index ??= (seam.loadIndex ?? runtime)());
  const now: () => number = seam.now ?? Date.now;

  let heavy: Readonly<{ budget: PilotBudget; countOutput: Counter; rawProviders: Providers }> | undefined;
  /** Cold composition, executed at most once per process and only from inside a query deadline. */
  const heavyNow = (): Readonly<{ budget: PilotBudget; countOutput: Counter; rawProviders: Providers }> => {
    if (heavy === undefined) {
      const countOutput = seam.countOutput !== undefined
        ? seam.countOutput(process.env['RAG_DEEPSEEK_TOKENIZER_DIR'] ?? '')
        : loadDeepSeekCounter(required('RAG_DEEPSEEK_TOKENIZER_DIR'));
      const usage: ProviderUsage[] = [];
      const onUsage = (entry: ProviderUsage) => console.log(JSON.stringify({ stage: 'provider-usage', ...entry }));
      const rawProviders: Providers = seam.rawProviders ?? {
        jev: createJevProvider({ apiKey: required('TYPESAFE_API_KEY'), onUsage }),
        generate: createDeepSeekProvider({
          apiKey: required('DEEPSEEK_API_KEY'),
          onUsage,
          onDiagnostic: (entry) => console.log(JSON.stringify({ stage: 'generation-invalid-shape', ...entry })),
        }),
      };
      heavy = Object.freeze({
        budget: createPilotBudget(region, stateTable, client, { now }),
        countOutput,
        rawProviders,
      });
    }
    return heavy;
  };

  const queryRun = (parent: AbortSignal): RagQuery => {
    const built = heavyNow();
    return createPilotQuery({
      readConfig,
      readApproval,
      loadIndex,
      budget: built.budget,
      rawProviders: built.rawProviders,
      counters: { evidence: built.countOutput, jev: jevInputUpperBound, output: built.countOutput },
      parentSignal: parent,
      log: (metadata) => console.log(JSON.stringify(metadata)),
    });
  };

  /**
   * The one request deadline starts here, before the cold composition below; `within` re-checks
   * the wall clock after that synchronous work, so a CPU block that outlives the budget can never
   * be followed by a paid canonical or provider dispatch.
   *
   * The runner is then awaited directly, never raced against that signal: it owns its own child
   * deadline parented to `deadline.signal`, and its `finally` awaits the independent bounded lease
   * release. Racing it away would return the wire response at the 26s abort while the release is
   * still in flight, so a frozen Lambda could lose the lease progress. The parent signal still
   * bounds the run, and the release keeps its own short independent budget.
   */
  const query: RagQuery = async (actor, request, requestId) => {
    const deadline = new RequestDeadline(REQUEST_TIMEOUT_MS, now);
    try {
      const run = await deadline.within(() => Promise.resolve(queryRun(deadline.signal)));
      return await run(actor, request, requestId);
    } finally {
      deadline.close();
    }
  };

  const consent = async (signal: AbortSignal): Promise<ConsentHandler> => {
    const config = await readConfig(signal);
    // Membership, not admission: a listed owner can always GET/revoke while admission is off.
    const assertActor = (actor: string) => {
      if (!isPilotOwner(config.policy, actor)) throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
    };
    // The exact captured config rides into the write transaction; every read/write re-validates
    // the whole captured identity against a fresh config, so a removal, generation move or corpus
    // change cannot use a stale permit.
    const guard: ConsentGuard = {
      table: stateTable,
      key: RUNTIME_CONFIG_KEY,
      value: config,
      revalidate: async (actor: string, io: AbortSignal) => {
        const fresh = await readConfig(io);
        // Membership first: a removed actor is denied even when the config identity also moved.
        if (!isPilotOwner(fresh.policy, actor)) throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
        // The captured whole-config identity is the permit. A generation/corpus/policy move is a
        // source change, never a stale success. The write transaction may already have committed,
        // so this reports the move; it never rolls back, revokes or refunds anything.
        if (!sameRuntimeConfig(config, fresh)) throw new RagFailure('SOURCE_CHANGED');
      },
    };
    return createConsentHandler({
      store: createConsentStore(region, notesTable, client, guard),
      assertActor,
      signal,
    });
  };

  return {
    query,
    consent,
    privateHandler: seam.privateHandler ?? privateHandler,
    requestId: seam.requestId,
    now,
  };
}

/**
 * The default Lambda entry: route first, compose lazily. A non-HTTP invocation never triggers any
 * Phase 5 setup, so the private IAM path keeps working with only its own environment.
 */
export function createDefaultHandler(seam: PilotProductionSeam = {}): PilotHttpHandler {
  let composed: PilotHttpHandler | undefined;
  return async function handle(event: unknown): Promise<unknown> {
    const id = safeRequestId(seam.requestId ?? randomUUID);
    if (!isHttpEvent(event)) {
      const forward = seam.privateHandler ?? privateHandler;
      try {
        return await forward(event);
      } catch (error) {
        return { status: 'ERROR', code: error instanceof RagFailure ? error.code : 'LIVE_POLICY_NOT_CONFIGURED' };
      }
    }
    if (event.rawPath !== RAG_PATH && event.rawPath !== CONSENT_PATH) {
      return errorEnvelope(id, 'SCOPE_DENIED');
    }
    try {
      composed ??= createPilotHttpHandler(composeProduction(seam));
      return await composed(event);
    } catch (error) {
      return errorEnvelope(id, error instanceof RagFailure ? error.code : 'LIVE_POLICY_NOT_CONFIGURED');
    }
  };
}

/** Default Lambda entry: lazy environment composition, HTTP routing and the private fallback. */
export const handler: PilotHttpHandler = createDefaultHandler();
