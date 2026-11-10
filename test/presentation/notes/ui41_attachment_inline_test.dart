import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/attachments/attachment_application.dart';
import 'package:note_ai_app/application/attachments/attachment_binding.dart';
import 'package:note_ai_app/application/attachments/attachment_draft_store.dart';
import 'package:note_ai_app/application/attachments/attachment_input.dart';
import 'package:note_ai_app/application/attachments/local_attachment_draft.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/notes/note_security_service.dart';
import 'package:note_ai_app/domain/notes/attachment.dart';
import 'package:note_ai_app/domain/notes/note.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/domain/notes/note_repository.dart';
import 'package:note_ai_app/presentation/notes/attachment_editor_controller.dart';
import 'package:note_ai_app/presentation/notes/attachment_editor_panel.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';

final _now = DateTime.utc(2026, 10, 23);

void main() {
  group('UI41 attachment inline bridge', () {
    testWidgets(
      'hidden panel owner supplies its File placeholder and revoke hides it',
      (tester) async {
        final harness = _PanelHarness.create();
        final inline = AttachmentEditorController();
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ListView(
                  children: [
                    _hiddenOwner(harness, inline, inlineLayout: true),
                    ListenableBuilder(
                      listenable: inline,
                      builder: (context, _) =>
                          inline.buildBlock(context, 'file-block-1', null),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Upload a file'), findsOneWidget);
          expect(find.text('Add attachment'), findsNothing);

          harness.security.allowed = false;
          harness.security.events.add(null);
          await tester.pumpAndSettle();

          expect(find.text('Upload a file'), findsNothing);
          expect(find.text('File'), findsNothing);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          inline.dispose();
          await harness.security.events.close();
        }
      },
    );

    testWidgets(
      'native Upload chooser cancels, reopens, and preserves the empty block',
      (tester) async {
        final harness = _PanelHarness.create();
        final inline = AttachmentEditorController();
        const placeholder = ValueKey(
          'attachment-inline-placeholder-file-block-1',
        );
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ListView(
                  children: [
                    _hiddenOwner(harness, inline, inlineLayout: true),
                    ListenableBuilder(
                      listenable: inline,
                      builder: (context, _) =>
                          inline.buildBlock(context, 'file-block-1', null),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(placeholder));
          await tester.pumpAndSettle();
          expect(find.text('Upload'), findsOneWidget);
          expect(find.text('Choose a file'), findsOneWidget);

          // The native sheet has no dedicated Cancel row; tapping its barrier
          // follows the platform's standard dismiss behavior.
          await tester.tapAt(const Offset(4, 4));
          await tester.pumpAndSettle();
          expect(find.byKey(placeholder), findsOneWidget);
          expect(find.text('Upload'), findsNothing);

          await tester.tap(find.byKey(placeholder));
          await tester.pumpAndSettle();
          expect(find.text('Choose a file'), findsOneWidget);
          await tester.tap(find.text('Choose a file'));
          await tester.pumpAndSettle();

          expect(harness.notes.pickedSources, [AttachmentSource.files]);
          expect(find.byKey(placeholder), findsOneWidget);
          expect(find.text('Upload'), findsNothing);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          inline.dispose();
          await harness.security.events.close();
        }
      },
    );

    testWidgets('legacy panel exposes no separate Add attachment footer', (
      tester,
    ) async {
      final harness = _PanelHarness.create();
      final inline = AttachmentEditorController();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  _hiddenOwner(harness, inline, inlineLayout: false),
                  ListenableBuilder(
                    listenable: inline,
                    builder: (context, _) => inline.buildLegacy(context),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Add attachment'), findsNothing);
        expect(find.text('Upload a file'), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        inline.dispose();
        await harness.security.events.close();
      }
    });

    testWidgets(
      'controller defers refresh and drops picker anchors on unbind',
      (tester) async {
        final inline = AttachmentEditorController();
        final owner = Object();
        var notifications = 0;
        var pickerCalls = 0;
        inline.addListener(() => notifications++);
        inline.bind(
          owner: owner,
          buildBlock: (context, blockId, attachmentId) => Text(
            'Synthetic file block $blockId',
            key: ValueKey('synthetic-$blockId'),
          ),
          buildLegacy: (context) => const Text('Synthetic legacy attachments'),
          openPicker: (context, blockId) async {
            expect(context.mounted, isTrue);
            expect(blockId, 'synthetic-block');
            pickerCalls++;
          },
          readAttachmentIds: () => const ['legacy-id'],
        );

        expect(notifications, 0, reason: 'bind must not notify synchronously');
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ListenableBuilder(
                  listenable: inline,
                  builder: (context, _) =>
                      inline.buildBlock(context, 'synthetic-block', null),
                ),
              ),
            ),
          );
          await tester.pump();

          expect(notifications, greaterThan(0));
          expect(
            find.text('Synthetic file block synthetic-block'),
            findsOneWidget,
          );
          expect(inline.attachmentIds, ['legacy-id']);

          await inline.openPicker('synthetic-block');
          expect(pickerCalls, 1);

          inline.unbind(owner);
          await tester.pumpAndSettle();
          expect(
            find.text('Synthetic file block synthetic-block'),
            findsNothing,
          );
          await inline.openPicker('synthetic-block');
          expect(pickerCalls, 1);

          await tester.pumpWidget(const SizedBox.shrink());
          await inline.openPicker('synthetic-block');
          expect(pickerCalls, 1);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          inline.dispose();
        }
      },
    );
  });
}

