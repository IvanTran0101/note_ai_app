import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/attachments/attachment_application.dart';
import 'package:note_ai_app/application/attachments/attachment_binding.dart';
import 'package:note_ai_app/application/attachments/attachment_draft_store.dart';
import 'package:note_ai_app/application/attachments/attachment_input.dart';
import 'package:note_ai_app/application/attachments/attachment_transfer.dart';
import 'package:note_ai_app/application/attachments/local_attachment_draft.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';
import 'package:note_ai_app/presentation/notes/attachment_editor_panel.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';

import '../../infrastructure/notes/note_repository_test_support.dart';

const _draft = LocalAttachmentDraft(
  cacheId: 'offline-attempt',
  fileName: 'offline.txt',
  mimeType: 'text/plain',
  sizeBytes: 5,
  sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  chunkCount: 1,
);

final class _PendingDrafts implements AttachmentDraftStore {
  @override
  Future<void> recoverIncomplete(AttachmentBinding binding) async {}
  @override
  Future<List<String>> pendingIds(AttachmentBinding binding) async => [
    _draft.cacheId,
  ];
  @override
  Future<LocalAttachmentDraft> load(
    AttachmentBinding binding,
    String id,
  ) async => _draft;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Controller implements AttachmentNotesController {
  _Controller(this.attachments);
  @override
  final AttachmentApplicationService attachments;
  @override
  Future<List<AttachmentInput>> pickAttachments(
    AttachmentSource source,
  ) async => [];
}

final class _Security implements SecuredNotesController {
  @override
  Stream<void> get securityChanges => const Stream.empty();
  @override
  NoteAccessCapabilities capabilitiesFor(NoteDto note) =>
      const NoteAccessCapabilities(canRead: true, canManage: true);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeLocalSyncStore store;
  late NoteRepository repository;
  late AttachmentApplicationService service;
  var uploads = 0, syncs = 0;
  setUp(() {
    uploads = syncs = 0;
    final time = DateTime.utc(2026, 10, 6);
    store = FakeLocalSyncStore(
      accountUserId: 'owner',
      initial: LocalSyncState(
        accountUserId: 'owner',
        notes: [
          LocalNoteState(
            id: 'note',
            ownerId: 'owner',
            title: 'Offline note',
            content: 'Body',
            createdAt: time,
            updatedAt: time,
            serverRevision: 0,
          ),
        ],
      ),
    );
    repository = NoteRepository(
      currentAccountUserId: () => 'owner',
      localSyncStoreFactory: ({required accountUserId}) => store,
      generateMutationId: () => 'unused',
      now: () => time,
    );
    service = AttachmentApplicationService(
      notes: repository,
      drafts: _PendingDrafts(),
      captureBinding: (id) async => AttachmentBinding(
        actorId: 'owner',
        note: NoteIdentity('owner', id),
        protection: const NoteProtection.unprotected(),
        accessRevision: 0,
        sessionGeneration: 1,
        contentRevision: 0,
      ),
      requireAccess: (_, _) {},
      upload: (_, _, _) async {
        uploads++;
        throw StateError('Must not upload before create ACK.');
      },
      now: () => time,
      requestSync: (_) => syncs++,
    );
  });

  test(
    'Create ACK waiting retains draft and never calls upload or Note writer',
    () async {
      final before = store.state;
      await expectLater(
        service.retry('note', _draft.cacheId),
        throwsA(isA<AttachmentAwaitingNoteSync>()),
      );
      expect(uploads, 0);
      expect(syncs, 1);
      expect(store.state, same(before));
      expect(await service.pending('note'), [_draft]);
    },
  );

  testWidgets('Offline Pending displays sync notice without false file error', (
    tester,
  ) async {
    final domainNote = await tester.runAsync(() => repository.findById('note'));
    final note = NoteDto.fromDomain(domainNote!);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttachmentEditorPanel(
            note: note,
            controller: _Controller(service),
            security: _Security(),
            enabled: true,
          ),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
    }
    await tester.pump();
    expect(find.text('offline.txt'), findsOneWidget);
    expect(find.textContaining('Saved on this device.'), findsOneWidget);
    expect(find.textContaining('Attachment operation failed'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(uploads, 0);
    await tester.tap(find.byTooltip('Retry upload'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Attachment operation failed'), findsNothing);
    expect(store.state.notes.single.attachments, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
