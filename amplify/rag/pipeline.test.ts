/**
 * Phase 2 pipeline tests: mocked full flow over the fixture runtime, the four synthetic gate
 * outcomes, canonical changes at every stage, budget preflights, the shared deadline and the
 * live-mode refusal. Synthetic fixtures only; no cloud, provider key or network call.
 *
 * Runner: node --import tsx --test amplify/rag/pipeline.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { APIGatewayProxyEventV2WithJWTAuthorizer as Event } from 'aws-lambda';
import notesFixture from '../../test/fixtures/rag/notes.json';
import { CONSENT_VERSION } from './contract';
import { createMockRuntime, MOCK_MODEL } from './mock';
import type { MockRuntime } from './mock';
import { buildLexicalSnapshot, createMockIndex } from './mock_index';
import { createQuery } from './pipeline';
import type { PipelineDeps } from './pipeline';
import { policy } from './types';
import type {
  CanonicalNote,
  CanonicalState,
  GenerateInput,
  JevInput,
  RagRequest,
  RagResponse,
  Ranked,
  RetrievalDeps,
  RuntimeConfig,
  Scope,
} from './types';

const QUESTION = 'SLGH031 chạy bao lâu khi lên cót đầy?';
const ACCOUNT: Scope = { type: 'account' };
const OWN_ELIGIBLE = [
  'n-watch',
  'n-conflict',
  'n-meeting',
  'n-condition',
  'n-negation',
  'n-unicode',
  'n-en',
  'n-en-conflict',
] as const;
const EXCLUDED_FIXTURE_TEXT = [
  'Nội dung này không được dùng',
  'Nội dung đã xóa',
  'Nội dung chưa sync',
  '999',
] as const;

type Mutable<T> = { -readonly [K in keyof T]: T[K] };
const asMutable = <T>(value: T): Mutable<T> => value as Mutable<T>;

const request = (question: string, scope: Scope): RagRequest => ({ wireVersion: 1, question, scope });
const noteScope = (noteId: string): Scope => ({ type: 'note', noteId });

const fixtureContent = (key: string): string => {
  const found = notesFixture.notes.find((note) => note.key === key);
  assert.ok(found, `fixture note ${key} must exist`);
  return found.content;
};

const runQuery = (
  deps: PipelineDeps,
  actor = 'actor-a',
  req: RagRequest = request(QUESTION, ACCOUNT),
  id = 'req-1',
): Promise<RagResponse> => createQuery(deps)(actor, req, id);

const errorCode = (response: RagResponse): string => {
  if (response.status !== 'ERROR') assert.fail(`expected ERROR, got ${response.status}`);
  return response.code;
};

const zeroCounts = (runtime: MockRuntime): boolean =>
  Object.values(runtime.counts).every((value) => value === 0);

const stateOf = (runtime: MockRuntime, actor = 'actor-a'): CanonicalState => {
  const state = runtime.store.states.get(actor);
  assert.ok(state, `synthetic state for ${actor}`);
  return state;
};

type Mutation = (runtime: MockRuntime) => void;

const mutateState = (runtime: MockRuntime, update: (state: CanonicalState) => CanonicalState): void => {
  runtime.store.states.set('actor-a', update(stateOf(runtime)));
};

const changeNote =
  (patch: Partial<CanonicalNote>): Mutation =>
  (runtime) => {
    mutateState(runtime, (state) => ({
      ...state,
      notes: state.notes.map((note) =>
        note.ownerId === 'actor-a' && note.noteId === 'n-watch' ? { ...note, ...patch } : note,
      ),
    }));
  };

const revokeConsent: Mutation = (runtime) => {
  mutateState(runtime, (state) => ({
    ...state,
    consent: { accepted: false, version: CONSENT_VERSION, generation: state.consent.generation },
  }));
};

/** Mutates canonical state from inside one port so the next revalidation must notice it. */
const installMutation: Readonly<Record<string, (runtime: MockRuntime, mutate: Mutation) => void>> = {
  embedQuery: (runtime, mutate) => {
    const original = runtime.deps.retrieval.embedQuery;
    asMutable(runtime.deps.retrieval).embedQuery = async (question, signal) => {
      mutate(runtime);
      return original(question, signal);
    };
  },
  vectorSearch: (runtime, mutate) => {
    const original = runtime.deps.retrieval.vectorSearch;
    asMutable(runtime.deps.retrieval).vectorSearch = async (vector, context) => {
      mutate(runtime);
      return original(vector, context);
    };
  },
  keywordSearch: (runtime, mutate) => {
    const original = runtime.deps.retrieval.keywordSearch;
    asMutable(runtime.deps.retrieval).keywordSearch = async (question, context) => {
      mutate(runtime);
      return original(question, context);
    };
  },
  getVectors: (runtime, mutate) => {
    const original = runtime.deps.retrieval.getVectors;
    asMutable(runtime.deps.retrieval).getVectors = async (chunks, context) => {
      mutate(runtime);
      return original(chunks, context);
    };
  },
  neighbors: (runtime, mutate) => {
    const original = runtime.deps.retrieval.neighbors;
    asMutable(runtime.deps.retrieval).neighbors = async (anchors, context) => {
      mutate(runtime);
      return original(anchors, context);
    };
  },
  jev: (runtime, mutate) => {
    const original = runtime.deps.providers.jev;
    asMutable(runtime.deps.providers).jev = async (input, signal) => {
      mutate(runtime);
      return original(input, signal);
    };
  },
  generate: (runtime, mutate) => {
    const original = runtime.deps.providers.generate;
    asMutable(runtime.deps.providers).generate = async (input, signal) => {
      mutate(runtime);
      return original(input, signal);
    };
  },
};

