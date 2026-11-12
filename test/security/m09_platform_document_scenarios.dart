import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_state_codec.dart';

import '../infrastructure/documents/m09_storage_fixtures.dart' as fixture;
import 'platform_probe.dart';
import 'security_fixtures.dart' show securityPassword;

/// Real IndexedDB/native file and device key custody, unique synthetic accounts.
void registerM09PlatformDocumentScenarios() {
  test(
    'real platform rich document/outbox seals and reopens offline',
    () async {
      final account = 'm09-platform-${DateTime.now().microsecondsSinceEpoch}';
      final store =
          createLocalSyncStore(accountUserId: account) as EncryptedSyncStore;
      addTearDown(store.dispose);
      final repository = NoteRepository(
        currentAccountUserId: () => account,
        localSyncStoreFactory: ({required accountUserId}) => store,
        generateMutationId: () => 'm09-stable',
        now: () => fixture.at,
      );
      await repository.save(
        Note.reconstitute(
          id: 'n',
          ownerId: account,
          title: 'Synthetic rich note',
          content: fixture.doc().plainText,
          document: fixture.doc(),
          pinnedAt: fixture.at,
          createdAt: fixture.at,
          updatedAt: fixture.at,
          attachments: [fixture.attachment],
        ),
      );
      final p = NoteProtection(enabled: true, revision: 1);
      await store.seal('n', securityPassword, p);
      store.dispose();
      final raw = await readPlatformRecord(account);
      expect(jsonDecode(raw)['schemaVersion'], 3);
      expect(raw, isNot(contains('private rich')));
      expect(raw, isNot(contains('fontSize')));
      final reopened =
          createLocalSyncStore(accountUserId: account) as EncryptedSyncStore;
      addTearDown(reopened.dispose);
      expect((await reopened.read()).notes.single.document, null);
      await reopened.unlock('n', securityPassword, p);
      final saved = await reopened.read();
      expect(saved.notes.single.document, fixture.doc());
      expect(saved.outbox.single.payload!.document, fixture.doc());
      expect(saved.outbox.single.mutationId, 'm09-stable');
      expect(saved.notes.single.pinnedAt, fixture.at);
      expect(saved.notes.single.attachments, [fixture.attachment]);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'real encrypted v6 cutover keeps exact legacy outbox and AAD3',
    () async {
      final account = 'm09-v6-${DateTime.now().microsecondsSinceEpoch}';
      final store =
          createLocalSyncStore(accountUserId: account) as EncryptedSyncStore;
      addTearDown(store.dispose);
      final repository = NoteRepository(
        currentAccountUserId: () => account,
        localSyncStoreFactory: ({required accountUserId}) => store,
        generateMutationId: () => 'legacy-stable',
        now: () => fixture.at,
      );
      await repository.save(
        Note.create(
          id: 'n',
          ownerId: account,
          title: 'Legacy title',
          content: 'Legacy body',
          now: fixture.at,
        ),
      );
      final before = await store.read();
      final oldEncoded = await store.backing.readEncoded();
      final envelope = Map<String, Object?>.from(
        jsonDecode(oldEncoded!) as Map,
      );
      final key = await store.codec.deviceKeys.read(
        envelope['keyId'] as String,
      );
      try {
        final aad = 'NoteFlow/M05/v3/${store.codec.namespace.hash}';
        final inner = await store.codec.crypto.decryptJson(
          envelope['packet'],
          key,
          aad,
        );
        final data = inner['state'] as Map;
        data['schemaVersion'] = 6;
        final legacy = jsonEncode({
          ...envelope,
          'packet': await store.codec.crypto.encryptJson(inner, key, aad),
        });
        expect(await store.backing.compareAndSet(oldEncoded, legacy), true);
        store.dispose();
        final reopened =
            createLocalSyncStore(accountUserId: account) as EncryptedSyncStore;
        addTearDown(reopened.dispose);
        final restored = await reopened.read();
        expect(restored, before);
        expect(restored.notes.single.document, null);
        expect(restored.outbox.single.mutationId, 'legacy-stable');
        final currentRaw = await readPlatformRecord(account);
        expect(jsonDecode(currentRaw)['schemaVersion'], 3);
        final currentInner = await reopened.codec.crypto.decryptJson(
          (jsonDecode(currentRaw) as Map)['packet'],
          key,
          aad,
        );
        expect((currentInner['state'] as Map)['schemaVersion'], 7);
        expect(LocalSyncStateCodec.encode(restored)['outbox'], data['outbox']);
        expect(currentRaw, isNot(contains('Legacy body')));
      } finally {
        key.destroy();
      }
    },
  );
}
