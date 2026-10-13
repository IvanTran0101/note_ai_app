/**
 * Phase 5 backend core slice public surface (plan 5.1A/5.1C/5.1D).
 *
 * The root composes these modules into the RAG stack: `readPilotPolicy`/`assertPilotActor`
 * gate admission, `createConsentStore` + `createConsentHandler` serve
 * `GET|PUT /ai/rag/consent`, and `createPilotBudget` owns every pilot counter atomically.
 * `createRuntimeConfigReader` reads the trusted `CONFIG#PHASE5`/`PILOT` row and
 * `createPilotIndexStore` wraps the existing `IndexStore` with the pilot scope permit.
 * Nothing here is wired or enabled by itself; the shipped policy stays closed.
 */
export {
  MAX_PILOT_OWNERS, PILOT_MODEL, PILOT_THRESHOLDS,
  allowsIndexOwner, assertPilotActor, isCognitoSub, isPilotOwner, readPilotPolicy,
} from './pilot_policy';
export type { PilotPolicy } from './pilot_policy';

export { DEFAULT_CONSENT, consentRowKey, createConsentStore } from './consent_store';
export type {
  ConsentCommand, ConsentGrant, ConsentGuard, ConsentPort, ConsentSendOptions, ConsentStore, ConsentWrite,
} from './consent_store';

export { CONSENT_PATH, createConsentHandler } from './consent_handler';
export type { ConsentHandler, ConsentHandlerDeps } from './consent_handler';

export {
  GLOBAL_EMBEDDING_KEY, GLOBAL_EMBEDDING_LIMIT, PILOT_BUDGET_KEY, PILOT_DAILY_QUERY_LIMIT, PILOT_LIMITS,
  PILOT_QUERY_LEASE_MS, PILOT_USD_MICROS_LIMIT, createPilotBudget,
} from './pilot_budget';
export type {
  PilotBudget, PilotBudgetCounters, PilotBudgetOptions, PilotBudgetPort, PilotCommand, PilotProvider,
  PilotSendOptions, QueryLease,
} from './pilot_budget';

export {
  RUNTIME_CASE_HASH, RUNTIME_CONFIG_KEY, RUNTIME_CONFIG_VERSION, RUNTIME_CORPUS_KIND,
  createRuntimeConfigReader, parseRuntimeConfig, sameRuntimeConfig,
} from './runtime_config';
export type {
  RuntimeConfig, RuntimeConfigReader, RuntimeConfigReaderOptions, RuntimeConfigReaderPort,
  RuntimeConfigSendOptions, RuntimeCorpusNote,
} from './runtime_config';

export { createPilotIndexStore } from './pilot_index_store';
export type { PilotIndexStoreDeps } from './pilot_index_store';

export { PILOT_JEV_MAX_TOKENS, PILOT_RELEASE_TIMEOUT_MS, createPilotQuery } from './pilot_query';
export type { PilotQuery, PilotQueryDeps } from './pilot_query';

export { composeProduction, createDefaultHandler, createPilotHttpHandler, handler } from './http_lambda';
export type { PilotHttpDeps, PilotHttpHandler, PilotProductionSeam } from './http_lambda';

export { PILOT_RECOVER_MS, createPilotWorkerHandler, sanitizePilotMetadata } from './pilot_worker';
export type { PilotRecover, PilotWorkerDeps, PilotWorkerHandler } from './pilot_worker';
