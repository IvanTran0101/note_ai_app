import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/notes/note_editor_snapshot.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/rich_note_editor.dart';
import 'package:note_ai_app/presentation/notes/note_detail_localizations.dart';
import 'package:note_ai_app/presentation/notes/note_detail_page.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';

void main() {
  testWidgets('pause flushes the newer rich draft after an in-flight save', (
    tester,
  ) async {
    final controller = _GatedController();
    final initial = controller.persisted;
    Widget page(NoteDto note) => MaterialApp(
      localizationsDelegates: const [
        NoteDetailCopy.delegate,
        engine.AppFlowyEditorLocalizations.delegate,
      ],
      home: NoteDetailPage(notesController: controller, note: note),
    );
    await tester.pumpWidget(page(initial));
    await tester.pumpAndSettle();
    final adapter = tester.widget<RichNoteEditor>(find.byType(RichNoteEditor)).adapter;
    final node = adapter.editor.document.root.children.first;
    await adapter.editor.apply(adapter.editor.transaction..insertText(node, 2, ' A'));
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(controller.attempts, 1);
    await adapter.editor.apply(adapter.editor.transaction..insertText(node, 4, ' B'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    controller.firstSave.complete();
    await tester.pump();
    await tester.pump();
    expect(controller.attempts, 2, reason: 'pause should not leave B on the debounce timer');
    expect(controller.persisted.content, 'AA A B');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page(controller.persisted));
    await tester.pumpAndSettle();
    expect(tester.widget<RichNoteEditor>(find.byType(RichNoteEditor)).adapter.document!.plainText, 'AA A B');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
  });
  for (final failure in ['write', 'conflict']) {
    testWidgets('pause preserves the draft on $failure failure', (tester) async {
      final controller = _GatedController();
      controller.failure = failure == 'write'
          ? StateError('synthetic write failure')
          : NoteEditorChanged(controller.persisted);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: const [
          NoteDetailCopy.delegate,
          engine.AppFlowyEditorLocalizations.delegate,
        ],
        home: NoteDetailPage(notesController: controller, note: controller.persisted),
      ));
      await tester.pumpAndSettle();
      final adapter = tester.widget<RichNoteEditor>(find.byType(RichNoteEditor)).adapter;
      final node = adapter.editor.document.root.children.first;
      await adapter.editor.apply(adapter.editor.transaction..insertText(node, 2, ' A'));
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      await adapter.editor.apply(adapter.editor.transaction..insertText(node, 4, ' B'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      controller.firstSave.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      expect(controller.attempts, 1, reason: 'failed A must not trigger a B write');
      expect(controller.persisted.content, 'AA');
      expect(adapter.document!.plainText, 'AA A B');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

final class _GatedController implements NotesApplicationController, DocumentNotesController {
  _GatedController() {
    final document = NoteDocument([
      DocumentBlock(id: 'p', kind: DocumentBlockKind.paragraph, runs: const [DocumentText('AA')]),
    ]);
    persisted = NoteDto(id: 'test', ownerId: 'owner', title: 'Title', content: 'AA', document: document, createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026));
  }
  final firstSave = Completer<void>();
  late NoteDto persisted;
  int attempts = 0;
  Object? failure;
  @override
  get summaryConsent => null;
  @override
  Future<NoteDto> saveDocumentSnapshot(NoteDto selected, String title, NoteDocument document) async {
    attempts++;
    if (attempts == 1) {
      await firstSave.future;
      if (failure case final error?) throw error;
    }
    return persisted = NoteDto(id: selected.id, ownerId: selected.ownerId, title: title, content: document.plainText, document: document, createdAt: selected.createdAt, updatedAt: DateTime.utc(2026));
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
