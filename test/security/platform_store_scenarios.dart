import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_state_codec.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store.dart';

import 'platform_probe.dart';
import 'security_fixtures.dart';

void registerPlatformStoreScenarios() {
  test('real platform storage commits ciphertext and reopens offline without losing pending', () async {
    final account = 'm05-platform-${DateTime.now().microsecondsSinceEpoch}';
    final p = NoteProtection(enabled: true, revision: 1);
    final store =
        createLocalSyncStore(accountUserId: account) as EncryptedSyncStore;
    addTearDown(store.dispose);
    await store.replace(securityState(account, pending: true));
    await store.seal('alpha', securityPassword, p);
    store.dispose();
    final raw = await readPlatformRecord(account);
    expect(jsonDecode(raw)['schemaVersion'], 3);
    expect(raw, isNot(contains(privateBody)));
    expect(raw, isNot(contains(privateTitle)));
    expect(raw, isNot(contains(securityPassword)));
    final reopened =
        createLocalSyncStore(accountUserId: account) as EncryptedSyncStore;
    addTearDown(reopened.dispose);
    expect((await reopened.read()).notes.first.contentAvailable, false);
    await reopened.unlock('alpha', securityPassword, p);
    final state = await reopened.read();
    expect(state.notes.first.content, privateBody);
    expect(state.outbox.single.mutationId, 'stable-mutation-id');
    expect(state.outbox.single.retryCount, 3);
    expect(state.conflicts.single.remote!.content, 'private remote content');
  }, timeout: const Timeout(Duration(minutes: 5)));

  test(
    'real v2 platform migration seals active and controlled staging records',
    () async {
      final account =
          'm05-platform-migration-${DateTime.now().microsecondsSinceEpoch}';
      final legacy = LocalSyncStateCodec.encode(
        securityState(account, pending: true),
      );
      legacy['schemaVersion'] = 2;
      for (final note in legacy['notes'] as List) {
        note.remove('attachments');
      }
      for (final conflict in legacy['conflicts'] as List) {
        conflict['local'].remove('attachments');
        conflict['remote']?.remove('attachments');
        conflict['remote']?.remove('includesAttachments');
      }
      await writeLegacyPlatformRecord(account, jsonEncode(legacy));
      final store =
          createLocalSyncStore(accountUserId: account) as EncryptedSyncStore;
      addTearDown(store.dispose);
      final locked = await store.read();
      expect(locked.notes.first.contentAvailable, false);
      expect(locked.cursor!.value, 'synthetic-cursor');
      for (final raw in await readControlledRecords(account)) {
        expect(raw, isNot(contains(privateBody)));
        expect(raw, isNot(contains(privateTitle)));
        expect(raw, isNot(contains('private remote content')));
      }
      await store.observeProtection(
        'alpha',
        const NoteProtection.unprotected(),
      );
      expect((await store.read()).notes.first.content, privateBody);
      expect(
        (await store.read()).outbox.single.mutationId,
        'stable-mutation-id',
      );
    },
  );
}
