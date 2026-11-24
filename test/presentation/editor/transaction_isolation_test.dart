import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/editor/rich_document_codec.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';

String _composedText(engine.Operation operation) {
  final update = operation as engine.UpdateOperation;
  final delta = engine.Delta.fromJson(
    update.attributes[engine.blockComponentDelta] as List<dynamic>,
  );
  return delta.toPlainText();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cancelling queued text edits', () {
    late engine.Document document;
    late engine.Node node;
    late engine.Transaction transaction;

    setUp(() {
      document = RichDocumentCodec.legacy('abc');
      node = document.root.children.first;
      transaction = engine.Transaction(document: document);
    });
    tearDown(() => document.dispose());

    test('insertText is discarded when operations are replaced', () {
      transaction.insertText(node, 0, 'X', sliceAttributes: false);
      expect(transaction.markNeedsComposing, isTrue);

      transaction.operations = [];

      expect(transaction.markNeedsComposing, isFalse);
      expect(transaction.operations, isEmpty);
      expect(transaction.operations, isEmpty);
      expect(node.delta!.toPlainText(), 'abc');
    });

    test('deleteText is discarded when operations are replaced', () {
      transaction.deleteText(node, 0, 1);
      expect(transaction.markNeedsComposing, isTrue);

      transaction.operations = [];

      expect(transaction.markNeedsComposing, isFalse);
      expect(transaction.operations, isEmpty);
      expect(transaction.operations, isEmpty);
      expect(node.delta!.toPlainText(), 'abc');
    });

    test('formatText is discarded when operations are replaced', () {
      transaction.formatText(node, 0, 1, {'bold': true});
      expect(transaction.markNeedsComposing, isTrue);

      transaction.operations = [];

      expect(transaction.markNeedsComposing, isFalse);
      expect(transaction.operations, isEmpty);
      expect(transaction.operations, isEmpty);
      expect(node.delta!.toPlainText(), 'abc');
    });
  });

  group('transaction isolation', () {
    test('same document keeps independent pending queues', () {
      final document = RichDocumentCodec.legacy('abc');
      addTearDown(document.dispose);
      final node = document.root.children.first;
      final first = engine.Transaction(document: document)
        ..insertText(node, 0, 'A', sliceAttributes: false);
      final second = engine.Transaction(document: document)
        ..insertText(node, 0, 'B', sliceAttributes: false);

      expect(_composedText(first.operations.single), 'Aabc');
      expect(_composedText(second.operations.single), 'Babc');
    });

    test(
      'cancelling one same-document transaction keeps the other pending',
      () {
        final document = RichDocumentCodec.legacy('abc');
        addTearDown(document.dispose);
        final node = document.root.children.first;
        final first = engine.Transaction(document: document)
          ..insertText(node, 0, 'A', sliceAttributes: false);
        final second = engine.Transaction(document: document)
          ..insertText(node, 0, 'B', sliceAttributes: false);

        first.operations = [];

        expect(first.operations, isEmpty);
        expect(_composedText(second.operations.single), 'Babc');
      },
    );

    test('different documents stay isolated', () {
      final firstDocument = RichDocumentCodec.legacy('aaa');
      final secondDocument = RichDocumentCodec.legacy('bbb');
      addTearDown(firstDocument.dispose);
      addTearDown(secondDocument.dispose);
      final first = engine.Transaction(document: firstDocument)
        ..insertText(
          firstDocument.root.children.first,
          0,
          'A',
          sliceAttributes: false,
        );
      final second = engine.Transaction(document: secondDocument)
        ..insertText(
          secondDocument.root.children.first,
          0,
          'B',
          sliceAttributes: false,
        );

      expect(_composedText(first.operations.single), 'Aaaa');
      expect(_composedText(second.operations.single), 'Bbbb');
    });

    test('different editors stay isolated', () {
      final firstEditor = engine.EditorState(
        document: RichDocumentCodec.legacy('aaa'),
      );
      final secondEditor = engine.EditorState(
        document: RichDocumentCodec.legacy('bbb'),
      );
      addTearDown(firstEditor.dispose);
      addTearDown(secondEditor.dispose);
      final first = firstEditor.transaction
        ..insertText(
          firstEditor.document.root.children.first,
          0,
          'A',
          sliceAttributes: false,
        );
      final second = secondEditor.transaction
        ..insertText(
          secondEditor.document.root.children.first,
          0,
          'B',
          sliceAttributes: false,
        );

      expect(_composedText(first.operations.single), 'Aaaa');
      expect(_composedText(second.operations.single), 'Bbbb');
    });

    test('repeated compose and getter calls do not duplicate operations', () {
      final document = RichDocumentCodec.legacy('abc');
      addTearDown(document.dispose);
      final transaction = engine.Transaction(document: document)
        ..insertText(
          document.root.children.first,
          0,
          'X',
          sliceAttributes: false,
        );

      final first = List<engine.Operation>.of(transaction.operations);
      final second = List<engine.Operation>.of(transaction.operations);
      transaction.compose();
      transaction.compose();
      final third = List<engine.Operation>.of(transaction.operations);

      expect(first, hasLength(1));
      expect(second, hasLength(1));
      expect(third, hasLength(1));
      expect(third.single.toJson(), first.single.toJson());
      expect(_composedText(third.single), 'Xabc');
    });

    test('repeated compose after cancellation does not resurrect edits', () {
      final document = RichDocumentCodec.legacy('abc');
      addTearDown(document.dispose);
      final transaction = engine.Transaction(document: document)
        ..insertText(
          document.root.children.first,
          0,
          'X',
          sliceAttributes: false,
        );

      transaction.operations = [];
      transaction.compose();
      expect(transaction.operations, isEmpty);
      transaction.compose();
      expect(transaction.operations, isEmpty);
    });

    test(
      'assigning a captured operations list stays safe and cancels pending',
      () {
        final document = RichDocumentCodec.legacy('abc');
        addTearDown(document.dispose);
        final node = document.root.children.first;
        final transaction = engine.Transaction(document: document)
          ..insertText(node, 0, 'X', sliceAttributes: false);
        final captured = transaction.operations;
        expect(captured, hasLength(1));

        // Replacing with the same list instance must still discard newer edits.
        transaction.insertText(node, 0, 'Y', sliceAttributes: false);
        expect(transaction.markNeedsComposing, isTrue);

        transaction.operations = captured;

        expect(transaction.markNeedsComposing, isFalse);
        expect(transaction.operations, hasLength(1));
        expect(_composedText(transaction.operations.single), 'Xabc');
      },
    );
  });

  group('production adapter guard', () {
    test(
      'canEdit revoked immediately before apply drops queued text silently',
      () async {
        var canEdit = true;
        var changed = 0;
        final adapter = RichEditorAdapter(
          document: null,
          legacyText: 'abc',
          canEdit: () => canEdit,
          isLive: () => true,
          accessGeneration: () => 1,
          onChanged: () => changed++,
        );
        addTearDown(adapter.dispose);

        final transaction = adapter.editor.transaction
          ..insertText(
            adapter.editor.document.root.children.first,
            0,
            'X',
            sliceAttributes: false,
          );

        // Keep EditorState.editable true so the before-transaction guard, not
        // the early return in EditorState.apply, has to cancel the edit.
        canEdit = false;
        expect(adapter.editor.editable, isTrue);
        await adapter.editor.apply(transaction, withUpdateSelection: false);

        expect(
          adapter.editor.document.root.children.first.delta!.toPlainText(),
          'abc',
        );
        expect(adapter.plainText, 'abc');
        expect(changed, 0);
        expect(adapter.editor.undoManager.undoStack.isEmpty, isTrue);
        expect(adapter.editor.undoManager.redoStack.isEmpty, isTrue);
      },
    );

    test('refused format leaves empty undo and redo stacks', () async {
      var canEdit = true;
      final adapter = RichEditorAdapter(
        document: null,
        legacyText: 'abc',
        canEdit: () => canEdit,
        isLive: () => true,
        accessGeneration: () => 1,
        onChanged: () {},
      );
      addTearDown(adapter.dispose);

      canEdit = false;
      final node = adapter.editor.document.root.children.first;
      final transaction = adapter.editor.transaction
        ..formatText(node, 0, 1, {'bold': true});
      await adapter.editor.apply(transaction, withUpdateSelection: false);

      expect(node.delta!.toPlainText(), 'abc');
      expect(node.delta!.first.attributes?['bold'], isNull);
      expect(adapter.editor.undoManager.undoStack.isEmpty, isTrue);
      expect(adapter.editor.undoManager.redoStack.isEmpty, isTrue);
    });

    test(
      'guard-refused edit preserves redo history across revoked access',
      () async {
        var canEdit = true;
        final adapter = RichEditorAdapter(
          document: null,
          legacyText: 'abc',
          canEdit: () => canEdit,
          isLive: () => true,
          accessGeneration: () => 1,
          onChanged: () {},
        );
        addTearDown(adapter.dispose);
        final editor = adapter.editor;

        String text() =>
            editor.document.root.children.first.delta!.toPlainText();

        Future<void> edit(String value) => editor.apply(
          editor.transaction..insertText(
            editor.document.root.children.first,
            0,
            value,
            sliceAttributes: false,
          ),
          withUpdateSelection: false,
          skipHistoryDebounce: true,
        );

        await edit('A');
        await edit('B');
        expect(text(), 'BAabc');

        editor.undoManager.undo();
        expect(text(), 'Aabc');
        expect(editor.undoManager.redoStack.isNonEmpty, isTrue);
        final preservedUndo = editor.undoManager.undoStack.last;

        canEdit = false;
        await editor.apply(
          editor.transaction..insertText(
            editor.document.root.children.first,
            0,
            'X',
            sliceAttributes: false,
          ),
          withUpdateSelection: false,
        );

        expect(text(), 'Aabc');
        expect(editor.undoManager.undoStack.last, same(preservedUndo));
        expect(editor.undoManager.redoStack.isNonEmpty, isTrue);

        canEdit = true;
        adapter.refreshAccess();
        expect(editor.editable, isTrue);

        editor.undoManager.redo();
        expect(text(), 'BAabc');
        expect(editor.undoManager.redoStack.isEmpty, isTrue);
      },
    );
  });
}
