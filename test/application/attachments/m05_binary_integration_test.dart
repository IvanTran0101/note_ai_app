import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/attachments/attachment_binding.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/notes/note_security_service.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/labels/local_label_state.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/attachments/attachment_chunk_cipher.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_state_codec.dart';

import '../../security/security_fixtures.dart';
import '../../security/security_harness.dart';
import '../../infrastructure/notes/attachment_metadata_test.dart'
    show descriptor;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('M05 opened key seals M03 chunks; lock forbids fallback; reopen restores descriptors', () async {
    final backing = MemoryCiphertextStore();
    var store = EncryptedSyncStore('user-1', backing);
    final time = DateTime.utc(2026, 10, 4);
    await store.replace(
      LocalSyncState(
        accountUserId: 'user-1',
        labels: [
          LocalLabelState(
            id: 'label-1',
            ownerId: 'user-1',
            name: 'Private label',
            createdAt: time,
            updatedAt: time,
          ),
        ],
        notes: [
          LocalNoteState(
            id: 'note-1',
            ownerId: 'user-1',
            title: 'Title',
            content: 'Body',
            createdAt: time,
            updatedAt: time,
            serverRevision: 1,
            pinnedAt: time,
            attachments: [descriptor()],
            labelIds: ['label-1'],
          ),
        ],
      ),
    );
    final p = NoteProtection(enabled: true, revision: 1);
    await store.seal('note-1', securityPassword, p);
    final binding = AttachmentBinding(
      actorId: 'user-1',
      note: NoteIdentity('user-1', 'note-1'),
      protection: p,
      accessRevision: 0,
      sessionGeneration: 1,
      contentRevision: 1,
    );
    final cipher = AttachmentChunkCipher(
      requireAccess: (_, _) {},
      resolveKey: (b) => store.attachmentKey(b),
    );
    final packet = await cipher.seal(binding, 'a' * 64, 0, [1, 2, 3]);
    expect(await cipher.open(binding, 'a' * 64, 0, packet), [1, 2, 3]);
    store.lock('note-1');
    expect((await store.read()).notes.single.attachments, isEmpty);
    expect((await store.read()).notes.single.labelIds, isEmpty);
    await expectLater(
      cipher.open(binding, 'a' * 64, 0, packet),
      throwsA(isA<NoteSecurityFailure>()),
    );
    store.dispose();
    store = EncryptedSyncStore('user-1', backing);
    addTearDown(store.dispose);
    await store.unlock('note-1', securityPassword, p);
    final restored = await store.read();
    expect(restored.notes.single.attachments, [descriptor()]);
    expect(restored.notes.single.pinnedAt, time);
    expect(restored.notes.single.labelIds, ['label-1']);
    expect(restored.labels.single.name, 'Private label');
    expect(await cipher.open(binding, 'a' * 64, 0, packet), [1, 2, 3]);
    expect(jsonDecode(backing.encoded!)['schemaVersion'], 3);
    expect(LocalSyncStateCodec.encode(restored)['schemaVersion'], 6);
    expect(backing.encoded, isNot(contains('file.txt')));
    expect(backing.encoded, isNot(contains('Private label')));
  });

  test(
    'M05 online and offline owner unlock include explicit binary scopes',
    () async {
      final h = SecurityHarness('binary-owner');
      await h.initialize();
      addTearDown(h.dispose);
      await h.security.enable('alpha', securityPassword, securityPassword);
      for (final offline in [false, true]) {
        h.security.lock('alpha');
        await h.security.unlock('alpha', securityPassword, offline: offline);
        for (final operation in [
          NoteOperation.attachmentRead,
          NoteOperation.attachmentWrite,
        ]) {
          expect(
            h.security.allows(
              ownerId: h.account,
              noteId: 'alpha',
              protection: h.gateway.protection,
              operation: operation,
            ),
            true,
          );
        }
      }
    },
  );
}
