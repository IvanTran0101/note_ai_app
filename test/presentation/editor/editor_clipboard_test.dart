import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/editor_clipboard.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  RichEditorAdapter create({
    NoteDocument? document,
    bool Function()? read,
    bool Function()? edit,
  }) {
    final adapter = RichEditorAdapter(
      document: document,
      legacyText: 'before',
      canEdit: edit ?? () => true,
      canRead: read ?? () => true,
      isLive: () => true,
      accessGeneration: () => 1,
      onChanged: () {},
    );
    addTearDown(adapter.dispose);
    return adapter;
  }

  void select(RichEditorAdapter adapter, int start, int end) =>
      adapter.editor.selection = engine.Selection.single(
        path: [0],
        startOffset: start,
        endOffset: end,
      );
  test('copy uses equation expression; Viewer can copy, lost read permission refuses', () async {
    var allowed = true;
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final adapter = create(
      read: () => allowed,
      edit: () => false,
      document: NoteDocument([
        DocumentBlock(
          id: 'p',
          kind: DocumentBlockKind.paragraph,
          runs: [
            const DocumentText('A'),
            DocumentMath(r'\sqrt{x}'),
            const DocumentText('B'),
          ],
        ),
      ]),
    );
    select(adapter, 1, 2);
    expect(await EditorClipboard(adapter).copy(), true);
    expect(copied, r'\sqrt{x}');
    allowed = false;
    copied = null;
    expect(await EditorClipboard(adapter).copy(), false);
    expect(copied, null);
    expect(adapter.revision, 0);
  });
  test('oversized or stale paste leaves selection content untouched', () async {
    final adapter = create(), clipboard = EditorClipboard(adapter);
    select(adapter, 0, 6);
    final snapshot = adapter.capture()!;
    expect(await clipboard.paste(snapshot, 'x' * 100001), false);
    expect(adapter.plainText, 'before');
    expect(adapter.revision, 0);
    select(adapter, 0, 0);
    expect(await clipboard.paste(snapshot, 'replacement'), false);
    expect(adapter.plainText, 'before');
  });
  test('external plaintext multiline paste keeps literal markup and newline; undo restores content', () async {
    final adapter = create(), clipboard = EditorClipboard(adapter);
    select(adapter, 6, 6);
    expect(
      await clipboard.paste(
        adapter.capture(range: false)!,
        '\n# plain <b>text</b>\r\nViệt 📝',
      ),
      true,
    );
    expect(adapter.plainText, 'before\n# plain <b>text</b>\nViệt 📝');
    expect(
      adapter.visibleDocument.blocks.every(
        (b) => b.kind == DocumentBlockKind.paragraph,
      ),
      true,
    );
    adapter.editor.undoManager.undo();
    expect(adapter.plainText, 'before');
  });
}