Widget _hiddenOwner(
  _PanelHarness harness,
  AttachmentEditorController inline, {
  required bool inlineLayout,
}) => AttachmentEditorPanel(
  note: harness.note,
  controller: harness.notes,
  security: harness.security,
  enabled: true,
  inlineController: inline,
  inlineLayout: inlineLayout,
  hiddenOwner: true,
);

final class _PanelHarness {
  _PanelHarness(this.note, this.security, this.notes);

  final NoteDto note;
  final _TestSecurity security;
  final _TestAttachmentNotes notes;

  factory _PanelHarness.create() {
    final domainNote = Note.reconstitute(
      id: 'note',
      ownerId: 'owner',
      title: 'Title',
      content: 'Body',
      createdAt: _now,
      updatedAt: _now,
    );
    final note = NoteDto(
      id: 'note',
      ownerId: 'owner',
      title: 'Title',
      content: 'Body',
      createdAt: _now,
      updatedAt: _now,
    );
    final service = AttachmentApplicationService(
      notes: _TestNoteRepository(domainNote),
      drafts: _EmptyDraftStore(),
      captureBinding: (noteId) async => AttachmentBinding(
        actorId: 'owner',
        note: NoteIdentity('owner', noteId),
        protection: const NoteProtection.unprotected(),
        accessRevision: 0,
        sessionGeneration: 1,
        contentRevision: 0,
      ),
      requireAccess: (_, _) {},
      upload: (_, _, _) async => throw UnimplementedError(),
      now: () => _now,
    );
    return _PanelHarness(note, _TestSecurity(), _TestAttachmentNotes(service));
  }
}

final class _TestSecurity implements SecuredNotesController {
  final events = StreamController<void>.broadcast(sync: true);
  bool allowed = true;

  @override
  NoteSecurityService? get noteSecurity => null;

  @override
  Stream<void> get securityChanges => events.stream;

  @override
  int get accessGeneration => allowed ? 0 : 1;

  @override
  int get sessionGeneration => 1;

  @override
  bool get securityServerAvailable => false;

  @override
  Future<NoteDto> readNote(String id) async => throw UnimplementedError();

  @override
  NoteAccessCapabilities capabilitiesFor(NoteDto note) =>
      NoteAccessCapabilities(
        canRead: allowed,
        canManage: allowed,
        canExport: allowed,
      );
}

final class _TestAttachmentNotes implements AttachmentNotesController {
  _TestAttachmentNotes(this.attachments);

  @override
  final AttachmentApplicationService attachments;
  final pickedSources = <AttachmentSource>[];

  @override
  Future<List<AttachmentInput>> pickAttachments(AttachmentSource source) async {
    pickedSources.add(source);
    return const [];
  }
}

final class _TestNoteRepository implements INoteRepository {
  _TestNoteRepository(this.note);
  final Note note;

  @override
  Future<Note?> findById(String id) async => id == note.id ? note : null;

  @override
  Future<List<Note>> findByOwnerId(String ownerId) async =>
      ownerId == note.ownerId ? [note] : const [];

  @override
  Future<void> save(Note value) async => throw UnimplementedError();

  @override
  Future<Note> updateById({
    required String noteId,
    required String ownerId,
    required String expectedAccountUserId,
    required NoteChange change,
    required NoteCommitFence canCommit,
  }) async => throw UnimplementedError();

  @override
  Future<void> deleteById(String id) async => throw UnimplementedError();
}

final class _EmptyDraftStore implements AttachmentDraftStore {
  @override
  Future<LocalAttachmentDraft> stage(
    AttachmentBinding binding,
    AttachmentInput input, {
    required Iterable<Attachment> existing,
  }) async => throw UnimplementedError();

  @override
  Future<List<String>> pendingIds(AttachmentBinding binding) async => const [];

  @override
  Future<void> recoverIncomplete(AttachmentBinding binding) async {}

  @override
  Future<LocalAttachmentDraft> load(
    AttachmentBinding binding,
    String id,
  ) async => throw UnimplementedError();

  @override
  Stream<List<int>> read(
    AttachmentBinding binding,
    LocalAttachmentDraft draft, {
    int start = 0,
    int? end,
  }) => const Stream.empty();

  @override
  Future<void> markLinked(AttachmentBinding binding, String id) async {}

  @override
  Future<void> cancelLocal(AttachmentBinding binding, String id) async {}
}
