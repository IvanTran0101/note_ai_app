/**
 * Phase 5 pilot query composition (plan 5.1B/5.1D, contract §8): the one HTTP-facing query runner
 * that ties the trusted `CONFIG#PHASE5` permit to the existing canonical pipeline.
 *
 * The outer 26s deadline starts before the config read, the approval read and the index/tokenizer
 * composition, so a cold start cannot run unbounded. Admission is the enabled+listed pilot actor
 * from the freshly read config; the config identity is then re-checked by the guarded index store
 * before every paid stage. The canonical pipeline still owns authority/revalidation/JEV/generation;
 * this module only reuses it, with two additions: the atomic query lease is acquired inside
 * `consumeQuota` (after canonical authorization) and released in a `finally` under an independent
 * 1.5s deadline, and JEV/DeepSeek reservations are made before the single raw provider call.
 *
 * Nothing is mocked here and no raw provider is constructed here: the caller injects the SDK-backed
 * clients, the budget and the raw providers, so the builder is fully testable offline.
 */
import { WIRE_VERSION, isValidIdentifier } from '../contract';
import { RequestDeadline } from '../deadline';
import { createQueryPorts } from '../indexing/query_ports';
import type { IndexDeps, IndexStore } from '../indexing/types';
import { LIVE_TOTAL_DEADLINE_MS } from '../live_policy';
import type { LiveApproval } from '../live_policy';
import { createQuery } from '../pipeline';
import { DEEPSEEK_SYSTEM_PROMPT } from '../providers/deepseek';
import { deepFreeze } from '../query_diagnostics';
import type { DiagnosticMetadata } from '../query_diagnostics';
import { deepSeekInputUpperBound, jevInputUpperBound } from '../token_fit';
import { RagFailure } from '../types';
import type { Counters, ErrorCode, Providers, RagRequest, RagResponse } from '../types';
import type { PilotBudget, QueryLease } from './pilot_budget';
import { createPilotIndexStore } from './pilot_index_store';
import { assertPilotActor } from './pilot_policy';
import type { RuntimeConfig } from './runtime_config';

/** Same 32k JEV bound and 1024-token output cap the private Phase 4 adapter pins. */
export const PILOT_JEV_MAX_TOKENS = 32_000;
/** Release runs after the outer deadline may already be aborted; it gets its own short budget. */
export const PILOT_RELEASE_TIMEOUT_MS = 1_500;

export type PilotQueryDeps = Readonly<{
  /** Trusted server-only config reader; one strongly consistent read per call. */
  readConfig: (signal: AbortSignal) => Promise<RuntimeConfig>;
  /** Existing `readPublishedApproval`; evaluated per request, never widened here. */
  readApproval: (signal: AbortSignal) => Promise<LiveApproval>;
  /** Lazily returns the SDK/tokenizer index; may safely be a cached factory. */
  loadIndex: () => IndexDeps;
  /** Pilot budget: lease, JEV/DeepSeek reservation and the atomic embedding admission. */
  budget: PilotBudget;
  /** Raw JEV/DeepSeek ports; reserved by this module before each single call. */
  rawProviders: Providers;
  /** Token counters; the embedding counter always comes from the loaded index. */
  counters: Omit<Counters, 'embedding'>;
  /**
   * Optional enclosing request deadline from the production entry. The per-call 26s deadline is
   * parented to it, so cold counter/provider composition that the entry runs before this builder
   * still shares the one request budget. Local-only: never serialized on the wire.
   */
  parentSignal?: AbortSignal;
  /** Safe bounded metadata sink (stage/codes/counts and typed trace arrays); never raw text/ids. */
  log?: (metadata: DiagnosticMetadata) => void;
}>;

export type PilotQuery = (actor: string, request: RagRequest, requestId: string) => Promise<RagResponse>;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const failure = (requestId: string, code: ErrorCode): RagResponse =>
  Object.freeze({ wireVersion: WIRE_VERSION, requestId, status: 'ERROR', code });

const logSafely = (
  deps: PilotQueryDeps,
  metadata: DiagnosticMetadata,
): void => {
  try {
    // Typed arrays/objects pass through; every nested value is frozen for the sink.
    deps.log?.(deepFreeze({ ...metadata }));
  } catch {
    // Logging must never change a request outcome.
  }
};

/** Releases the lease only when the token still matches; a stale/expired lease is a silent no-op. */
const releaseLease = async (deps: PilotQueryDeps, lease: QueryLease): Promise<void> => {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), PILOT_RELEASE_TIMEOUT_MS);
  const expired = new Promise<never>((_resolve, reject) => {
    controller.signal.addEventListener('abort', () => reject(new RagFailure('TIMEOUT')), { once: true });
  });
  try {
    // Race the independent deadline too: a port that ignores the abort signal still cannot hold
    // the request open past the release budget.
    await Promise.race([deps.budget.release(lease, controller.signal), expired]);
  } catch (error) {
    logSafely(deps, {
      stage: 'query-lease-release',
      code: error instanceof RagFailure ? error.code : 'PROVIDER_UNAVAILABLE',
    });
  } finally {
    clearTimeout(timer);
  }
};

