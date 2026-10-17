/**
 * Operator-only preview/apply CLI for rebinding the reviewed six-note pilot to the active
 * EmbeddingGemma policy. Preview is read-only. Apply changes exactly one value:
 * `CONFIG#PHASE5`/`PILOT`.config. It never writes notes, consent, counters, manifests,
 * snapshots, vectors or receipts, and it never calls a model.
 *
 * Pure hashing, reviewed-source binding and next-config/budget planning live in
 * `migrate_embedding_profile_core.ts`. This file owns AWS clients, files, environment and argv.
 */
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { pathToFileURL } from 'node:url';
import { isSafeInteger } from '../../amplify/rag/chunking';
import { loadEmbeddingGemmaTokenCounter } from '../../amplify/rag/indexing/tokenizer';
import { createIndexStore, type StorePort } from '../../amplify/rag/indexing/store';
import type { IndexState } from '../../amplify/rag/indexing/types';
import {
  createPilotBudget, GLOBAL_EMBEDDING_KEY,
  type PilotBudgetCounters, type PilotBudgetPort,
} from '../../amplify/rag/phase5/pilot_budget';
import { parseRuntimeConfig, RUNTIME_CONFIG_KEY, type RuntimeConfig } from '../../amplify/rag/phase5/runtime_config';
import type { Counter } from '../../amplify/rag/types';
import {
  buildMigrationPlan, MigrationRefusal, MIGRATION_PROFILE, MIGRATION_REGION, parseMigrationInventory,
  refuse, sameConfigIdentity, type BuildPlanOptions, type MigrationPlan, type MigrationReport,
} from './migrate_embedding_profile_core';

export const OUTPUT_DIRECTORY = 'output/rag/embeddinggemma-migration';
export const FIXED_INVENTORY_PATH = 'output/rag/smoke/inventory.json';
export const FIXED_REFERENCE_PATH = 'output/rag/phase5-implementation/reviewed-runtime-config.json';

/** The one permitted write: exact whole-config CAS, only the `config` value. */
export function configUpdateCommand(
  table: string, captured: RuntimeConfig, next: RuntimeConfig,
): UpdateCommand {
  if (typeof table !== 'string' || table.length === 0) return refuse('INVALID_TABLE');
  return new UpdateCommand({
    TableName: table,
    Key: RUNTIME_CONFIG_KEY,
    UpdateExpression: 'SET #config = :nextConfig',
    ConditionExpression: 'attribute_exists(#config) AND #config = :capturedConfig',
    ExpressionAttributeNames: { '#config': 'config' },
    ExpressionAttributeValues: { ':nextConfig': next, ':capturedConfig': captured },
    ReturnValues: 'ALL_NEW',
  });
}

export type MigrationDeps = Readonly<{
  inventory: unknown;
  reference: unknown;
  counter: Counter;
  readConfig(signal: AbortSignal): Promise<RuntimeConfig>;
  loadState(owner: string, signal: AbortSignal): Promise<IndexState>;
  readPilotCounters(signal: AbortSignal): Promise<PilotBudgetCounters>;
  readGlobalUsed(signal: AbortSignal): Promise<number>;
  writeConfig(captured: RuntimeConfig, next: RuntimeConfig, signal: AbortSignal): Promise<RuntimeConfig>;
}>;
export type RunMigrationOptions = BuildPlanOptions & Readonly<{ timeoutMs?: number }>;

const planFromDeps = async (
  deps: MigrationDeps, signal: AbortSignal, options: RunMigrationOptions,
): Promise<MigrationPlan> => {
  const config = await deps.readConfig(signal);
  const owners = Object.keys(config.corpus.owners);
  if (owners.length !== 1) return refuse('REFERENCE_SCOPE_UNSUPPORTED');
  const [state, counters, globalUsed] = await Promise.all([
    deps.loadState(owners[0], signal),
    deps.readPilotCounters(signal),
    deps.readGlobalUsed(signal),
  ]);
  return buildMigrationPlan({
    inventory: deps.inventory,
    reference: deps.reference,
    config,
    state,
    counters,
    globalUsed,
    counter: deps.counter,
  }, options);
};

