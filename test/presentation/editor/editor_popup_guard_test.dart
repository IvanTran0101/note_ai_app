import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/editor/editor_value_dialog.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';

void main() {
  for (final change in ['access', 'document', 'dispose']) {
    testWidgets(
      '$change closes only owned value popup without applying its private draft',
      (tester) async {
        var live = true, allowed = true;
        String? result;
        final adapter = RichEditorAdapter(
          document: null,
          legacyText: 'body',
          canRead: () => allowed,
          canEdit: () => allowed,
          isLive: () => live,
          accessGeneration: () => 1,
          onChanged: () {},
        );
        adapter.editor.selection = engine.Selection.single(
          path: [0],
          startOffset: 0,
          endOffset: 4,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async => result = await editorValueDialog(
                    context,
                    title: 'Link',
                    initial: 'https://example.invalid/private-draft',
                    label: 'URL',
                    validate: validateEditorLink,
                    adapter: adapter,
                    snapshot: adapter.capture()!,
                  ),
                  child: const Text('Open popup'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open popup'));
        await tester.pumpAndSettle();
        expect(find.text('Link'), findsOneWidget);
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
        } else {
          live = false;
          adapter.dispose();
        }
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('Link'), findsNothing);
        expect(find.text('Open popup'), findsOneWidget);
        expect(result, null);
        await tester.pumpWidget(const SizedBox());
        if (change != 'dispose') adapter.dispose();
      },
    );
  }
}
