import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/native_clipboard_toolbar.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';

void main() {
  testWidgets(
    'native range exposes accessible clipboard actions and copies selection',
    (tester) async {
      String? copiedText;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final harness = await _showToolbar(tester);

      expect(find.text('Cut'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Paste'), findsOneWidget);
      final copyButton = find.ancestor(
        of: find.text('Copy'),
        matching: find.byType(TextButton),
      );
      expect(copyButton, findsOneWidget);
      expect(tester.getSize(copyButton).height, greaterThanOrEqualTo(48));

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(copiedText, 'alpha');
      expect(harness.adapter.plainText, 'alpha beta');
      expect(find.text('Copy'), findsNothing);
    },
  );

  testWidgets('cut button uses the guarded cut path', (tester) async {
    String? copiedText;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final harness = await _showToolbar(tester);
    await tester.tap(find.text('Cut'));
    await tester.pumpAndSettle();

    expect(copiedText, 'alpha');
    expect(harness.adapter.plainText, ' beta');
  });

  testWidgets('paste button uses the guarded clipboard read path', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': 'replacement'};
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final harness = await _showToolbar(tester);
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();

    expect(harness.adapter.plainText, 'replacement beta');
  });

  testWidgets('read-only range offers copy and permission loss hides it', (
    tester,
  ) async {
    var canRead = true;
    final harness = await _showToolbar(
      tester,
      canEdit: () => false,
      canRead: () => canRead,
    );

    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Cut'), findsNothing);
    expect(find.text('Paste'), findsNothing);

    canRead = false;
    harness.adapter.refreshAccess();
    await tester.pumpAndSettle();

    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('desktop platforms do not show the native clipboard toolbar', (
    tester,
  ) async {
    await _showToolbar(tester, platform: TargetPlatform.linux);

    expect(find.text('Cut'), findsNothing);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Paste'), findsNothing);
  });

  testWidgets('selection refreshes toolbar; focus and route changes hide it', (
    tester,
  ) async {
    final harness = await _showToolbar(tester);
    expect(find.text('Copy'), findsOneWidget);

    harness.adapter.editor.service.selectionService.updateSelection(
      engine.Selection.single(path: [0], startOffset: 1, endOffset: 5),
    );
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);

    harness.focus.requestFocus();
    harness.adapter.editor.service.selectionService.updateSelection(
      engine.Selection.single(path: [0], startOffset: 1, endOffset: 5),
    );
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);

    harness.focus.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsNothing);

    harness.focus.requestFocus();
    harness.adapter.editor.service.selectionService.updateSelection(
      engine.Selection.single(path: [0], startOffset: 1, endOffset: 5),
    );
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final routeFuture = navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other route')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsNothing);
    navigator.pop();
    await tester.pumpAndSettle();
    await routeFuture;
  });
}

Future<_ToolbarHarness> _showToolbar(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.android,
  bool Function()? canEdit,
  bool Function()? canRead,
}) async {
  final focus = FocusNode();
  final adapter = RichEditorAdapter(
    document: NoteDocument([
      DocumentBlock(
        id: 'paragraph',
        kind: DocumentBlockKind.paragraph,
        runs: const [DocumentText('alpha beta')],
      ),
    ]),
    legacyText: '',
    canEdit: canEdit ?? () => true,
    canRead: canRead ?? () => true,
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
      theme: ThemeData(platform: platform),
      localizationsDelegates: const [
        engine.AppFlowyEditorLocalizations.delegate,
      ],
      home: Scaffold(
        body: NativeClipboardToolbar(
          adapter: adapter,
          focusNode: focus,
          child: engine.AppFlowyEditor(
            editorState: adapter.editor,
            focusNode: focus,
            editable: adapter.editable,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  focus.requestFocus();
  adapter.editor.service.selectionService.updateSelection(
    engine.Selection.single(path: [0], startOffset: 0, endOffset: 5),
  );
  await tester.pumpAndSettle();

  return _ToolbarHarness(adapter: adapter, focus: focus);
}

final class _ToolbarHarness {
  const _ToolbarHarness({required this.adapter, required this.focus});

  final RichEditorAdapter adapter;
  final FocusNode focus;
}
