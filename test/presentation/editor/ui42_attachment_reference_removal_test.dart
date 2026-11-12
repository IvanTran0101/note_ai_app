import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  RichEditorAdapter create(NoteDocument document, {bool Function()? canEdit}) {
    final adapter = RichEditorAdapter(
      document: document,
      legacyText: '',
      canEdit: canEdit ?? () => true,
      isLive: () => true,
      accessGeneration: () => 1,
      onChanged: () {},
    );
    addTearDown(adapter.dispose);
    return adapter;
  }

  DocumentBlock file(String blockId, String? attachmentId) => DocumentBlock(
    id: blockId,
    kind: DocumentBlockKind.attachment,
    attachmentId: attachmentId,
  );

  test('removes nested duplicate refs and shifts a nested caret safely', () async {
    final document = NoteDocument([
      file('root-file', 'remove-me'),
      DocumentBlock(
        id: 'toggle',
        kind: DocumentBlockKind.toggle,
        children: [
          file('nested-one', 'remove-me'),
          file('nested-two', 'remove-me'),
          DocumentBlock(
            id: 'inside',
            kind: DocumentBlockKind.paragraph,
            runs: const [DocumentText('preserve this text')],
          ),
        ],
      ),
      file('other-file', 'keep-me'),
      DocumentBlock(
        id: 'tail',
        kind: DocumentBlockKind.paragraph,
        runs: const [DocumentText('tail text')],
      ),
    ], inlineAttachments: true);
    final adapter = create(document);
    adapter.editor.selection = engine.Selection.collapsed(
      engine.Position(path: [1, 2], offset: 4),
    );
    final expected = NoteDocument([
      DocumentBlock(
        id: 'toggle',
        kind: DocumentBlockKind.toggle,
        children: [
          DocumentBlock(
            id: 'inside',
            kind: DocumentBlockKind.paragraph,
            runs: const [DocumentText('preserve this text')],
          ),
        ],
      ),
      file('other-file', 'keep-me'),
      DocumentBlock(
        id: 'tail',
        kind: DocumentBlockKind.paragraph,
        runs: const [DocumentText('tail text')],
      ),
    ], inlineAttachments: true);

    expect(await adapter.removeAttachmentBlocks({'remove-me'}), true);

    expect(adapter.document!.attachmentReferenceIds, {'keep-me'});
    expect(adapter.document, expected);
    expect(adapter.document!.plainText, expected.plainText);
    expect(adapter.editor.selection!.start.path, [0, 0]);
    expect(adapter.editor.selection!.start.offset, 4);
  });

  test('clears incompatible undo history after irreversible removal', () async {
    final adapter = create(
      NoteDocument([
        file('pending', 'remove-me'),
        DocumentBlock(
          id: 'text',
          kind: DocumentBlockKind.paragraph,
          runs: const [DocumentText('body')],
        ),
      ], inlineAttachments: true),
    );
    final text = adapter.editor.document.root.children[1];
    final edit = adapter.editor.transaction
      ..insertText(text, 4, '!')
      ..afterSelection = engine.Selection.collapsed(
        engine.Position(path: [1], offset: 5),
      );
    await adapter.editor.apply(edit);
    expect(adapter.editor.undoManager.undoStack.isNonEmpty, true);

    expect(await adapter.removeAttachmentBlocks({'remove-me'}), true);
    expect(adapter.editor.undoManager.undoStack.isEmpty, true);
    expect(adapter.editor.undoManager.redoStack.isEmpty, true);
    adapter.editor.undoManager.undo();
    expect(adapter.document!.plainText, 'body!');
    expect(adapter.document!.attachmentReferenceIds, isEmpty);
  });

  test('clears stale undo history when the File is already absent', () async {
    final adapter = create(
      NoteDocument([
        file('pending', 'remove-me'),
        DocumentBlock(
          id: 'text',
          kind: DocumentBlockKind.paragraph,
          runs: const [DocumentText('body')],
        ),
      ], inlineAttachments: true),
    );
    final fileNode = adapter.editor.document.root.children.first;
    await adapter.editor.apply(
      adapter.editor.transaction..deleteNodes([fileNode]),
    );
    expect(adapter.document!.referencesAttachment('remove-me'), false);
    expect(adapter.editor.undoManager.undoStack.isNonEmpty, true);

    expect(await adapter.removeAttachmentBlocks({'remove-me'}), true);

    expect(adapter.editor.undoManager.undoStack.isEmpty, true);
    adapter.editor.undoManager.undo();
    expect(adapter.document!.referencesAttachment('remove-me'), false);
  });

  test('shifts a caret by all removed siblings using its original path', () async {
    final adapter = create(
      NoteDocument([
        DocumentBlock(
          id: 'toggle',
          kind: DocumentBlockKind.toggle,
          children: [
            file('remove-1', 'remove-me'),
            DocumentBlock(
              id: 'keep-1',
              kind: DocumentBlockKind.paragraph,
              runs: const [DocumentText('first')],
            ),
            file('remove-2', 'remove-me'),
            DocumentBlock(
              id: 'keep-2',
              kind: DocumentBlockKind.paragraph,
              runs: const [DocumentText('second')],
            ),
            DocumentBlock(
              id: 'caret-target',
              kind: DocumentBlockKind.paragraph,
              runs: const [DocumentText('caret target')],
            ),
          ],
        ),
      ], inlineAttachments: true),
    );
    adapter.editor.selection = engine.Selection.collapsed(
      engine.Position(path: [0, 4], offset: 3),
    );

    expect(await adapter.removeAttachmentBlocks({'remove-me'}), true);

    expect(adapter.editor.selection!.start.path, [0, 2]);
    expect(adapter.editor.selection!.start.offset, 3);
  });

  test(
    'leaves an editable virtual paragraph when the last File is removed',
    () async {
      final adapter = create(
        NoteDocument(
          [file('only-file', 'remove-me')],
          inlineAttachments: true,
        ),
      );

      expect(await adapter.removeAttachmentBlocks({'remove-me'}), true);

      expect(adapter.document!.blocks, isEmpty);
      expect(adapter.editor.document.root.children, hasLength(1));
      expect(adapter.editor.document.root.children.single.type, 'paragraph');
      expect(adapter.editor.selection!.start.path, [0]);
      expect(adapter.editor.selection!.start.offset, 0);
    },
  );

  test('does not mutate a viewer or stale editor', () async {
    var live = true;
    final adapter = RichEditorAdapter(
      document: NoteDocument([file('file', 'remove-me')], inlineAttachments: true),
      legacyText: '',
      canEdit: () => false,
      isLive: () => live,
      accessGeneration: () => 1,
      onChanged: () {},
    );
    addTearDown(adapter.dispose);
    expect(await adapter.removeAttachmentBlocks({'remove-me'}), false);
    expect(adapter.document!.referencesAttachment('remove-me'), true);
    live = false;
    expect(await adapter.removeAttachmentBlocks({'remove-me'}), false);
    expect(adapter.document!.referencesAttachment('remove-me'), true);
  });
}
