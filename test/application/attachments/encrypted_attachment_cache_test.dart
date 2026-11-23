import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/attachments/attachment_binding.dart';
import 'package:note_ai_app/application/attachments/attachment_input.dart';
import 'package:note_ai_app/application/attachments/attachment_policy.dart';
import 'package:note_ai_app/application/attachments/local_attachment_draft.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/attachments/attachment_blob_store_io.dart';
import 'package:note_ai_app/infrastructure/attachments/attachment_blob_store.dart';
import 'package:note_ai_app/infrastructure/attachments/attachment_chunk_cipher.dart';
import 'package:note_ai_app/infrastructure/attachments/encrypted_attachment_cache.dart';
import 'package:note_ai_app/infrastructure/security/note_crypto.dart';

AttachmentBinding binding([String actor = 'owner']) => AttachmentBinding(
  actorId: actor,
  note: NoteIdentity('owner', 'note'),
  protection: NoteProtection(enabled: true, revision: 1),
  accessRevision: 1,
  sessionGeneration: 1,
  contentRevision: 1,
);
AttachmentInput text(List<int> bytes, {int? declaredLength}) => AttachmentInput(
  fileName: 'PRIVATE-FILENAME.txt',
  mimeType: 'text/plain',
  sizeBytes: declaredLength ?? bytes.length,
  openRead: ([start, end]) =>
      Stream.value(bytes.sublist(start ?? 0, end ?? bytes.length)),
);

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('noteflow-m03-test-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  test('ciphertext survives restart and supports cross-chunk ranges', () async {
    final key = await NoteCrypto().newKey();
    addTearDown(key.destroy);
    final store = FileAttachmentBlobStore(
      actorId: 'owner',
      supportPath: () async => directory.path,
    );
    final cipher = AttachmentChunkCipher(
      requireAccess: (_, _) {},
      resolveKey: (_) async => key,
    );
    final cache = EncryptedAttachmentCache(
      actorId: 'owner',
      store: store,
      cipher: cipher,
      generateId: () => 'attempt',
    );
    final bytes = utf8.encode(
      'PRIVATE-BODY:${'x' * AttachmentPolicy.chunkBytes}',
    );
    final draft = await cache.stage(binding(), text(bytes), existing: const []);
    expect(draft.sha256, crypto.sha256.convert(bytes).toString());
    expect(draft.chunkCount, 2);
    for (final file in directory.listSync(recursive: true).whereType<File>()) {
      final stored = await file.readAsString();
      expect(stored, isNot(contains('PRIVATE-FILENAME')));
      expect(stored, isNot(contains('PRIVATE-BODY')));
      expect(stored, isNot(contains('"key"')));
    }
    final restartedStore = FileAttachmentBlobStore(
      actorId: 'owner',
      supportPath: () async => directory.path,
    );
    final restarted = EncryptedAttachmentCache(
      actorId: 'owner',
      store: restartedStore,
      cipher: cipher,
      generateId: () => 'unused',
    );
    final restored = await restarted.load(binding(), draft.cacheId);
    await expectLater(
      restarted
          .read(
            binding(),
            LocalAttachmentDraft(
              cacheId: restored.cacheId,
              fileName: restored.fileName,
              mimeType: restored.mimeType,
              sizeBytes: restored.sizeBytes,
              sha256: restored.sha256,
              chunkCount: 0,
            ),
          )
          .toList(),
      throwsFormatException,
    );
    expect(await restarted.pendingIds(binding()), [draft.cacheId]);
    expect(restored.sha256, draft.sha256);
    final output = BytesBuilder(copy: true);
    final start = AttachmentPolicy.chunkBytes - 5;
    await for (final chunk in restarted.read(
      binding(),
      restored,
      start: start,
    )) {
      output.add(chunk);
    }
    expect(output.takeBytes(), bytes.sublist(start));
    await expectLater(
      restarted.load(binding('other'), draft.cacheId),
      throwsStateError,
    );
    await restarted.cancelLocal(binding(), draft.cacheId);
    expect(await restartedStore.readIndex(), isEmpty);
  });
  test('invalid text and changed sizes cannot leave queued drafts', () async {
    final key = await NoteCrypto().newKey();
    addTearDown(key.destroy);
    final store = FileAttachmentBlobStore(
      actorId: 'owner',
      supportPath: () async => directory.path,
    );
    final cipher = AttachmentChunkCipher(
      requireAccess: (_, _) {},
      resolveKey: (_) async => key,
    );
    var id = 0;
    final cache = EncryptedAttachmentCache(
      actorId: 'owner',
      store: store,
      cipher: cipher,
      generateId: () => '${++id}',
    );
    await expectLater(
      cache.stage(binding(), text([0xc3, 0x28]), existing: const []),
      throwsFormatException,
    );
    expect(await store.readIndex(), isEmpty);
    await expectLater(
      cache.stage(
        binding(),
        text([65, 66], declaredLength: 1),
        existing: const [],
      ),
      throwsFormatException,
    );
    expect(await store.readIndex(), isEmpty);
  });
  test('lock stops a reader but keeps its queued ciphertext', () async {
    final key = await NoteCrypto().newKey();
    addTearDown(key.destroy);
    final store = FileAttachmentBlobStore(
      actorId: 'owner',
      supportPath: () async => directory.path,
    );
    var allowed = true;
    final cipher = AttachmentChunkCipher(
      requireAccess: (_, _) {
        if (!allowed) throw StateError('locked');
      },
      resolveKey: (_) async => key,
    );
    final cache = EncryptedAttachmentCache(
      actorId: 'owner',
      store: store,
      cipher: cipher,
      generateId: () => 'attempt',
    );
    final bytes = utf8.encode('x' * (AttachmentPolicy.chunkBytes + 1));
    final draft = await cache.stage(binding(), text(bytes), existing: const []);
    final reader = StreamIterator(cache.read(binding(), draft));
    expect(await reader.moveNext(), isTrue);
    allowed = false;
    await expectLater(reader.moveNext(), throwsStateError);
    await reader.cancel();
    expect((await store.readIndex()).containsKey(draft.cacheId), isTrue);
  });

  test(
    'failed cancellation is unreadable and cleanup can be retried',
    () async {
      final key = await NoteCrypto().newKey();
      addTearDown(key.destroy);
      final disk = FileAttachmentBlobStore(
        actorId: 'owner',
        supportPath: () async => directory.path,
      );
      final store = _FailingCleanupStore(disk);
      final cache = EncryptedAttachmentCache(
        actorId: 'owner',
        store: store,
        cipher: AttachmentChunkCipher(
          requireAccess: (_, _) {},
          resolveKey: (_) async => key,
        ),
        generateId: () => 'attempt',
      );
      final draft = await cache.stage(
        binding(),
        text(utf8.encode('hello')),
        existing: const [],
      );
      store.failDeletion = true;
      await expectLater(
        cache.cancelLocal(binding(), draft.cacheId),
        throwsStateError,
      );
      expect(
        (await disk.readIndex())[draft.cacheId],
        containsPair('phase', 'cancelling'),
      );
      expect(await cache.pendingIds(binding()), isEmpty);
      await expectLater(cache.load(binding(), draft.cacheId), throwsStateError);
      await expectLater(
        cache.read(binding(), draft).toList(),
        throwsStateError,
      );
      store.failDeletion = false;
      await cache.cancelLocal(binding(), draft.cacheId);
      await cache.cancelLocal(binding(), draft.cacheId); // idempotent
      expect(await disk.readIndex(), isEmpty);
    },
  );

  test(
    'restart recovery cleans only incomplete records for the canonical note',
    () async {
      final key = await NoteCrypto().newKey();
      addTearDown(key.destroy);
      final store = FileAttachmentBlobStore(
        actorId: 'owner',
        supportPath: () async => directory.path,
      );
      var sequence = 0;
      final cache = EncryptedAttachmentCache(
        actorId: 'owner',
        store: store,
        cipher: AttachmentChunkCipher(
          requireAccess: (_, _) {},
          resolveKey: (_) async => key,
        ),
        generateId: () => '${++sequence}',
      );
      final interrupted = await cache.stage(
        binding(),
        text(utf8.encode('partial')),
        existing: const [],
      );
      final retained = await cache.stage(
        binding(),
        text(utf8.encode('pending')),
        existing: const [],
      );
      final otherBinding = AttachmentBinding(
        actorId: 'owner',
        note: NoteIdentity('owner', 'other'),
        protection: binding().protection,
        accessRevision: 1,
        sessionGeneration: 1,
        contentRevision: 1,
      );
      final other = await cache.stage(
        otherBinding,
        text(utf8.encode('other note')),
        existing: const [],
      );
      // Simulate the durable marker left by a process exit before stage commit.
      await store.updateIndex(
        (index) => {
          ...index,
          interrupted.cacheId: {
            ...index[interrupted.cacheId] as Map,
            'phase': 'staging',
            'chunkCount': 0,
          },
        },
      );
      await cache.recoverIncomplete(binding());
      expect(await cache.pendingIds(binding()), [retained.cacheId]);
      expect(await cache.pendingIds(otherBinding), [other.cacheId]);
      expect(
        (await store.readIndex()).containsKey(interrupted.cacheId),
        isFalse,
      );
      expect(
        (await cache.load(binding(), retained.cacheId)).sha256,
        retained.sha256,
      );
      await cache.recoverIncomplete(binding()); // restart cleanup is idempotent
    },
  );

  test(
    'linked cache is not pending and cannot be cancelled as a draft',
    () async {
      final key = await NoteCrypto().newKey();
      addTearDown(key.destroy);
      final store = FileAttachmentBlobStore(
        actorId: 'owner',
        supportPath: () async => directory.path,
      );
      final cache = EncryptedAttachmentCache(
        actorId: 'owner',
        store: store,
        cipher: AttachmentChunkCipher(
          requireAccess: (_, _) {},
          resolveKey: (_) async => key,
        ),
        generateId: () => 'attempt',
      );
      final draft = await cache.stage(
        binding(),
        text(utf8.encode('hello')),
        existing: const [],
      );
      await cache.markLinked(binding(), draft.cacheId);
      await cache.markLinked(binding(), draft.cacheId);
      expect(await cache.pendingIds(binding()), isEmpty);
      expect((await cache.load(binding(), draft.cacheId)).sha256, draft.sha256);
      await expectLater(
        cache.cancelLocal(binding(), draft.cacheId),
        throwsStateError,
      );
      expect(
        await cache.read(binding(), draft).expand((bytes) => bytes).toList(),
        utf8.encode('hello'),
      );
    },
  );
}

final class _FailingCleanupStore implements AttachmentBlobStore {
  _FailingCleanupStore(this.delegate);
  final AttachmentBlobStore delegate;
  bool failDeletion = false;
  @override
  Future<Map<String, Object?>> readIndex() => delegate.readIndex();
  @override
  Future<Map<String, Object?>> updateIndex(
    Map<String, Object?> Function(Map<String, Object?>) change,
  ) => delegate.updateIndex(change);
  @override
  Future<Map<String, Object?>?> readChunk(String key) =>
      delegate.readChunk(key);
  @override
  Future<void> writeChunk(String key, Map<String, Object?> packet) =>
      delegate.writeChunk(key, packet);
  @override
  Future<void> removeChunk(String key) {
    if (failDeletion) throw StateError('Injected disk failure');
    return delegate.removeChunk(key);
  }
}