const withShortDeadline = (runtime: MockRuntime, requestTimeoutMs = 120): PipelineDeps => ({
  ...runtime.deps,
  config: { ...runtime.deps.config, requestTimeoutMs },
});

const eventOf = (actor: string, req: RagRequest): Event =>
  ({
    rawPath: policy.technicalDefaults.wire.route,
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(req),
    requestContext: {
      http: { method: 'POST' },
      authorizer: { jwt: { claims: { sub: actor, token_use: 'access' } } },
    },
  }) as unknown as Event;

test('full mocked flow answers from the fixture with one call per port and a cited source quote', async () => {
  const runtime = createMockRuntime();
  const result = await runtime.handler(eventOf('actor-a', request(QUESTION, noteScope('n-watch'))));
  assert.equal(result.statusCode, 200);
  const body = JSON.parse(result.body) as {
    status: string;
    answer: string;
    sources: readonly { sourceId: string; noteId: string; title: string; startOffset: number; endOffset: number; quote: string }[];
  };
  assert.equal(body.status, 'ANSWERED');
  assert.match(body.answer, /\[S1\]/);
  assert.equal(body.sources.length, 1);
  const source = body.sources[0];
  assert.ok(source);
  assert.equal(source.noteId, 'n-watch');
  assert.equal(source.title, 'SLGH031');
  assert.equal(source.quote, fixtureContent('a-watch'));
  assert.equal(source.quote, fixtureContent('a-watch').slice(source.startOffset, source.endOffset));
  assert.deepEqual({ ...runtime.counts }, {
    embedding: 1,
    vector: 1,
    keyword: 1,
    getVectors: 1,
    neighbors: 1,
    jev: 1,
    generation: 1,
  });
});

test('all four synthetic Jev gate outcomes map to the wire verdict and only ALLOW generates', async () => {
  const cases = [
    ['allow', 'ANSWERED'],
    ['insufficient', 'INSUFFICIENT_EVIDENCE'],
    ['conflict', 'UNRESOLVED_CONFLICT'],
    ['uncertain', 'UNCERTAIN'],
  ] as const;
  for (const [scenario, expected] of cases) {
    const runtime = createMockRuntime({ scenario });
    const response = await runQuery(runtime.deps);
    switch (response.status) {
      case 'ANSWERED':
        assert.equal(expected, 'ANSWERED', scenario);
        assert.equal(runtime.counts.generation, 1, scenario);
        assert.equal(runtime.counts.jev, 1, scenario);
        break;
      case 'NOT_ENOUGH_CONTEXT':
        assert.equal(response.reason, expected, scenario);
        assert.equal(response.answer, null, scenario);
        assert.equal(response.sources.length, 0, scenario);
        assert.equal(runtime.counts.generation, 0, `${scenario} must not generate`);
        assert.equal(runtime.counts.jev, 1, scenario);
        break;
      default:
        assert.fail(`${scenario}: unexpected ${response.status}`);
    }
  }
});

