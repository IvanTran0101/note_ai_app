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
  Future<void> paint(
    WidgetTester tester, {
    double scale = 1,
    bool focusEditor = false,
  }) async {
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
    if (focusEditor) {
      // The native rail is only mounted while the editor owns focus.
      focus.requestFocus();
      await tester.pumpAndSettle();
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    focus.unfocus();
    adapter.dispose();
    focus.dispose();
  }

  testWidgets('table measurement is viewing, not an undoable document edit', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(411, 914)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
    // Table options and history share the native rail with the IME above it.
    tester.view
      ..physicalSize = const Size(411, 914)
      ..devicePixelRatio = 1
      ..viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.reset);
    try {
      await paint(tester, focusEditor: true);
      final before = adapter.document;
      adapter.editor.selection = engine.Selection.collapsed(
        engine.Position(path: [0, 0, 0], offset: 0),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Table options'), findsOneWidget);
      await tester.tap(find.byTooltip('Table options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add row below'));
      await tester.pumpAndSettle();
      final added = adapter.document;
      expect(added!.blocks.single.rows.length, 3);
      // The dialog took focus; the rail only returns once the editor has it.
      focus.requestFocus();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Undo'), findsOneWidget);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(adapter.document, before);
      expect(adapter.editor.undoManager.redoStack.isNonEmpty, true);
      await paint(tester, scale: 1.6, focusEditor: true);
      expect(adapter.document, before);
      expect(adapter.editor.undoManager.redoStack.isNonEmpty, true);
      expect(find.byTooltip('Redo'), findsOneWidget);
      await tester.tap(find.byTooltip('Redo'));
      await tester.pumpAndSettle();
      expect(adapter.document, added);
      expect(tester.takeException(), null);
    } finally {
      await dispose(tester);
    }
  });
}
