import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { ANALYZER_VERSION, BM25_B, BM25_K1 } from '../../amplify/rag/keyword';
import { embeddingInputDigest, policyIdentity } from '../../amplify/rag/indexing/snapshot';
import type { IndexState } from '../../amplify/rag/indexing/types';
import { GLOBAL_EMBEDDING_LIMIT, PILOT_EMBEDDING_LIMIT, type PilotBudgetCounters } from '../../amplify/rag/phase5/pilot_budget';
import {
  parseRuntimeConfig, RUNTIME_CASE_HASH, RUNTIME_CONFIG_KEY, type RuntimeConfig,
} from '../../amplify/rag/phase5/runtime_config';
import {
  ACTIVE_POLICY_IDENTITY, LEGACY_LEXICAL, LEGACY_POLICY_IDENTITY, MIGRATION_PROFILE, MIGRATION_REGION,
  MIGRATION_ACCOUNT, buildMigrationPlan, legacyEmbeddingInputDigest, legacyPolicyIdentityFor,
  parseMigrationInventory, sameConfigIdentity, type MigrationTarget,
} from './migrate_embedding_profile_core';
import {
  assertMigrationEnvironment, configUpdateCommand, resolveTokenizerDirectory, runMigration,
  type MigrationDeps,
} from './migrate_embedding_profile';

const OWNER = '293a65cc-20f1-70e3-16e8-5317be9e95a6';
const TARGET: MigrationTarget = {
  profile: MIGRATION_PROFILE,
  region: MIGRATION_REGION,
  account: MIGRATION_ACCOUNT,
  stateTable: 'synthetic-state-table',
  notesTable: 'synthetic-notes-table',
};
const INVENTORY = {
  state: TARGET.stateTable,
  notes: TARGET.notesTable,
  index: `arn:aws:s3vectors:${MIGRATION_REGION}:${MIGRATION_ACCOUNT}:bucket/b/index/rag-v1`,
};
const COUNTERS: PilotBudgetCounters = {
  queryCalls: 0, jevCalls: 0, deepseekCalls: 0,
  cohereCalls: 1, selfHostedEmbeddingCalls: 0, reservedUsdMicros: 0,
};
const GLOBAL_USED = 13;
const counter = (text: string): number => Math.max(0, Math.ceil([...text].length / 4));

const SPECS = [
  ['p5-hs', 'Synthetic HS', 'Synthetic HS body.'],
  ['p5-cost', 'Synthetic cost', 'Synthetic cost body.'],
  ['p5-iris', 'Synthetic iris', 'Synthetic iris body.'],
  ['p5-truc-a', 'Synthetic truc A', 'Synthetic truc A body.'],
  ['p5-truc-b', 'Synthetic truc B', 'Synthetic truc B body.'],
  ['note-1791284611425000-3', 'Synthetic reviewed', 'Synthetic reviewed body.'],
] as const;

const makeNote = (spec: readonly [string, string, string]) => ({
  ownerId: OWNER,
  noteId: spec[0],
  revision: 1,
  title: spec[1],
  content: spec[2],
  synced: true,
  protected: false,
  deleted: false,
  available: true,
  incomingShared: false,
  protectionRevision: 0,
});
type Note = ReturnType<typeof makeNote>;

const makeNotes = (): Note[] => SPECS.map((spec) => makeNote(spec));

const makeReference = (notes: readonly Note[]) => ({
  ownerId: RUNTIME_CONFIG_KEY.ownerId,
  noteId: RUNTIME_CONFIG_KEY.noteId,
  config: {
    version: 'rag-pilot-config.v1',
    generation: 1,
    policy: {
      enabled: false,
      owners: [OWNER],
      model: 'jev-1.13.0',
      thresholds: { answerabilityMin: 0.85, conflictMax: 0.1 },
    },
    corpus: {
      kind: 'reviewed-pilot',
      caseHash: RUNTIME_CASE_HASH,
      owners: {
        [OWNER]: notes.map((note) => ({
          noteId: note.noteId,
          inputDigest: legacyEmbeddingInputDigest(note.title, note.content),
        })),
      },
    },
  },
});