/** One reservation before one raw provider call; a refused reservation never reaches the provider. */
const reserveProviders = (deps: PilotQueryDeps): Providers =>
  Object.freeze({
    jev: async (input, signal, beforeDispatch) => {
      await deps.budget.reserve('jev', jevInputUpperBound(JSON.stringify(input)), signal);
      // The reservation is async; re-validate the captured context once more before the raw call
      // so a permit/consent/source change during the reservation never reaches the provider.
      if (typeof beforeDispatch === 'function') await beforeDispatch();
      return deps.rawProviders.jev(input, signal);
    },
    generate: async (input, signal, beforeDispatch) => {
      const bound = deepSeekInputUpperBound(
        DEEPSEEK_SYSTEM_PROMPT + JSON.stringify({ question: input.question, evidence: input.evidence.text }),
      );
      if (bound > PILOT_JEV_MAX_TOKENS) throw new RagFailure('INPUT_TOO_LONG');
      await deps.budget.reserve('deepseek', bound, signal);
      if (typeof beforeDispatch === 'function') await beforeDispatch();
      return deps.rawProviders.generate(input, signal);
    },
  });

const hasDeps = (value: unknown): value is PilotQueryDeps => {
  if (!isRecord(value)) return false;
  const budget = value['budget'];
  const rawProviders = value['rawProviders'];
  const counters = value['counters'];
  return (
    typeof value['readConfig'] === 'function' &&
    typeof value['readApproval'] === 'function' &&
    typeof value['loadIndex'] === 'function' &&
    isRecord(budget) &&
    typeof budget['acquireQuery'] === 'function' &&
    typeof budget['release'] === 'function' &&
    typeof budget['reserve'] === 'function' &&
    typeof budget['acquireEmbedding'] === 'function' &&
    isRecord(rawProviders) &&
    typeof rawProviders['jev'] === 'function' &&
    typeof rawProviders['generate'] === 'function' &&
    isRecord(counters) &&
    typeof counters['evidence'] === 'function' &&
    typeof counters['jev'] === 'function' &&
    typeof counters['output'] === 'function' &&
    (value['parentSignal'] === undefined || value['parentSignal'] instanceof AbortSignal)
  );
};

/**
 * Builds the pilot query over injected ports. Every invocation captures its own outer deadline,
 * fresh config, fresh approval and a fresh guarded store/pipeline; nothing captured for one
 * request is reused for another.
 */
export function createPilotQuery(deps: PilotQueryDeps): PilotQuery {
  if (!hasDeps(deps)) throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');

  return async function query(actor, request, requestId): Promise<RagResponse> {
    if (!isValidIdentifier(requestId)) throw new RagFailure('INVALID_INPUT');
    const deadline = new RequestDeadline(LIVE_TOTAL_DEADLINE_MS, Date.now, deps.parentSignal);
    let lease: QueryLease | null = null;
    try {
      // Initial trusted permit: read the config and require an enabled, listed actor before any
      // canonical body/index/tokenizer composition.
      const config = await deadline.within(() => deps.readConfig(deadline.signal));
      assertPilotActor(config.policy, actor);
      const approval = await deadline.within(() => deps.readApproval(deadline.signal));

      const index = deps.loadIndex();
      const store: IndexStore = createPilotIndexStore({
        store: index.store,
        budget: deps.budget,
        readConfig: deps.readConfig,
        config,
      });
      const ports = createQueryPorts({ ...index, store });
      const counters: Counters = Object.freeze({
        embedding: index.embedding.count,
        evidence: deps.counters.evidence,
        jev: deps.counters.jev,
        output: deps.counters.output,
      });
      const run = createQuery({
        authority: ports.authority,
        retrieval: ports.retrieval,
        providers: reserveProviders(deps),
        counters,
        config: Object.freeze({
          mode: 'live',
          model: config.policy.model,
          thresholds: config.policy.thresholds,
          jevMaxTokens: PILOT_JEV_MAX_TOKENS,
          requestTimeoutMs: LIVE_TOTAL_DEADLINE_MS,
        }),
        liveApproval: approval,
        pilotPolicy: config.policy,
        signal: deadline.signal,
        // Reuse the existing bounded sink; the pipeline freezes an allowlisted event and swallows
        // sink failures, so the production JSON console logger can never change the response.
        onDiagnostic: (diagnostic) => logSafely(deps, diagnostic),
        consumeQuota: async (quotaActor, signal) => {
          lease = await deps.budget.acquireQuery(quotaActor, requestId, signal);
          return true;
        },
      });
      return await run(actor, request, requestId);
    } catch (error) {
      return failure(requestId, error instanceof RagFailure ? error.code : 'PROVIDER_UNAVAILABLE');
    } finally {
      if (lease !== null) await releaseLease(deps, lease);
      deadline.close();
    }
  };
}
