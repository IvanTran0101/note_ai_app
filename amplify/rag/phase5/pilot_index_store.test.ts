/**
 * Phase 5 guarded index store tests: the scope permit, canonical identity of the returned state,
 * membership-before-body-load, corpus admission/denial, the exact config-generation fail-closed
 * behavior, the one-and-only `acquireEmbedding` debit and the unconditional `finish` release.
 *
 * The underlying `IndexStore`, the pilot budget and the config reader are injected fakes that
 * record the exact objects/arguments they receive, so the tests assert forwarding and identity
 * rather than a reimplementation of the wrapper. No AWS, network or provider call is made.
 *
 * Runner: node --import tsx --test amplify/rag/phase5/pilot_index_store.test.ts
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CONSENT_VERSION } from '../contract';
import { markersOf, sameMarkers } from '../indexing/jobs';
import { embeddingInputDigest } from '../indexing/snapshot';
import { IndexFailure } from '../indexing/types';
import type {
  FreshnessMarkers, IndexNote, IndexState, IndexStore, JobStatus, Lease, Manifest,
} from '../indexing/types';
import { RagFailure } from '../types';
import { RUNTIME_CASE_HASH, RUNTIME_ELIGIBLE_OWN_NOTES_KIND, parseRuntimeConfig } from './runtime_config';
import type { RuntimeConfig } from './runtime_config';
import { createPilotIndexStore } from './pilot_index_store';

type Row = Record<string, unknown>;

const ACTOR = '00000001-0000-4000-8000-000000000001';
const OTHER = '00000009-0000-4000-8000-000000000009';
const TITLE = 'Pilot note';
const CONTENT = 'Approved synthetic body';
const DIGEST = embeddingInputDigest(TITLE, CONTENT);
const FINGERPRINT = 'b'.repeat(64);
const LEASE: Lease = Object.freeze({ token: 'lease-1', expiresAt: 1000, fingerprint: FINGERPRINT });

const signal = (): AbortSignal => new AbortController().signal;
const isFailure = (code: string, retryable?: boolean) => (error: unknown): boolean =>
  error instanceof IndexFailure && error.code === code &&
  (retryable === undefined || error.retryable === retryable);

const note = (patch: Partial<IndexNote> = {}): IndexNote => ({
  ownerId: ACTOR, noteId: 'n1', revision: 1, title: TITLE, content: CONTENT,
  synced: true, protected: false, deleted: false, available: true, protectionRevision: 0, ...patch,
});
const consent = (accepted: boolean, generation = 1): IndexState['consent'] =>
  ({ accepted, version: CONSENT_VERSION, generation });
const state = (overrides: Partial<IndexState> = {}): IndexState =>
  ({ ownerId: ACTOR, accountEpoch: 0, consent: consent(true), notes: [note()], manifest: null, ...overrides });

const policyRaw = (enabled = true): Row => ({
  enabled, owners: [ACTOR], model: 'jev-1.13.0',
  thresholds: { answerabilityMin: 0.85, conflictMax: 0.1 },
});
const rawConfig = (patch: Row = {}): Row => ({
  version: 'rag-pilot-config.v1',
  generation: 1,
  policy: policyRaw(),
  corpus: {
    kind: 'reviewed-pilot', caseHash: RUNTIME_CASE_HASH,
    owners: { [ACTOR]: [{ noteId: 'n1', inputDigest: DIGEST }] },
  },
  ...patch,
});
const dynamicConfig = (patch: Row = {}): Row => ({
  version: 'rag-pilot-config.v1',
  generation: 1,
  policy: policyRaw(),
  corpus: {
    kind: RUNTIME_ELIGIBLE_OWN_NOTES_KIND, caseHash: null, owners: { [ACTOR]: [] },
  },
  ...patch,
});

const manifest = (status: Manifest['status']): Manifest => Object.freeze({
  ownerId: ACTOR, generation: 1, version: 'v1', fingerprint: FINGERPRINT, consentGeneration: 1,
  accountEpoch: 0, status, snapshotKey: 'snap', checksum: FINGERPRINT, policyIdentity: FINGERPRINT,
});

type Calls = Readonly<{
  load: string[];
  loadMarkers: string[];
  acquire: Array<{ state: IndexState; requested: string; nowMs: number }>;
  publish: Array<{ state: IndexState; lease: Lease; manifest: Manifest; nowMs: number }>;
  finish: Array<{ ownerId: string; lease: Lease; status: JobStatus; code: string; nowMs: number }>;
  reserveEmbedding: number;
}>;

const fakeStore = (
  loadImpl: (ownerId: string, call: number) => IndexState | Promise<IndexState>,
  markersImpl?: (ownerId: string) => FreshnessMarkers,
) => {
  const calls: {
    load: string[];
    loadMarkers: string[];
    acquire: Array<{ state: IndexState; requested: string; nowMs: number }>;
    publish: Array<{ state: IndexState; lease: Lease; manifest: Manifest; nowMs: number }>;
    finish: Array<{ ownerId: string; lease: Lease; status: JobStatus; code: string; nowMs: number }>;
    reserveEmbedding: number;
  } = { load: [], loadMarkers: [], acquire: [], publish: [], finish: [], reserveEmbedding: 0 };
  const store: IndexStore = {
    async load(ownerId) {
      const call = calls.load.length;
      calls.load.push(ownerId);
      return loadImpl(ownerId, call);
    },
    // Present only when the test injects it: absent means the decorator keeps the full path.
    ...(markersImpl === undefined ? {} : {
      async loadMarkers(ownerId: string): Promise<FreshnessMarkers> {
        calls.loadMarkers.push(ownerId);
        return markersImpl(ownerId);
      },
    }),
    async acquire(state_, requested, nowMs) {
      calls.acquire.push({ state: state_, requested, nowMs });
      return LEASE;
    },
    async publish(state_, lease, manifest_, nowMs) {
      calls.publish.push({ state: state_, lease, manifest: manifest_, nowMs });
      return true;
    },
    async finish(ownerId, lease, status, code, nowMs) {
      calls.finish.push({ ownerId, lease, status, code, nowMs });
    },
    async reserveEmbedding() {
      calls.reserveEmbedding += 1;
    },
  };
  return { store, calls: calls as Calls & typeof calls };
};

const setup = (
  capturedRaw: Row,
  reads: readonly Row[],
  loadImpl: (ownerId: string, call: number) => IndexState | Promise<IndexState>,
  budgetImpl?: () => Promise<void>,
  markersImpl?: (ownerId: string) => FreshnessMarkers,
) => {
  const captured = parseRuntimeConfig(capturedRaw);
  const { store, calls } = fakeStore(loadImpl, markersImpl);
  const budgetCalls: number[] = [];
  const budget = {
    async acquireEmbedding(): Promise<void> {
      budgetCalls.push(1);
      if (budgetImpl !== undefined) await budgetImpl();
    },
  };
  let index = 0;
  const readConfig = async (): Promise<RuntimeConfig> =>
    parseRuntimeConfig(reads[Math.min(index++, reads.length - 1)]);
  const guard = createPilotIndexStore({ store, budget, readConfig, config: captured });
  return { guard, calls, budgetCalls, captured };
};

test('load returns the original canonical state for a listed approved owner', async () => {
  const target = state();
  const h = setup(rawConfig(), [rawConfig()], () => target);
  const loaded = await h.guard.load(ACTOR, signal());
  assert.equal(loaded, target);
  assert.deepEqual(h.calls.load, [ACTOR]);
});

test('a non-member is refused before the underlying body load', async () => {
  const h = setup(rawConfig(), [rawConfig()], () => {
    throw new Error('the body must never be loaded for a non-member');
  });
  await assert.rejects(h.guard.load(OTHER, signal()), isFailure('LIVE_POLICY_NOT_CONFIGURED', false));
  assert.equal(h.calls.load.length, 0);
  await assert.rejects(h.guard.reserveEmbedding(OTHER, signal()), isFailure('LIVE_POLICY_NOT_CONFIGURED'));
  assert.equal(h.budgetCalls.length, 0);
});

test('an eligible note with an unknown id or a drifted digest is refused before any paid work', async () => {
  const unknown = setup(rawConfig(), [rawConfig()], () => state({ notes: [note({ noteId: 'n2' })] }));
  await assert.rejects(unknown.guard.load(ACTOR, signal()), isFailure('SOURCE_CHANGED', true));
  assert.equal(unknown.calls.load.length, 1);
  assert.equal(unknown.calls.reserveEmbedding, 0);

  const drift = setup(rawConfig(), [rawConfig()], () => state({ notes: [note({ content: 'drifted body' })] }));
  await assert.rejects(drift.guard.load(ACTOR, signal()), isFailure('SOURCE_CHANGED', true));
  assert.equal(drift.calls.reserveEmbedding, 0);
});

test('dynamic mode admits a new eligible note with no frozen id or digest', async () => {
  const target = state({ notes: [note({ noteId: 'new-own-note', content: 'new canonical body' })] });
  const h = setup(dynamicConfig(), [dynamicConfig()], () => target);
  assert.equal(await h.guard.load(ACTOR, signal()), target);
  await h.guard.reserveEmbedding(ACTOR, signal());
  assert.equal(h.budgetCalls.length, 1);
  assert.equal(
    await h.guard.publish(target, LEASE, manifest('READY'), 7, signal()),
    true,
  );
  assert.equal(h.calls.publish.length, 1);
});

test('dynamic mode still fails closed on mode or generation drift before the body load', async () => {
  const generation = setup(dynamicConfig(), [dynamicConfig({ generation: 2 })], () => state());
  await assert.rejects(generation.guard.load(ACTOR, signal()), isFailure('SOURCE_CHANGED', true));
  assert.equal(generation.calls.load.length, 0);

  // Switching between the dynamic and reviewed mode is a whole-config source change, never a
  // silent widening or narrowing of the permit.
  const mode = setup(dynamicConfig(), [rawConfig()], () => state());
  await assert.rejects(mode.guard.load(ACTOR, signal()), isFailure('SOURCE_CHANGED', true));
  assert.equal(mode.calls.load.length, 0);
});

test('a revoked listed owner can still reach cleanup/BLOCKED while the policy is disabled', async () => {
  const raw = rawConfig({ policy: policyRaw(false) });
  const target = state({ consent: consent(false, 2) });
  const h = setup(raw, [raw], () => target);
  assert.equal(await h.guard.load(ACTOR, signal()), target);
  assert.equal(await h.guard.publish(target, LEASE, manifest('BLOCKED'), 7, signal()), true);
  assert.equal(h.calls.publish.length, 1);
  assert.equal(h.calls.reserveEmbedding, 0);
});

test('accepted consent on a disabled policy is refused with no READY and no embedding', async () => {
  const raw = rawConfig({ policy: policyRaw(false) });
  const target = state();
  const h = setup(raw, [raw], () => target);
  await assert.rejects(h.guard.load(ACTOR, signal()), isFailure('LIVE_POLICY_NOT_CONFIGURED', false));
  await assert.rejects(
    h.guard.publish(target, LEASE, manifest('READY'), 7, signal()),
    isFailure('LIVE_POLICY_NOT_CONFIGURED', false),
  );
  await assert.rejects(h.guard.reserveEmbedding(ACTOR, signal()), isFailure('LIVE_POLICY_NOT_CONFIGURED', false));
  assert.equal(h.budgetCalls.length, 0);
  assert.equal(h.calls.publish.length, 0);
});

test('a changed whole-config identity fails closed before any underlying work', async () => {
  const h = setup(rawConfig(), [rawConfig({ generation: 2 })], () => state());
  await assert.rejects(h.guard.load(ACTOR, signal()), isFailure('SOURCE_CHANGED', true));
  assert.equal(h.calls.load.length, 0);
});

test('a config change between load and the paid stage blocks the debit and the publish', async () => {
  const captured = rawConfig();
  const changed = rawConfig({ generation: 2 });
  const target = state();
  // `load` now reads the captured identity both before and after the awaited canonical load, so
  // keep both reads captured and let the paid stage observe the change.
  const paid = setup(captured, [captured, captured, changed], () => target);
  assert.equal(await paid.guard.load(ACTOR, signal()), target);
  await assert.rejects(paid.guard.reserveEmbedding(ACTOR, signal()), isFailure('SOURCE_CHANGED', true));
  assert.equal(paid.budgetCalls.length, 0);
  assert.equal(paid.calls.reserveEmbedding, 0);

  const published = setup(captured, [captured, captured, changed], () => target);
  assert.equal(await published.guard.load(ACTOR, signal()), target);
  await assert.rejects(
    published.guard.publish(target, LEASE, manifest('READY'), 7, signal()),
    isFailure('SOURCE_CHANGED', true),
  );
  assert.equal(published.calls.publish.length, 0);
});

test('a config withdrawal while the canonical body load is in flight is refused at the port', async () => {
  const reads: Row[] = [rawConfig()];
  const h = setup(rawConfig(), reads, () => {
    // The withdrawal lands while the canonical load is awaited: a guard that only compared the
    // config before the load would authorize this state and reach the paid stage.
    reads[0] = rawConfig({ generation: 2, policy: policyRaw(false) });
    return state();
  });
  await assert.rejects(h.guard.load(ACTOR, signal()), isFailure('SOURCE_CHANGED', true));
  assert.equal(h.calls.load.length, 1, 'the canonical body was loaded');
  await assert.rejects(h.guard.reserveEmbedding(ACTOR, signal()), isFailure('SOURCE_CHANGED', true));
  assert.equal(h.budgetCalls.length, 0);
  assert.equal(h.calls.reserveEmbedding, 0);
});

test('a config withdrawal during the acquire canonical load refuses the lease', async () => {
  const reads: Row[] = [rawConfig()];
  const h = setup(rawConfig(), reads, () => {
    reads[0] = rawConfig({ generation: 2 });
    return state();
  });
  await assert.rejects(h.guard.acquire(state(), FINGERPRINT, 1, signal()), isFailure('SOURCE_CHANGED', true));
  assert.equal(h.calls.acquire.length, 0, 'the underlying CAS is never reached');
});

test('a config withdrawal during the publish canonical load refuses the READY CAS', async () => {
  const reads: Row[] = [rawConfig()];
  const h = setup(rawConfig(), reads, () => {
    reads[0] = rawConfig({ generation: 2, policy: policyRaw(false) });
    return state();
  });
  await assert.rejects(
    h.guard.publish(state(), LEASE, manifest('READY'), 7, signal()),
    isFailure('SOURCE_CHANGED', true),
  );
  assert.equal(h.calls.publish.length, 0, 'the final CAS is never reached');
});

test('an injected config port that resolves after an abort cannot grant a permit', async () => {
  const controller = new AbortController();
  const { store, calls } = fakeStore(() => state());
  const guard = createPilotIndexStore({
    store,
    budget: { async acquireEmbedding(): Promise<void> {} },
    config: parseRuntimeConfig(rawConfig()),
    readConfig: async () => {
      // A port that ignores the abort signal and resolves late must still be refused.
      controller.abort();
      return parseRuntimeConfig(rawConfig());
    },
  });
  await assert.rejects(guard.load(ACTOR, controller.signal), isFailure('TIMEOUT', true));
  assert.equal(calls.load.length, 0, 'the body is never loaded after the permit deadline fired');
});

test('a signal aborted during the canonical load refuses the authorized state and any paid stage', async () => {
  const controller = new AbortController();
  const { store, calls } = fakeStore(() => {
    // The body port ignores the abort and resolves; the shared guard must still refuse it.
    controller.abort();
    return state();
  });
  const guard = createPilotIndexStore({
    store,
    budget: { async acquireEmbedding(): Promise<void> {} },
    config: parseRuntimeConfig(rawConfig()),
    readConfig: async () => parseRuntimeConfig(rawConfig()),
  });
  await assert.rejects(guard.load(ACTOR, controller.signal), isFailure('TIMEOUT', true));
  assert.equal(calls.reserveEmbedding, 0);
});

test('acquire re-checks config and canonical state, then forwards the original arguments', async () => {
  const target = state();
  const h = setup(rawConfig(), [rawConfig()], () => target);
  const lease = await h.guard.acquire(target, FINGERPRINT, 42, signal());
  assert.equal(lease, LEASE);
  assert.equal(h.calls.acquire.length, 1);
  assert.equal(h.calls.acquire[0].state, target);
  assert.equal(h.calls.acquire[0].requested, FINGERPRINT);
  assert.equal(h.calls.acquire[0].nowMs, 42);
});

test('acquire refuses a fresh canonical state that no longer matches the bound state', async () => {
  const passed = state();
  const fresh = state({ notes: [note({ revision: 2 })] });
  const h = setup(rawConfig(), [rawConfig()], () => fresh);
  await assert.rejects(h.guard.acquire(passed, FINGERPRINT, 1, signal()), isFailure('SOURCE_CHANGED', true));
  assert.equal(h.calls.acquire.length, 0);
});

test('publish forwards the original bound state/lease/manifest/clock for a permitted READY', async () => {
  const target = state();
  const h = setup(rawConfig(), [rawConfig()], () => target);
  const ready = manifest('READY');
  assert.equal(await h.guard.publish(target, LEASE, ready, 7, signal()), true);
  assert.equal(h.calls.publish.length, 1);
  assert.equal(h.calls.publish[0].state, target);
  assert.equal(h.calls.publish[0].lease, LEASE);
  assert.equal(h.calls.publish[0].manifest, ready);
  assert.equal(h.calls.publish[0].nowMs, 7);
});

test('a BLOCKED manifest is refused while canonical consent is accepted', async () => {
  const h = setup(rawConfig(), [rawConfig()], () => state());
  await assert.rejects(
    h.guard.publish(state(), LEASE, manifest('BLOCKED'), 7, signal()),
    isFailure('SOURCE_CHANGED', true),
  );
  assert.equal(h.calls.publish.length, 0);
});

test('reserveEmbedding performs exactly one atomic acquireEmbedding and never the legacy debit', async () => {
  const target = state();
  const h = setup(rawConfig(), [rawConfig()], () => target);
  await h.guard.reserveEmbedding(ACTOR, signal());
  assert.equal(h.budgetCalls.length, 1);
  assert.equal(h.calls.reserveEmbedding, 0);
  assert.deepEqual(h.calls.load, [ACTOR]);
});

test('reserveEmbedding performs no debit for a revoked or disabled/accepted state', async () => {
  const revoked = setup(rawConfig(), [rawConfig()], () => state({ consent: consent(false, 2) }));
  await assert.rejects(revoked.guard.reserveEmbedding(ACTOR, signal()), isFailure('LIVE_POLICY_NOT_CONFIGURED'));
  assert.equal(revoked.budgetCalls.length, 0);

  const disabled = setup(rawConfig({ policy: policyRaw(false) }), [rawConfig({ policy: policyRaw(false) })], () => state());
  await assert.rejects(disabled.guard.reserveEmbedding(ACTOR, signal()), isFailure('LIVE_POLICY_NOT_CONFIGURED'));
  assert.equal(disabled.budgetCalls.length, 0);
});

test('budget and reader failures keep typed codes and the retryable flag', async () => {
  // A config reader that reports an SDK 429/5xx/timeout is a transient transport failure: it must
  // stay replayable so a later invocation can re-read the latest config.
  const rate = setup(rawConfig(), [rawConfig()], () => state(), async () => { throw new RagFailure('RATE_LIMITED'); });
  await assert.rejects(rate.guard.reserveEmbedding(ACTOR, signal()), isFailure('RATE_LIMITED', true));

  const timeout = setup(rawConfig(), [rawConfig()], () => state(), async () => { throw new RagFailure('TIMEOUT'); });
  await assert.rejects(timeout.guard.reserveEmbedding(ACTOR, signal()), isFailure('TIMEOUT', true));

  const captured = parseRuntimeConfig(rawConfig());
  const store = fakeStore(() => state()).store;
  const budget = { async acquireEmbedding(): Promise<void> {} };
  const provider = createPilotIndexStore({
    store, budget, config: captured, readConfig: async () => { throw new RagFailure('PROVIDER_UNAVAILABLE'); },
  });
  await assert.rejects(provider.load(ACTOR, signal()), isFailure('PROVIDER_UNAVAILABLE', true));

  // Schema/membership failures are terminal, never a silent replay.
  const invalid = createPilotIndexStore({
    store, budget, config: captured, readConfig: async () => { throw new RagFailure('INVALID_INPUT'); },
  });
  await assert.rejects(invalid.load(ACTOR, signal()), isFailure('INVALID_INPUT', false));

  const untyped = createPilotIndexStore({
    store, budget, config: captured, readConfig: async () => { throw new Error('transport'); },
  });
  await assert.rejects(untyped.load(ACTOR, signal()), isFailure('PORT_FAILURE', true));

  const malformed = createPilotIndexStore({
    store, budget, config: captured, readConfig: async () => ({ version: 'bad' } as never),
  });
  await assert.rejects(malformed.load(ACTOR, signal()), isFailure('LIVE_POLICY_NOT_CONFIGURED', false));
});

test('finish always releases the lease, even for a non-member or after a config change', async () => {
  const h = setup(rawConfig(), [rawConfig({ generation: 2 })], () => state());
  await h.guard.finish(OTHER, LEASE, 'FAILED', 'REVOKED', 9, signal());
  assert.equal(h.calls.finish.length, 1);
  assert.deepEqual(h.calls.finish[0], { ownerId: OTHER, lease: LEASE, status: 'FAILED', code: 'REVOKED', nowMs: 9 });
  // finish consults neither the config nor the canonical store.
  assert.equal(h.calls.load.length, 0);
});

test('an aborted signal is a timeout before any port call', async () => {
  const target = state();
  const h = setup(rawConfig(), [rawConfig()], () => target);
  const controller = new AbortController();
  controller.abort();
  await assert.rejects(h.guard.load(ACTOR, controller.signal), isFailure('TIMEOUT', true));
  assert.equal(h.calls.load.length, 0);
});

test('construction validates the store, budget, reader and the captured config', () => {
  const captured = parseRuntimeConfig(rawConfig());
  const store = fakeStore(() => state()).store;
  const budget = { async acquireEmbedding(): Promise<void> {} };
  const readConfig = async (): Promise<RuntimeConfig> => captured;
  assert.ok(createPilotIndexStore({ store, budget, readConfig, config: captured }));
  assert.throws(() => createPilotIndexStore(null as never), isFailure('INVALID_STATE', false));
  assert.throws(
    () => createPilotIndexStore({ store: {} as never, budget, readConfig, config: captured }),
    isFailure('INVALID_STATE', false),
  );
  assert.throws(
    () => createPilotIndexStore({ store, budget: {} as never, readConfig, config: captured }),
    isFailure('INVALID_STATE', false),
  );
  assert.throws(
    () => createPilotIndexStore({ store, budget, readConfig: 'nope' as never, config: captured }),
    isFailure('INVALID_STATE', false),
  );
  assert.throws(
    () => createPilotIndexStore({ store, budget, readConfig, config: rawConfig({ generation: 0 }) as never }),
    isFailure('LIVE_POLICY_NOT_CONFIGURED', false),
  );
});

// ---------------------------------------------------------------------------------------------
// Light loadMarkers forwarding and the light reserveEmbedding path (Patch 5A)
// ---------------------------------------------------------------------------------------------

test('loadMarkers is forwarded under the config and membership fence when the inner store has it', async () => {
  const target = state();
  const h = setup(rawConfig(), [rawConfig()], () => target, undefined, () => markersOf(target));
  const forward = h.guard.loadMarkers;
  assert.ok(forward !== undefined, 'the decorator forwards the inner marker read');
  assert.ok(sameMarkers(await forward(ACTOR, signal()), markersOf(target)));
  assert.deepEqual(h.calls.loadMarkers, [ACTOR]);
  assert.equal(h.calls.load.length, 0, 'the forwarded read never loads the body');

  await assert.rejects(forward(OTHER, signal()), isFailure('LIVE_POLICY_NOT_CONFIGURED', false));
  assert.equal(h.calls.loadMarkers.includes(OTHER), false, 'membership fences the marker read');

  const drifted = setup(rawConfig(), [rawConfig({ generation: 2 })], () => target, undefined,
    () => markersOf(target));
  const driftedForward = drifted.guard.loadMarkers;
  assert.ok(driftedForward !== undefined);
  await assert.rejects(driftedForward(ACTOR, signal()), isFailure('SOURCE_CHANGED', true));
  assert.deepEqual(drifted.calls.loadMarkers, [], 'a moved config refuses before the inner read');

  const bare = setup(rawConfig(), [rawConfig()], () => target);
  assert.equal(bare.guard.loadMarkers, undefined,
    'absent on the inner store means absent on the decorator');
});

test('the light reserveEmbedding admits from markers alone: no body load, one atomic debit', async () => {
  const target = state();
  const h = setup(rawConfig(), [rawConfig()], () => {
    throw new Error('the canonical body must never load on the light path');
  }, undefined, () => markersOf(target));
  await h.guard.reserveEmbedding(ACTOR, signal());
  assert.equal(h.budgetCalls.length, 1);
  assert.deepEqual(h.calls.loadMarkers, [ACTOR]);
  assert.equal(h.calls.load.length, 0);
  assert.equal(h.calls.reserveEmbedding, 0, 'the legacy global counter is never used');
});

test('the light reserveEmbedding refuses disabled policy, withdrawn consent and non-members from markers only', async () => {
  // The canonical body would still authorize; the marker consent is the only permit on the paid
  // path, so the refusal proves the decision came from the marker read.
  const withdrawn = setup(rawConfig(), [rawConfig()], () => {
    throw new Error('the canonical body must never load on the light path');
  }, undefined, () => markersOf(state({ consent: consent(false, 2) })));
  await assert.rejects(
    withdrawn.guard.reserveEmbedding(ACTOR, signal()),
    isFailure('LIVE_POLICY_NOT_CONFIGURED', false),
  );
  assert.equal(withdrawn.budgetCalls.length, 0);
  assert.deepEqual(withdrawn.calls.loadMarkers, [ACTOR]);
  assert.equal(withdrawn.calls.load.length, 0);

  const disabled = setup(
    rawConfig({ policy: policyRaw(false) }),
    [rawConfig({ policy: policyRaw(false) })],
    () => state(),
    undefined,
    () => markersOf(state()),
  );
  await assert.rejects(
    disabled.guard.reserveEmbedding(ACTOR, signal()),
    isFailure('LIVE_POLICY_NOT_CONFIGURED', false),
  );
  assert.equal(disabled.budgetCalls.length, 0);

  const nonMember = setup(rawConfig(), [rawConfig()], () => state(), undefined, () => markersOf(state()));
  await assert.rejects(
    nonMember.guard.reserveEmbedding(OTHER, signal()),
    isFailure('LIVE_POLICY_NOT_CONFIGURED', false),
  );
  assert.deepEqual(nonMember.calls.loadMarkers, [], 'membership is checked before the marker read');
  assert.equal(nonMember.budgetCalls.length, 0);
  assert.equal(nonMember.calls.load.length, 0);
});

test('reserveEmbedding keeps the full authorize path when the inner store lacks loadMarkers', async () => {
  const target = state();
  const h = setup(rawConfig(), [rawConfig()], () => target);
  assert.equal(h.guard.loadMarkers, undefined);
  await h.guard.reserveEmbedding(ACTOR, signal());
  assert.equal(h.budgetCalls.length, 1);
  assert.deepEqual(h.calls.load, [ACTOR], 'without the marker read the full authorize load runs');
  assert.equal(h.calls.loadMarkers.length, 0);
});
