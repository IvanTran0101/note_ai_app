import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';
import 'package:note_ai_app/presentation/editor/rich_note_editor.dart';

NoteDocument _table() => NoteDocument([
  DocumentBlock(
    id: 'table',
    kind: DocumentBlockKind.table,
    rows: [
      for (var row = 0; row < 2; row++)
        DocumentRow(
          id: 'r$row',
          cells: [
            for (var col = 0; col < 2; col++)
              DocumentCell(
                id: 'c${row}_$col',
                runs: [DocumentText('Cell $row,$col')],
              ),
          ],
        ),
    ],
  ),
]);

void main() {
  late RichEditorAdapter adapter;
  late FocusNode focus;
  var edits = 0;
  setUp(() {
    edits = 0;
    focus = FocusNode();
    adapter = RichEditorAdapter(
      document: _table(),
      legacyText: '',
      canEdit: () => true,
      isLive: () => true,
      accessGeneration: () => 1,
      onChanged: () => edits++,
    );
  });
  Future<void> paint(WidgetTester tester, {double scale = 1}) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          engine.AppFlowyEditorLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: RichNoteEditor(
                adapter: adapter,
                focusNode: focus,
                header: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    adapter.dispose();
    focus.dispose();
  }

  testWidgets('table measurement is viewing, not an undoable document edit', (
    tester,
  ) async {
    try {
      final before = adapter.document;
      await paint(tester);
      expect(adapter.document, before);
      expect(edits, 0);
      expect(adapter.editor.undoManager.undoStack.isEmpty, true);
      await paint(tester, scale: 1.6);
      expect(adapter.document, before);
      expect(edits, 0);
      expect(adapter.editor.undoManager.undoStack.isEmpty, true);
    } finally {
      await dispose(tester);
    }
  });

  testWidgets('painted row change undoes once and layout retains redo', (
    tester,
  ) async {
    try {
      await paint(tester);
      final before = adapter.document;
      adapter.editor.selection = engine.Selection.collapsed(
        engine.Position(path: [0, 0, 0], offset: 0),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Table options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add row below'));
      await tester.pumpAndSettle();
      final added = adapter.document;
      expect(added!.blocks.single.rows.length, 3);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(adapter.document, before);
      expect(adapter.editor.undoManager.redoStack.isNonEmpty, true);
      await paint(tester, scale: 1.6);
      expect(adapter.document, before);
      expect(adapter.editor.undoManager.redoStack.isNonEmpty, true);
      await tester.tap(find.byTooltip('Redo'));
      await tester.pumpAndSettle();
      expect(adapter.document, added);
      expect(tester.takeException(), null);
    } finally {
      await dispose(tester);
    }
  });
}