/** Preview performs reads only. Apply re-reads everything, then CASes the whole config exactly once. */
export async function runMigration(
  deps: MigrationDeps, mode: 'preview' | 'apply', options: RunMigrationOptions = {},
): Promise<MigrationReport> {
  const signal = AbortSignal.timeout(options.timeoutMs ?? 60_000);
  try {
    const first = await planFromDeps(deps, signal, options);
    if (mode === 'preview') return first.report;
    if (!first.report.budget.fits) return refuse('MIGRATION_BUDGET_INSUFFICIENT');
    // Fresh canonical source + config recheck immediately before the one write.
    const fresh = await planFromDeps(deps, signal, options);
    if (!fresh.report.budget.fits) return refuse('MIGRATION_BUDGET_INSUFFICIENT');
    // The fresh recheck must bind exactly the config generation the first read captured.
    if (!sameConfigIdentity(fresh.capturedConfig, first.capturedConfig, false)) {
      return refuse('CONFIG_CHANGED');
    }
    if (!sameConfigIdentity(fresh.nextConfig, first.nextConfig, false)) {
      return refuse('SOURCE_CHANGED');
    }
    const written = await deps.writeConfig(fresh.capturedConfig, fresh.nextConfig, signal);
    if (!sameConfigIdentity(written, fresh.nextConfig, false)) {
      return refuse('CONFIG_WRITE_UNVERIFIED');
    }
    return {
      ...fresh.report,
      mode: 'apply',
      status: 'APPLIED',
      writes: [`${RUNTIME_CONFIG_KEY.ownerId}/${RUNTIME_CONFIG_KEY.noteId}.config`],
    };
  } catch (error) {
    if (signal.aborted) return refuse('TIMEOUT');
    throw error;
  }
}

export function resolveTokenizerDirectory(env: NodeJS.ProcessEnv): string {
  const directory = env.RAG_EMBEDDINGGEMMA_TOKENIZER_DIR;
  if (typeof directory !== 'string' || directory.trim().length === 0) {
    return refuse('EMBEDDINGGEMMA_TOKENIZER_DIR_REQUIRED');
  }
  return directory;
}

/** Fixed target only: no region/profile/model switch is accepted from argv or ambient overrides. */
export function assertMigrationEnvironment(env: NodeJS.ProcessEnv): void {
  if (env.AWS_PROFILE !== undefined && env.AWS_PROFILE !== MIGRATION_PROFILE) {
    return refuse('UNEXPECTED_AWS_PROFILE');
  }
  const region = env.AWS_REGION ?? env.AWS_DEFAULT_REGION;
  if (region !== undefined && region !== MIGRATION_REGION) return refuse('UNEXPECTED_AWS_REGION');
  for (const key of ['AWS_ENDPOINT_URL', 'AWS_ENDPOINT_URL_DYNAMODB'] as const) {
    if (env[key] !== undefined) return refuse('UNEXPECTED_ENDPOINT_OVERRIDE');
  }
}

export function loadFixedInputs(cwd = process.cwd()): Readonly<{ inventory: unknown; reference: unknown }> {
  try {
    return {
      inventory: JSON.parse(readFileSync(join(cwd, FIXED_INVENTORY_PATH), 'utf8')) as unknown,
      reference: JSON.parse(readFileSync(join(cwd, FIXED_REFERENCE_PATH), 'utf8')) as unknown,
    };
  } catch {
    return refuse('FIXED_INPUT_UNREADABLE');
  }
}