test('malformed Jev, a timed-out gate and an invented source are distinct safe failures', async () => {
  const malformed = createMockRuntime({ scenario: 'malformed' });
  assert.equal(errorCode(await runQuery(malformed.deps)), 'EVIDENCE_VALIDATION_UNAVAILABLE');
  assert.equal(malformed.counts.jev, 1);
  assert.equal(malformed.counts.generation, 0);

  const hanging = createMockRuntime({ scenario: 'timeout' });
  assert.equal(errorCode(await runQuery(withShortDeadline(hanging))), 'TIMEOUT');
  assert.equal(hanging.counts.jev, 1);
  assert.equal(hanging.counts.generation, 0);

  const invented = createMockRuntime({ scenario: 'invalid-output' });
  assert.equal(errorCode(await runQuery(invented.deps)), 'INVALID_PROVIDER_OUTPUT');
  assert.equal(invented.counts.generation, 1);
});

test('two actors can share a noteId without ever seeing the other account text', async () => {
  const runtime = createMockRuntime();
  const scoped = request(QUESTION, noteScope('n-watch'));
  const forA = await runQuery(runtime.deps, 'actor-a', scoped, 'a');
  const forB = await runQuery(runtime.deps, 'actor-b', scoped, 'b');
  if (forA.status !== 'ANSWERED' || forB.status !== 'ANSWERED') assert.fail('both actors must be answered');
  assert.equal(forA.sources[0]?.quote, fixtureContent('a-watch'));
  assert.equal(forB.sources[0]?.quote, fixtureContent('b-watch'));
  assert.ok(forA.sources.every((source) => !source.quote.includes('999')));
  assert.ok(forB.sources.every((source) => !source.quote.includes('Caliber 9SA5')));
  assert.equal(runtime.counts.generation, 2);
});

test('account scope returns own eligible notes only: protected, deleted, local and foreign stay out', async () => {
  const runtime = createMockRuntime();
  const response = await runQuery(runtime.deps, 'actor-a', request('Nội dung nào không được dùng?', ACCOUNT));
  if (response.status !== 'ANSWERED') assert.fail(`expected ANSWERED, got ${response.status}`);
  assert.ok(response.sources.length > 0);
  assert.ok(response.sources.every((source) => (OWN_ELIGIBLE as readonly string[]).includes(source.noteId)));
  for (const source of response.sources) {
    for (const excluded of EXCLUDED_FIXTURE_TEXT) assert.ok(!source.quote.includes(excluded), excluded);
  }
});

test('note scope on protected, deleted, local-only or unknown notes is denied before any port call', async () => {
  for (const noteId of ['n-protected', 'n-deleted', 'n-local', 'n-unknown']) {
    const runtime = createMockRuntime();
    const response = await runQuery(runtime.deps, 'actor-a', request(QUESTION, noteScope(noteId)));
    assert.equal(errorCode(response), 'SCOPE_DENIED', noteId);
    assert.ok(zeroCounts(runtime), `${noteId} must not reach embedding/retrieval/gate/generation`);
  }
});

test('consent off fails before embedding, Jev or generation', async () => {
  const runtime = createMockRuntime();
  revokeConsent(runtime);
  const response = await runQuery(runtime.deps);
  assert.equal(errorCode(response), 'CONSENT_REQUIRED');
  assert.ok(zeroCounts(runtime));
});

