import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';
import 'package:note_ai_app/presentation/editor/rich_note_editor.dart';

RichEditorAdapter visibleRichEditor(WidgetTester tester) =>
    tester.widget<RichNoteEditor>(find.byType(RichNoteEditor)).adapter;

/// Drive the production public transaction stream, including its dirty/save
/// listeners. Individual keyboard/IME behavior has separate host widget tests.
Future<void> replaceRichText(RichEditorAdapter adapter, String text) async {
  final node = adapter.editor.document.root.children.first;
  final transaction = adapter.editor.transaction
    ..deleteText(node, 0, node.delta!.length)
    ..insertText(node, 0, text, sliceAttributes: false);
  transaction.afterSelection = engine.Selection.collapsed(
    engine.Position(path: node.path, offset: text.length),
  );
  await adapter.editor.apply(transaction);
}
