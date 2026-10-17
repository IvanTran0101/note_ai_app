/**
 * Pure planning core for the reviewed EmbeddingGemma profile rebind: frozen 75a90b0 legacy
 * hashing, reviewed-source binding, the next disabled config and the shared budget proof.
 * No AWS calls, filesystem, process or model access lives here; the CLI adapts those ports.
 */
import { isEligibleNote } from '../../amplify/rag/authority';
import { chunkNote, isSafeInteger, isWellFormed } from '../../amplify/rag/chunking';
import { embeddingInputDigest, policyIdentity, sha256Hex } from '../../amplify/rag/indexing/snapshot';
import type { IndexState } from '../../amplify/rag/indexing/types';
import { GLOBAL_EMBEDDING_LIMIT, PILOT_EMBEDDING_LIMIT,
  type PilotBudgetCounters } from '../../amplify/rag/phase5/pilot_budget';
import {
  parseRuntimeConfig, RUNTIME_CONFIG_KEY, RUNTIME_CORPUS_KIND, type RuntimeConfig,
} from '../../amplify/rag/phase5/runtime_config';
import type { Counter } from '../../amplify/rag/types';
import policyV1 from '../../docs/rag/policy_v1.json';
import legacyTokenizerManifest from '../../docs/rag/tokenizer_manifest.json';

export const MIGRATION_PROFILE = 'noteflow-dev';
export const MIGRATION_REGION = 'ap-southeast-1';
export const MIGRATION_ACCOUNT = '864946423771';
export const MIGRATION_CONSENT_VERSION = 'rag-consent.v2';
export const EMBED_BATCH_SIZE = 1;
export const PLANNED_CANARY_CALLS = 1;
export const PLANNED_GOLD_QUERIES = 20;
export const PLANNED_SMOKES = 3;
export const EXPECTED_APPROVED_NOTE_COUNT = 6;
export const EXPECTED_STATE_TABLE =
  'amplify-noteaiapp-noteflowsmoke-sandbox-98162ed7f2-SyncStackB3B4A43F-3HR13CIGYKMT-RagStateEB1783ED-12Q9N5QXYCBAF';
export const EXPECTED_NOTES_TABLE =
  'amplify-noteaiapp-noteflowsmoke-sandbox-98162ed7f2-SyncStackB3B4A43F-3HR13CIGYKMT-NotesTableD0D0D2F1-1X9H8LYT3PNZ4';

export type MigrationTarget = Readonly<{
  profile: string; region: string; account: string; stateTable: string; notesTable: string;
}>;
export const DEFAULT_TARGET: MigrationTarget = Object.freeze({
  profile: MIGRATION_PROFILE,
  region: MIGRATION_REGION,
  account: MIGRATION_ACCOUNT,
  stateTable: EXPECTED_STATE_TABLE,
  notesTable: EXPECTED_NOTES_TABLE,
});

export class MigrationRefusal extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = 'MigrationRefusal';
  }
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

export const refuse = (code: string): never => { throw new MigrationRefusal(code); };

const LEGACY_INPUT_DOMAIN = 'rag-embedding-input.v1';
/** Frozen 75a90b0 lexical constants; pinned so a later keyword change cannot move the old hash. */
export const LEGACY_LEXICAL = Object.freeze({
  analyzer: 'rag-analyzer.v1', k1: 1.2, b: 0.75,
});

