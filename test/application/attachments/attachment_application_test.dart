import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/attachments/attachment_application.dart';
import 'package:note_ai_app/application/attachments/attachment_binding.dart';
import 'package:note_ai_app/application/attachments/attachment_draft_store.dart';
import 'package:note_ai_app/application/attachments/attachment_input.dart';
import 'package:note_ai_app/application/attachments/local_attachment_draft.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/domain/notes/attachment.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';

import '../../infrastructure/notes/note_repository_test_support.dart';

final time = DateTime.utc(2026, 10, 4);
const draft = LocalAttachmentDraft(
  cacheId: 'attempt',
  fileName: 'hello.txt',
  mimeType: 'text/plain',
  sizeBytes: 5,
  sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  chunkCount: 1,
);

Attachment verified({String? checksum}) => Attachment(
  id: draft.cacheId,
  noteId: 'note',
  fileName: draft.fileName,
  mimeType: draft.mimeType,
  sizeBytes: draft.sizeBytes,
  storageObjectId: 'object',
  objectVersion: 'v1',
  sha256: checksum ?? draft.sha256,
  addedAt: time,
);

final class _Drafts implements AttachmentDraftStore {
  bool queued = false, linked = false, failLink = false;
  @override
  Future<void> recoverIncomplete(AttachmentBinding binding) async {}
  @override
  Future<LocalAttachmentDraft> stage(
    AttachmentBinding binding,
    AttachmentInput input, {
    required Iterable<Attachment> existing,
  }) async {
    queued = true;
    return draft;
  }

  @override
  Future<List<String>> pendingIds(AttachmentBinding binding) async =>
      queued ? [draft.cacheId] : [];
  @override
  Future<LocalAttachmentDraft> load(
    AttachmentBinding binding,
    String id,
  ) async {
    if (id != draft.cacheId || (!queued && !linked)) {
      throw StateError('missing');
    }
    return draft;
  }

  @override
  Stream<List<int>> read(
    AttachmentBinding binding,
    LocalAttachmentDraft value, {
    int start = 0,
    int? end,
  }) => Stream.value([104, 101, 108, 108, 111]);
  @override
  Future<void> markLinked(AttachmentBinding binding, String id) async {
    if (failLink) throw StateError('disk failure');
    linked = true;
    queued = false;
  }

  @override
  Future<void> cancelLocal(AttachmentBinding binding, String id) async {
    queued = false;
  }
}

