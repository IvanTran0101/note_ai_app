import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_state_codec.dart';

import 'security_fixtures.dart';

/// The same real crypto assertions run in Chrome and on Android.
void registerEncryptedStoreScenarios() {
  final p1 = NoteProtection(enabled: true, revision: 1);
  final p2 = NoteProtection(enabled: true, revision: 2);
  test('ciphertext covers notes, pending and conflict; lock/reopen preserves bookkeeping', () async {
    final backing = MemoryCiphertextStore();
    final store = EncryptedSyncStore('security-pending', backing);
    addTearDown(store.dispose);
    await store.replace(securityState('security-pending', pending: true));
    await store.seal('alpha', securityPassword, p1);
    for (final encoded in backing.commits) {
      for (final secret in [
        privateTitle,
        privateBody,
        securityPassword,
        'private remote title',
        'private remote content',
      ]) {
        expect(encoded, isNot(contains(secret)));
      }
    }
    store.lock('alpha');
    final locked = await store.read();
    expect(locked.notes.first.contentAvailable, false);
    expect(locked.notes.first.title, isEmpty);
    expect(locked.outbox.single.payload!.content, isEmpty);
    expect(locked.conflicts.single.remote!.content, isEmpty);
    expect(locked.cursor!.value, 'synthetic-cursor');
    final reopened = EncryptedSyncStore('security-pending', backing);
    addTearDown(reopened.dispose);
    expect((await reopened.read()).notes.first.contentAvailable, false);
    await expectLater(
      reopened.unlock('alpha', 'wrong-password', p1),
      throwsA(isA<NoteSecurityFailure>()),
    );
    expect((await reopened.read()).notes.first.contentAvailable, false);
    await reopened.unlock('alpha', securityPassword, p1);
    final state = await reopened.read();
    expect(state.notes.first.content, privateBody);
    expect(state.outbox.single.mutationId, 'stable-mutation-id');
    expect(state.outbox.single.baseRevision, 7);
    expect(state.outbox.single.retryCount, 3);
    expect(state.outbox.single.payload!.content, privateBody);
    expect(state.conflicts.single.remote!.content, 'private remote content');
    expect(state.notes.last.content, 'sibling content');
  }, timeout: const Timeout(Duration(minutes: 5)));

  test(
    'two protected notes keep distinct passwords and independent locks',
    () async {
      final store = EncryptedSyncStore(
        'security-isolation',
        MemoryCiphertextStore(),
      );
      addTearDown(store.dispose);
      await store.replace(securityState('security-isolation'));
      await store.seal('alpha', securityPassword, p1);
      await store.seal('beta', 'sibling-password', p1);
      store.lock(null);
      await store.unlock('alpha', securityPassword, p1);
      var state = await store.read();
      expect(state.notes.first.content, privateBody);
      expect(state.notes.last.contentAvailable, false);
      await expectLater(
        store.unlock('beta', securityPassword, p1),
        throwsA(isA<NoteSecurityFailure>()),
      );
      await store.unlock('beta', 'sibling-password', p1);
      state = await store.read();
      expect(state.notes.last.content, 'sibling content');
      store.lock('alpha');
      state = await store.read();
      expect(state.notes.first.contentAvailable, false);
      expect(state.notes.last.content, 'sibling content');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'rewrap rejects old password and disable preserves body and sibling',
    () async {
      final store = EncryptedSyncStore(
        'security-rewrap',
        MemoryCiphertextStore(),
      );
      addTearDown(store.dispose);
      await store.replace(securityState('security-rewrap'));
      await store.seal('alpha', securityPassword, p1);
      await store.rewrap('alpha', securityPassword, 'replacement-password', p2);
      store.lock('alpha');
      await expectLater(
        store.unlock('alpha', securityPassword, p2),
        throwsA(isA<NoteSecurityFailure>()),
      );
      await store.unlock('alpha', 'replacement-password', p2);
      expect((await store.read()).notes.first.content, privateBody);
      await store.disable(
        'alpha',
        'replacement-password',
        NoteProtection(enabled: false, revision: 3),
      );
      final state = await store.read();
      expect(state.notes.first.protection.enabled, false);
      expect(state.notes.first.content, privateBody);
      expect(state.notes.last.content, 'sibling content');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('v2 migration is atomic, quarantines unknown content and preserves identities', () async {
    final original = LocalSyncStateCodec.encode(
      securityState('security-migration', pending: true),
    );
    original['schemaVersion'] = 2;
    for (final note in original['notes'] as List) {
      note.remove('attachments');
    }
    for (final conflict in original['conflicts'] as List) {
      conflict['local'].remove('attachments');
      conflict['remote']?.remove('attachments');
      conflict['remote']?.remove('includesAttachments');
    }
    for (final note in original['notes'] as List) {
      (note as Map).remove('protected');
      note.remove('protectionRevision');
      note.remove('contentAvailable');
    }
    final backing = MemoryCiphertextStore()
      ..encoded = jsonEncode(original)
      ..failCommits = 5;
    final store = EncryptedSyncStore('security-migration', backing);
    addTearDown(store.dispose);
    final old = backing.encoded;
    await expectLater(store.read(), throwsA(isA<NoteSecurityFailure>()));
    expect(
      backing.encoded,
      old,
      reason: 'failed commit must not reset the source',
    );
    final locked = await store.read();
    expect(jsonDecode(backing.encoded!)['schemaVersion'], 3);
    expect(backing.encoded, isNot(contains(privateBody)));
    expect(locked.notes.first.contentAvailable, false);
    expect(locked.outbox.single.mutationId, 'stable-mutation-id');
    await store.observeProtection('alpha', const NoteProtection.unprotected());
    final restored = await store.read();
    expect(restored.notes.first.content, privateBody);
    expect(restored.outbox.single.payload!.content, privateBody);
    expect(restored.conflicts.single.remote!.content, 'private remote content');
    expect(restored.cursor!.value, 'synthetic-cursor');
  });

  test(
    'tampering and wrong account fail closed without overwriting ciphertext',
    () async {
      final backing = MemoryCiphertextStore();
      final store = EncryptedSyncStore('security-authentic', backing);
      addTearDown(store.dispose);
      await store.replace(securityState('security-authentic'));
      final foreign = EncryptedSyncStore('security-foreign', backing);
      addTearDown(foreign.dispose);
      await expectLater(foreign.read(), throwsA(isA<NoteSecurityFailure>()));
      final value = jsonDecode(backing.encoded!) as Map;
      final packet = value['packet'] as Map;
      final bytes = base64Decode(packet['ciphertext'] as String)..[0] ^= 1;
      packet['ciphertext'] = base64Encode(bytes);
      backing.encoded = jsonEncode(value);
      final corrupt = backing.encoded;
      await expectLater(store.read(), throwsA(isA<NoteSecurityFailure>()));
      expect(backing.encoded, corrupt);
    },
  );

  test('password reset retains unsynced old ciphertext and blocks destructive edits', () async {
    final store = EncryptedSyncStore(
      'security-retained',
      MemoryCiphertextStore(),
    );
    addTearDown(store.dispose);
    await store.replace(securityState('security-retained', pending: true));
    await store.seal('alpha', securityPassword, p1);
    store.lock('alpha');
    await store.observeProtection('alpha', p2);
    await store.unlock('alpha', 'reset-password', p2, verifiedOnline: true);
    expect(store.hasRetainedCiphertext('alpha'), true);
    expect((await store.read()).notes.first.content, isNot(privateBody));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
