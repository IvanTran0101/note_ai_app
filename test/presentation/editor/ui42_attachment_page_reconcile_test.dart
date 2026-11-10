import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/attachments/attachment_application.dart';
import 'package:note_ai_app/application/attachments/attachment_input.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/rich_note_editor.dart';
import 'package:note_ai_app/presentation/notes/attachment_editor_panel.dart';
import 'package:note_ai_app/presentation/notes/note_detail_localizations.dart';
import 'package:note_ai_app/presentation/notes/note_detail_page.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';
import 'package:note_ai_app/presentation/notes/notes_localizations.dart';

import 'note_detail_test_controller.dart';

final class _Controller
    implements
        NotesApplicationController,
        DocumentNotesController,
        AttachmentNotesController {
  final delegate = RichTestNotesController();
  @override
  AttachmentApplicationService? get attachments => null;
  @override
  get summaryConsent => null;
  @override
  Future<List<AttachmentInput>> pickAttachments(
    AttachmentSource source,
  ) async => [];
  @override
  Future<NoteDto> saveDocumentSnapshot(
    NoteDto selected,
    String title,
    NoteDocument document,
  ) => delegate.saveDocumentSnapshot(selected, title, document);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('ordered File ACKs block autosave and retain newer text draft', (
    tester,
  ) async {
    final before = NoteDocument([
      DocumentBlock(
        id: 'file',
        kind: DocumentBlockKind.attachment,
        attachmentId: 'pending-file',
      ),
      DocumentBlock(
        id: 'tail',
        kind: DocumentBlockKind.paragraph,
        runs: const [DocumentText('Before')],
      ),
      DocumentBlock(
        id: 'second-file',
        kind: DocumentBlockKind.attachment,
        attachmentId: 'second-pending-file',
      ),
    ], inlineAttachments: true);
    NoteDto note(NoteDocument document) => NoteDto(
      id: 'note',
      ownerId: 'owner',
      title: 'UI42',
      content: document.plainText,
      document: document,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026, 10, 24),
    );
    final controller = _Controller();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          NotesCopy.delegate,
          NoteDetailCopy.delegate,
          engine.AppFlowyEditorLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: NoteDetailPage(notesController: controller, note: note(before)),
      ),
    );
    await tester.pumpAndSettle();
    final adapter = tester
        .widget<RichNoteEditor>(find.byType(RichNoteEditor))
        .adapter;
    final node = adapter.editor.getNodeAtPath([1])!;
    final edit = adapter.editor.transaction
      ..insertText(node, 6, ' newer draft');
    await adapter.editor.apply(edit);
    await tester.pump();
    final panel = tester.widget<AttachmentEditorPanel>(
      find.byType(AttachmentEditorPanel),
    );
    panel.onChanged!(note(before.removeAttachmentReferences(['pending-file'])));
    final state = tester.state<NoteDetailPageState>(
      find.byType(NoteDetailPage),
    );
    expect(
      state.hasActiveOperation,
      true,
      reason: 'canonical ACK fences stale autosave synchronously',
    );
    panel.onChanged!(
      note(
        before.removeAttachmentReferences([
          'pending-file',
          'second-pending-file',
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(adapter.document!.referencesAttachment('pending-file'), false);
    expect(adapter.document!.attachmentReferenceIds, isEmpty);
    expect(adapter.document!.plainText, 'Before newer draft');
    expect(state.hasActiveOperation, false);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(
      controller.delegate.last!.document!.referencesAttachment('pending-file'),
      false,
    );
    expect(controller.delegate.last!.document!.attachmentReferenceIds, isEmpty);
    expect(controller.delegate.last!.document!.plainText, 'Before newer draft');
    expect(find.textContaining('File unavailable'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
