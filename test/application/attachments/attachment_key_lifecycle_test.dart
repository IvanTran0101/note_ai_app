import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/attachments/attachment_binding.dart';
import 'package:note_ai_app/application/attachments/attachment_input.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/attachments/attachment_chunk_cipher.dart';
import 'package:note_ai_app/infrastructure/attachments/encrypted_attachment_cache.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';
import 'package:note_ai_app/infrastructure/security/note_crypto.dart';

import '../../security/security_fixtures.dart';
import 'attachment_transfer_test.dart' show MemoryBlobs;

AttachmentBinding bound(NoteProtection p) => AttachmentBinding(
  actorId: 'owner',
  note: NoteIdentity('owner', 'alpha'),
  protection: p,
  accessRevision: 0,
  sessionGeneration: 1,
  contentRevision: 7,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'durable binary DEK survives offline enable, change, disable and restart',
    () async {
      final backing = MemoryCiphertextStore();
      var store = EncryptedSyncStore('owner', backing);
      addTearDown(() => store.dispose());
    await store.replace(securityState('owner'));
      final cipher = AttachmentChunkCipher(
        requireAccess: (_, _) {},
        resolveKey: (b) => store.attachmentKey(b),
      );
      var p = const NoteProtection.unprotected();
      final id = 'a' * 64;
      final packet = await cipher.seal(bound(p), id, 0, [1, 2, 3]);
      final firstWrap = backing.encoded;
      p = await store.enableLocal('alpha', securityPassword);
      expect(backing.encoded, isNot(firstWrap));
      await expectLater(
        cipher.open(bound(const NoteProtection.unprotected()), id, 0, packet),
        throwsA(isA<NoteSecurityFailure>()),
      );
      expect(await cipher.open(bound(p), id, 0, packet), [1, 2, 3]);
      p = await store.changeLocal(
        'alpha',
        securityPassword,
        '$securityPassword-next',
      );
      expect(await cipher.open(bound(p), id, 0, packet), [1, 2, 3]);
      store.lock('alpha');
      await expectLater(
        cipher.open(bound(p), id, 0, packet),
        throwsA(isA<NoteSecurityFailure>()),
      );
      store.dispose();
      store = EncryptedSyncStore('owner', backing);
      await store.unlock('alpha', '$securityPassword-next', p);
      expect(await cipher.open(bound(p), id, 0, packet), [1, 2, 3]);
      p = await store.disableLocal('alpha', '$securityPassword-next');
      store.dispose();
      store = EncryptedSyncStore('owner', backing);
      expect(await cipher.open(bound(p), id, 0, packet), [1, 2, 3]);
      expect((await store.read()).outbox, isNotEmpty);
      expect(jsonDecode(backing.encoded!)['schemaVersion'], 3);
    },
  );

  test(
    'legacy queued chunks and metadata migrate before protection rotation',
    () async {
      final backing = MemoryCiphertextStore(), blobs = MemoryBlobs();
      final store = EncryptedSyncStore('owner', backing);
      addTearDown(store.dispose);
      await store.replace(securityState('owner'));
      var p = const NoteProtection.unprotected();
      final cipher = AttachmentChunkCipher(
        requireAccess: (_, _) {},
        resolveKey: store.attachmentKey,
        resolveLegacyKey: store.attachmentLegacyKey,
      );
      final cache = EncryptedAttachmentCache(
        actorId: 'owner',
        store: blobs,
        cipher: cipher,
        generateId: () => 'legacy-draft',
      );
      final bytes = utf8.encode('legacy Pending bytes');
      final draft = await cache.stage(
        bound(p),
        AttachmentInput(
          fileName: 'pending.txt',
          mimeType: 'text/plain',
          sizeBytes: bytes.length,
          openRead: ([start, end]) =>
              Stream.value(bytes.sublist(start ?? 0, end)),
        ),
        existing: [],
      );
      for (final entry in blobs.packets.entries.toList()) {
        final chunk = entry.key.endsWith('-meta') ? -1 : 0;
        final plain = await cipher.open(
          bound(p),
          draft.cacheId,
          chunk,
          entry.value,
        );
        final root = await store.attachmentLegacyKey(bound(p));
        blobs.packets[entry.key] = await NoteCrypto().encrypt(
          plain,
          root,
          jsonEncode([
            'NoteFlow/M03/chunk/v1',
            'owner',
            'owner',
            'alpha',
            false,
            0,
            0,
            draft.cacheId,
            chunk,
          ]),
        );
        plain.fillRange(0, plain.length, 0);
      }
      store.beforeAttachmentProtectionChange = (_) =>
          cache.upgradeLegacyPackets(bound(p));
      p = await store.enableLocal('alpha', securityPassword);
      expect(
        (await cache.load(bound(p), draft.cacheId)).fileName,
        'pending.txt',
      );
      expect(
        await cache.read(bound(p), draft).expand((b) => b).toList(),
        bytes,
      );
      p = await store.changeLocal(
        'alpha',
        securityPassword,
        '$securityPassword-next',
      );
      expect(
        await cache.read(bound(p), draft).expand((b) => b).toList(),
        bytes,
      );
      expect(jsonEncode(blobs.packets), isNot(contains('legacy Pending')));
    },
  );

  test(
    'failed first DEK commit cannot write chunks with an unpersisted key',
    () async {
      final backing = MemoryCiphertextStore();
      var store = EncryptedSyncStore('owner', backing);
      addTearDown(() => store.dispose());
      await store.replace(securityState('owner'));
      final cipher = AttachmentChunkCipher(
        requireAccess: (_, _) {},
        resolveKey: (b) => store.attachmentKey(b),
      );
      final before = backing.encoded;
      backing.failCommits = 5;
      await expectLater(
        cipher.seal(bound(const NoteProtection.unprotected()), 'b' * 64, 0, [
          7,
        ]),
        throwsA(isA<NoteSecurityFailure>()),
      );
      expect(backing.encoded, before);
      final packet = await cipher.seal(
        bound(const NoteProtection.unprotected()),
        'b' * 64,
        0,
        [7],
      );
      store.dispose();
      store = EncryptedSyncStore('owner', backing);
      expect(
        await cipher.open(
          bound(const NoteProtection.unprotected()),
          'b' * 64,
          0,
          packet,
        ),
        [7],
      );
    },
  );

  test(
    'remote protection reset retains but never substitutes a device key',
    () async {
      final backing = MemoryCiphertextStore();
      final store = EncryptedSyncStore('owner', backing);
      addTearDown(store.dispose);
      await store.replace(securityState('owner'));
      final p = await store.enableLocal('alpha', securityPassword);
      final cipher = AttachmentChunkCipher(
        requireAccess: (_, _) {},
        resolveKey: store.attachmentKey,
      );
      final packet = await cipher.seal(bound(p), 'c' * 64, 0, [9]);
      final reset = NoteProtection(enabled: false, revision: p.revision + 1);
      await store.observeProtection('alpha', reset);
      await expectLater(
        cipher.open(bound(reset), 'c' * 64, 0, packet),
        throwsA(isA<NoteSecurityFailure>()),
      );
      expect(backing.encoded, isNotNull);
    },
  );
}
