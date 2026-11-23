import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/attachments/attachment_application.dart';
import 'package:note_ai_app/application/attachments/attachment_input.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/domain/notes/attachment.dart';
import 'package:note_ai_app/infrastructure/attachments/attachment_chunk_cipher.dart';
import 'package:note_ai_app/infrastructure/attachments/encrypted_attachment_cache.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';
import 'package:note_ai_app/infrastructure/security/note_crypto.dart';

import '../../infrastructure/notes/note_repository_test_support.dart';
import 'attachment_transfer_test.dart' show MemoryBlobs, binding;

void main() {
  late MemoryBlobs blobs;
  late EncryptedAttachmentCache cache;
  late FakeLocalSyncStore store;
  late NoteRepository notes;
  late AttachmentApplicationService service;
  late Attachment descriptor;
  var cancelCalls = 0, associated = false, failCancel = true;
  Completer<void>? network;
  final time = DateTime.utc(2026, 10, 5);
  setUp(() async {
    cancelCalls = 0;
    associated = false;
    failCancel = true;
    network = null;
    final key = await NoteCrypto().newKey();
    addTearDown(key.destroy);
    blobs = MemoryBlobs();
    cache = EncryptedAttachmentCache(
      actorId: 'owner',
      store: blobs,
      cipher: AttachmentChunkCipher(
        requireAccess: (_, _) {},
        resolveKey: (_) async => key,
      ),
      generateId: () => 'durable-removal',
    );
    store = FakeLocalSyncStore(
      accountUserId: 'owner',
      initial: LocalSyncState(
        accountUserId: 'owner',
        notes: [
          LocalNoteState(
            id: 'note',
            ownerId: 'owner',
            title: 'Preserved title',
            content: 'Preserved body',
            createdAt: time,
            updatedAt: time,
            pinnedAt: time,
            serverRevision: 1,
          ),
        ],
      ),
    );
    var mutation = 0;
    notes = NoteRepository(
      currentAccountUserId: () => 'owner',
      localSyncStoreFactory: ({required accountUserId}) => store,
      generateMutationId: () => 'remove-${++mutation}',
      now: () => time,
    );
    service = AttachmentApplicationService(
      notes: notes,
      drafts: cache,
      captureBinding: (_) async => binding(),
      requireAccess: (_, _) {},
      now: () => time,
      isAssociated: (_, _) async => associated,
      remoteCancel: (_, _) async {
        cancelCalls++;
        if (network != null) await network!.future;
        if (failCancel) throw StateError('offline or waiting for unlink ACK');
      },
      upload: (b, d, openRead) async => descriptor = Attachment(
        id: d.cacheId,
        noteId: 'note',
        fileName: d.fileName,
        mimeType: d.mimeType,
        sizeBytes: d.sizeBytes,
        sha256: d.sha256,
        storageObjectId: 'immutable',
        objectVersion: 'v1',
        addedAt: time,
      ),
    );
    final data = utf8.encode('local-first removal');
    final draft = await service.stage(
      'note',
      AttachmentInput(
        fileName: 'removal.txt',
        mimeType: 'text/plain',
        sizeBytes: data.length,
        openRead: ([start, end]) => Stream.value(data.sublist(start ?? 0, end)),
      ),
    );
    await service.retry('note', draft.cacheId);
  });
  Future<void> drain() async {
    for (var i = 0; i < 25; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  test('remove before association ACK never resurrects Pending; cloud retry is background', () async {
    network = Completer<void>();
    final removed = await service.remove('note', descriptor.id);
    expect(removed.attachments, isEmpty);
    expect(removed.title, 'Preserved title');
    expect(removed.pinnedAt, time);
    expect(blobs.packets, isEmpty);
    expect((blobs.index[descriptor.id] as Map)['phase'], 'remoteCancelled');
    expect(
      await service.pending('note').timeout(const Duration(seconds: 1)),
      isEmpty,
    );
    expect(store.state.outbox.last.payload!.attachments, isEmpty);
    expect(store.state.outbox.last.payload!.content, 'Preserved body');
    network!.complete();
    await drain();
    failCancel = false;
    network = null;
    await service.pending('note');
    await drain();
    expect(blobs.index, isEmpty);
    expect(cancelCalls, greaterThanOrEqualTo(2));
  });
  test('failed Note writer keeps durable removal intent and ciphertext; reopen recovers same removal', () async {
    store.failure = StateError('failed canonical CAS');
    await expectLater(service.remove('note', descriptor.id), throwsStateError);
    expect(store.state.notes.single.attachments, [descriptor]);
    expect(await cache.removalIds(binding()), [descriptor.id]);
    expect(blobs.packets, isNotEmpty);
    await expectLater(cache.load(binding(), descriptor.id), throwsStateError);
    expect(cancelCalls, 0);
    store.failure = null;
    expect(await service.pending('note'), isEmpty);
    await drain();
    expect(store.state.notes.single.attachments, isEmpty);
    expect(blobs.packets, isEmpty);
    expect(await cache.cancellationIds(binding()), [descriptor.id]);
  });
  test('crash after persisted intent resumes via one canonical writer without extra upload', () async {
    await cache.prepareRemoval(binding(), descriptor);
    expect(await service.pending('note'), isEmpty);
    await drain();
    expect(store.state.notes.single.attachments, isEmpty);
    expect(blobs.packets, isEmpty);
    expect(store.state.outbox, hasLength(1));
  });
  test('explicit cloud restore retains authoritative object and clears cancellation intent', () async {
    await service.remove('note', descriptor.id);
    await drain();
    await notes.updateById(
      noteId: 'note',
      ownerId: 'owner',
      expectedAccountUserId: 'owner',
      canCommit: () => true,
      change: (fresh) => fresh..addAttachment(descriptor, time),
    );
    associated = true;
    final calls = cancelCalls;
    await service.pending('note');
    await drain();
    expect(store.state.notes.single.attachments, [descriptor]);
    expect(blobs.index, isEmpty);
    expect(cancelCalls, calls);
  });
}
