import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/rich_note_editor.dart';
import 'package:note_ai_app/presentation/common/note_flow_page_header.dart';
import 'package:note_ai_app/presentation/notes/note_detail_localizations.dart';
import 'package:note_ai_app/presentation/notes/note_detail_page.dart';
import 'package:note_ai_app/presentation/notes/note_detail_surface.dart';

import 'note_detail_test_controller.dart';

void main() {
  testWidgets(
    'early local ACK must not replace Undo during an in-flight save',
    (tester) async {
      final controller = RichTestNotesController()
        ..saveGate = Completer<void>();
      final date = DateTime.utc(2026);
      final initial = NoteDocument([
        DocumentBlock(
          id: 'p',
          kind: DocumentBlockKind.paragraph,
          runs: const [DocumentText('AA')],
        ),
      ]);
      final incoming = ValueNotifier(
        NoteDto(
          id: 'early-ack',
          ownerId: 'owner',
          title: 'Early ACK',
          content: 'AA',
          document: initial,
          createdAt: date,
          updatedAt: date,
        ),
      );
      addTearDown(incoming.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            NoteDetailCopy.delegate,
            engine.AppFlowyEditorLocalizations.delegate,
          ],
          home: ValueListenableBuilder<NoteDto>(
            valueListenable: incoming,
            builder: (_, note, _) => NoteDetailPage(
              showAppBar: false,
              notesController: controller,
              note: note,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final adapter = tester
          .widget<RichNoteEditor>(find.byType(RichNoteEditor))
          .adapter;
      final node = adapter.editor.document.root.children.first;
      await adapter.editor.apply(
        adapter.editor.transaction..insertText(node, 2, ' saved'),
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(controller.richSaves, 1);
      incoming.value = controller.last!;
      await tester.pump();
      adapter.editor.undoManager.undo();
      await tester.pump();
      expect(
        adapter.document,
        initial,
        reason: 'pending ACK cannot erase Undo',
      );
      controller.saveGate!.complete();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(controller.last!.content, 'AA');
      expect(controller.richSaves, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final undoTiming in ['before', 'after', 'none']) {
    testWidgets('save feedback follows current dirty state, undo=$undoTiming', (
      tester,
    ) async {
      final undoToSaved = undoTiming != 'none';
      final controller = RichTestNotesController()
        ..saveGate = Completer<void>();
      final date = DateTime.utc(2026);
      final initial = NoteDocument([
        DocumentBlock(
          id: 'p',
          kind: DocumentBlockKind.paragraph,
          runs: const [DocumentText('AA')],
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            NoteDetailCopy.delegate,
            engine.AppFlowyEditorLocalizations.delegate,
          ],
          home: NoteDetailPage(
            showAppBar: false,
            notesController: controller,
            note: NoteDto(
              id: 'feedback',
              ownerId: 'owner',
              title: 'Feedback',
              content: initial.plainText,
              document: initial,
              createdAt: date,
              updatedAt: date,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final adapter = tester
          .widget<RichNoteEditor>(find.byType(RichNoteEditor))
          .adapter;
      final node = adapter.editor.document.root.children.first;
      await adapter.editor.apply(
        adapter.editor.transaction..insertText(node, 2, ' saved'),
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(controller.richSaves, 1);
      await adapter.editor.apply(
        adapter.editor.transaction..insertText(node, 8, ' later'),
      );
      await tester.pump();
      if (undoTiming == 'before') {
        adapter.editor.undoManager.undo();
        await tester.pump();
        expect(adapter.document, controller.last!.document);
      }
      controller.saveGate!.complete();
      await tester.pumpAndSettle();
      final copy = NoteDetailCopy.of(
        tester.element(find.byType(NoteDetailSurface)),
      );
      if (undoTiming == 'after') {
        expect(
          tester
              .widget<NoteFlowPageHeader>(find.byType(NoteFlowPageHeader))
              .statusLabel,
          copy.autoSavePending,
        );
        adapter.editor.undoManager.undo();
        await tester.pump();
        expect(adapter.document, controller.last!.document);
      }
      expect(
        tester
            .widget<NoteFlowPageHeader>(find.byType(NoteFlowPageHeader))
            .statusLabel,
        undoToSaved ? copy.saved : copy.autoSavePending,
      );
      if (!undoToSaved) {
        expect(
          tester
              .widget<NoteDetailSurface>(find.byType(NoteDetailSurface))
              .statusMessage,
          isNot(copy.autoSavePending),
          reason: 'Pending is derived from dirty state, never a stored message',
        );
      }
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(controller.richSaves, undoToSaved ? 1 : 2);
      expect(
        controller.last!.content,
        undoToSaved ? 'AA saved' : 'AA saved later',
      );
      await tester.pumpWidget(const SizedBox());
    });
  }
}
