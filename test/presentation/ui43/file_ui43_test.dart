import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/attachments/attachment_application.dart';
import 'package:note_ai_app/application/attachments/attachment_binding.dart';
import 'package:note_ai_app/application/attachments/attachment_draft_store.dart';
import 'package:note_ai_app/domain/notes/note.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/domain/notes/note_repository.dart';
import 'package:note_ai_app/application/attachments/attachment_input.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/notes/note_security_service.dart';
import 'package:note_ai_app/presentation/notes/attachment_document_controls.dart';
import 'package:note_ai_app/presentation/notes/attachment_editor_controller.dart';
import 'package:note_ai_app/presentation/notes/attachment_editor_panel.dart';
import 'package:note_ai_app/presentation/notes/attachment_file_row.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';

void main() {
  testWidgets('file row keeps Notion-like inline hierarchy in both themes', (
    tester,
  ) async {
    final name = '${List.filled(8, 'Tài liệu ghi chú dài').join(' ')}.pdf';

    for (final theme in [ThemeData.light(), ThemeData.dark()]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 220,
                child: AttachmentFileRow(
                  name: name,
                  mimeType: 'application/pdf',
                  sizeLabel: '123456.0 MiB',
                  statusLabel: 'Ready',
                  onOpen: () {},
                  onRemove: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final nameText = tester.widget<Text>(find.text(name));
      final sizeText = tester.widget<Text>(find.text('123456.0 MiB'));
      final colors = Theme.of(tester.element(find.text(name))).colorScheme;

      expect(find.byType(Card), findsNothing);
      expect(nameText.maxLines, 1);
      expect(sizeText.maxLines, 1);
      expect(sizeText.style?.fontSize, lessThan(nameText.style!.fontSize!));
      expect(sizeText.style?.color, colors.onSurfaceVariant);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.upload_file_outlined)).size,
        18,
      );
      expect(find.text('Ready'), findsNothing);
      expect(find.byTooltip('Ready'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('PDF controls wrap and scroll without shrinking touch targets', (
    tester,
  ) async {
    final changes = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2.2)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 176,
              height: 68,
              child: AttachmentDocumentControls(
                page: 123,
                pages: 456,
                busy: false,
                onPage: changes.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(
      tester
          .getSize(find.widgetWithIcon(IconButton, Icons.chevron_right))
          .width,
      greaterThanOrEqualTo(48),
    );

    final next = find.byTooltip('Next PDF page');
    await tester.ensureVisible(next);
    await tester.pumpAndSettle();
    await tester.tap(next);
    expect(changes, [124]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'native Upload sheet scrolls around the IME and keeps large labels readable',
    (tester) async {
      tester.view
        ..physicalSize = const Size(360, 520)
        ..devicePixelRatio = 1
        ..viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(tester.view.reset);

      final harness = _PickerHarness.create();
      final inline = AttachmentEditorController();
      const placeholder = ValueKey(
        'attachment-inline-placeholder-file-block-1',
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2.2)),
              child: child!,
            ),
            home: Scaffold(
              body: ListView(
                children: [
                  AttachmentEditorPanel(
                    note: harness.note,
                    controller: harness.notes,
                    security: harness.security,
                    enabled: true,
                    inlineController: inline,
                    inlineLayout: true,
                    hiddenOwner: true,
                  ),
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

        final sheetScroll = find.byType(SingleChildScrollView);
        expect(sheetScroll, findsOneWidget);
        expect(find.text('Upload'), findsOneWidget);
        expect(find.text('Choose a file'), findsOneWidget);
        expect(find.text('Record a video'), findsOneWidget);
        expect(
          tester.widget<Text>(find.text('Choose from gallery')).maxLines,
          isNull,
        );
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(find.text('Record a video'));
        await tester.pumpAndSettle();
        final viewport = tester.getRect(sheetScroll);
        final lastOption = tester.getRect(find.text('Record a video'));
        expect(lastOption.top, greaterThanOrEqualTo(viewport.top));
        expect(lastOption.bottom, lessThanOrEqualTo(viewport.bottom));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        inline.dispose();
        await harness.security.events.close();
      }
    },
    skip: kIsWeb,
  );
}

final class _PickerHarness {
  _PickerHarness(this.note, this.security, this.notes);

  final NoteDto note;
  final _TestSecurity security;
  final _TestAttachmentNotes notes;

  factory _PickerHarness.create() {
    final now = DateTime.utc(2026, 10, 26);
    return _PickerHarness(
      NoteDto(
        id: 'ui43-note',
        ownerId: 'owner',
        title: 'UI43 synthetic note',
        content: 'Body',
        createdAt: now,
        updatedAt: now,
      ),
      _TestSecurity(),
      _TestAttachmentNotes(
        AttachmentApplicationService(
          notes: _PickerNoteRepository(
            Note.reconstitute(
              id: 'ui43-note',
              ownerId: 'owner',
              title: 'UI43 synthetic note',
              content: 'Body',
              createdAt: now,
              updatedAt: now,
            ),
          ),
          drafts: _PickerDrafts(),
          captureBinding: (id) async => AttachmentBinding(
            actorId: 'owner',
            note: NoteIdentity('owner', id),
            protection: const NoteProtection.unprotected(),
            accessRevision: 0,
            sessionGeneration: 1,
            contentRevision: 0,
          ),
          requireAccess: (_, _) {},
          upload: (_, _, _) async =>
              throw StateError('This layout test never uploads.'),
          now: () => now,
        ),
      ),
    );
  }
}

final class _TestSecurity implements SecuredNotesController {
  final events = StreamController<void>.broadcast(sync: true);

  @override
  NoteSecurityService? get noteSecurity => null;

  @override
  Stream<void> get securityChanges => events.stream;

  @override
  int get accessGeneration => 0;

  @override
  int get sessionGeneration => 1;

  @override
  bool get securityServerAvailable => false;

  @override
  Future<NoteDto> readNote(String id) async => throw UnimplementedError();

  @override
  NoteAccessCapabilities capabilitiesFor(NoteDto note) =>
      const NoteAccessCapabilities(
        canRead: true,
        canManage: true,
        canExport: true,
      );
}

final class _TestAttachmentNotes implements AttachmentNotesController {
  _TestAttachmentNotes(this.attachments);
  @override
  final AttachmentApplicationService attachments;

  @override
  Future<List<AttachmentInput>> pickAttachments(
    AttachmentSource source,
  ) async => const [];
}

final class _PickerNoteRepository implements INoteRepository {
  _PickerNoteRepository(this.note);
  final Note note;
  @override
  Future<Note?> findById(String id) async => id == note.id ? note : null;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected repository call: ${invocation.memberName}');
}

final class _PickerDrafts implements AttachmentDraftStore {
  @override
  Future<List<String>> pendingIds(AttachmentBinding binding) async => const [];
  @override
  Future<void> recoverIncomplete(AttachmentBinding binding) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected draft call: ${invocation.memberName}');
}
