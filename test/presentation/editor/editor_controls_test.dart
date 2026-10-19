import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';
import 'package:note_ai_app/presentation/editor/rich_note_editor.dart';
import 'package:note_ai_app/presentation/editor/basic_block_commands.dart';
import 'package:note_ai_app/presentation/editor/basic_block_menu.dart';

void main() {
  Future<RichEditorAdapter> show(
    WidgetTester tester,
    NoteDocument document,
  ) async {
    final adapter = RichEditorAdapter(
      document: document,
      legacyText: '',
      canEdit: () => true,
      isLive: () => true,
      accessGeneration: () => 1,
      onChanged: () {},
    );
    final focus = FocusNode();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
      focus.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          engine.AppFlowyEditorLocalizations.delegate,
        ],
        home: Scaffold(
          body: RichNoteEditor(
            adapter: adapter,
            focusNode: focus,
            header: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return adapter;
  }

  testWidgets(
    'table menu retains captured cell when popup clears editor focus',
    (tester) async {
      final adapter = await show(
        tester,
        NoteDocument([
          DocumentBlock(
            id: 'table',
            kind: DocumentBlockKind.table,
            rows: [
              for (var r = 0; r < 2; r++)
                DocumentRow(
                  id: 'r$r',
                  cells: [
                    for (var c = 0; c < 2; c++)
                      DocumentCell(id: 'c${r}_$c', runs: const []),
                  ],
                ),
            ],
          ),
        ]),
      );
      adapter.editor.selection = engine.Selection.collapsed(
        engine.Position(path: [0, 0, 0], offset: 0),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Table options'));
      await tester.pumpAndSettle();
      adapter.editor.selection = null;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add row below'));
      await tester.pumpAndSettle();
      expect(adapter.document!.blocks.single.rows.length, 3);
      expect(tester.takeException(), null);
    },
  );
  testWidgets('touch block menu converts the selected paragraph', (
    tester,
  ) async {
    final adapter = await show(
      tester,
      NoteDocument([
        for (final id in ['first', 'second'])
          DocumentBlock(
            id: id,
            kind: DocumentBlockKind.paragraph,
            runs: [DocumentText(id)],
          ),
      ]),
    );
    adapter.editor.selection = engine.Selection.collapsed(
      engine.Position(path: [1], offset: 6),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Add block'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heading 1'));
    await tester.pumpAndSettle();
    expect(adapter.document!.blocks.first.kind, DocumentBlockKind.paragraph);
    expect(adapter.document!.blocks.last.kind, DocumentBlockKind.heading);
    expect(adapter.document!.blocks.last.id, 'second');
  });
  for (final choice in basicBlockChoices) {
    testWidgets(
      'touch picker applies ${choice.label} after popup takes focus',
      (tester) async {
        final adapter = await show(
          tester,
          NoteDocument([
            DocumentBlock(
              id: 'body',
              kind: DocumentBlockKind.paragraph,
              runs: const [DocumentText('sample')],
            ),
          ]),
        );
        adapter.editor.selection = engine.Selection.collapsed(
          engine.Position(path: [0], offset: 6),
        );
        await tester.pump();
        await tester.tap(find.byTooltip('Add block'));
        await tester.pumpAndSettle();
        expect(
          find.byType(BottomSheet),
          kIsWeb ? findsNothing : findsOneWidget,
        );
        adapter.editor.selection = null;
        await tester.pumpAndSettle();
        final menu = find.byType(BasicBlockMenu);
        final target = find.descendant(
          of: menu,
          matching: find.text(choice.label),
        );
        await tester.scrollUntilVisible(
          target,
          180,
          scrollable: find.descendant(
            of: menu,
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(find.byType(BasicBlockMenu), findsNothing);
        final blocks = adapter.visibleDocument.blocks;
        if (choice.kind == DocumentBlockKind.table ||
            choice.kind == DocumentBlockKind.divider) {
          expect(blocks[1].kind, choice.kind);
          expect(blocks.first.runs.single.plainText, 'sample');
        } else {
          expect(blocks.single.kind, choice.kind);
          expect(blocks.single.runs.single.plainText, 'sample');
          expect(blocks.single.id, 'body');
          expect(blocks.single.level, choice.level);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
