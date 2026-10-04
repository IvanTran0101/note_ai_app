import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_security_service.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/domain/notes/note_repository.dart' as domain;
import 'package:note_ai_app/domain/users/user_preferences.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';
import 'package:note_ai_app/infrastructure/security/device_envelope_keys.dart';
import 'package:note_ai_app/infrastructure/security/note_crypto.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store.dart';
import 'package:note_ai_app/infrastructure/sync/sync_http_mapper.dart';

import 'local_first_scenarios.dart';
import 'platform_probe.dart';
import 'security_fixtures.dart';

void registerM02StoreScenarios() {
  test(
    'M02 pin/layout survive offline protection, encrypted reopen and unpin',
    () async {
      final account = 'm02-protected-${DateTime.now().microsecondsSinceEpoch}';
      var store =
          createLocalSyncStore(accountUserId: account) as EncryptedSyncStore;
      final preferences = UserPreferences.create(
        userId: account,
        theme: AppThemePreference.system,
        noteFontSize: NoteFontSizePreference.medium,
      )..changeNoteLayout(NoteLayoutPreference.list);
      await store.replace(
        LocalSyncState(
          accountUserId: account,
          userPreferences: preferences,
          notes: [
            LocalNoteState(
              id: 'alpha',
              ownerId: account,
              title: privateTitle,
              content: privateBody,
              createdAt: fixtureTime,
              updatedAt: fixtureTime,
              pinnedAt: fixtureTime,
            ),
          ],
        ),
      );
      var service = localService(account, store);
      await service.enable('alpha', securityPassword, securityPassword);
      expect((await store.read()).outbox.single.payload!.pinnedAt, fixtureTime);
      service.dispose();
      store.dispose();
      final raw = await readPlatformRecord(account);
      expect(raw, isNot(contains(privateBody)));
      store =
          createLocalSyncStore(accountUserId: account) as EncryptedSyncStore;
      service = localService(account, store);
      addTearDown(() {
        service.dispose();
        store.dispose();
      });
      final locked = await store.read();
      expect(locked.notes.single.contentAvailable, false);
      expect(locked.notes.single.pinnedAt, fixtureTime);
      expect(locked.userPreferences.noteLayout, NoteLayoutPreference.list);
      await service.unlock('alpha', securityPassword, offline: true);
      final repository = NoteRepository(
        currentAccountUserId: () => account,
        localSyncStoreFactory: ({required accountUserId}) => store,
        generateMutationId: () => 'm02-unpin',
        now: () => fixtureTime,
        accessGuard: service,
      );
      await repository.updateById(
        noteId: 'alpha',
        ownerId: account,
        expectedAccountUserId: account,
        canCommit: () => true,
        change: (fresh) {
          fresh.unpin(fixtureTime);
          return fresh;
        },
      );
      final saved = await store.read();
      expect(saved.notes.single.content, privateBody);
      expect(saved.notes.single.pinnedAt, isNull);
      expect(saved.outbox.single.payload!.includesPinnedAt, true);
      expect(saved.outbox.single.payload!.pinnedAt, isNull);
      expect(saved.userPreferences.noteLayout, NoteLayoutPreference.list);
      await store.hydrate(
        SyncNoteSnapshot(
          id: 'alpha',
          ownerId: account,
          title: privateTitle,
          content: privateBody,
          createdAt: fixtureTime,
          serverUpdatedAt: fixtureTime,
          revision: 1,
          pinnedAt: fixtureTime,
          protection: saved.notes.single.protection,
        ),
      );
      expect((await store.read()).notes.single.pinnedAt, isNull);
    },
  );

  test(
    'M05 old encrypted v3 packet keeps device key, cursor and attempted bytes',
    () async {
      final account = 'm02-v3-${DateTime.now().microsecondsSinceEpoch}';
      var store =
          createLocalSyncStore(accountUserId: account) as EncryptedSyncStore;
      final state = securityState(account, pending: true);
      await store.replace(state);
      final current = await store.backing.readEncoded();
      final document = jsonDecode(current!) as Map<String, dynamic>;
      final hash = store.codec.namespace.hash;
      final crypto = NoteCrypto();
      final key = await DeviceEnvelopeKeys(
        hash,
        crypto,
      ).read(document['keyId'] as String);
      try {
        final inner = await crypto.decryptJson(
          document['packet'],
          key,
          'NoteFlow/M05/v3/$hash',
        );
        final old = inner['state'] as Map;
        old['schemaVersion'] = 3;
        old.remove('userPreferences');
        for (final note in old['notes'] as List) {
          note.remove('pinnedAt');
          note.remove('attachments');
        }
        for (final conflict in old['conflicts'] as List) {
          conflict['local'].remove('pinnedAt');
          conflict['local'].remove('attachments');
          conflict['remote']?.remove('pinnedAt');
          conflict['remote']?.remove('attachments');
          conflict['remote']?.remove('includesAttachments');
        }
        document['packet'] = await crypto.encryptJson(
          inner,
          key,
          'NoteFlow/M05/v3/$hash',
        );
        expect(
          await store.backing.compareAndSet(current, jsonEncode(document)),
          true,
        );
      } finally {
        key.destroy();
      }
      store.dispose();
      store =
          createLocalSyncStore(accountUserId: account) as EncryptedSyncStore;
      addTearDown(store.dispose);
      final migrated = await store.read();
      expect(migrated.cursor, state.cursor);
      expect(migrated.outbox.single.mutationId, state.outbox.single.mutationId);
      expect(
        jsonEncode(encodeSyncMutation(migrated.outbox.single.mutation)),
        jsonEncode(encodeSyncMutation(state.outbox.single.mutation)),
      );
      expect(migrated.conflicts, state.conflicts);
      expect(migrated.userPreferences.userId, account);
      await expectLater(
        NoteRepository(
          currentAccountUserId: () => account,
          localSyncStoreFactory: ({required accountUserId}) => store,
          generateMutationId: () => 'unused',
          now: () => fixtureTime,
        ).updateById(
          noteId: 'missing',
          ownerId: account,
          expectedAccountUserId: account,
          canCommit: () => true,
          change: (note) => note,
        ),
        throwsA(isA<domain.NoteMutationMissingException>()),
      );
    },
  );
}
