import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';
import 'package:note_ai_app/presentation/editor/rich_note_editor.dart';

void main() {
  testWidgets(
    'cell focus survives selection feedback and Tab keeps row order',
    (tester) async {
      final focus = FocusNode();
      final adapter = RichEditorAdapter(
        document: NoteDocument([
          DocumentBlock(
            id: 'table',
            kind: DocumentBlockKind.table,
            rows: [
              for (var r = 0; r < 2; r++)
                DocumentRow(
                  id: 'row$r',
                  cells: [
                    for (var c = 0; c < 2; c++)
                      DocumentCell(
                        id: 'cell${r}_$c',
                        runs: [DocumentText('$r:$c')],
                      ),
                  ],
                ),
            ],
          ),
        ]),
        legacyText: '',
        canEdit: () => true,
        isLive: () => true,
        accessGeneration: () => 1,
        onChanged: () {},
      );
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
      final service = adapter.editor.service.selectionService;
      service.updateSelection(
        engine.Selection.collapsed(engine.Position(path: [0, 0, 0], offset: 0)),
      );
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      final primary = FocusManager.instance.primaryFocus;
      if (kIsWeb) expect(primary!.debugLabel, 'Document text block');
      service.updateSelection(
        engine.Selection.collapsed(engine.Position(path: [0, 0, 0], offset: 1)),
      );
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(primary));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(adapter.editor.selection!.start.path, [0, 2, 0]);
      expect(adapter.document!.plainText, '0:0\t0:1\n1:0\t1:1');
      expect(focus.hasFocus, isTrue);
      if (kIsWeb) {
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          'Document text block',
        );
        expect(FocusManager.instance.primaryFocus, isNot(same(primary)));
      }
      expect(tester.takeException(), isNull);
    },
  );
}
