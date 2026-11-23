import 'dart:convert';

import 'package:crypto/crypto.dart' as hash;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/attachments/attachment_binding.dart';
import 'package:note_ai_app/application/attachments/attachment_input.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/domain/notes/attachment.dart';
import 'package:note_ai_app/infrastructure/attachments/attachment_chunk_cipher.dart';
import 'package:note_ai_app/infrastructure/attachments/encrypted_attachment_cache.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';

import '../../security/security_fixtures.dart';
import 'attachment_transfer_test.dart' show MemoryBlobs;
import 'attachment_key_lifecycle_test.dart' show bound;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('fresh remote read survives a retired cache key without changing ciphertext', () async {
    final fixture = await _retiredCase();
    final backing = fixture.backing,
        blobs = fixture.blobs,
        cache = fixture.cache;
    final descriptor = fixture.descriptor, bytes = fixture.bytes;
    final current = fixture.protection;
    final before = backing.encoded,
        packets = jsonEncode(blobs.packets),
        index = jsonEncode(blobs.index);
    var requests = 0;
    Stream<List<int>> remote(
      AttachmentBinding b,
      Attachment a, {
      int start = 0,
      int? end,
    }) async* {
      expect(b.protection, current);
      requests++;
      yield List.of(bytes.sublist(start, end));
    }

    expect(
      await cache
          .readAssociated(bound(current), descriptor, remote)
          .expand((b) => b)
          .toList(),
      bytes,
    );
    expect(requests, 1);
    expect(backing.encoded, before);
    expect(jsonEncode(blobs.packets), packets);
    expect(jsonEncode(blobs.index), index);
    Stream<List<int>> offline(
      AttachmentBinding b,
      Attachment a, {
      int start = 0,
      int? end,
    }) async* {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
    }

    await expectLater(
      cache.readAssociated(bound(current), descriptor, offline).toList(),
      throwsA(isA<NoteSecurityFailure>()),
    );
    expect(jsonEncode(blobs.packets), packets);
  });

  for (final code in [
    NoteSecurityFailureCode.locked,
    NoteSecurityFailureCode.sessionChanged,
    NoteSecurityFailureCode.denied,
    NoteSecurityFailureCode.unavailable,
    NoteSecurityFailureCode.staleRevision,
  ]) {
    test(
      'remote read cannot bypass a cache authority failure: $code',
      () async {
        final bytes = utf8.encode('must remain private'), blobs = MemoryBlobs();
        var allowed = true;
        final cache = EncryptedAttachmentCache(
          actorId: 'owner',
          store: blobs,
          generateId: () => 'unused',
          cipher: AttachmentChunkCipher(
            requireAccess: (_, _) {
              if (!allowed) {
                throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
              }
            },
            resolveKey: (_) async {
              if (code == NoteSecurityFailureCode.staleRevision) {
                allowed = false;
              }
              throw NoteSecurityFailure(code);
            },
          ),
        );
        final descriptor = Attachment(
          id: 'd' * 64,
          noteId: 'alpha',
          fileName: 'private.txt',
          mimeType: 'text/plain',
          sizeBytes: bytes.length,
          storageObjectId: 'final/object',
          objectVersion: 'v1',
          sha256: hash.sha256.convert(bytes).toString(),
          addedAt: DateTime.utc(2026, 10, 6),
        );
        Stream<List<int>> remote(
          AttachmentBinding b,
          Attachment a, {
          int start = 0,
          int? end,
        }) async* {
          yield List.of(bytes.sublist(start, end));
        }

        final delivered = <List<int>>[];
        await expectLater(
          cache
              .readAssociated(
                bound(const NoteProtection.unprotected()),
                descriptor,
                remote,
              )
              .map((b) {
                delivered.add(b);
                return b;
              })
              .toList(),
          throwsA(
            isA<NoteSecurityFailure>().having(
              (e) => e.code,
              'code',
              code == NoteSecurityFailureCode.staleRevision
                  ? NoteSecurityFailureCode.denied
                  : code,
            ),
          ),
        );
        expect(delivered, isEmpty);
        expect(blobs.packets, isEmpty);
      },
    );
  }
}

typedef _CacheCase = ({
  EncryptedSyncStore store,
  MemoryCiphertextStore backing,
  MemoryBlobs blobs,
  EncryptedAttachmentCache cache,
  Attachment descriptor,
  List<int> bytes,
  NoteProtection protection,
});

Attachment _descriptor(String id, List<int> bytes) => Attachment(
  id: id,
  noteId: 'alpha',
  fileName: 'file.txt',
  mimeType: 'text/plain',
  sizeBytes: bytes.length,
  storageObjectId: 'final/immutable',
  objectVersion: 'v1',
  sha256: hash.sha256.convert(bytes).toString(),
  addedAt: DateTime.utc(2026, 10, 6),
);

Future<_CacheCase> _cachedCase() async {
  final backing = MemoryCiphertextStore(), blobs = MemoryBlobs();
  final store = EncryptedSyncStore('owner', backing);
  addTearDown(store.dispose);
  await store.replace(securityState('owner'));
  final protection = await store.enableLocal('alpha', securityPassword);
  final cache = EncryptedAttachmentCache(
    actorId: 'owner',
    store: blobs,
    generateId: () => 'retired-local',
    cipher: AttachmentChunkCipher(
      requireAccess: (_, _) {},
      resolveKey: store.attachmentKey,
    ),
  );
  final bytes = utf8.encode('verified remote contents');
  final draft = await cache.stage(
    bound(protection),
    AttachmentInput(
      fileName: 'file.txt',
      mimeType: 'text/plain',
      sizeBytes: bytes.length,
      openRead: ([start, end]) =>
          Stream.value(List.of(bytes.sublist(start ?? 0, end))),
    ),
    existing: [],
  );
  await cache.markLinked(bound(protection), draft.cacheId);
  return (
    store: store,
    backing: backing,
    blobs: blobs,
    cache: cache,
    descriptor: _descriptor(draft.cacheId, bytes),
    bytes: bytes,
    protection: protection,
  );
}

Future<_CacheCase> _retiredCase() async {
  final c = await _cachedCase();
  final protection = NoteProtection(
    enabled: false,
    revision: c.protection.revision + 1,
  );
  await c.store.observeProtection('alpha', protection);
  await c.store.hydrate(
    SyncNoteSnapshot(
      id: 'alpha',
      ownerId: 'owner',
      title: privateTitle,
      content: privateBody,
      createdAt: fixtureTime,
      serverUpdatedAt: fixtureTime,
      revision: 8,
      protection: protection,
      attachments: [c.descriptor],
      includesAttachments: true,
    ),
  );
  final readable = (await c.store.read()).notes.firstWhere(
    (n) => n.id == 'alpha',
  );
  expect(readable.contentAvailable, true);
  expect(readable.protection, protection);
  return (
    store: c.store,
    backing: c.backing,
    blobs: c.blobs,
    cache: c.cache,
    descriptor: c.descriptor,
    bytes: c.bytes,
    protection: protection,
  );
}
