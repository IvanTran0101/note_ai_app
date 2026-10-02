import assert from 'node:assert/strict';
import { test } from 'node:test';
import { Argon2idPasswordHasher } from './argon2id_password_hasher';
import { NoteSecurityError, OwnerNoteAcl } from './protection_store';
import type { NoteSecurityCode } from './protection_store';
import { ProtectionUseCases, securityDigest } from './use_cases';
import { TestPasswordHasher, TestProtectionStore } from './test_support';

const password = 'test-password-alpha';
const deny = (code: NoteSecurityCode) => (e: unknown) =>
  e instanceof NoteSecurityError && e.code === code;
function fixture() {
  const store = new TestProtectionStore();
  let now = Date.parse('2026-10-02T00:00:00Z');
  let otp = '';
  const api = new ProtectionUseCases(store, new TestPasswordHasher(), new OwnerNoteAcl(),
    { async sendCode(_mailbox, code) { otp = code; } }, () => now);
  return { store, api, advance: (ms: number) => { now += ms; }, code: () => otp };
}

test('real Argon2id salts, verifies, rejects wrong and malformed representations', async () => {
  const h = new Argon2idPasswordHasher();
  const a = await h.hash(password), b = await h.hash(password);
  assert.notEqual(a, b);
  assert.ok(!a.includes(password));
  assert.equal(await h.verify(password, a), true);
  assert.equal(await h.verify('wrong-password', a), false);
  await assert.rejects(h.hash('short'), deny('invalidInput'));
  await assert.rejects(h.hash('🧪'.repeat(150)), deny('invalidInput'));
  await assert.rejects(h.verify(password, 'broken'), deny('unavailable'));
});

test('enable pins canonical revision and leaves sibling unprotected', async () => {
  const { api, store } = fixture();
  await assert.rejects(api.enable('other', 'owner', 'alpha', password, 1), deny('denied'));
  await assert.rejects(api.enable('owner', 'owner', 'alpha', password, 2), deny('staleRevision'));
  assert.deepEqual(await api.enable('owner', 'owner', 'alpha', password, 1),
    { enabled: true, revision: 1 });
  assert.equal(store.protections.get('beta')?.enabled, false);
  assert.ok(!JSON.stringify(store.protections.get('alpha')).includes(password));
});

test('JWT alone cannot authorize any protected operation or content', async () => {
  const { api } = fixture();
  await api.enable('owner', 'owner', 'alpha', password, 1);
  for (const op of ['read', 'edit', 'delete', 'manage', 'summary', 'export'] as const) {
    await assert.rejects(api.authorize('owner', 'owner', 'alpha', op), deny('locked'));
  }
  await assert.rejects(api.content('owner', 'owner', 'alpha'), deny('locked'));
});