test('a source that changes during retrieval, the gate or generation is never answered stale', async () => {
  const cases: readonly (readonly [string, string, Mutation, string])[] = [
    ['revision change during the query embedding', 'embedQuery', changeNote({ revision: 2 }), 'SOURCE_CHANGED'],
    ['delete during the vector search', 'vectorSearch', changeNote({ deleted: true }), 'SOURCE_CHANGED'],
    ['protect during the keyword search', 'keywordSearch', changeNote({ protected: true }), 'SOURCE_CHANGED'],
    ['revision change during getVectors', 'getVectors', changeNote({ revision: 3 }), 'SOURCE_CHANGED'],
    ['revision change during neighbour expansion', 'neighbors', changeNote({ revision: 4 }), 'SOURCE_CHANGED'],
    ['consent revocation during the Jev gate', 'jev', revokeConsent, 'CONSENT_REQUIRED'],
    ['delete during the Jev gate', 'jev', changeNote({ deleted: true }), 'SOURCE_CHANGED'],
    ['revision change during generation', 'generate', changeNote({ revision: 5 }), 'SOURCE_CHANGED'],
  ];
  for (const [name, hook, mutate, expected] of cases) {
    const runtime = createMockRuntime();
    const install = installMutation[hook];
    assert.ok(install, hook);
    install(runtime, mutate);
    const response = await runQuery(runtime.deps);
    assert.equal(errorCode(response), expected, name);
    // Only the generation-stage case may have reached the generator; none releases an answer.
    assert.equal(runtime.counts.generation, hook === 'generate' ? 1 : 0, name);
  }
});

test('an empty union abstains while a broken branch is an error and a timeout cannot degrade', async () => {
  const empty = createMockRuntime();
  const emptyResponse = await runQuery(empty.deps, 'actor-a', request('qqqq unrelated tokens', ACCOUNT));
  if (emptyResponse.status !== 'NOT_ENOUGH_CONTEXT') assert.fail(`expected abstention, got ${emptyResponse.status}`);
  assert.equal(emptyResponse.reason, 'INSUFFICIENT_EVIDENCE');
  assert.deepEqual({ ...empty.counts }, {
    embedding: 1,
    vector: 1,
    keyword: 1,
    getVectors: 0,
    neighbors: 0,
    jev: 0,
    generation: 0,
  });

  const broken = createMockRuntime();
  asMutable(broken.deps.retrieval).vectorSearch = async () => {
    throw new Error('vector store down');
  };
  assert.equal(errorCode(await runQuery(broken.deps)), 'PROVIDER_UNAVAILABLE');
  assert.equal(broken.counts.jev, 0);

  const hung = createMockRuntime();
  asMutable(hung.deps.retrieval).keywordSearch = () => new Promise<readonly Ranked[]>(() => {});
  assert.equal(errorCode(await runQuery(withShortDeadline(hung))), 'TIMEOUT');
  assert.equal(hung.counts.jev, 0);
  assert.equal(hung.counts.generation, 0);
});

test('a single-branch union still answers: stored vectors are reused, never re-embedded', async () => {
  // The handler is built once from deps; replacing a retrieval hook must be picked up per request.
  const runtime = createMockRuntime();
  asMutable(runtime.deps.retrieval).vectorSearch = async () => [];
  const result = await runtime.handler(eventOf('actor-a', request(QUESTION, ACCOUNT)));
  assert.equal(result.statusCode, 200);
  const body = JSON.parse(result.body) as { status: string; sources: readonly { noteId: string }[] };
  assert.equal(body.status, 'ANSWERED');
  assert.ok(body.sources.length > 0);
  assert.ok(body.sources.every((source) => (OWN_ELIGIBLE as readonly string[]).includes(source.noteId)));
  assert.equal(runtime.counts.embedding, 1);
  assert.equal(runtime.counts.getVectors, 1);
  assert.equal(runtime.counts.neighbors, 1);

  const keywordEmpty = createMockRuntime();
  asMutable(keywordEmpty.deps.retrieval).keywordSearch = async () => [];
  const response = await runQuery(keywordEmpty.deps);
  if (response.status !== 'ANSWERED') assert.fail(`expected ANSWERED, got ${response.status}`);
  assert.ok(response.sources.length > 0);
  assert.equal(keywordEmpty.counts.embedding, 1);
  assert.equal(keywordEmpty.counts.getVectors, 1);
});