const configOf = (reference: ReturnType<typeof makeReference>, generation = 3): RuntimeConfig =>
  parseRuntimeConfig({ ...reference.config, generation });

const stateOf = (notes: readonly Note[], overrides: Partial<IndexState> = {}): IndexState => ({
  ownerId: OWNER,
  accountEpoch: 7,
  consent: { accepted: true, version: 'rag-consent.v1', generation: 4 },
  notes,
  manifest: null,
  ...overrides,
});

const depsOf = (
  reference: ReturnType<typeof makeReference>,
  notes: readonly Note[],
  overrides: Partial<MigrationDeps> = {},
): MigrationDeps & { writes: number; captured: RuntimeConfig | null; next: RuntimeConfig | null } => {
  const tracker = {
    writes: 0,
    captured: null as RuntimeConfig | null,
    next: null as RuntimeConfig | null,
  };
  const deps: MigrationDeps = {
    inventory: INVENTORY,
    reference,
    counter,
    readConfig: async () => configOf(reference),
    loadState: async () => stateOf(notes),
    readPilotCounters: async () => COUNTERS,
    readGlobalUsed: async () => GLOBAL_USED,
    writeConfig: async (captured, next) => {
      tracker.writes += 1;
      tracker.captured = captured;
      tracker.next = next;
      return next;
    },
    ...overrides,
  };
  Object.defineProperties(deps, {
    writes: { get: () => tracker.writes },
    captured: { get: () => tracker.captured },
    next: { get: () => tracker.next },
  });
  return deps as MigrationDeps & {
    writes: number; captured: RuntimeConfig | null; next: RuntimeConfig | null;
  };
};

const planOf = (
  reference = makeReference(makeNotes()),
  notes = makeNotes(),
  stateOverrides: Partial<IndexState> = {},
  config = configOf(reference),
) => buildMigrationPlan({
  inventory: INVENTORY,
  reference,
  config,
  state: stateOf(notes, stateOverrides),
  counters: COUNTERS,
  globalUsed: GLOBAL_USED,
  counter,
}, { expectedTarget: TARGET });

test('legacy identity matches the frozen 75a90b0 source algorithm and pinned hash', () => {
  const policy = JSON.parse(readFileSync(new URL('../../docs/rag/policy_v1.json', import.meta.url), 'utf8'));
  const tokenizer = JSON.parse(readFileSync(new URL('../../docs/rag/tokenizer_manifest.json', import.meta.url), 'utf8'));
  assert.deepEqual(LEGACY_LEXICAL, { analyzer: ANALYZER_VERSION, k1: BM25_K1, b: BM25_B });
  const fields = {
    tokenizer,
    lexical: LEGACY_LEXICAL,
    model: policy.embedding.model,
    dimensions: policy.embedding.dimensions,
    documentInputType: policy.embedding.documentInputType,
    queryInputType: policy.embedding.queryInputType,
    truncate: policy.embedding.truncate,
    chunking: { ...policy.chunking },
    offsetUnit: policy.technicalDefaults.offsetUnit,
    spanEnd: policy.technicalDefaults.spanEnd,
    embeddingText: policy.technicalDefaults.embeddingText,
  };
  const expected = createHash('sha256').update(JSON.stringify(fields), 'utf8').digest('hex');
  assert.equal(expected, '010b757a319577c571acb15f9a16f68f517d36801ccbbd94a5cbfee2d102cc76');
  assert.equal(legacyPolicyIdentityFor(policy, tokenizer), expected);
  assert.equal(LEGACY_POLICY_IDENTITY, expected);
  assert.equal(
    legacyEmbeddingInputDigest('Synthetic title', 'Synthetic body.'),
    '40397151cd488c163ecb3076fad20d3a6887ce021b6253fd2d18dd4415e70ebf',
  );
});

