/**
 * Phase 5 HTTP entry tests: the exact route/method matrix, authorizer-only identity, the private
 * IAM forwarding path, the real `createRagHandler` envelope and the consent GET/PUT CAS generation
 * preservation. Every dependency is injected; no AWS, environment or model call is made.
 *
 * Runner: node --import tsx --test amplify/rag/phase5/http_lambda.test.ts
 */
import { mock, test } from 'node:test';
import assert from 'node:assert/strict';
import { DeleteCommand, GetCommand, TransactWriteCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import type { APIGatewayProxyEventV2WithJWTAuthorizer as Event } from 'aws-lambda';
import { chunkNote } from '../chunking';
import { CONSENT_VERSION } from '../contract';
import { countSyntheticTokens } from '../mock';
import { policy, sourceKey } from '../types';
import type { GenerateInput, JevInput, Providers, RagRequest, RagResponse } from '../types';
import { RagFailure } from '../types';
import { readLiveApproval } from '../live_policy';
import { fingerprint } from '../indexing/jobs';
import { checksum, embeddingInputDigest, policyIdentity, sha256Hex } from '../indexing/snapshot';
import type { Artifacts, Document, IndexDeps, IndexState, IndexStore, Manifest, Snapshot } from '../indexing/types';
import { createConsentHandler } from './consent_handler';
import type { ConsentGrant, ConsentStore } from './consent_store';
import { consentRowKey } from './consent_store';
import {
  createDefaultHandler, createPilotHttpHandler, composeProduction, EMBEDDING_CANARY_KIND,
  isEmbeddingCanaryEvent, queryAdmissionEnabled,
} from './http_lambda';
import type { PilotHttpDeps, PilotProductionSeam } from './http_lambda';
import type { PilotBudgetPort } from './pilot_budget';
import { PILOT_RELEASE_TIMEOUT_MS } from './pilot_query';
import { RUNTIME_CASE_HASH, RUNTIME_CONFIG_VERSION, RUNTIME_CORPUS_KIND } from './runtime_config';
import { LIVE_TOTAL_DEADLINE_MS } from '../live_policy';

const ACTOR = '00000001-0000-4000-8000-000000000001';

const QUERY_BODY = JSON.stringify({ wireVersion: 1, question: 'q', scope: { type: 'account' } });

const httpEvent = (patch: Record<string, unknown> = {}): Event => ({
  rawPath: '/ai/rag/query',
  headers: { 'content-type': 'application/json' },
  body: QUERY_BODY,
  isBase64Encoded: false,
  requestContext: {
    http: { method: 'POST' },
    authorizer: { jwt: { claims: { sub: ACTOR, token_use: 'access' } } },
  },
  ...patch,
} as unknown as Event);

const answering = (calls: RagRequest[]) => async (_actor: string, request: RagRequest, id: string): Promise<RagResponse> => {
  calls.push(request);
  return Object.freeze({ wireVersion: 1, requestId: id, status: 'ANSWERED', answer: 'alpha [S1]',
    sources: [{ sourceId: 'S1', noteId: 'n', revision: 1, title: 't', startOffset: 0, endOffset: 5, quote: 'alpha' }] });
};

const deps = (overrides: Partial<PilotHttpDeps> = {}): PilotHttpDeps => ({
  query: answering([]),
  consent: async () => createConsentHandler({ store: consentStore(), assertActor: () => {} }),
  requestId: () => 'req-1',
  ...overrides,
});

const consentStore = (grant?: ConsentGrant): ConsentStore => {
  const stored: ConsentGrant = grant ?? Object.freeze({ accepted: false, version: CONSENT_VERSION, generation: 0 });
  return {
    async read(): Promise<ConsentGrant> { return stored; },
    async write(_actor, write): Promise<ConsentGrant> {
      return Object.freeze({ accepted: write.accepted, version: write.version, generation: stored.generation + 1 });
    },
  };
};

test('an anonymous HTTP request is 401 and never reaches the query', async () => {
  const calls: RagRequest[] = [];
  const handler = createPilotHttpHandler(deps({ query: answering(calls) }));
  const response = await handler(httpEvent({ requestContext: { http: { method: 'POST' } } })) as { statusCode: number; body: string };
  assert.equal(response.statusCode, 401);
  assert.match(response.body, /"code":"UNAUTHORIZED"/);
  assert.equal(calls.length, 0);
});

test('an ID token is 401 and never reaches the query', async () => {
  const calls: RagRequest[] = [];
  const handler = createPilotHttpHandler(deps({ query: answering(calls) }));
  const response = await handler(httpEvent({
    requestContext: { http: { method: 'POST' }, authorizer: { jwt: { claims: { sub: ACTOR, token_use: 'id' } } } },
  })) as { statusCode: number };
  assert.equal(response.statusCode, 401);
  assert.equal(calls.length, 0);
});

test('an unknown path and a wrong method cannot invoke a handler or a provider', async () => {
  const calls: RagRequest[] = [];
  let privateCalls = 0;
  const handler = createPilotHttpHandler(deps({ query: answering(calls), privateHandler: async () => { privateCalls += 1; } }));
  const unknown = await handler(httpEvent({ rawPath: '/ai/rag/other' })) as { statusCode: number; body: string };
  assert.equal(unknown.statusCode, 404);
  assert.match(unknown.body, /"code":"SCOPE_DENIED"/);
  const wrongMethod = await handler(httpEvent({ requestContext: { http: { method: 'GET' }, authorizer: { jwt: { claims: { sub: ACTOR, token_use: 'access' } } } } })) as { statusCode: number };
  assert.equal(wrongMethod.statusCode, 400);
  assert.equal(calls.length, 0);
  assert.equal(privateCalls, 0);
});

test('a private operation cannot be smuggled through an HTTP body', async () => {
  const calls: RagRequest[] = [];
  let privateCalls = 0;
  const handler = createPilotHttpHandler(deps({ query: answering(calls), privateHandler: async () => { privateCalls += 1; } }));
  const response = await handler(httpEvent({ body: JSON.stringify({ operation: 'reconcile', fixture: 'f1' }) })) as { statusCode: number };
  assert.equal(response.statusCode, 400);
  assert.equal(calls.length, 0);
  assert.equal(privateCalls, 0);
});

test('a non-HTTP invocation is forwarded unchanged to the private phase 4 handler', async () => {
  const payload = { operation: 'reconcile', fixture: 'f1' };
  const seen: unknown[] = [];
  const handler = createPilotHttpHandler(deps({ privateHandler: async (event) => { seen.push(event); return { ok: true }; } }));
  const result = await handler(payload);
  assert.deepEqual(seen, [payload]);
  assert.deepEqual(result, { ok: true });
});

test('the real rag handler produces the canonical answered envelope', async () => {
  const handler = createPilotHttpHandler(deps());
  const response = await handler(httpEvent()) as { statusCode: number; body: string };
  assert.equal(response.statusCode, 200);
  assert.deepEqual(JSON.parse(response.body), {
    wireVersion: 1, requestId: 'req-1', status: 'ANSWERED', answer: 'alpha [S1]',
    sources: [{ sourceId: 'S1', noteId: 'n', revision: 1, title: 't', startOffset: 0, endOffset: 5, quote: 'alpha' }],
  });
});

test('the consent route keeps a listed owner able to read/revoke generation 2 while disabled', async () => {
  const store = consentStore(Object.freeze({ accepted: false, version: CONSENT_VERSION, generation: 2 }));
  const handler = createPilotHttpHandler(deps({
    consent: async () => createConsentHandler({ store, assertActor: (actor) => {
      // Listed-owner membership, not admission: enabled is deliberately false.
      if (actor !== ACTOR) throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
    } }),
  }));
  const get = await handler(httpEvent({ rawPath: '/ai/rag/consent', body: undefined, requestContext: { http: { method: 'GET' }, authorizer: { jwt: { claims: { sub: ACTOR, token_use: 'access' } } } } })) as { statusCode: number; body: string };
  assert.equal(get.statusCode, 200);
  assert.deepEqual(JSON.parse(get.body).consent, { accepted: false, version: CONSENT_VERSION, generation: 2 });

  const put = await handler(httpEvent({
    rawPath: '/ai/rag/consent',
    body: JSON.stringify({ accepted: true, version: CONSENT_VERSION, expectedGeneration: 2 }),
    requestContext: { http: { method: 'PUT' }, authorizer: { jwt: { claims: { sub: ACTOR, token_use: 'access' } } } },
  })) as { statusCode: number; body: string };
  assert.equal(put.statusCode, 200);
  assert.deepEqual(JSON.parse(put.body).consent, { accepted: true, version: CONSENT_VERSION, generation: 3 });
});

test('a non-listed consent actor is a bounded 503 with zero store reads', async () => {
  let reads = 0;
  const store: ConsentStore = {
    async read(): Promise<ConsentGrant> { reads += 1; return Object.freeze({ accepted: false, version: CONSENT_VERSION, generation: 0 }); },
    async write(): Promise<ConsentGrant> { reads += 1; return Object.freeze({ accepted: false, version: CONSENT_VERSION, generation: 0 }); },
  };
  const handler = createPilotHttpHandler(deps({
    consent: async () => createConsentHandler({ store, assertActor: () => { throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED'); } }),
  }));
  const response = await handler(httpEvent({ rawPath: '/ai/rag/consent', body: undefined, requestContext: { http: { method: 'GET' }, authorizer: { jwt: { claims: { sub: '00000009-0000-4000-8000-000000000009', token_use: 'access' } } } } })) as { statusCode: number; body: string };
  assert.equal(response.statusCode, 503);
  assert.ok(!response.body.includes(ACTOR));
  assert.equal(reads, 0);
});

test('the consent factory runs inside the request deadline and a late factory is bounded', async () => {
  let seenSignal: AbortSignal | undefined;
  const handler = createPilotHttpHandler(deps({
    consent: async (signal) => { seenSignal = signal; return createConsentHandler({ store: consentStore(), assertActor: () => {} }); },
  }));
  await handler(httpEvent({ rawPath: '/ai/rag/consent', body: undefined, requestContext: { http: { method: 'GET' }, authorizer: { jwt: { claims: { sub: ACTOR, token_use: 'access' } } } } }));
  assert.ok(seenSignal instanceof AbortSignal);
});

/* ------------------------------------------------------------------ *
 * Groups 1 + 2: the default production entry. Routing is first and
 * composition is lazy; consent uses the notes table, config/budget the
 * state table; a non-HTTP private event triggers no Phase 5 setup.
 * ------------------------------------------------------------------ */

type Row = Record<string, unknown>;
const NOTES_TABLE = 'notes-table';
const STATE_TABLE = 'state-table';
const TITLE = 'Tieu de n-a';
const CONTENT = Array.from({ length: 220 }, (_, index) => `doan ${index} noi ve alpha beta gamma cua a`).join('. ');

const configValue = {
  version: RUNTIME_CONFIG_VERSION,
  generation: 1,
  policy: { enabled: true, owners: [ACTOR], model: 'jev-1.13.0',
    thresholds: { answerabilityMin: 0.85, conflictMax: 0.1 } },
  corpus: { kind: RUNTIME_CORPUS_KIND, caseHash: RUNTIME_CASE_HASH,
    owners: { [ACTOR]: [{ noteId: 'n-a', inputDigest: embeddingInputDigest(TITLE, CONTENT) }] } },
};

const approval = readLiveApproval(Object.freeze({
  model: 'jev-1.13.0',
  thresholds: Object.freeze({ answerabilityMin: 0.85, conflictMax: 0.1 }),
  fixtureVersion: 'fix-1', calibrationVersion: 'cal-1',
}));

const keyOf = (key: Row): string => `${String(key['ownerId'])}\u0000${String(key['noteId'])}`;

const vector1024 = (seed: number): readonly number[] =>
  Object.freeze(Array.from({ length: policy.embedding.dimensions }, (_, index) => (index === seed % 8 ? 1 : 0)));

/** The real budget/consent/config commands over a fake document client, applied atomically. */
const documentFake = (stateItems: Map<string, Row>) => {
  const notesItems = new Map<string, Row>();
  const commands: Row[] = [];
  const client: PilotBudgetPort = {
    async send(command: unknown): Promise<unknown> {
      const input = (command as { input: Row }).input;
      const table = input['TableName'];
      const transactItems = (input['TransactItems'] as readonly Row[] | undefined) ?? [];
      const tables = transactItems.length > 0
        ? transactItems.map((entry) =>
          String(((entry['ConditionCheck'] ?? entry['Update'] ?? entry['Put']) as Row)['TableName']))
        : [String(table)];
      commands.push({ kind: (command as object).constructor.name, table, tables, input });
      if (command instanceof GetCommand) {
        const map = input['TableName'] === STATE_TABLE ? stateItems : notesItems;
        const item = map.get(keyOf(input['Key'] as Row));
        return item === undefined ? {} : { Item: item };
      }
      if (command instanceof UpdateCommand || command instanceof DeleteCommand) return {};
      if (command instanceof TransactWriteCommand) {
        for (const entry of (input['TransactItems'] as readonly Row[]) ?? []) {
          const check = entry['ConditionCheck'] as Row | undefined;
          if (check !== undefined) {
            const stored = stateItems.get(keyOf(check['Key'] as Row))?.['config'];
            const captured = (check['ExpressionAttributeValues'] as Row)[':capturedConfig'];
            if (JSON.stringify(stored) !== JSON.stringify(captured)) {
              throw Object.assign(new Error('cancelled'), {
                name: 'TransactionCanceledException',
                CancellationReasons: [{ Code: 'ConditionalCheckFailed' }],
              });
            }
          }
          const update = entry['Update'] as Row | undefined;
          if (update !== undefined) {
            const key = update['Key'] as Row;
            const values = (update['ExpressionAttributeValues'] ?? {}) as Row;
            const map = update['TableName'] === STATE_TABLE ? stateItems : notesItems;
            const current = map.get(keyOf(key)) ?? {};
            const next: Row = { ...current, ownerId: key['ownerId'], noteId: key['noteId'] };
            if (values[':accepted'] !== undefined) {
              next['accepted'] = values[':accepted'];
              next['version'] = values[':version'];
              next['generation'] = values[':generation'];
            }
            map.set(keyOf(key), next);
          }
          const put = entry['Put'] as Row | undefined;
          if (put !== undefined) {
            const item = put['Item'] as Row;
            const map = put['TableName'] === STATE_TABLE ? stateItems : notesItems;
            map.set(keyOf(item), item);
          }
        }
        return {};
      }
      return {};
    },
  };
  return { client, commands, notesItems, stateItems };
};

const syntheticIndex = (): Readonly<{ deps: IndexDeps; counts: { loads: number; embeds: number; texts: string[] } }> => {
  const counts = { loads: 0, embeds: 0, texts: [] as string[] };
  const baseNote = {
    ownerId: ACTOR, noteId: 'n-a', revision: 7, title: TITLE, content: CONTENT,
    synced: true, protected: false, deleted: false, available: true, protectionRevision: 0,
  };
  const documents: readonly Document[] = Object.freeze(
    chunkNote(baseNote, countSyntheticTokens).map((chunk) => Object.freeze({
      chunk, vectorKey: sha256Hex(`vector\u0000${sourceKey(chunk)}`),
      embeddingDigest: sha256Hex(`digest\u0000${sourceKey(chunk)}`),
    })),
  );
  const base: IndexState = {
    ownerId: ACTOR, accountEpoch: 3,
    consent: Object.freeze({ accepted: true, version: CONSENT_VERSION, generation: 2 }),
    notes: Object.freeze([baseNote]), manifest: null,
  };
  const version = 'v1';
  const snapshot: Snapshot = Object.freeze({
    schemaVersion: 1, ownerId: ACTOR, version, consentGeneration: 2, accountEpoch: 3,
    policyIdentity: policyIdentity(), documents,
  });
  const manifest: Manifest = Object.freeze({
    ownerId: ACTOR, generation: 1, version, fingerprint: fingerprint(base),
    consentGeneration: 2, accountEpoch: 3, status: 'READY',
    snapshotKey: 'snap', checksum: checksum(snapshot), policyIdentity: policyIdentity(),
  });
  const ready: IndexState = Object.freeze({ ...base, manifest });
  const store: IndexStore = {
    async load() { counts.loads += 1; return ready; },
    async acquire() { return null; },
    async publish() { return false; },
    async finish() {},
    async reserveEmbedding() {},
  };
  const artifacts: Artifacts = {
    async read() { return snapshot; },
    async put() { return { key: 'k', checksum: sha256Hex('put') }; },
    async putVectors() {},
    async getVectors(keys) { return new Map(keys.map((key, index) => [key, vector1024(index)] as const)); },
    async query(_vector, ownerId, _version, noteId) {
      return documents
        .filter((document) => document.chunk.ownerId === ownerId && (noteId === null || document.chunk.noteId === noteId))
        .map((document) => document.vectorKey);
    },
    async cleanup() {},
  };
  const embedding = {
    count: countSyntheticTokens,
    async embed(texts: readonly string[]) {
      counts.embeds += 1;
      counts.texts.push(...texts);
      return texts.map((_text, index) => vector1024(index));
    },
  };
  return Object.freeze({ deps: { store, artifacts, embedding }, counts });
};

const jevEnvelope = (input: JevInput): unknown => ({
  model: 'jev-1.13.0',
  answers: {
    answerable_from_evidence: { type: 'noul', noul: 0.96 },
    has_unresolved_conflict: { type: 'noul', noul: 0.03 },
  },
  usage: { input_tokens: countSyntheticTokens(JSON.stringify(input)), output_tokens: 10 },
});

const generateEnvelope = (input: GenerateInput): unknown => {
  const first = input.evidence.sources[0];
  if (first === undefined) throw new RagFailure('EVIDENCE_VALIDATION_UNAVAILABLE');
  return { answer: `Theo nguồn [${first.sourceId}]`, sources: [{ ...first }] };
};

const syntheticProviders = (counts: { jev: number; generate: number }): Providers => ({
  async jev(input) { counts.jev += 1; return jevEnvelope(input); },
  async generate(input) { counts.generate += 1; return generateEnvelope(input); },
});

const withEnv = async (env: Readonly<Record<string, string>>, run: () => Promise<void>): Promise<void> => {
  const saved: Record<string, string | undefined> = {};
  for (const [key, value] of Object.entries(env)) {
    saved[key] = process.env[key];
    process.env[key] = value;
  }
  try {
    await run();
  } finally {
    for (const [key, value] of Object.entries(saved)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
};

const consentGet = (): Event => httpEvent({
  rawPath: '/ai/rag/consent', body: undefined,
  requestContext: { http: { method: 'GET' }, authorizer: { jwt: { claims: { sub: ACTOR, token_use: 'access' } } } },
});

test('the default consent GET/PUT target the notes table while the config stays on the state table', async () => {
  const stateItems = new Map<string, Row>([
    [keyOf({ ownerId: 'CONFIG#PHASE5', noteId: 'PILOT' }),
      { ownerId: 'CONFIG#PHASE5', noteId: 'PILOT', config: configValue }],
  ]);
  const fake = documentFake(stateItems);
  await withEnv({ RAG_REGION: 'ap-southeast-1', RAG_STATE_TABLE: STATE_TABLE, RAG_NOTES_TABLE: NOTES_TABLE }, async () => {
    const seam: PilotProductionSeam = {
      client: () => fake.client,
      requestId: () => 'req-1',
      loadIndex: () => { throw new Error('consent must not load the index'); },
      countOutput: () => { throw new Error('consent must not load the tokenizer'); },
    };
    const handler = createDefaultHandler(seam);
    const get = await handler(consentGet()) as { statusCode: number; body: string };
    assert.equal(get.statusCode, 200);
    assert.deepEqual(JSON.parse(get.body).consent, { accepted: false, version: CONSENT_VERSION, generation: 0 });

    const put = await handler(httpEvent({
      rawPath: '/ai/rag/consent',
      body: JSON.stringify({ accepted: true, version: CONSENT_VERSION, expectedGeneration: 0 }),
      requestContext: { http: { method: 'PUT' }, authorizer: { jwt: { claims: { sub: ACTOR, token_use: 'access' } } } },
    })) as { statusCode: number; body: string };
    assert.equal(put.statusCode, 200);
    assert.deepEqual(JSON.parse(put.body).consent, { accepted: true, version: CONSENT_VERSION, generation: 1 });

    // The canonical consent row is read and written on the notes table.
    const consentKey = keyOf(consentRowKey(ACTOR) as Row);
    assert.ok(fake.commands.some((command) =>
      command['table'] === NOTES_TABLE && command['kind'] === 'GetCommand' &&
      keyOf((command['input'] as Row)['Key'] as Row) === consentKey));
    const write = fake.commands.find((command) => command['kind'] === 'TransactWriteCommand');
    assert.ok(write !== undefined, 'the consent PUT commits one transaction');
    const transact = (write['input'] as Row)['TransactItems'] as Row[];
    assert.equal((transact[0]?.['ConditionCheck'] as Row)['TableName'], STATE_TABLE);
    assert.equal((transact[1]?.['Update'] as Row)['TableName'], NOTES_TABLE);
    // The config read stayed on the state table only.
    assert.ok(fake.commands.some((command) =>
      command['table'] === STATE_TABLE && command['kind'] === 'GetCommand' &&
      keyOf((command['input'] as Row)['Key'] as Row) === keyOf({ ownerId: 'CONFIG#PHASE5', noteId: 'PILOT' })));
    assert.ok(fake.commands.every((command) =>
      (command['tables'] as string[]).every((table) => table === STATE_TABLE || table === NOTES_TABLE)));
  });
});

test('the default query path composes lazily and keeps config/budget on the state table', async () => {
  const stateItems = new Map<string, Row>([
    [keyOf({ ownerId: 'CONFIG#PHASE5', noteId: 'PILOT' }),
      { ownerId: 'CONFIG#PHASE5', noteId: 'PILOT', config: configValue }],
  ]);
  const fake = documentFake(stateItems);
  const index = syntheticIndex();
  const providerCalls = { jev: 0, generate: 0 };
  await withEnv({
    RAG_REGION: 'ap-southeast-1', RAG_STATE_TABLE: STATE_TABLE, RAG_NOTES_TABLE: NOTES_TABLE,
    RAG_QUERY_ADMISSION_ENABLED: 'true',
  }, async () => {
    let loads = 0;
    const seam: PilotProductionSeam = {
      client: () => fake.client,
      requestId: () => 'req-1',
      loadIndex: () => { loads += 1; return index.deps; },
      countOutput: () => countSyntheticTokens,
      readApproval: async () => approval,
      rawProviders: syntheticProviders(providerCalls),
    };
    const handler = createDefaultHandler(seam);
    const response = await handler(httpEvent()) as { statusCode: number; body: string };
    assert.equal(response.statusCode, 200, response.body);
    assert.equal(JSON.parse(response.body).status, 'ANSWERED');
    assert.equal(loads, 1, 'the index factory is lazy but used once');
    assert.equal(providerCalls.jev, 1);
    assert.equal(providerCalls.generate, 1);
    // Every AWS command on the query path was issued against the state table; the notes table is
    // only the consent row and is never touched by a query.
    assert.ok(fake.commands.length > 0);
    assert.ok(
      fake.commands.every((command) => (command['tables'] as string[]).every((table) => table === STATE_TABLE)),
      'no query command targets the notes table',
    );
    assert.ok(fake.commands.some((command) => command['kind'] === 'TransactWriteCommand'), 'query admission is a transaction');
    assert.ok(fake.commands.some((command) => command['kind'] === 'UpdateCommand'), 'a provider reservation is an update');
  });
});

test('a non-HTTP private invocation is forwarded with zero Phase 5 composition', async () => {
  const payload = { operation: 'budget' };
  const seen: unknown[] = [];
  const handler = createDefaultHandler({
    client: () => { throw new Error('Phase 5 client must not be built for a private event'); },
    countOutput: () => { throw new Error('Phase 5 tokenizer must not be loaded for a private event'); },
    loadIndex: () => { throw new Error('Phase 5 index must not be loaded for a private event'); },
    privateHandler: async (event) => { seen.push(event); return { status: 'OK' }; },
  });
  assert.deepEqual(await handler(payload), { status: 'OK' });
  assert.deepEqual(seen, [payload]);
});

test('the exact IAM canary embeds fixed synthetic text once and returns metadata only', async () => {
  const fake = documentFake(new Map());
  const index = syntheticIndex();
  let privateCalls = 0;
  await withEnv({
    RAG_REGION: 'ap-southeast-1', RAG_STATE_TABLE: STATE_TABLE, RAG_NOTES_TABLE: NOTES_TABLE,
  }, async () => {
    const handler = createDefaultHandler({
      client: () => fake.client,
      requestId: () => 'req-1',
      loadIndex: () => index.deps,
      countOutput: () => countSyntheticTokens,
      privateHandler: async () => { privateCalls += 1; return { leaked: true }; },
    });
    assert.equal(isEmbeddingCanaryEvent({ kind: EMBEDDING_CANARY_KIND }), true);
    assert.equal(isEmbeddingCanaryEvent({ kind: EMBEDDING_CANARY_KIND, text: 'note body' }), false);
    assert.equal(isEmbeddingCanaryEvent({ kind: 'embedding-canary.v2' }), false);

    const result = await handler({ kind: EMBEDDING_CANARY_KIND }) as Record<string, unknown>;
    assert.equal(result['status'], 'OK');
    assert.equal(result['canary'], EMBEDDING_CANARY_KIND);
    assert.equal(result['dimensions'], policy.embedding.dimensions);
    assert.equal(typeof result['norm'], 'number');
    assert.ok((result['norm'] as number) > 0);
    assert.equal(result['finite'], true);
    assert.deepEqual(result['profile'], {
      model: 'embeddinggemma2', dimensions: policy.embedding.dimensions,
    });
    assert.equal(typeof (result['timing'] as Row)['totalMs'], 'number');
    const tokenizerCounts = result['tokenizerCounts'] as Row;
    assert.equal(typeof tokenizerCounts['embedding'], 'number');
    assert.equal(typeof tokenizerCounts['deepseek'], 'number');
    // No caller text, vector, credentials or provider payload is echoed.
    assert.ok(!('vector' in result) && !('vectors' in result));
    assert.ok(!JSON.stringify(result).includes('synthetic embedding canary'));
    assert.equal(privateCalls, 0);
    assert.equal(index.counts.embeds, 1);
    assert.equal(index.counts.texts.length, 1);
    assert.match(index.counts.texts[0] as string, /^NoteFlow synthetic embedding canary/);
    // The one budget reservation is on the state table; no canonical note read was issued.
    assert.ok(fake.commands.some((command) => command['kind'] === 'TransactWriteCommand'));
    assert.ok(fake.commands.every((command) =>
      (command['tables'] as string[]).every((table) => table === STATE_TABLE)));
  });
});

test('a canary-like payload with extra keys or another kind stays a private forward', async () => {
  let canaryCalls = 0;
  let privateCalls = 0;
  const seen: unknown[] = [];
  const handler = createPilotHttpHandler(deps({
    canary: async () => { canaryCalls += 1; return { status: 'OK' }; },
    privateHandler: async (event) => { privateCalls += 1; seen.push(event); return { private: true }; },
  }));
  const payloads: readonly object[] = [
    { kind: EMBEDDING_CANARY_KIND, text: 'note body' },
    { kind: EMBEDDING_CANARY_KIND, model: 'other' },
    { kind: 'embedding-canary.v2' },
    {},
  ];
  for (const payload of payloads) {
    assert.deepEqual(await handler(payload), { private: true });
  }
  assert.equal(canaryCalls, 0);
  assert.equal(privateCalls, payloads.length);
  assert.deepEqual(seen, payloads);
});

test('a canary event with no injected runner fails closed and never reaches the private handler', async () => {
  let privateCalls = 0;
  const handler = createPilotHttpHandler(deps({
    privateHandler: async () => { privateCalls += 1; return { private: true }; },
  }));
  assert.deepEqual(await handler({ kind: EMBEDDING_CANARY_KIND }), {
    status: 'ERROR', canary: EMBEDDING_CANARY_KIND, code: 'LIVE_POLICY_NOT_CONFIGURED',
  });
  assert.equal(privateCalls, 0);
});

test('an HTTP event carrying a canary kind still routes to consent and never the canary', async () => {
  let canaryCalls = 0;
  let privateCalls = 0;
  const store = consentStore(Object.freeze({ accepted: false, version: CONSENT_VERSION, generation: 2 }));
  const handler = createPilotHttpHandler(deps({
    canary: async () => { canaryCalls += 1; return { status: 'OK' }; },
    consent: async () => createConsentHandler({ store, assertActor: () => {} }),
    privateHandler: async () => { privateCalls += 1; return { private: true }; },
  }));
  const response = await handler(httpEvent({
    kind: EMBEDDING_CANARY_KIND,
    rawPath: '/ai/rag/consent',
    body: undefined,
    requestContext: { http: { method: 'GET' }, authorizer: { jwt: { claims: { sub: ACTOR, token_use: 'access' } } } },
  })) as { statusCode: number; body: string };
  assert.equal(response.statusCode, 200);
  assert.deepEqual(JSON.parse(response.body).consent, {
    accepted: false, version: CONSENT_VERSION, generation: 2,
  });
  assert.equal(canaryCalls, 0);
  assert.equal(privateCalls, 0);

  // A public JWT body cannot inject the top-level kind the IAM canary requires.
  const bodyKind = await handler(httpEvent({
    body: JSON.stringify({ kind: EMBEDDING_CANARY_KIND }),
  })) as { statusCode: number; body: string };
  assert.equal(bodyKind.statusCode, 400);
  assert.equal(JSON.parse(bodyKind.body).code, 'INVALID_INPUT');
  assert.equal(canaryCalls, 0);
  assert.equal(privateCalls, 0);
});

test('a canary with a failed budget or adapter returns a safe code and never echoes detail', async () => {
  const index = syntheticIndex();
  const denyAll: PilotBudgetPort = {
    async send(): Promise<unknown> {
      throw Object.assign(new Error('raw provider detail'), { name: 'AccessDeniedException' });
    },
  };
  await withEnv({
    RAG_REGION: 'ap-southeast-1', RAG_STATE_TABLE: STATE_TABLE, RAG_NOTES_TABLE: NOTES_TABLE,
  }, async () => {
    const handler = createDefaultHandler({
      client: () => denyAll,
      requestId: () => 'req-1',
      loadIndex: () => index.deps,
      countOutput: () => countSyntheticTokens,
    });
    const denied = await handler({ kind: EMBEDDING_CANARY_KIND }) as Record<string, unknown>;
    assert.deepEqual(denied, {
      status: 'ERROR', canary: EMBEDDING_CANARY_KIND, code: 'PROVIDER_UNAVAILABLE',
    });
    assert.equal(index.counts.embeds, 0, 'no dispatch before a successful reservation');
  });

  const fake = documentFake(new Map());
  const failing = {
    ...index.deps,
    embedding: {
      count: countSyntheticTokens,
      async embed(): Promise<readonly (readonly number[])[]> {
        throw new RagFailure('PROVIDER_UNAVAILABLE');
      },
    },
  };
  await withEnv({
    RAG_REGION: 'ap-southeast-1', RAG_STATE_TABLE: STATE_TABLE, RAG_NOTES_TABLE: NOTES_TABLE,
  }, async () => {
    const handler = createDefaultHandler({
      client: () => fake.client,
      requestId: () => 'req-1',
      loadIndex: () => failing,
      countOutput: () => countSyntheticTokens,
    });
    assert.deepEqual(await handler({ kind: EMBEDDING_CANARY_KIND }), {
      status: 'ERROR', canary: EMBEDDING_CANARY_KIND, code: 'PROVIDER_UNAVAILABLE',
    });
  });
});

test('the default query stops before any paid dispatch when cold composition outlives the budget', async () => {
  const stateItems = new Map<string, Row>([
    [keyOf({ ownerId: 'CONFIG#PHASE5', noteId: 'PILOT' }),
      { ownerId: 'CONFIG#PHASE5', noteId: 'PILOT', config: configValue }],
  ]);
  const fake = documentFake(stateItems);
  const index = syntheticIndex();
  const providerCalls = { jev: 0, generate: 0 };
  await withEnv({
    RAG_REGION: 'ap-southeast-1', RAG_STATE_TABLE: STATE_TABLE, RAG_NOTES_TABLE: NOTES_TABLE,
    RAG_QUERY_ADMISSION_ENABLED: 'true',
  }, async () => {
    let clock = 0;
    let loads = 0;
    const handler = createDefaultHandler({
      client: () => fake.client,
      requestId: () => 'req-1',
      now: () => clock,
      // A synchronous cold tokenizer load that overruns the 26s request budget.
      countOutput: () => { clock += 30_000; return countSyntheticTokens; },
      loadIndex: () => { loads += 1; return index.deps; },
      readApproval: async () => approval,
      rawProviders: syntheticProviders(providerCalls),
    });
    const response = await handler(httpEvent()) as { statusCode: number; body: string };
    assert.equal(response.statusCode, 504);
    assert.equal(JSON.parse(response.body).code, 'TIMEOUT');
    assert.equal(loads, 0, 'no canonical index composition after the deadline');
    assert.equal(providerCalls.jev, 0);
    assert.equal(providerCalls.generate, 0);
    assert.equal(fake.commands.length, 0, 'no AWS command after the deadline');
  });
});

/* ------------------------------------------------------------------ *
 * Group 3: the production entry's paid-dispatch/deadline edges.
 * ------------------------------------------------------------------ */

const CONFIG_ITEM_KEY = keyOf({ ownerId: 'CONFIG#PHASE5', noteId: 'PILOT' });
const accountRequest = (): RagRequest => ({ wireVersion: 1, question: 'q', scope: { type: 'account' } });

const flush = async (turns = 80): Promise<void> => {
  for (let index = 0; index < turns; index += 1) await Promise.resolve();
};

const until = async (predicate: () => boolean, turns = 500): Promise<void> => {
  for (let index = 0; index < turns && !predicate(); index += 1) await Promise.resolve();
};

const stateWithConfig = (config: Row): Map<string, Row> =>
  new Map<string, Row>([[CONFIG_ITEM_KEY, { ownerId: 'CONFIG#PHASE5', noteId: 'PILOT', config }]]);

const moveConfig = (stateItems: Map<string, Row>, generation: number): void => {
  stateItems.set(CONFIG_ITEM_KEY, {
    ownerId: 'CONFIG#PHASE5', noteId: 'PILOT', config: { ...configValue, generation },
  });
};

const consentPut = (expectedGeneration: number): Event => httpEvent({
  rawPath: '/ai/rag/consent',
  body: JSON.stringify({ accepted: true, version: CONSENT_VERSION, expectedGeneration }),
  requestContext: { http: { method: 'PUT' }, authorizer: { jwt: { claims: { sub: ACTOR, token_use: 'access' } } } },
});

const QUERY_ENV = Object.freeze({
  RAG_REGION: 'ap-southeast-1', RAG_STATE_TABLE: STATE_TABLE, RAG_NOTES_TABLE: NOTES_TABLE,
  RAG_QUERY_ADMISSION_ENABLED: 'true',
});

test('query admission is explicit and defaults off', () => {
  assert.equal(queryAdmissionEnabled({}), false);
  assert.equal(queryAdmissionEnabled({ RAG_QUERY_ADMISSION_ENABLED: 'false' }), false);
  assert.equal(queryAdmissionEnabled({ RAG_QUERY_ADMISSION_ENABLED: '1' }), false);
  assert.equal(queryAdmissionEnabled({ RAG_QUERY_ADMISSION_ENABLED: 'TRUE' }), false);
  assert.equal(queryAdmissionEnabled({ RAG_QUERY_ADMISSION_ENABLED: 'true' }), true);
});

test('admission off refuses the query before any config, index, lease or provider call', async () => {
  const fake = documentFake(stateWithConfig(configValue));
  const providerCalls = { jev: 0, generate: 0 };
  let loads = 0;
  await withEnv({
    RAG_REGION: 'ap-southeast-1', RAG_STATE_TABLE: STATE_TABLE, RAG_NOTES_TABLE: NOTES_TABLE,
    RAG_QUERY_ADMISSION_ENABLED: 'false',
  }, async () => {
    const handler = createDefaultHandler({
      client: () => fake.client,
      requestId: () => 'req-1',
      loadIndex: () => { loads += 1; return syntheticIndex().deps; },
      countOutput: () => { throw new Error('admission off must not load the tokenizer'); },
      readApproval: async () => approval,
      rawProviders: syntheticProviders(providerCalls),
    });
    const response = await handler(httpEvent()) as { statusCode: number; body: string };
    assert.equal(response.statusCode, 503, response.body);
    assert.equal(JSON.parse(response.body).code, 'PROVIDER_UNAVAILABLE');
    assert.equal(loads, 0);
    assert.equal(providerCalls.jev, 0);
    assert.equal(providerCalls.generate, 0);
    assert.equal(fake.commands.length, 0, 'no config/lease/budget read happened');
  });
});

test('the consent route works while query admission is off', async () => {
  const disabled = { ...configValue, policy: { ...configValue.policy, enabled: false } };
  const fake = documentFake(stateWithConfig(disabled));
  await withEnv({
    RAG_REGION: 'ap-southeast-1', RAG_STATE_TABLE: STATE_TABLE, RAG_NOTES_TABLE: NOTES_TABLE,
    RAG_QUERY_ADMISSION_ENABLED: 'false',
  }, async () => {
    const handler = createDefaultHandler({ client: () => fake.client, requestId: () => 'req-1' });
    const get = await handler(consentGet()) as { statusCode: number; body: string };
    assert.equal(get.statusCode, 200, get.body);
    assert.deepEqual(JSON.parse(get.body).consent, { accepted: false, version: CONSENT_VERSION, generation: 0 });
  });
});

test('the production query budget plus its bounded lease release fits the 28s Lambda', () => {
  assert.ok(LIVE_TOTAL_DEADLINE_MS + PILOT_RELEASE_TIMEOUT_MS <= 28_000);
});

test('the production query awaits a slow lease release before returning a provider failure', async (t) => {
  t.after(() => mock.timers.reset());
  mock.timers.enable({ apis: ['setTimeout'] });
  const fake = documentFake(stateWithConfig(configValue));
  const index = syntheticIndex();
  const base = fake.client;
  let releaseStarted = 0;
  let releaseFinished = false;
  const client: PilotBudgetPort = {
    async send(command: unknown, options?: unknown): Promise<unknown> {
      if (command instanceof DeleteCommand) {
        releaseStarted += 1;
        // A slow-but-completing release, independent of the request deadline.
        await new Promise((resolve) => setTimeout(resolve, 300));
        releaseFinished = true;
        return {};
      }
      return (base.send.bind(base) as (c: unknown, o?: unknown) => Promise<unknown>)(command, options);
    },
  };
  await withEnv(QUERY_ENV, async () => {
    const deps = composeProduction({
      client: () => client,
      requestId: () => 'req-1',
      loadIndex: () => index.deps,
      countOutput: () => countSyntheticTokens,
      readApproval: async () => approval,
      rawProviders: {
        async jev() { throw new RagFailure('PROVIDER_UNAVAILABLE'); },
        async generate() { throw new RagFailure('PROVIDER_UNAVAILABLE'); },
      },
    });
    const pending = deps.query(ACTOR, accountRequest(), 'req-1');
    await until(() => releaseStarted === 1);
    let settled = false;
    void pending.then(() => { settled = true; }, () => { settled = true; });
    await flush();
    assert.equal(settled, false, 'the wire waits for the independent lease release');
    assert.equal(releaseFinished, false);
    mock.timers.tick(300);
    await flush();
    const response = await pending;
    assert.equal(response.status, 'ERROR');
    if (response.status !== 'ERROR') throw new Error('expected an error envelope');
    assert.equal(response.code, 'PROVIDER_UNAVAILABLE');
    assert.equal(releaseFinished, true);
  });
});

test('the production query never races away a hung lease release on timeout', async (t) => {
  t.after(() => mock.timers.reset());
  mock.timers.enable({ apis: ['setTimeout'] });
  const fake = documentFake(stateWithConfig(configValue));
  const index = syntheticIndex();
  const base = fake.client;
  let releaseStarted = 0;
  let releaseFinished = false;
  let releaseNow!: () => void;
  const held = new Promise<void>((resolve) => { releaseNow = resolve; });
  const client: PilotBudgetPort = {
    async send(command: unknown, options?: unknown): Promise<unknown> {
      if (command instanceof DeleteCommand) {
        releaseStarted += 1;
        await held;
        releaseFinished = true;
        return {};
      }
      return (base.send.bind(base) as (c: unknown, o?: unknown) => Promise<unknown>)(command, options);
    },
  };
  await withEnv(QUERY_ENV, async () => {
    // The provider hangs until the shared 26s deadline aborts the request.
    const hang = new Promise<never>(() => {});
    const deps = composeProduction({
      client: () => client,
      requestId: () => 'req-1',
      loadIndex: () => index.deps,
      countOutput: () => countSyntheticTokens,
      readApproval: async () => approval,
      rawProviders: {
        async jev() { return hang; },
        async generate() { return hang; },
      },
    });
    const pending = deps.query(ACTOR, accountRequest(), 'req-1');
    await flush();
    assert.equal(releaseStarted, 0, 'the request is still before the timeout');
    mock.timers.tick(26_000);
    await until(() => releaseStarted === 1);
    let settled = false;
    void pending.then(() => { settled = true; }, () => { settled = true; });
    await flush();
    assert.equal(settled, false, 'the wire waits for the independent release after the deadline');
    mock.timers.tick(1_500);
    await flush();
    const response = await pending;
    assert.equal(response.status, 'ERROR');
    if (response.status !== 'ERROR') throw new Error('expected an error envelope');
    assert.equal(response.code, 'TIMEOUT');
    assert.equal(releaseFinished, false, 'the hung release is bounded, not awaited forever');
    releaseNow();
  });
});

test('the production consent GET refuses a config generation move during the canonical read', async () => {
  const stateItems = stateWithConfig(configValue);
  const fake = documentFake(stateItems);
  const base = fake.client;
  let configReads = 0;
  const client: PilotBudgetPort = {
    async send(command: unknown, options?: unknown): Promise<unknown> {
      const send = base.send.bind(base) as (c: unknown, o?: unknown) => Promise<unknown>;
      if (
        command instanceof GetCommand &&
        keyOf((command as unknown as { input: Row }).input['Key'] as Row) === CONFIG_ITEM_KEY
      ) {
        configReads += 1;
        const result = await send(command, options);
        // The captured identity moves immediately after the admission read.
        if (configReads === 1) moveConfig(stateItems, 2);
        return result;
      }
      return send(command, options);
    },
  };
  await withEnv(QUERY_ENV, async () => {
    const handler = createDefaultHandler({ client: () => client, requestId: () => 'req-1' });
    const get = await handler(consentGet()) as { statusCode: number; body: string };
    assert.equal(get.statusCode, 409, get.body);
    assert.equal(JSON.parse(get.body).code, 'SOURCE_CHANGED');
  });
});

test('the production consent PUT reports a config move after the atomic commit without rollback', async () => {
  const stateItems = stateWithConfig(configValue);
  const fake = documentFake(stateItems);
  const base = fake.client;
  let moved = false;
  const client: PilotBudgetPort = {
    async send(command: unknown, options?: unknown): Promise<unknown> {
      const send = base.send.bind(base) as (c: unknown, o?: unknown) => Promise<unknown>;
      const result = await send(command, options);
      // The ConditionCheck matched and the consent CAS committed one transaction; the whole
      // config identity then moves, which the post-commit revalidation must report.
      if (command instanceof TransactWriteCommand && !moved) {
        moved = true;
        moveConfig(stateItems, 2);
      }
      return result;
    },
  };
  await withEnv(QUERY_ENV, async () => {
    const handler = createDefaultHandler({ client: () => client, requestId: () => 'req-1' });
    const put = await handler(consentPut(0)) as { statusCode: number; body: string };
    assert.equal(put.statusCode, 409, put.body);
    assert.equal(JSON.parse(put.body).code, 'SOURCE_CHANGED');
    // The consent write itself committed before the move: it is reported, never rolled back.
    const stored = fake.notesItems.get(keyOf(consentRowKey(ACTOR) as Row));
    assert.equal(stored?.['accepted'], true);
    assert.equal(stored?.['generation'], 1);
  });
});

test('the production consent GET stays available to a listed owner while admission is stably disabled', async () => {
  const disabled = { ...configValue, policy: { ...configValue.policy, enabled: false } };
  const fake = documentFake(stateWithConfig(disabled));
  await withEnv(QUERY_ENV, async () => {
    const handler = createDefaultHandler({ client: () => fake.client, requestId: () => 'req-1' });
    const get = await handler(consentGet()) as { statusCode: number; body: string };
    assert.equal(get.statusCode, 200, get.body);
    assert.deepEqual(JSON.parse(get.body).consent, { accepted: false, version: CONSENT_VERSION, generation: 0 });
  });
});