test('a wrong-size or zero query vector and an invalid counter fail closed before retrieval', async () => {
  const wrongSize = createMockRuntime();
  asMutable(wrongSize.deps.retrieval).embedQuery = async () => new Array<number>(1023).fill(0.5);
  assert.equal(errorCode(await runQuery(wrongSize.deps)), 'INDEX_NOT_READY');
  assert.equal(wrongSize.counts.vector, 0);
  assert.equal(wrongSize.counts.jev, 0);

  const zero = createMockRuntime();
  asMutable(zero.deps.retrieval).embedQuery = async () => new Array<number>(1024).fill(0);
  assert.equal(errorCode(await runQuery(zero.deps)), 'INDEX_NOT_READY');
  assert.equal(zero.counts.vector, 0);

  const brokenCounter = createMockRuntime();
  const deps: PipelineDeps = {
    ...brokenCounter.deps,
    counters: { ...brokenCounter.deps.counters, embedding: () => Number.NaN },
  };
  assert.equal(errorCode(await runQuery(deps)), 'EVIDENCE_VALIDATION_UNAVAILABLE');
  assert.equal(brokenCounter.counts.embedding, 0);
  assert.equal(brokenCounter.counts.jev, 0);
});

test('the embedding and Jev budgets preflight before any provider call and truncate nothing', async () => {
  const longQuestion = createMockRuntime();
  const overTokens = await runQuery(longQuestion.deps, 'actor-a', request('a'.repeat(3000), ACCOUNT));
  assert.equal(errorCode(overTokens), 'INPUT_TOO_LONG');
  assert.equal(longQuestion.counts.embedding, 0);

  const overCodepoints = createMockRuntime();
  const permissiveCounter: PipelineDeps = {
    ...overCodepoints.deps,
    counters: { ...overCodepoints.deps.counters, embedding: () => 1 },
  };
  const atCharacters = await runQuery(permissiveCounter, 'actor-a', request('a'.repeat(2049), ACCOUNT));
  assert.equal(errorCode(atCharacters), 'INPUT_TOO_LONG');
  assert.equal(overCodepoints.counts.embedding, 0);

  const tinyJev = createMockRuntime();
  const jevBudget: PipelineDeps = {
    ...tinyJev.deps,
    config: { ...tinyJev.deps.config, jevMaxTokens: 8 },
  };
  assert.equal(errorCode(await runQuery(jevBudget)), 'EVIDENCE_VALIDATION_UNAVAILABLE');
  assert.equal(tinyJev.counts.jev, 0);
  assert.equal(tinyJev.counts.generation, 0);
});

test('a fully populated live config still cannot enable the pipeline', async () => {
  const runtime = createMockRuntime();
  let authorityReads = 0;
  const liveConfig: RuntimeConfig = {
    mode: 'live',
    model: 'jev-live-approved',
    thresholds: { answerabilityMin: 0.9, conflictMax: 0.1 },
    jevMaxTokens: 32_768,
    requestTimeoutMs: 26_000,
  };
  const deps: PipelineDeps = {
    ...runtime.deps,
    authority: {
      read: async (actor, signal) => {
        authorityReads += 1;
        return runtime.store.read(actor, signal);
      },
    },
    config: liveConfig,
  };
  const response = await runQuery(deps);
  assert.equal(errorCode(response), 'LIVE_POLICY_NOT_CONFIGURED');
  assert.equal(authorityReads, 0);
  assert.ok(zeroCounts(runtime));
  // Why it stays disabled: the policy gates are closed and there is no live adapter in this slice.
  assert.equal(policy.runtimeEnabled, false);
  assert.equal(policy.jev.liveModel, null);
  assert.equal(policy.jev.liveThresholds, null);
});

