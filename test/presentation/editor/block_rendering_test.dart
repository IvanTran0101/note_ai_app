import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';
import 'package:note_ai_app/presentation/editor/rich_note_editor.dart';

void main() {
  for (final kind in DocumentBlockKind.values.where(
    (kind) =>
        kind != DocumentBlockKind.table && kind != DocumentBlockKind.divider,
  )) {
    testWidgets('$kind painted inline size survives every renderer decorator', (
      tester,
    ) async {
      final adapter = RichEditorAdapter(
        document: NoteDocument([
          DocumentBlock(
            id: 'paint',
            kind: kind,
            level: kind == DocumentBlockKind.heading ? 4 : null,
            checked: kind == DocumentBlockKind.todo ? true : null,
            runs: [
              DocumentText('Painted range', marks: DocumentMarks(fontSize: 28)),
            ],
          ),
        ]),
        legacyText: '',
        canEdit: () => true,
        isLive: () => true,
        accessGeneration: () => 1,
        onChanged: () {},
      );
      final focus = FocusNode();
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
      final sizes = <double?>[];
      for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
        rich.text.visitChildren((span) {
          if (span is TextSpan && span.text == 'Painted range') {
            sizes.add(span.style?.fontSize);
          }
          return true;
        });
      }
      expect(sizes, isNotEmpty);
      expect(sizes.every((size) => size == 28), true);
      if (kind == DocumentBlockKind.todo) {
        expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, true);
        await tester.tap(find.byType(Checkbox));
        await tester.pump();
        expect(adapter.document!.blocks.single.checked, false);
        adapter.editor.undoManager.undo();
        expect(adapter.document!.blocks.single.checked, true);
      }
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
      focus.dispose();
    });
  }
}
