// The regression concerns Web's non-delta DOM input client. Native uses the
// existing platform input lifecycle and is covered by the generic editor suite.
@TestOn('browser')
library;

import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/editor_popup_guard.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';
import 'package:note_ai_app/presentation/editor/rich_note_editor.dart';
import 'package:note_ai_app/presentation/editor/selection_formatting_controller.dart';

void main() {
  testWidgets(
    'popup releases old input client; formatting and real deletion survive',
    (tester) async {
      const text = 'Local first tiếng Việt 😀';
      final focus = FocusNode();
      final adapter = RichEditorAdapter(
        document: null,
        legacyText: text,
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
      await tester.pumpAndSettle();
      adapter.editor.service.selectionService.updateSelection(
        engine.Selection.single(
          path: [0],
          startOffset: 0,
          endOffset: text.length,
        ),
      );
      await tester.pumpAndSettle();
      expect(focus.hasFocus, true);
      expect(tester.testTextInput.hasAnyClients, true);
      final snapshot = adapter.capture()!;
      final result = guardedEditorDialog<String>(
        tester.element(find.byType(RichNoteEditor)),
        adapter,
        snapshot,
        (context) => SimpleDialog(
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'blue'),
              child: const Text('blue'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(focus.hasFocus, false);
      expect(
        tester.testTextInput.hasAnyClients,
        false,
        reason: 'A dialog owns focus; its hidden/recreated DOM field must not keep the editor client.',
      );
      await tester.tap(find.text('blue'));
      await tester.pumpAndSettle();
      expect(await result, 'blue');
      expect(
        await SelectionFormattingController(adapter)
            .color(snapshot, DocumentColor.blue, popupOwnsFocus: true),
        true,
      );
      await tester.pumpAndSettle();
      expect(adapter.plainText, text);
      adapter.editor.service.selectionService.updateSelection(
        engine.Selection.single(
          path: [0],
          startOffset: 0,
          endOffset: text.length,
        ),
      );
      await tester.pumpAndSettle();
      adapter.editor.service.keyboardService!.enableKeyBoard(
        adapter.editor.selection!,
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: ' ',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        adapter.plainText,
        '',
        reason: 'Real delete-all remains available.',
      );
      expect(tester.takeException(), null);
    },
  );
}