test('the runtime config and both provider inputs are cloned and deep-frozen once per run', async () => {
  const runtime = createMockRuntime();
  const originalJev = runtime.deps.providers.jev;
  let jevInput: JevInput | undefined;
  let generateInput: GenerateInput | undefined;
  let criteriaAfterProviderWrite = '';
  asMutable(runtime.deps.providers).jev = async (input, signal) => {
    jevInput = input;
    // A frozen clone refuses this write (sloppy CJS ignores it, strict mode throws); either way
    // the value read back must still be the policy criteria, never the provider string.
    try { input.questions.answerable_from_evidence.criteria.true = 'provider write'; }
    catch (error) { assert.ok(error instanceof TypeError); }
    criteriaAfterProviderWrite = input.questions.answerable_from_evidence.criteria.true;
    return originalJev(input, signal);
  };
  const originalGenerate = runtime.deps.providers.generate;
  let neighborsAtRelease = -1;
  let getVectorsAtRelease = -1;
  asMutable(runtime.deps.providers).generate = async (input, signal) => {
    generateInput = input;
    neighborsAtRelease = runtime.counts.neighbors;
    getVectorsAtRelease = runtime.counts.getVectors;
    return originalGenerate(input, signal);
  };

  const callerConfig: {
    mode: 'mock' | 'live';
    model: string;
    thresholds: { answerabilityMin: number; conflictMax: number };
    jevMaxTokens: number;
    requestTimeoutMs: number;
  } = {
    mode: 'mock',
    model: MOCK_MODEL,
    thresholds: { answerabilityMin: 0.9, conflictMax: 0.1 },
    jevMaxTokens: 32_768,
    requestTimeoutMs: 26_000,
  };
  const query = createQuery({ ...runtime.deps, config: callerConfig });
  callerConfig.thresholds.answerabilityMin = 0.99;
  callerConfig.mode = 'live';
  const response = await query('actor-a', request(QUESTION, ACCOUNT), 'req-frozen');

  // The frozen 0.9/0.1 clone decided ALLOW even though the caller object now says live/0.99.
  assert.equal(response.status, 'ANSWERED');
  assert.ok(!Object.isFrozen(callerConfig));

  assert.ok(jevInput);
  assert.ok(generateInput);
  assert.equal(jevInput.model, MOCK_MODEL);
  assert.equal(jevInput.questionSetVersion, policy.jev.questionSetVersion);
  assert.deepEqual(Object.keys(jevInput).sort(), ['model', 'questionSetVersion', 'questions', 'state']);
  assert.deepEqual(Object.keys(jevInput.state).sort(), ['evidence', 'question']);
  assert.equal(jevInput.state.question, QUESTION);
  assert.ok(Object.isFrozen(jevInput));
  assert.ok(Object.isFrozen(jevInput.state));
  assert.ok(Object.isFrozen(jevInput.questions));
  assert.ok(Object.isFrozen(jevInput.questions.answerable_from_evidence.criteria));
  assert.ok(jevInput.questions !== policy.jev.questions);
  assert.equal(
    criteriaAfterProviderWrite,
    policy.jev.questions.answerable_from_evidence.criteria.true,
  );
  assert.ok(!criteriaAfterProviderWrite.includes('provider write'));

  // Generation receives the same gated bundle object: no second retrieval, no re-built evidence.
  assert.equal(generateInput.question, QUESTION);
  assert.equal(generateInput.maxOutputTokens, policy.technicalDefaults.wire.outputMaxTokens);
  assert.equal(generateInput.evidence.text, jevInput.state.evidence);
  assert.ok(Object.isFrozen(generateInput));
  assert.ok(Object.isFrozen(generateInput.evidence));
  assert.equal(getVectorsAtRelease, 1);
  assert.equal(neighborsAtRelease, 1);
  if (response.status !== 'ANSWERED') assert.fail('expected ANSWERED');
  assert.ok(
    response.sources.every((source) =>
      generateInput!.evidence.sources.some((approved) => approved.sourceId === source.sourceId && approved.quote === source.quote),
    ),
  );
});