/** Exact frozen 75a90b0 algorithm: policy_v1 fields, old tokenizer manifest, pinned lexical constants. */
export function legacyPolicyIdentityFor(policyV1Value: unknown, tokenizerManifest: unknown): string {
  if (!isRecord(policyV1Value) || !isRecord(policyV1Value['embedding']) ||
      !isRecord(policyV1Value['chunking']) || !isRecord(policyV1Value['technicalDefaults']) ||
      !isRecord(tokenizerManifest)) {
    return refuse('LEGACY_POLICY_UNREADABLE');
  }
  const embedding = policyV1Value['embedding'];
  const technical = policyV1Value['technicalDefaults'];
  if (typeof embedding['model'] !== 'string' || typeof embedding['dimensions'] !== 'number' ||
      typeof embedding['documentInputType'] !== 'string' ||
      typeof embedding['queryInputType'] !== 'string' || typeof embedding['truncate'] !== 'string' ||
      typeof technical['offsetUnit'] !== 'string' || typeof technical['spanEnd'] !== 'string' ||
      typeof technical['embeddingText'] !== 'string') {
    return refuse('LEGACY_POLICY_UNREADABLE');
  }
  const fields = {
    tokenizer: tokenizerManifest,
    lexical: LEGACY_LEXICAL,
    model: embedding['model'],
    dimensions: embedding['dimensions'],
    documentInputType: embedding['documentInputType'],
    queryInputType: embedding['queryInputType'],
    truncate: embedding['truncate'],
    chunking: { ...policyV1Value['chunking'] },
    offsetUnit: technical['offsetUnit'],
    spanEnd: technical['spanEnd'],
    embeddingText: technical['embeddingText'],
  };
  return sha256Hex(JSON.stringify(fields));
}

export const LEGACY_POLICY_IDENTITY = legacyPolicyIdentityFor(policyV1, legacyTokenizerManifest);
export const ACTIVE_POLICY_IDENTITY = policyIdentity();

/** Legacy embedding-input digest, identical to 75a90b0 snapshot.embeddingInputDigest. */
export function legacyEmbeddingInputDigest(title: string, content: string): string {
  if (typeof title !== 'string' || typeof content !== 'string' ||
      !isWellFormed(title) || !isWellFormed(content)) {
    return refuse('INVALID_SOURCE_TEXT');
  }
  return sha256Hex(JSON.stringify([LEGACY_INPUT_DOMAIN, LEGACY_POLICY_IDENTITY, title, content]));
}

const INDEX_ARN = /^arn:aws:s3vectors:([a-z0-9-]+):([0-9]{12}):bucket\/[^/]+\/index\/[^/]+$/;

/** Fixed private inventory: exact sandbox tables plus the account/region metadata in its index ARN. */
export function parseMigrationInventory(
  value: unknown, expected: MigrationTarget = DEFAULT_TARGET,
): MigrationTarget {
  if (!isRecord(value)) return refuse('UNEXPECTED_INVENTORY');
  const state = value['state'];
  const notes = value['notes'];
  const index = value['index'];
  if (state !== expected.stateTable || notes !== expected.notesTable) return refuse('UNEXPECTED_TARGET');
  if (typeof index !== 'string') return refuse('UNEXPECTED_TARGET');
  const match = INDEX_ARN.exec(index);
  if (match === null || match[1] !== expected.region || match[2] !== expected.account) {
    return refuse('UNEXPECTED_TARGET');
  }
  return expected;
}

const requireReviewedScope = (
  config: RuntimeConfig, expectedNoteCount: number, code: string,
): RuntimeConfig => {
  const owners = Object.keys(config.corpus.owners);
  if (owners.length !== 1 || config.corpus.owners[owners[0]].length !== expectedNoteCount) return refuse(code);
  return config;
};

const parseReference = (value: unknown, expectedNoteCount: number): RuntimeConfig => {
  if (!isRecord(value) || value['ownerId'] !== RUNTIME_CONFIG_KEY.ownerId ||
      value['noteId'] !== RUNTIME_CONFIG_KEY.noteId || !('config' in value)) {
    return refuse('REFERENCE_UNREADABLE');
  }
  let parsed: RuntimeConfig;
  try {
    parsed = parseRuntimeConfig(value['config']);
  } catch {
    return refuse('REFERENCE_UNREADABLE');
  }
  // The operator rebind is reviewed-gold-only: a dynamic null caseHash is not a migration input.
  if (parsed.corpus.kind !== RUNTIME_CORPUS_KIND || parsed.corpus.caseHash === null) {
    return refuse('REFERENCE_SCOPE_UNSUPPORTED');
  }
  if (parsed.policy.enabled !== false) return refuse('REFERENCE_ENABLED');
  return requireReviewedScope(parsed, expectedNoteCount, 'REFERENCE_SCOPE_UNSUPPORTED');
};