export function saveReport(report: MigrationReport, cwd = process.cwd()): string {
  const directory = join(cwd, OUTPUT_DIRECTORY);
  const path = join(
    directory, report.mode === 'apply' ? 'migration-apply.json' : 'migration-preview.json',
  );
  mkdirSync(directory, { recursive: true });
  writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`);
  return relative(cwd, path);
}

type ToolCommand = GetCommand | UpdateCommand;
type ToolPort = Readonly<{
  send(command: ToolCommand, options?: Readonly<{ abortSignal?: AbortSignal }>): Promise<unknown>;
}>;
export type AwsMigrationDepsOptions = Readonly<{
  region: string; stateTable: string; notesTable: string;
  inventory: unknown; reference: unknown; counter: Counter; client?: ToolPort;
}>;

const errorNameOf = (error: unknown): string =>
  isRecord(error) && typeof error['name'] === 'string' ? error['name'] : '';

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

export function createAwsMigrationDeps(options: AwsMigrationDepsOptions): MigrationDeps {
  const client: ToolPort = options.client ??
    (DynamoDBDocumentClient.from(new DynamoDBClient({
      region: options.region, maxAttempts: 1,
    })) as unknown as ToolPort);
  const store = createIndexStore(
    { region: options.region, notesTable: options.notesTable, stateTable: options.stateTable },
    { client: client as unknown as StorePort },
  );

  const send = async (command: ToolCommand, signal: AbortSignal): Promise<unknown> => {
    try {
      return await client.send(command, { abortSignal: signal });
    } catch (error) {
      if (signal.aborted) return refuse('TIMEOUT');
      const name = errorNameOf(error);
      if (name === 'ConditionalCheckFailedException' ||
          name === 'TransactionCanceledException') {
        return refuse('CONFIG_CHANGED');
      }
      return refuse('MIGRATION_IO_FAILED');
    }
  };

  const readConfig = async (signal: AbortSignal): Promise<RuntimeConfig> => {
    const output = await send(
      new GetCommand({ TableName: options.stateTable, Key: RUNTIME_CONFIG_KEY, ConsistentRead: true }),
      signal,
    );
    if (!isRecord(output)) return refuse('CONFIG_UNREADABLE');
    const item = output['Item'];
    if (!isRecord(item) || item['ownerId'] !== RUNTIME_CONFIG_KEY.ownerId ||
        item['noteId'] !== RUNTIME_CONFIG_KEY.noteId || !('config' in item)) {
      return refuse('CONFIG_UNREADABLE');
    }
    try {
      return parseRuntimeConfig(item['config']);
    } catch {
      return refuse('CONFIG_UNREADABLE');
    }
  };

  const loadState = async (owner: string, signal: AbortSignal): Promise<IndexState> => {
    try {
      return await store.load(owner, signal);
    } catch {
      if (signal.aborted) return refuse('TIMEOUT');
      return refuse('SOURCE_UNREADABLE');
    }
  };

  const readPilotCounters = async (signal: AbortSignal): Promise<PilotBudgetCounters> => {
    try {
      const budget = createPilotBudget(
        options.region, options.stateTable, client as unknown as PilotBudgetPort,
      );
      return await budget.read(signal);
    } catch {
      if (signal.aborted) return refuse('TIMEOUT');
      return refuse('COUNTER_UNREADABLE');
    }
  };

  const readGlobalUsed = async (signal: AbortSignal): Promise<number> => {
    const output = await send(new GetCommand({
      TableName: options.stateTable, Key: GLOBAL_EMBEDDING_KEY, ConsistentRead: true,
    }), signal);
    if (!isRecord(output)) return refuse('COUNTER_CORRUPT');
    const item = output['Item'];
    if (item === undefined) return 0;
    if (!isRecord(item) || item['ownerId'] !== GLOBAL_EMBEDDING_KEY.ownerId ||
        item['noteId'] !== GLOBAL_EMBEDDING_KEY.noteId) {
      return refuse('COUNTER_CORRUPT');
    }
    const used = item['used'];
    if (used === undefined) return 0;
    if (!isSafeInteger(used) || used < 0) return refuse('COUNTER_CORRUPT');
    return used;
  };

  const writeConfig = async (
    captured: RuntimeConfig, next: RuntimeConfig, signal: AbortSignal,
  ): Promise<RuntimeConfig> => {
    const output = await send(
      configUpdateCommand(options.stateTable, captured, next), signal,
    );
    if (!isRecord(output)) return refuse('CONFIG_WRITE_UNVERIFIED');
    const attributes = output['Attributes'];
    if (!isRecord(attributes) || attributes['ownerId'] !== RUNTIME_CONFIG_KEY.ownerId ||
        attributes['noteId'] !== RUNTIME_CONFIG_KEY.noteId || !('config' in attributes)) {
      return refuse('CONFIG_WRITE_UNVERIFIED');
    }
    try {
      return parseRuntimeConfig(attributes['config']);
    } catch {
      return refuse('CONFIG_WRITE_UNVERIFIED');
    }
  };

  return Object.freeze({
    inventory: options.inventory,
    reference: options.reference,
    counter: options.counter,
    readConfig,
    loadState,
    readPilotCounters,
    readGlobalUsed,
    writeConfig,
  });
}

const parseArgs = (argv: readonly string[]): Readonly<{ apply: boolean; save: boolean }> => {
  let apply = false;
  let save = false;
  for (const arg of argv) {
    if (arg === '--apply') apply = true;
    else if (arg === '--save') save = true;
    else return refuse('UNKNOWN_ARGUMENT');
  }
  return { apply, save };
};

export async function main(argv = process.argv.slice(2)): Promise<number> {
  const args = parseArgs(argv);
  assertMigrationEnvironment(process.env);
  if (process.env.AWS_PROFILE === undefined) process.env.AWS_PROFILE = MIGRATION_PROFILE;
  let counter: Counter;
  try {
    counter = loadEmbeddingGemmaTokenCounter(resolveTokenizerDirectory(process.env));
  } catch (error) {
    if (error instanceof MigrationRefusal) throw error;
    return refuse('TOKENIZER_UNAVAILABLE');
  }
  const { inventory, reference } = loadFixedInputs();
  const target = parseMigrationInventory(inventory);
  const deps = createAwsMigrationDeps({
    region: target.region,
    stateTable: target.stateTable,
    notesTable: target.notesTable,
    inventory,
    reference,
    counter,
  });
  const report = await runMigration(deps, args.apply ? 'apply' : 'preview');
  if (args.save) saveReport(report);
  console.log(JSON.stringify(report, null, 2));
  return 0;
}

const entry = process.argv[1];
if (entry !== undefined && import.meta.url === pathToFileURL(entry).href) {
  main().then((code) => {
    process.exitCode = code;
  }).catch((error: unknown) => {
    const code = error instanceof MigrationRefusal ? error.code : 'MIGRATION_FAILED';
    console.error(JSON.stringify({ status: 'REFUSED', code }));
    process.exitCode = 1;
  });
}
