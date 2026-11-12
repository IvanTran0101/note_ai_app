import { LIVE_QUESTION_SET, LIVE_RECORDING_PROVENANCE } from './question_set';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand } from '@aws-sdk/lib-dynamodb';
import fixturesFile from '../../test/fixtures/rag/phase4/fixtures.json';
import { loadFixtureFile, evaluateConfirmation, type CalibrationPolicy, type RecordingFile } from './calibration';
import { contentHash } from './calibration/hash';
import { createPrivateHandler } from './private_handler';
import { createJevProvider, JEV_MODEL, type ProviderUsage } from './providers/jev';
import { createDeepSeekProvider, DEEPSEEK_SYSTEM_PROMPT } from './providers/deepseek';
import { createPhase4Budget } from './budget';
import { loadDeepSeekCounter, jevInputUpperBound, deepSeekInputUpperBound } from './token_fit';
import { createQuery } from './pipeline';
import { readLiveApproval, type LiveApproval } from './live_policy';
import { createQueryPorts } from './indexing/query_ports';
import { runtime } from './indexing/runtime';
import type { Embedding } from './indexing/types';
import { policy, RagFailure, type Providers } from './types';

export const CALIBRATION_KEY = { ownerId: 'CONFIG#PHASE4', noteId: 'CALIBRATION' } as const;
const fixtures = loadFixtureFile(fixturesFile);
const fixtureById = new Map(fixtures.fixtures.map(f => [f.id, f]));
const required = (name: string) => {
  const value = process.env[name];
  if (!value || value.includes('<value will be resolved')) throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  return value;
};
function freeze<T>(value: T): T {
  if (value && typeof value === 'object') {
    Object.freeze(value);
    for (const child of Object.values(value)) freeze(child);
  }
  return value;
}

/**
 * Wraps a runtime embedding with the Phase 4 Cohere reservation. The reservation is async, so a
 * permit/consent/source change that lands while it is in flight must be revalidated by the
 * forwarded `beforeDispatch` callback before the raw paid embed; the callback is then forwarded
 * into the signed transport, which re-runs it after signing and immediately before the fetch.
 * `reserve` is called exactly once per embed and is never refunded.
 */
export function reserveCohere(
  embedding: Embedding,
  reserve: (signal: AbortSignal) => Promise<void>,
): Embedding {
  return Object.freeze({
    ...embedding,
    embed: async (texts, purpose, signal, beforeDispatch) => {
      await reserve(signal);
      if (typeof beforeDispatch === 'function') await beforeDispatch();
      return embedding.embed(texts, purpose, signal, beforeDispatch);
    },
  });
}

type ApprovalStore = {
  send(command: GetCommand, options: { abortSignal: AbortSignal }): Promise<{ Item?: Record<string, unknown> }>;
};

/** Storage failures are transport errors; they cannot be reported as an unconfigured policy. */
export async function readPublishedApproval(client: ApprovalStore, table: string, signal: AbortSignal): Promise<LiveApproval> {
  let item;
  try {
    item = (await client.send(new GetCommand({ TableName: table, Key: CALIBRATION_KEY, ConsistentRead: true }), { abortSignal: signal })).Item;
  } catch {
    console.log(JSON.stringify({ stage: 'approval-unavailable', validationStage: 'storage-read' }));
    throw new RagFailure(signal.aborted ? 'TIMEOUT' : 'PROVIDER_UNAVAILABLE');
  }
  let validationStage = 'question-binding';
  try {
    const Item = item;
    if (!Item || Item.questionSetHash !== contentHash(LIVE_QUESTION_SET)) throw new Error('unconfigured');
    validationStage = 'provenance';
    const frozen = freeze(structuredClone(Item.policy)) as CalibrationPolicy;
    const recording = Item.recording as RecordingFile;
    if (frozen.model !== JEV_MODEL || frozen.developmentRecordingProvenance !== LIVE_RECORDING_PROVENANCE ||
      recording.provenance !== LIVE_RECORDING_PROVENANCE) throw new Error('provenance');
    validationStage = 'confirmation';
    const report = evaluateConfirmation({ fixtureSet: fixtures, recording, policy: frozen });
    if (!report.gates.passed || report.fixtureHash !== fixtures.fixtureHash) throw new Error('gate');
    validationStage = 'live-policy';
    return readLiveApproval(Object.freeze({ model: JEV_MODEL, thresholds: Object.freeze({ ...frozen.thresholds }),
      fixtureVersion: frozen.fixtureVersion, calibrationVersion: frozen.calibrationVersion, retrievalStageMs: 6000 }));
  } catch {
    console.log(JSON.stringify({ stage: 'approval-unavailable', validationStage }));
    throw new RagFailure(signal.aborted ? 'TIMEOUT' : 'LIVE_POLICY_NOT_CONFIGURED');
  }
}

