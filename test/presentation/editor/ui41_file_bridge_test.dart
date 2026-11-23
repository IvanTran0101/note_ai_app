import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';
import 'package:note_ai_app/presentation/editor/rich_note_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  bool writable = true, live = true;
  RichEditorAdapter create() {
    writable = live = true;
    final adapter = RichEditorAdapter(
      document: NoteDocument([
        DocumentBlock(id: 'file', kind: DocumentBlockKind.attachment),
        DocumentBlock(
          id: 'after',
          kind: DocumentBlockKind.paragraph,
          runs: const [DocumentText('after')],
        ),
      ], inlineAttachments: true),
      legacyText: '',
      canEdit: () => writable,
      isLive: () => live,
      accessGeneration: () => 1,
      onChanged: () {},
    );
    addTearDown(adapter.dispose);
    adapter.editor.selection = engine.Selection.collapsed(
      engine.Position(path: [1], offset: 2),
    );
    return adapter;
  }

  test(
    'bind staged IDs inline, preserve caret and undo one association',
    () async {
      final adapter = create();
      expect(
        await adapter.bindFiles('file', ['attachment_1', 'attachment_2']),
        true,
      );
      expect(adapter.document!.blocks.map((b) => b.attachmentId), [
        'attachment_1',
        'attachment_2',
        null,
      ]);
      expect(adapter.plainText, '\n\nafter');
      // The text remains selected even when insertion shifts its document path.
      expect(adapter.editor.selection?.start.offset, 2);
      expect(adapter.editor.selection?.start.path, [2]);
      adapter.editor.undoManager.undo();
      expect(adapter.document!.blocks.length, 2);
      expect(adapter.document!.blocks.first.attachmentId, null);
      adapter.editor.undoManager.redo();
      expect(adapter.document!.blocks.first.attachmentId, 'attachment_1');
    },
  );

  test('revoked, stale, removed and malformed bindings refuse', () async {
    final adapter = create();
    writable = false;
    expect(await adapter.bindFiles('file', ['attachment_1']), false);
    writable = true;
    live = false;
    expect(await adapter.bindFiles('file', ['attachment_1']), false);
    live = true;
    expect(await adapter.bindFiles('missing', ['attachment_1']), false);
    expect(await adapter.bindFiles('file', ['https://bad.invalid']), false);
    expect(adapter.document!.blocks.first.attachmentId, null);
  });

  test('picker cannot overwrite an already bound block', () async {
    final adapter = create();
    expect(await adapter.bindFiles('file', ['attachment_1']), true);
    expect(await adapter.bindFiles('file', ['attachment_2']), false);
    expect(adapter.document!.blocks.first.attachmentId, 'attachment_1');
  });

  test(
    'the block filter input cannot leak a late engine edit into the note',
    () async {
      final adapter = create();
      final before = adapter.document;
      final snapshot = adapter.capture(range: false)!;
      adapter.setMenuInput(true);
      final edit = adapter.editor.transaction
        ..insertText(adapter.editor.getNodeAtPath([1])!, 2, 'file');
      expect(await adapter.apply(edit, snapshot), false);
      await adapter.editor.apply(edit);
      expect(adapter.document, before);
      adapter.setMenuInput(false);
      expect(adapter.menuOwnsInput.value, false);
      expect(await adapter.bindFiles('file', ['attachment_1']), true);
    },
  );

  testWidgets('a refreshed File callback keeps the mounted input service', (
    tester,
  ) async {
    final adapter = create(), focus = FocusNode();
    Future<void> render(String label) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          engine.AppFlowyEditorLocalizations.delegate,
        ],
        home: Scaffold(
          body: RichNoteEditor(
            adapter: adapter,
            focusNode: focus,
            header: const SizedBox.shrink(),
            fileBlockBuilder: (_, _) => Text(label),
          ),
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
    });
    await render('first callback');
    await tester.pumpAndSettle();
    final inputOwner = tester.widget<engine.AppFlowyEditor>(
      find.byType(engine.AppFlowyEditor),
    );
    await render('new callback after note ACK');
    await tester.pumpAndSettle();
    expect(
      identical(
        inputOwner,
        tester.widget<engine.AppFlowyEditor>(
          find.byType(engine.AppFlowyEditor),
        ),
      ),
      true,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