const sameStringSet = (left: readonly string[], right: readonly string[]): boolean => {
  if (left.length !== right.length) return false;
  const set = new Set(right);
  return left.every((value) => set.has(value));
};

/** Compare the whole reviewed identity; generation is the only field apply is allowed to move. */
export function sameConfigIdentity(
  left: RuntimeConfig, right: RuntimeConfig, ignoreGeneration = true,
): boolean {
  if (!ignoreGeneration && left.generation !== right.generation) return false;
  if (left.version !== right.version || left.policy.enabled !== right.policy.enabled ||
      left.policy.model !== right.policy.model ||
      left.policy.thresholds.answerabilityMin !== right.policy.thresholds.answerabilityMin ||
      left.policy.thresholds.conflictMax !== right.policy.thresholds.conflictMax ||
      !sameStringSet(left.policy.owners, right.policy.owners) || left.corpus.kind !== right.corpus.kind ||
      left.corpus.caseHash !== right.corpus.caseHash) {
    return false;
  }
  const leftOwners = Object.keys(left.corpus.owners);
  const rightOwners = Object.keys(right.corpus.owners);
  if (!sameStringSet(leftOwners, rightOwners)) return false;
  for (const owner of leftOwners) {
    const leftNotes = left.corpus.owners[owner];
    const rightNotes = right.corpus.owners[owner];
    if (leftNotes === undefined || rightNotes === undefined || leftNotes.length !== rightNotes.length) {
      return false;
    }
    const byId = new Map(rightNotes.map((note) => [note.noteId, note.inputDigest]));
    if (leftNotes.some((note) => byId.get(note.noteId) !== note.inputDigest)) return false;
  }
  return true;
}

export type MigrationBinding = Readonly<{ ordinal: number; revision: number; oldDigest: string; newDigest: string }>;

export type MigrationReport = Readonly<{
  mode: 'preview' | 'apply';
  status: 'READY_FOR_REVIEW' | 'APPLIED';
  target: MigrationTarget;
  unchangedSourceProof: Readonly<{
    verified: true; approvedNoteCount: number; matchedLegacyDigests: number;
    legacyPolicyIdentity: string; activePolicyIdentity: string;
    oldDigestSetHash: string; newDigestSetHash: string;
  }>;
  config: Readonly<{
    version: string; generation: Readonly<{ current: number; next: number }>; enabled: false; caseHash: string;
  }>;
  consent: Readonly<{
    accepted: boolean; version: string; generation: number;
    pendingGrantGate: Readonly<{
      requiredVersion: string; satisfied: boolean; grantCopied: false; applyWritesConsent: false;
    }>;
  }>;
  bindings: readonly MigrationBinding[];
  chunks: Readonly<{ batchSize: 1; totalChunks: number; uniqueEmbeddingInputs: number }>;
  budget: Readonly<{
    global: Readonly<{ used: number; limit: number; remaining: number }>;
    pilot: Readonly<{ cohere: number; selfHosted: number; limit: number; remaining: number }>;
    planned: Readonly<{ backfill: number; canary: number; goldQueries: number; smokes: number; total: number }>;
    fits: boolean;
  }>;
  source: Readonly<{ accountEpoch: number; manifestGeneration: number | null; manifestPolicyIdentity: string | null }>;
  writes: readonly string[];
}>;

export type MigrationPlan = Readonly<{ report: MigrationReport; capturedConfig: RuntimeConfig; nextConfig: RuntimeConfig }>;

export type BuildPlanInput = Readonly<{
  inventory: unknown; reference: unknown; config: RuntimeConfig; state: IndexState;
  counters: PilotBudgetCounters; globalUsed: number; counter: Counter;
}>;
export type BuildPlanOptions = Readonly<{
  expectedTarget?: MigrationTarget;
  expectedApprovedNoteCount?: number;
}>;

