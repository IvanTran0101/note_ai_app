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
    // The native rail lives in the root overlay only while the IME is open,
    // the editor owns focus and the selection is collapsed or null.
    tester.view
      ..physicalSize = const Size(411, 914)
      ..devicePixelRatio = 1
      ..viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.reset);
    final focus = FocusNode();
    final adapter = RichEditorAdapter(
      document: null,
      legacyText: 'text',
      canEdit: () => true,
      isLive: () => true,
      accessGeneration: () => 1,
      onChanged: () {},
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      focus.unfocus();
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
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    adapter.editor.service.selectionService.updateSelection(
      engine.Selection.collapsed(engine.Position(path: [0], offset: 0)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EditorControls), findsOneWidget);
    expect(find.byTooltip('Add block'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    final controls = tester.widget<EditorControls>(find.byType(EditorControls));
    controls.slash.openTouch();
    final scheduled = tester.binding.hasScheduledFrame;
    // Always clean up even when the frame scheduling assertion fails.
    await tester.pumpAndSettle();
    expect(find.text('Basic blocks'), findsOneWidget);
    controls.slash.close();
    await tester.pumpAndSettle();
    expect(scheduled, isTrue);
  });
}