void main() {
  late FakeLocalSyncStore store;
  late NoteRepository repository;
  late _Drafts drafts;
  late AttachmentApplicationService service;
  var actor = 'owner', allowed = true, uploads = 0, syncs = 0;
  late UploadAttachment transport;
  setUp(() {
    actor = 'owner';
    allowed = true;
    uploads = 0;
    syncs = 0;
    store = FakeLocalSyncStore(
      accountUserId: 'owner',
      initial: LocalSyncState(
        accountUserId: 'owner',
        notes: [
          LocalNoteState(
            id: 'note',
            ownerId: 'owner',
            title: 'Title',
            content: 'Body',
            createdAt: time,
            updatedAt: time,
            pinnedAt: time,
            serverRevision: 1,
          ),
        ],
      ),
    );
    var mutation = 0;
    repository = NoteRepository(
      currentAccountUserId: () => 'owner',
      localSyncStoreFactory: ({required accountUserId}) => store,
      generateMutationId: () => 'mutation-${++mutation}',
      now: () => time,
    );
    drafts = _Drafts();
    transport = (binding, file, openRead) async {
      uploads++;
      expect(drafts.queued, isTrue);
      expect(await openRead().expand((bytes) => bytes).toList(), [
        104,
        101,
        108,
        108,
        111,
      ]);
      return verified();
    };
    service = AttachmentApplicationService(
      notes: repository,
      drafts: drafts,
      captureBinding: (id) async => AttachmentBinding(
        actorId: actor,
        note: NoteIdentity('owner', id),
        protection: const NoteProtection.unprotected(),
        accessRevision: 1,
        sessionGeneration: 1,
        contentRevision: 1,
      ),
      requireAccess: (binding, operation) {
        if (!allowed) throw StateError('locked/session changed');
      },
      upload: (binding, file, openRead) => transport(binding, file, openRead),
      now: () => time,
      requestSync: (_) => syncs++,
    );
  });
  Future<void> stage() async {
    await service.stage(
      'note',
      AttachmentInput(
        fileName: 'hello.txt',
        mimeType: 'text/plain',
        sizeBytes: 5,
        openRead: ([start, end]) => Stream.value([1]),
      ),
    );
  }

  test(
    'stage is local-first; upload uses the fresh M02 atomic writer',
    () async {
      await stage();
      expect(uploads, 0);
      expect(store.state.outbox, isEmpty);
      expect(await service.pending('note'), [draft]);
      await repository.updateById(
        noteId: 'note',
        ownerId: 'owner',
        canCommit: () => true,
        expectedAccountUserId: 'owner',
        change: (note) {
          note.replaceText('New text', 'New body', time);
          return note;
        },
      );
      final result = await service.retry('note', draft.cacheId);
      expect(result.title, 'New text');
      expect(result.content, 'New body');
      expect(result.pinnedAt, time);
      expect(result.attachments, [verified()]);
      expect(store.state.outbox.last.payload!.attachments, [verified()]);
      expect(syncs, 1);
      expect(drafts.linked, isTrue);
      expect(await service.pending('note'), isEmpty);
    },
  );

  test(
    'network failure preserves the queued draft and never changes the note',
    () async {
      await stage();
      transport = (_, _, _) async => throw StateError('offline');
      await expectLater(service.retry('note', draft.cacheId), throwsStateError);
      expect(drafts.queued, isTrue);
      expect(store.state.notes.single.attachments, isEmpty);
      expect(store.state.outbox, isEmpty);
    },
  );

  test('server descriptor mismatch cannot enter the aggregate', () async {
    await stage();
    transport = (_, _, _) async => verified(checksum: 'b' * 64);
    await expectLater(service.retry('note', draft.cacheId), throwsStateError);
    expect(store.state.notes.single.attachments, isEmpty);
    expect(drafts.queued, isTrue);
  });

  test('lock while upload is in flight prevents note commit', () async {
    await stage();
    transport = (_, _, _) async {
      allowed = false;
      return verified();
    };
    await expectLater(service.retry('note', draft.cacheId), throwsStateError);
    expect(store.state.notes.single.attachments, isEmpty);
    expect(drafts.queued, isTrue);
  });

  test(
    'retry recovers a committed note after cache checkpoint failure',
    () async {
      await stage();
      drafts.failLink = true;
      await expectLater(service.retry('note', draft.cacheId), throwsStateError);
      expect(store.state.notes.single.attachments, [verified()]);
      final count = store.state.outbox.length;
      drafts.failLink = false;
      await service.retry('note', draft.cacheId);
      expect(uploads, 1);
      expect(store.state.outbox.length, count);
      expect(drafts.linked, isTrue);
    },
  );

  test('duplicate concurrent retries share one upload', () async {
    await stage();
    final gate = Completer<Attachment>();
    final started = Completer<void>();
    transport = (_, _, _) {
      uploads++;
      started.complete();
      return gate.future;
    };
    final first = service.retry('note', draft.cacheId);
    await started.future;
    final second = service.retry('note', draft.cacheId);
    gate.complete(verified());
    final results = await Future.wait([first, second]);
    expect(results.first, results.last);
    expect(uploads, 1);
    expect(store.state.notes.single.attachments, hasLength(1));
  });

  test('cancellation during upload fences its eventual response', () async {
    await stage();
    final gate = Completer<Attachment>();
    final started = Completer<void>();
    transport = (_, _, _) {
      started.complete();
      return gate.future;
    };
    final work = service.retry('note', draft.cacheId);
    await started.future;
    await service.cancel('note', draft.cacheId);
    gate.complete(verified());
    await expectLater(work, throwsStateError);
    expect(store.state.notes.single.attachments, isEmpty);
    expect(drafts.queued, isFalse);
  });

  test(
    'viewer/editor cannot add/remove, and linked cancellation is rejected',
    () async {
      actor = 'recipient';
      await expectLater(stage(), throwsStateError);
      await expectLater(service.remove('note', 'anything'), throwsStateError);
      actor = 'owner';
      await stage();
      await service.retry('note', draft.cacheId);
      await expectLater(
        service.cancel('note', draft.cacheId),
        throwsStateError,
      );
      final result = await service.remove('note', draft.cacheId);
      expect(result.attachments, isEmpty);
      expect(result.title, 'Title');
      expect(result.pinnedAt, time);
      expect(store.state.outbox.last.payload!.attachments, isEmpty);
      expect(store.state.outbox.last.payload!.includesAttachments, isTrue);
    },
  );
}