let handle: ReturnType<typeof createPrivateHandler> | undefined;
function compose() {
  if (required('RAG_PRIVATE_PHASE4') !== 'synthetic-only') throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  const region = required('RAG_REGION');
  const table = required('RAG_STATE_TABLE');
  const budget = createPhase4Budget(region, table);
  const count = loadDeepSeekCounter(required('RAG_DEEPSEEK_TOKENIZER_DIR'));
  const usage: ProviderUsage[] = [];
  const onUsage = (entry: ProviderUsage) => { usage.push(entry); console.log(JSON.stringify({ stage: 'provider-usage', ...entry })); };
  const rawProviders: Providers = {
    jev: createJevProvider({ apiKey: required('TYPESAFE_API_KEY'), onUsage }),
    generate: createDeepSeekProvider({ apiKey: required('DEEPSEEK_API_KEY'), onUsage, onDiagnostic: entry => console.log(JSON.stringify({ stage: 'generation-invalid-shape', ...entry })) }),
  };
  const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region, maxAttempts: 1 }));
  const approval = (signal: AbortSignal) => readPublishedApproval(ddb, table, signal);
  // Cohere/index clients are not loaded for calibration-only calls.
  let ports: ReturnType<typeof createQueryPorts> | undefined;
  let cohereCount: ReturnType<typeof runtime>['embedding']['count'] | undefined;
  const query = async (approved: LiveApproval, actor: string, request: Parameters<ReturnType<typeof createQuery>>[1], requestId: string, signal: AbortSignal) => {
    if (!ports) {
      const index = runtime();
      cohereCount = index.embedding.count;
      // One Cohere reservation, then the captured revalidation, then the raw signed embed: a
      // withdrawal during the Phase 4 counter window can never reach the provider.
      const embedding = reserveCohere(index.embedding, (io) => budget.reserve('cohere', 0, io));
      ports = createQueryPorts({ ...index, embedding });
    }
    const providers: Providers = {
      jev: async (input, signal, beforeDispatch) => {
        await budget.reserve('jev', jevInputUpperBound(JSON.stringify(input)), signal);
        if (typeof beforeDispatch === 'function') await beforeDispatch();
        return rawProviders.jev(input, signal);
      },
      generate: async (input, signal, beforeDispatch) => {
        const bound = deepSeekInputUpperBound(DEEPSEEK_SYSTEM_PROMPT + JSON.stringify({ question: input.question, evidence: input.evidence.text }));
        if (bound > 32_000) throw new RagFailure('INPUT_TOO_LONG');
        await budget.reserve('deepseek', bound, signal);
        if (typeof beforeDispatch === 'function') await beforeDispatch();
        return rawProviders.generate(input, signal);
      },
    };
    return createQuery({ ...ports, providers, liveApproval: approved, signal,
      config: { mode: 'live', model: JEV_MODEL, thresholds: approved.thresholds, jevMaxTokens: 32_000, requestTimeoutMs: 26_000 },
      counters: { embedding: cohereCount!, evidence: count, jev: jevInputUpperBound, output: count },
      consumeQuota: async (_actor, signal) => { await budget.reserve('query', 0, signal); return true; },
    })(actor, request, requestId);
  };
  return createPrivateHandler({ fixture: id => fixtureById.get(id), providers: rawProviders, usage, budget, approval, countOutput: count, query });
}

export async function handler(event: unknown) {
  try { handle ??= compose(); return await handle(event); }
  catch (error) { return { status: 'ERROR', code: error instanceof RagFailure ? error.code : 'LIVE_POLICY_NOT_CONFIGURED' }; }
}
