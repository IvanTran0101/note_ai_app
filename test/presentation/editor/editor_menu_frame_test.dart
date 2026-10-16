import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/editor/editor_controls.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';
import 'package:note_ai_app/presentation/editor/rich_note_editor.dart';

void main() {
  testWidgets('touch menu schedules a frame when the editor is idle', (
    tester,
  ) async {
    final focus = FocusNode();
    final adapter = RichEditorAdapter(
      document: null,
      legacyText: 'text',
      canEdit: () => true,
      isLive: () => true,
      accessGeneration: () => 1,
      onChanged: () {},
    );
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
    adapter.editor.service.selectionService.updateSelection(
      engine.Selection.collapsed(engine.Position(path: [0], offset: 0)),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    final controls = tester.widget<EditorControls>(find.byType(EditorControls));
    controls.slash.openTouch();
    final scheduled = tester.binding.hasScheduledFrame;
    // Always clean up even when the frame scheduling assertion fails.
    await tester.pumpAndSettle();
    expect(find.text('Basic blocks'), findsOneWidget);
    controls.slash.close();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    adapter.dispose();
    focus.dispose();
    expect(scheduled, isTrue);
  });
}