test('the shared deadline stops a hanging stage: no Jev after retrieval hang, no release after generate hang', async () => {
  const hangingGate = createMockRuntime({ scenario: 'timeout' });
  assert.equal(errorCode(await runQuery(withShortDeadline(hangingGate))), 'TIMEOUT');
  assert.equal(hangingGate.counts.generation, 0);

  const hangingGenerate = createMockRuntime();
  asMutable(hangingGenerate.deps.providers).generate = () => {
    hangingGenerate.counts.generation += 1;
    return new Promise<never>(() => {});
  };
  const response = await runQuery(withShortDeadline(hangingGenerate));
  assert.equal(errorCode(response), 'TIMEOUT');
  assert.equal(hangingGenerate.counts.generation, 1);
});

test('quota runs after authorization and before any provider call, and fails closed', async () => {
  const runtime = createMockRuntime();
  let authorityReads = 0;
  let quotaActor = '';
  let signalWasLive = false;
  const denied: PipelineDeps = {
    ...runtime.deps,
    authority: {
      read: async (actor, signal) => {
        authorityReads += 1;
        return runtime.store.read(actor, signal);
      },
    },
    consumeQuota: async (actor, signal) => {
      quotaActor = actor;
      signalWasLive = !signal.aborted;
      return false;
    },
  };
  assert.equal(errorCode(await runQuery(denied)), 'RATE_LIMITED');
  assert.equal(quotaActor, 'actor-a');
  assert.equal(signalWasLive, true);
  assert.equal(authorityReads, 1);
  assert.ok(zeroCounts(runtime));

  const throwing = createMockRuntime();
  const broken: PipelineDeps = {
    ...throwing.deps,
    consumeQuota: async () => {
      throw new Error('quota service down');
    },
  };
  assert.equal(errorCode(await runQuery(broken)), 'PROVIDER_UNAVAILABLE');
  assert.ok(zeroCounts(throwing));

  const missing = createMockRuntime();
  const unconfigured = {
    ...missing.deps,
    consumeQuota: undefined as unknown as PipelineDeps['consumeQuota'],
  };
  assert.equal(errorCode(await runQuery(unconfigured)), 'PROVIDER_UNAVAILABLE');
  assert.ok(zeroCounts(missing));
});

test('an index artifact that lags canonical state is INDEX_NOT_READY while an empty corpus abstains', async () => {
  const stuck = createMockRuntime();
  const emptySnapshot = buildLexicalSnapshot(
    'actor-a',
    { ...stateOf(stuck), notes: [] },
    stuck.deps.counters.embedding,
  );
  const emptyIndex = createMockIndex(emptySnapshot);
  const retrieval: RetrievalDeps = {
    ...stuck.deps.retrieval,
    vectorSearch: (vector, context) => emptyIndex.vectorSearch(vector, context),
    keywordSearch: (question, context) => emptyIndex.keywordSearch(question, context),
    getVectors: (chunks, context) => emptyIndex.getVectors(chunks, context),
    neighbors: (anchors, context) => emptyIndex.neighbors(anchors, context),
  };
  assert.equal(errorCode(await runQuery({ ...stuck.deps, retrieval })), 'INDEX_NOT_READY');
  assert.equal(stuck.counts.jev, 0);
  assert.equal(stuck.counts.generation, 0);

  const notReady = createMockRuntime();
  mutateState(notReady, (state) => ({ ...state, indexReady: false }));
  assert.equal(errorCode(await runQuery(notReady.deps)), 'INDEX_NOT_READY');
  assert.ok(zeroCounts(notReady));

  const legitimateEmpty = createMockRuntime();
  mutateState(legitimateEmpty, (state) => ({ ...state, notes: [] }));
  const emptyResponse = await runQuery(legitimateEmpty.deps);
  if (emptyResponse.status !== 'NOT_ENOUGH_CONTEXT') assert.fail('empty corpus must abstain');
  assert.equal(emptyResponse.reason, 'INSUFFICIENT_EVIDENCE');
  assert.equal(legitimateEmpty.counts.getVectors, 0);
  assert.equal(legitimateEmpty.counts.jev, 0);
});
