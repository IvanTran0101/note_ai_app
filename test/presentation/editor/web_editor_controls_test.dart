import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/editor/web_editor_controls.dart';

void main() {
  testWidgets(
    'wide Web controls appear on editor focus and leave idle canvas quiet',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1280, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final editorFocus = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Focus(
                  focusNode: editorFocus,
                  child: const SizedBox(height: 40),
                ),
                WebEditorControls(
                  focusNode: editorFocus,
                  child: TextButton(
                    onPressed: () {},
                    child: const Text('Add block'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);
      editorFocus.requestFocus();
      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
      editorFocus.unfocus();
      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);
      await tester.pumpWidget(const SizedBox());
      editorFocus.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact Web keeps block control visible without editor focus', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final editorFocus = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WebEditorControls(
            focusNode: editorFocus,
            child: TextButton(onPressed: () {}, child: const Text('Add block')),
          ),
        ),
      ),
    );
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
    await tester.pumpWidget(const SizedBox());
    editorFocus.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard Tab reveals and activates the quiet block control', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final editorFocus = FocusNode();
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WebEditorControls(
            focusNode: editorFocus,
            child: TextButton(
              onPressed: () => opened++,
              child: const Text('Add block'),
            ),
          ),
        ),
      ),
    );
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, 1);
    await tester.pumpWidget(const SizedBox());
    editorFocus.dispose();
    expect(tester.takeException(), isNull);
  });
}
