import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/attachments/attachment_input.dart';
import 'package:note_ai_app/infrastructure/attachments/attachment_chunk_cipher.dart';
import 'package:note_ai_app/infrastructure/attachments/attachment_store.dart';
import 'package:note_ai_app/infrastructure/attachments/encrypted_attachment_cache.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';

import '../../security/security_fixtures.dart';

import 'package:note_ai_app/application/attachments/attachment_binding.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';

late String actor;
AttachmentBinding bound(NoteProtection p) => AttachmentBinding(
  actorId: actor,
  note: NoteIdentity(actor, 'alpha'),
  protection: p,
  accessRevision: 0,
  sessionGeneration: 1,
  contentRevision: 7,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    actor = 'm03-indexeddb-${DateTime.now().microsecondsSinceEpoch}';
  });
  test('real IndexedDB encrypted multi-chunk Pending reopens, rotates offline and cancels', () async {
    final backing = MemoryCiphertextStore();
    var store = EncryptedSyncStore(actor, backing);
    addTearDown(() => store.dispose());
    await store.replace(securityState(actor));
    final blobs = createAttachmentBlobStore(actorId: actor);
    var p = const NoteProtection.unprotected();
    final cipher = AttachmentChunkCipher(
      requireAccess: (_, _) {},
      resolveKey: (b) => store.attachmentKey(b),
    );
    EncryptedAttachmentCache cache() => EncryptedAttachmentCache(
      actorId: actor,
      store: blobs,
      cipher: cipher,
      generateId: () => 'indexeddb-${DateTime.now().microsecondsSinceEpoch}',
    );
    final bytes = utf8.encode('PRIVATE-CACHE-' * 25000);
    var active = cache();
    final draft = await active.stage(
      bound(p),
      AttachmentInput(
        fileName: 'private.txt',
        mimeType: 'text/plain',
        sizeBytes: bytes.length,
        openRead: ([a, b]) => Stream.value(bytes.sublist(a ?? 0, b)),
      ),
      existing: [],
    );
    expect(draft.chunkCount, 2);
    expect(
      jsonEncode(await blobs.readChunk('${draft.cacheId}-meta')),
      isNot(contains('private.txt')),
    );
    expect(
      jsonEncode(await blobs.readChunk('${draft.cacheId}-000')),
      isNot(contains('PRIVATE-CACHE')),
    );
    store.beforeAttachmentProtectionChange = (_) =>
        active.upgradeLegacyPackets(bound(p));
    p = await store.enableLocal('alpha', securityPassword);
    p = await store.changeLocal(
      'alpha',
      securityPassword,
      '$securityPassword-next',
    );
    store.dispose();
    store = EncryptedSyncStore(actor, backing);
    await store.unlock('alpha', '$securityPassword-next', p);
    active = EncryptedAttachmentCache(
      actorId: actor,
      store: createAttachmentBlobStore(actorId: actor),
      cipher: cipher,
      generateId: () => 'unused',
    );
    expect(
      (await active.load(bound(p), draft.cacheId)).fileName,
      'private.txt',
    );
    expect(await active.read(bound(p), draft).expand((b) => b).toList(), bytes);
    await active.cancelLocal(bound(p), draft.cacheId);
    expect(await blobs.readChunk('${draft.cacheId}-000'), isNull);
    expect(await blobs.readChunk('${draft.cacheId}-meta'), isNull);
    expect(await active.pendingIds(bound(p)), isEmpty);
  }, skip: !kIsWeb);

  test('real IndexedDB two cache instances commit reservations without overwriting each other', () async {
    final backing = MemoryCiphertextStore();
    final keys = EncryptedSyncStore(actor, backing);
    addTearDown(keys.dispose);
    await keys.replace(securityState(actor));
    final cipher = AttachmentChunkCipher(
      requireAccess: (_, _) {},
      resolveKey: keys.attachmentKey,
    );
    EncryptedAttachmentCache cache(String id) => EncryptedAttachmentCache(
      actorId: actor,
      store: createAttachmentBlobStore(actorId: actor),
      cipher: cipher,
      generateId: () => id,
    );
    final a = cache('concurrent-a'), b = cache('concurrent-b');
    AttachmentInput input() => AttachmentInput(
      fileName: 'file.txt',
      mimeType: 'text/plain',
      sizeBytes: 3,
      openRead: ([a, b]) => Stream.value([65, 66, 67].sublist(a ?? 0, b)),
    );
    final binding = bound(const NoteProtection.unprotected());
    final drafts = await Future.wait([
      a.stage(binding, input(), existing: []),
      b.stage(binding, input(), existing: []),
    ]);
    expect(
      (await a.pendingIds(binding)).toSet(),
      drafts.map((d) => d.cacheId).toSet(),
    );
    for (final draft in drafts) {
      await a.cancelLocal(binding, draft.cacheId);
    }
  }, skip: !kIsWeb);
}