test('grant is hashed, scoped to actor/note/operations/epoch and expires by clock', async () => {
  const { api, store, advance } = fixture();
  await api.enable('owner', 'owner', 'alpha', password, 1);
  await api.enable('owner', 'owner', 'beta', 'beta-password', 1);
  const lease = await api.unlock('owner', 'owner', 'alpha', password, ['read']);
  assert.match(lease.grant, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(store.grants.has(securityDigest(lease.grant)), true);
  assert.ok(!JSON.stringify([...store.grants.values()]).includes(lease.grant));
  assert.equal((await api.content('owner', 'owner', 'alpha', lease.grant)).content, 'secret alpha');
  await assert.rejects(api.authorize('other', 'owner', 'alpha', 'read', lease.grant), deny('denied'));
  await assert.rejects(api.authorize('owner', 'owner', 'beta', 'read', lease.grant), deny('denied'));
  await assert.rejects(api.authorize('owner', 'owner', 'alpha', 'edit', lease.grant), deny('denied'));
  await assert.rejects(api.authorize('owner', 'owner', 'alpha', 'read', 'bad'), deny('locked'));
  advance(15 * 60_000);
  await assert.rejects(api.content('owner', 'owner', 'alpha', lease.grant), deny('expired'));
});

test('password attempts are bounded per actor/note and wrong password mints no grant', async () => {
  const { api, store, advance } = fixture();
  await api.enable('owner', 'owner', 'alpha', password, 1);
  for (let i = 0; i < 5; i++) {
    await assert.rejects(api.unlock('owner', 'owner', 'alpha', 'wrong-password', ['read']), deny('invalidPassword'));
  }
  assert.equal(store.grants.size, 0);
  await assert.rejects(api.unlock('owner', 'owner', 'alpha', password, ['read']), deny('rateLimited'));
  advance(60_001);
  await api.unlock('owner', 'owner', 'alpha', password, ['read']);
});

test('change and disable require current password; prior grant and password are invalidated', async () => {
  const { api, advance } = fixture();
  await api.enable('owner', 'owner', 'alpha', password, 1);
  const old = await api.unlock('owner', 'owner', 'alpha', password, ['read', 'manage']);
  await assert.rejects(api.change('owner', 'owner', 'alpha', 'wrong-password', 'new-password', 1, old.grant), deny('invalidPassword'));
  await api.change('owner', 'owner', 'alpha', password, 'new-password', 1, old.grant);
  await assert.rejects(api.content('owner', 'owner', 'alpha', old.grant), deny('denied'));
  await assert.rejects(api.unlock('owner', 'owner', 'alpha', password, ['read']), deny('invalidPassword'));
  advance(60_001);
  const next = await api.unlock('owner', 'owner', 'alpha', 'new-password', ['read', 'manage']);
  await assert.rejects(api.disable('owner', 'owner', 'alpha', password, 2, next.grant), deny('invalidPassword'));
  assert.deepEqual(await api.disable('owner', 'owner', 'alpha', 'new-password', 2, next.grant),
    { enabled: false, revision: 3 });
  assert.equal((await api.content('owner', 'owner', 'alpha')).content, 'secret alpha');
});

test('OTP recovery binds note/mailbox and consumes once; sibling password remains valid', async () => {
  const { api, store, code } = fixture();
  await api.enable('owner', 'owner', 'alpha', password, 1);
  await api.enable('owner', 'owner', 'beta', 'beta-password', 1);
  const challenge = await api.requestRecovery('owner', 'owner', 'alpha', 'owner@example.test');
  const otp = code();
  assert.match(otp, /^\d{6}$/);
  assert.ok(!JSON.stringify([...store.challenges.values()]).includes(otp));
  await assert.rejects(api.confirmRecovery('owner', 'owner', 'beta', 'owner@example.test',
    challenge.challengeId, otp, 'reset-password'), deny('invalidChallenge'));
  await assert.rejects(api.confirmRecovery('owner', 'owner', 'alpha', 'other@example.test',
    challenge.challengeId, otp, 'reset-password'), deny('invalidChallenge'));
  const lease = await api.confirmRecovery('owner', 'owner', 'alpha', 'owner@example.test',
    challenge.challengeId, otp, 'reset-password');
  assert.equal(lease.revision, 2);
  await assert.rejects(api.confirmRecovery('owner', 'owner', 'alpha', 'owner@example.test',
    challenge.challengeId, otp, 'reset-password'), deny('invalidChallenge'));
  assert.equal((await api.unlock('owner', 'owner', 'beta', 'beta-password', ['read'])).revision, 1);
});

test('OTP rejects expiration, five wrong attempts and concurrent duplicate confirm', async () => {
  for (const mode of ['expired', 'attempts', 'concurrent']) {
    const { api, code, advance } = fixture();
    await api.enable('owner', 'owner', 'alpha', password, 1);
    const c = await api.requestRecovery('owner', 'owner', 'alpha', 'owner@example.test');
    const confirm = (otp: string) => api.confirmRecovery('owner', 'owner', 'alpha',
      'owner@example.test', c.challengeId, otp, 'reset-password');
    if (mode === 'expired') {
      advance(5 * 60_000);
      await assert.rejects(confirm(code()), deny('invalidChallenge'));
    } else if (mode === 'attempts') {
      for (let i = 0; i < 5; i++) await assert.rejects(confirm('not-otp'), deny('invalidChallenge'));
      await assert.rejects(confirm(code()), deny('invalidChallenge'));
    } else {
      const results = await Promise.allSettled([confirm(code()), confirm(code())]);
      assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
    }
  }
});
