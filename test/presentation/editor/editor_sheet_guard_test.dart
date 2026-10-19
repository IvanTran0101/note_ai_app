import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/editor/editor_popup_guard.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';

void main() {
  for (final change in ['access', 'document', 'generation', 'dispose']) {
    testWidgets('$change closes the owned block sheet without a choice', (
      tester,
    ) async {
      var allowed = true;
      var generation = 1;
      String? result;
      final adapter = _adapter(() => allowed, () => generation);
      await tester.pumpWidget(_host(adapter, (value) => result = value));
      await tester.tap(find.text('Open sheet'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      if (change == 'access') {
        allowed = false;
        adapter.refreshAccess();
      } else if (change == 'document') {
        await adapter.editor.apply(
          adapter.editor.transaction..insertText(
            adapter.editor.document.root.children.first,
            4,
            ' changed',
          ),
        );
      } else if (change == 'generation') {
        generation++;
        adapter.refreshAccess();
      } else {
        adapter.dispose();
      }
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Open sheet'), findsOneWidget);
      expect(result, isNull);
      await tester.pumpWidget(const SizedBox());
      if (change != 'dispose') adapter.dispose();
    });
  }
  testWidgets(
    'sheet focus can clear the caret without invalidating its choice',
    (tester) async {
      String? result;
      final adapter = _adapter(() => true, () => 1);
      await tester.pumpWidget(_host(adapter, (value) => result = value));
      await tester.tap(find.text('Open sheet'));
      await tester.pumpAndSettle();
      adapter.editor.selection = null;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose block'));
      await tester.pumpAndSettle();
      expect(result, 'choice');
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
    },
  );
}

RichEditorAdapter _adapter(bool Function() allowed, int Function() generation) {
  return RichEditorAdapter(
      document: null,
      legacyText: 'body',
      canRead: allowed,
      canEdit: allowed,
      isLive: () => true,
      accessGeneration: generation,
      onChanged: () {},
    )
    ..editor.selection = engine.Selection.collapsed(
      engine.Position(path: [0], offset: 4),
    );
}

Widget _host(RichEditorAdapter adapter, ValueChanged<String?> completed) =>
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => completed(
              await guardedEditorSheet<String>(
                context,
                adapter,
                adapter.capture(range: false)!,
                (context) => SizedBox(
                  height: 200,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, 'choice'),
                    child: const Text('Choose block'),
                  ),
                ),
              ),
            ),
            child: const Text('Open sheet'),
          ),
        ),
      ),
    );