test('active identity and new digest are the imported current codec', () => {
  assert.equal(ACTIVE_POLICY_IDENTITY, policyIdentity());
  assert.equal(ACTIVE_POLICY_IDENTITY, 'b3cd39a5710fe32f54346aae999321f8d2b8bb4f315a3c35fb2f7218d6fd31b0');
  assert.equal(
    embeddingInputDigest('Synthetic title', 'Synthetic body.'),
    'c611eeb28ed1ae6a87816499c6c290e65230c04dc253694e08a5ce9cfd3edab1',
  );
});

test('preview binds the approved six without mutating state/counters or printing note data', () => {
  const notes = makeNotes();
  const reference = makeReference(notes);
  const state = stateOf(notes);
  const before = JSON.stringify({ state, COUNTERS });
  const plan = planOf(reference, notes);
  assert.equal(JSON.stringify({ state, COUNTERS }), before);
  assert.equal(plan.report.mode, 'preview');
  assert.equal(plan.report.status, 'READY_FOR_REVIEW');
  assert.equal(plan.report.unchangedSourceProof.approvedNoteCount, 6);
  assert.equal(plan.report.unchangedSourceProof.matchedLegacyDigests, 6);
  assert.equal(plan.report.bindings.length, 6);
  assert.equal(plan.report.chunks.batchSize, 1);
  assert.equal(plan.report.chunks.totalChunks, 6);
  assert.equal(plan.report.chunks.uniqueEmbeddingInputs, 6);
  assert.deepEqual(plan.report.budget, {
    global: { used: 13, limit: GLOBAL_EMBEDDING_LIMIT, remaining: GLOBAL_EMBEDDING_LIMIT - 13 },
    pilot: { cohere: 1, selfHosted: 0, limit: PILOT_EMBEDDING_LIMIT, remaining: PILOT_EMBEDDING_LIMIT - 1 },
    planned: { backfill: 6, canary: 1, goldQueries: 20, smokes: 3, total: 30 },
    fits: true,
  });
  const serialized = JSON.stringify(plan.report);
  assert.equal(serialized.includes(OWNER), false);
  assert.equal(serialized.includes('p5-hs'), false);
  assert.equal(serialized.includes('Synthetic HS body.'), false);
});

test('a changed title is refused before any new digest is produced', () => {
  const reference = makeReference(makeNotes());
  const notes = makeNotes();
  notes[0] = { ...notes[0], title: 'Changed title' };
  assert.throws(() => planOf(reference, notes), (error: unknown) =>
    error instanceof Error && 'code' in error && error.code === 'SOURCE_CONTENT_CHANGED');
});

test('a changed body is refused before any new digest is produced', () => {
  const reference = makeReference(makeNotes());
  const notes = makeNotes();
  notes[0] = { ...notes[0], content: 'Changed body.' };
  assert.throws(() => planOf(reference, notes), (error: unknown) =>
    error instanceof Error && 'code' in error && error.code === 'SOURCE_CONTENT_CHANGED');
});

test('an extra eligible note is refused rather than broadened', () => {
  const reference = makeReference(makeNotes());
  const notes = makeNotes();
  notes.push(makeNote(['p5-extra', 'Synthetic extra', 'Synthetic extra body.']));
  assert.throws(() => planOf(reference, notes), (error: unknown) =>
    error instanceof Error && 'code' in error && error.code === 'SOURCE_SCOPE_DRIFT');
});

