import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/attachments/attachment_application.dart';
import 'package:note_ai_app/application/attachments/attachment_binding.dart';
import 'package:note_ai_app/application/attachments/attachment_draft_store.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';

import '../../infrastructure/notes/note_repository_test_support.dart';

final class _Drafts implements AttachmentDraftStore {
  int cancelCalls = 0;
  Object? failure;
  final events = <String>[];

  @override
  Future<void> cancelLocal(AttachmentBinding binding, String id) async {
    cancelCalls++;
    events.add('cleanup');
    final error = failure;
    if (error != null) throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final now = DateTime.utc(2026, 10, 23, 10);
  final document = NoteDocument([
    DocumentBlock(
      id: 'toggle',
      kind: DocumentBlockKind.toggle,
      children: [
        DocumentBlock(
          id: 'pending-copy-1',
          kind: DocumentBlockKind.attachment,
          attachmentId: 'pending-file',
        ),
        DocumentBlock(
          id: 'inside-text',
          kind: DocumentBlockKind.paragraph,
          runs: const [DocumentText('keep this text')],
        ),
        DocumentBlock(
          id: 'pending-copy-2',
          kind: DocumentBlockKind.attachment,
          attachmentId: 'pending-file',
        ),
      ],
    ),
    DocumentBlock(
      id: 'other-file',
      kind: DocumentBlockKind.attachment,
      attachmentId: 'other-pending-file',
    ),
  ], inlineAttachments: true);

  late FakeLocalSyncStore store;
  late NoteRepository notes;
  late _Drafts drafts;
  late AttachmentApplicationService service;
  var syncRequests = 0;

  setUp(() {
    syncRequests = 0;
    store = FakeLocalSyncStore(
      accountUserId: 'owner',
      initial: LocalSyncState(
        accountUserId: 'owner',
        notes: [
          LocalNoteState(
            id: 'note',
            ownerId: 'owner',
            title: 'Attachment note',
            content: document.plainText,
            document: document,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      ),
    );
    notes = NoteRepository(
      currentAccountUserId: () => 'owner',
      localSyncStoreFactory: ({required accountUserId}) => store,
      generateMutationId: () => 'ui42-remove-${store.replaceCount}',
      now: () => now,
    );
    drafts = _Drafts();
    service = AttachmentApplicationService(
      notes: notes,
      drafts: drafts,
      captureBinding: (noteId) async => AttachmentBinding(
        actorId: 'owner',
        note: NoteIdentity('owner', noteId),
        protection: const NoteProtection.unprotected(),
        accessRevision: 0,
        sessionGeneration: 1,
        contentRevision: 0,
      ),
      requireAccess: (_, _) {},
      upload: (_, _, _) async => throw StateError('No upload expected.'),
      now: () => now,
      requestSync: (_) => syncRequests++,
    );
  });

  test('pending cancel removes all document refs through one Note writer', () async {
    final removed = await service.cancel('note', 'pending-file');
    final expected = NoteDocument([
      DocumentBlock(
        id: 'toggle',
        kind: DocumentBlockKind.toggle,
        children: [
          DocumentBlock(
            id: 'inside-text',
            kind: DocumentBlockKind.paragraph,
            runs: const [DocumentText('keep this text')],
          ),
        ],
      ),
      DocumentBlock(
        id: 'other-file',
        kind: DocumentBlockKind.attachment,
        attachmentId: 'other-pending-file',
      ),
    ], inlineAttachments: true);

    expect(removed.document, expected);
    expect(removed.document!.referencesAttachment('pending-file'), false);
    expect(removed.document!.referencesAttachment('other-pending-file'), true);
    expect(store.state.notes.single.document, expected);
    expect(store.state.notes.single.content, expected.plainText);
    expect(store.state.outbox, hasLength(1));
    expect(store.state.outbox.single.payload!.document, expected);
    expect(store.state.outbox.single.payload!.attachments, isEmpty);
    expect(drafts.cancelCalls, 1);
    expect(syncRequests, 1);
  });

  test(
    'canonical writer failure preserves pending File blocks and draft bytes',
    () async {
      store.failure = StateError('local Note write failed');
      var committed = false;

      await expectLater(
        service.cancel(
          'note',
          'pending-file',
          onCommitted: (_) => committed = true,
        ),
        throwsA(isA<StateError>()),
      );

      expect(committed, false);
      expect(store.state.notes.single.document, document);
      expect(
        store.state.notes.single.document!.referencesAttachment(
          'pending-file',
        ),
        true,
      );
      expect(drafts.cancelCalls, 0);
      expect(syncRequests, 0);
    },
  );

  test('explicit removal also repairs refs without a manifest entry', () async {
    final removed = await service.remove('note', 'pending-file');

    expect(removed.document!.referencesAttachment('pending-file'), false);
    expect(removed.document!.referencesAttachment('other-pending-file'), true);
    expect(store.state.outbox, hasLength(1));
    expect(store.state.outbox.single.payload!.document, removed.document);
    expect(syncRequests, 1);
  });

  test('post-commit cache failure returns the canonical updated Note', () async {
    drafts.failure = StateError('cache cleanup failed');
    final events = drafts.events;

    await expectLater(
      service.cancel(
        'note',
        'pending-file',
        onCommitted: (note) {
          events.add('committed');
          expect(
            note.document!.referencesAttachment('pending-file'),
            false,
          );
        },
      ),
      throwsA(
        isA<AttachmentRemovalCleanupFailure>().having(
          (failure) => failure.note.document!.referencesAttachment(
            'pending-file',
          ),
          'removed pending File reference',
          isFalse,
        ),
      ),
    );

    expect(
      store.state.notes.single.document!.referencesAttachment('pending-file'),
      false,
    );
    expect(store.state.outbox, hasLength(1));
    expect(drafts.cancelCalls, 1);
    expect(syncRequests, 1);
    expect(events, ['committed', 'cleanup']);
  });
}