export function buildMigrationPlan(
  input: BuildPlanInput, options: BuildPlanOptions = {},
): MigrationPlan {
  const expectedNoteCount = options.expectedApprovedNoteCount ?? EXPECTED_APPROVED_NOTE_COUNT;
  const target = parseMigrationInventory(input.inventory, options.expectedTarget ?? DEFAULT_TARGET);
  const reference = parseReference(input.reference, expectedNoteCount);
  const current = input.config;
  if (current.policy.enabled !== false) return refuse('CONFIG_ENABLED');
  // Keep the reviewed report's caseHash non-null and the dynamic corpus out of this operator path.
  if (current.corpus.kind !== RUNTIME_CORPUS_KIND || current.corpus.caseHash === null) {
    return refuse('CONFIG_SCOPE_UNSUPPORTED');
  }
  if (!sameConfigIdentity(current, reference, true)) return refuse('CONFIG_SCOPE_DRIFT');

  const owners = Object.keys(current.corpus.owners);
  if (owners.length !== 1) return refuse('CONFIG_SCOPE_DRIFT');
  const ownerId = owners[0];
  if (input.state.ownerId !== ownerId) return refuse('SOURCE_SCOPE_DRIFT');

  const approved = new Map<string, string>();
  for (const note of current.corpus.owners[ownerId]) {
    if (approved.has(note.noteId)) return refuse('CONFIG_SCOPE_DRIFT');
    approved.set(note.noteId, note.inputDigest);
  }

  const eligible = new Map<string, IndexState['notes'][number]>();
  for (const note of input.state.notes) {
    if (note.ownerId !== ownerId) return refuse('SOURCE_SCOPE_DRIFT');
    if (!isEligibleNote(note, ownerId)) continue;
    if (eligible.has(note.noteId)) return refuse('SOURCE_SCOPE_DRIFT');
    eligible.set(note.noteId, note);
  }
  if (eligible.size !== approved.size) return refuse('SOURCE_SCOPE_DRIFT');

  const bindings: MigrationBinding[] = [];
  const newDigestById = new Map<string, string>();
  let ordinal = 0;
  for (const entry of current.corpus.owners[ownerId]) {
    const note = eligible.get(entry.noteId);
    if (note === undefined) return refuse('SOURCE_SCOPE_DRIFT');
    // Compare the reviewed legacy digest FIRST; a changed title/body must never be "rehashed".
    const legacy = legacyEmbeddingInputDigest(note.title, note.content);
    if (legacy !== entry.inputDigest) return refuse('SOURCE_CONTENT_CHANGED');
    let nextDigest: string;
    try {
      nextDigest = embeddingInputDigest(note.title, note.content);
    } catch {
      return refuse('SOURCE_CONTENT_CHANGED');
    }
    ordinal += 1;
    bindings.push({ ordinal, revision: note.revision, oldDigest: legacy, newDigest: nextDigest });
    newDigestById.set(note.noteId, nextDigest);
  }
  if (bindings.length !== expectedNoteCount) return refuse('SOURCE_SCOPE_DRIFT');

  const uniqueInputs = new Set<string>();
  let totalChunks = 0;
  for (const entry of current.corpus.owners[ownerId]) {
    const note = eligible.get(entry.noteId)!;
    let chunks;
    try {
      chunks = chunkNote(note, input.counter);
    } catch {
      return refuse('CHUNK_PLAN_FAILED');
    }
    totalChunks += chunks.length;
    for (const chunk of chunks) {
      try {
        uniqueInputs.add(embeddingInputDigest(chunk.title, chunk.text));
      } catch {
        return refuse('CHUNK_PLAN_FAILED');
      }
    }
  }

  for (const value of [
    input.counters.queryCalls, input.counters.jevCalls, input.counters.deepseekCalls,
    input.counters.cohereCalls, input.counters.selfHostedEmbeddingCalls,
    input.counters.reservedUsdMicros, input.globalUsed,
  ]) {
    if (!isSafeInteger(value) || value < 0) return refuse('COUNTER_CORRUPT');
  }
  const globalRemaining = Math.max(0, GLOBAL_EMBEDDING_LIMIT - input.globalUsed);
  const pilotRemaining = Math.max(
    0, PILOT_EMBEDDING_LIMIT - (input.counters.cohereCalls + input.counters.selfHostedEmbeddingCalls),
  );
  const room = Math.min(globalRemaining, pilotRemaining);
  const plannedTotal =
    uniqueInputs.size + PLANNED_CANARY_CALLS + PLANNED_GOLD_QUERIES + PLANNED_SMOKES;

  const nextOwners: Record<string, readonly { noteId: string; inputDigest: string }[]> = {};
  for (const owner of owners) {
    nextOwners[owner] = current.corpus.owners[owner].map((note) => {
      const digest = newDigestById.get(note.noteId);
      if (digest === undefined) return refuse('SOURCE_SCOPE_DRIFT');
      return { noteId: note.noteId, inputDigest: digest };
    });
  }
  let nextConfig: RuntimeConfig;
  try {
    nextConfig = parseRuntimeConfig({
      version: current.version,
      generation: current.generation + 1,
      policy: JSON.parse(JSON.stringify(current.policy)) as unknown,
      corpus: {
        kind: current.corpus.kind,
        caseHash: current.corpus.caseHash,
        owners: nextOwners,
      },
    });
  } catch {
    return refuse('NEXT_CONFIG_INVALID');
  }
  if (nextConfig.policy.enabled !== false) return refuse('NEXT_CONFIG_INVALID');

  const oldDigestSetHash = sha256Hex(JSON.stringify(bindings.map((entry) => entry.oldDigest).sort()));
  const newDigestSetHash = sha256Hex(JSON.stringify(bindings.map((entry) => entry.newDigest).sort()));
  const report: MigrationReport = {
    mode: 'preview',
    status: 'READY_FOR_REVIEW',
    target,
    unchangedSourceProof: {
      verified: true,
      approvedNoteCount: bindings.length,
      matchedLegacyDigests: bindings.length,
      legacyPolicyIdentity: LEGACY_POLICY_IDENTITY,
      activePolicyIdentity: ACTIVE_POLICY_IDENTITY,
      oldDigestSetHash,
      newDigestSetHash,
    },
    config: {
      version: current.version,
      generation: { current: current.generation, next: nextConfig.generation },
      enabled: false,
      caseHash: current.corpus.caseHash,
    },
    consent: {
      accepted: input.state.consent.accepted,
      version: input.state.consent.version,
      generation: input.state.consent.generation,
      pendingGrantGate: {
        requiredVersion: MIGRATION_CONSENT_VERSION,
        satisfied: input.state.consent.accepted === true &&
          input.state.consent.version === MIGRATION_CONSENT_VERSION,
        grantCopied: false,
        applyWritesConsent: false,
      },
    },
    bindings,
    chunks: {
      batchSize: EMBED_BATCH_SIZE,
      totalChunks,
      uniqueEmbeddingInputs: uniqueInputs.size,
    },
    budget: {
      global: {
        used: input.globalUsed, limit: GLOBAL_EMBEDDING_LIMIT, remaining: globalRemaining,
      },
      pilot: {
        cohere: input.counters.cohereCalls,
        selfHosted: input.counters.selfHostedEmbeddingCalls,
        limit: PILOT_EMBEDDING_LIMIT,
        remaining: pilotRemaining,
      },
      planned: {
        backfill: uniqueInputs.size,
        canary: PLANNED_CANARY_CALLS,
        goldQueries: PLANNED_GOLD_QUERIES,
        smokes: PLANNED_SMOKES,
        total: plannedTotal,
      },
      fits: plannedTotal <= room,
    },
    source: {
      accountEpoch: input.state.accountEpoch,
      manifestGeneration: input.state.manifest?.generation ?? null,
      manifestPolicyIdentity: input.state.manifest?.policyIdentity ?? null,
    },
    writes: [],
  };
  return { report, capturedConfig: current, nextConfig };
}