test('protected, deleted, unsynced and foreign approved notes are refused', () => {
  const reference = makeReference(makeNotes());
  const mutations: Partial<Note>[] = [
    { protected: true },
    { deleted: true },
    { synced: false },
    { ownerId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' },
  ];
  for (const mutation of mutations) {
    const notes = makeNotes();
    notes[0] = { ...notes[0], ...mutation };
    assert.throws(() => planOf(reference, notes), (error: unknown) =>
      error instanceof Error && 'code' in error && error.code === 'SOURCE_SCOPE_DRIFT');
  }
});

test('generation may differ from the reference but every other config field may not', () => {
  const reference = makeReference(makeNotes());
  const current = configOf(reference, 3);
  const plan = planOf(reference, makeNotes(), {}, current);
  assert.equal(plan.report.config.generation.current, 3);
  assert.equal(plan.report.config.generation.next, 4);
  assert.equal(sameConfigIdentity(current, configOf(reference, 1), true), true);
  assert.equal(sameConfigIdentity(current, configOf(reference, 1), false), false);

  const drifted = parseRuntimeConfig({
    ...current,
    corpus: {
      ...current.corpus,
      owners: {
        [OWNER]: current.corpus.owners[OWNER].map((note, index) =>
          index === 0 ? { ...note, inputDigest: '0'.repeat(64) } : note),
      },
    },
  });
  assert.throws(() => planOf(reference, makeNotes(), {}, drifted), (error: unknown) =>
    error instanceof Error && 'code' in error && error.code === 'CONFIG_SCOPE_DRIFT');

  const widened = parseRuntimeConfig({
    ...current,
    corpus: {
      ...current.corpus,
      owners: {
        [OWNER]: [
          ...current.corpus.owners[OWNER],
          { noteId: 'p5-extra', inputDigest: '1'.repeat(64) },
        ],
      },
    },
  });
  assert.throws(() => planOf(reference, makeNotes(), {}, widened), (error: unknown) =>
    error instanceof Error && 'code' in error && error.code === 'CONFIG_SCOPE_DRIFT');

  const enabled = parseRuntimeConfig({
    ...current,
    policy: { ...current.policy, enabled: true },
  });
  assert.throws(() => planOf(reference, makeNotes(), {}, enabled), (error: unknown) =>
    error instanceof Error && 'code' in error && error.code === 'CONFIG_ENABLED');
});

test('the reviewed operator CLI refuses a dynamic corpus instead of widening caseHash', () => {
  const reference = makeReference(makeNotes());
  const reviewed = configOf(reference);
  const dynamic = parseRuntimeConfig({
    ...reviewed,
    corpus: { kind: 'eligible-own-notes.v1', caseHash: null, owners: { [OWNER]: [] } },
  });
  const isRefusal = (code: string) => (error: unknown): boolean =>
    error instanceof Error && 'code' in error && error.code === code;
  assert.throws(() => planOf(reference, makeNotes(), {}, dynamic),
    isRefusal('CONFIG_SCOPE_UNSUPPORTED'));
  assert.throws(() => planOf({
    ownerId: RUNTIME_CONFIG_KEY.ownerId,
    noteId: RUNTIME_CONFIG_KEY.noteId,
    config: dynamic,
  }, makeNotes(), {}, dynamic), isRefusal('REFERENCE_SCOPE_UNSUPPORTED'));
  // Legacy reviewed gold keeps its non-null case hash and unchanged identity.
  const plan = planOf(reference, makeNotes(), {}, reviewed);
  assert.equal(plan.report.config.caseHash, RUNTIME_CASE_HASH);
});

test('the old v1 grant is shown but never accepted or copied', () => {
  const reference = makeReference(makeNotes());
  const plan = planOf(reference, makeNotes(), {
    consent: { accepted: true, version: 'rag-consent.v1', generation: 4 },
  });
  assert.deepEqual(plan.report.consent, {
    accepted: true,
    version: 'rag-consent.v1',
    generation: 4,
    pendingGrantGate: {
      requiredVersion: 'rag-consent.v2',
      satisfied: false,
      grantCopied: false,
      applyWritesConsent: false,
    },
  });
  assert.equal(JSON.stringify(plan.nextConfig).includes('rag-consent.v1'), false);
  assert.equal(JSON.stringify(plan.nextConfig).includes('consent'), false);

  const acceptedV2 = planOf(reference, makeNotes(), {
    consent: { accepted: true, version: 'rag-consent.v2', generation: 5 },
  });
  assert.equal(acceptedV2.report.consent.pendingGrantGate.satisfied, true);
  assert.equal(acceptedV2.report.consent.pendingGrantGate.grantCopied, false);
});

test('preview performs no config write', async () => {
  const reference = makeReference(makeNotes());
  let writes = 0;
  const deps = depsOf(reference, makeNotes(), {
    writeConfig: async () => {
      writes += 1;
      throw new Error('preview must not write');
    },
  });
  const report = await runMigration(deps, 'preview', { timeoutMs: 5_000, expectedTarget: TARGET });
  assert.equal(writes, 0);
  assert.equal(report.mode, 'preview');
  assert.equal(report.status, 'READY_FOR_REVIEW');
  assert.deepEqual(report.writes, []);
});

test('apply writes only the config CAS, keeps enabled false and increments generation', async () => {
  const notes = makeNotes();
  const reference = makeReference(notes);
  const deps = depsOf(reference, notes);
  const report = await runMigration(deps, 'apply', { timeoutMs: 5_000, expectedTarget: TARGET });
  assert.equal(deps.writes, 1);
  assert.equal(deps.captured?.generation, 3);
  assert.equal(deps.next?.generation, 4);
  assert.equal(deps.next?.policy.enabled, false);
  assert.equal(report.mode, 'apply');
  assert.equal(report.status, 'APPLIED');
  assert.deepEqual(report.writes, ['CONFIG#PHASE5/PILOT.config']);
  assert.deepEqual(
    deps.next?.corpus.owners[OWNER].map((entry) => entry.inputDigest),
    notes.map((note) => embeddingInputDigest(note.title, note.content)),
  );
  assert.equal(JSON.stringify(deps.next).includes('rag-consent'), false);
});

test('apply re-reads config and canonical source once more before the single write', async () => {
  const notes = makeNotes();
  const reference = makeReference(notes);
  let configReads = 0;
  let sourceLoads = 0;
  const deps = depsOf(reference, notes, {
    readConfig: async () => {
      configReads += 1;
      return configOf(reference);
    },
    loadState: async () => {
      sourceLoads += 1;
      return stateOf(notes);
    },
  });
  await runMigration(deps, 'apply', { timeoutMs: 5_000, expectedTarget: TARGET });
  assert.equal(configReads, 2);
  assert.equal(sourceLoads, 2);
  assert.equal(deps.writes, 1);
});

test('apply refuses when the config generation moves between the two reads', async () => {
  const notes = makeNotes();
  const reference = makeReference(notes);
  let reads = 0;
  const deps = depsOf(reference, notes, {
    readConfig: async () => {
      reads += 1;
      return configOf(reference, reads === 1 ? 3 : 4);
    },
  });
  await assert.rejects(runMigration(deps, 'apply', {
    timeoutMs: 5_000, expectedTarget: TARGET,
  }), (error: unknown) =>
    error instanceof Error && 'code' in error && error.code === 'CONFIG_CHANGED');
  assert.equal(deps.writes, 0);
});

test('apply is refused when the shared embedding allowance cannot cover backfill + gates', async () => {
  const reference = makeReference(makeNotes());
  const deps = depsOf(reference, makeNotes(), {
    readPilotCounters: async () => ({ ...COUNTERS, cohereCalls: 1, selfHostedEmbeddingCalls: PILOT_EMBEDDING_LIMIT - 1 }),
    readGlobalUsed: async () => PILOT_EMBEDDING_LIMIT,
  });
  const preview = await runMigration(deps, 'preview', { timeoutMs: 5_000, expectedTarget: TARGET });
  assert.equal(preview.budget.fits, false);
  await assert.rejects(runMigration(deps, 'apply', { timeoutMs: 5_000, expectedTarget: TARGET }), (error: unknown) =>
    error instanceof Error && 'code' in error && error.code === 'MIGRATION_BUDGET_INSUFFICIENT');
  assert.equal(deps.writes, 0);
});

test('the write command CASes the whole config and only sets the config value', () => {
  const reference = makeReference(makeNotes());
  const captured = configOf(reference, 3);
  const plan = planOf(reference, makeNotes(), {}, captured);
  const command = configUpdateCommand(TARGET.stateTable, captured, plan.nextConfig);
  assert.deepEqual(command.input.Key, RUNTIME_CONFIG_KEY);
  assert.equal(command.input.TableName, TARGET.stateTable);
  assert.equal(command.input.UpdateExpression, 'SET #config = :nextConfig');
  assert.equal(
    command.input.ConditionExpression,
    'attribute_exists(#config) AND #config = :capturedConfig',
  );
  assert.deepEqual(command.input.ExpressionAttributeValues, {
    ':nextConfig': plan.nextConfig,
    ':capturedConfig': captured,
  });
  assert.equal(command.input.UpdateExpression?.includes('ADD'), false);
  assert.equal(JSON.stringify(command.input).includes('cohereCalls'), false);
});

test('missing tokenizer env path fails explicitly, with no fallback', () => {
  assert.throws(() => resolveTokenizerDirectory({}), (error: unknown) =>
    error instanceof Error && 'code' in error && error.code === 'EMBEDDINGGEMMA_TOKENIZER_DIR_REQUIRED');
  assert.throws(() => resolveTokenizerDirectory({ RAG_EMBEDDINGGEMMA_TOKENIZER_DIR: '  ' }), (error: unknown) =>
    error instanceof Error && 'code' in error && error.code === 'EMBEDDINGGEMMA_TOKENIZER_DIR_REQUIRED');
});

test('unexpected table, account or region metadata is refused', () => {
  assert.throws(() => parseMigrationInventory({ ...INVENTORY, state: 'other' }, TARGET), (error: unknown) =>
    error instanceof Error && 'code' in error && error.code === 'UNEXPECTED_TARGET');
  assert.throws(() => parseMigrationInventory({
    ...INVENTORY,
    index: `arn:aws:s3vectors:${MIGRATION_REGION}:999999999999:bucket/b/index/rag-v1`,
  }, TARGET), (error: unknown) =>
    error instanceof Error && 'code' in error && error.code === 'UNEXPECTED_TARGET');
  assert.throws(() => parseMigrationInventory({
    ...INVENTORY,
    index: `arn:aws:s3vectors:us-east-1:${MIGRATION_ACCOUNT}:bucket/b/index/rag-v1`,
  }, TARGET), (error: unknown) =>
    error instanceof Error && 'code' in error && error.code === 'UNEXPECTED_TARGET');
});

test('ambient profile, region and endpoint switches are refused', () => {
  assert.doesNotThrow(() => assertMigrationEnvironment({
    AWS_PROFILE: 'noteflow-dev', AWS_REGION: 'ap-southeast-1',
  }));
  for (const env of [
    { AWS_PROFILE: 'other' },
    { AWS_REGION: 'us-east-1' },
    { AWS_DEFAULT_REGION: 'us-east-1' },
    { AWS_ENDPOINT_URL: 'http://localhost' },
    { AWS_ENDPOINT_URL_DYNAMODB: 'http://localhost' },
  ]) {
    assert.throws(() => assertMigrationEnvironment(env), (error: unknown) =>
      error instanceof Error && 'code' in error && typeof error.code === 'string');
  }
});

test('the reference scope is pinned to one owner and six notes', () => {
  const five = makeReference(makeNotes().slice(0, 5));
  assert.throws(() => planOf(five, makeNotes().slice(0, 5)), (error: unknown) =>
    error instanceof Error && 'code' in error && error.code === 'REFERENCE_SCOPE_UNSUPPORTED');

  const enabled = makeReference(makeNotes());
  enabled.config.policy.enabled = true;
  assert.throws(() => planOf(enabled, makeNotes()), (error: unknown) =>
    error instanceof Error && 'code' in error && error.code === 'REFERENCE_ENABLED');
});
