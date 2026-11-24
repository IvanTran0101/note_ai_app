import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/editor_identity_normalizer.dart';
import 'package:note_ai_app/presentation/editor/rich_document_codec.dart';

import '../../domain/notes/m09_document_fixtures.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  engine.EditorState create(NoteDocument doc, {void Function()? reject}) {
    final state = engine.EditorState(document: RichDocumentCodec.encode(doc));
    var next = 0;
    final normalizer = EditorIdentityNormalizer(
      state,
      onRejected: reject ?? () {},
      generateId: () => 'new-${++next}',
    );
    addTearDown(() {
      normalizer.dispose();
      state.dispose();
    });
    return state;
  }

  final text = NoteDocument([fixture.block('p', text: 'Text')]);

  test('copy gets a fresh stable ID in the original history and undo/redo reuses it', () async {
    final state = create(text);
    final transaction = state.transaction
      ..insertNode([1], state.document.root.children.first);
    await state.apply(
      transaction,
      withUpdateSelection: false,
      skipHistoryDebounce: true,
    );
    final copied = RichDocumentCodec.decode(state.document);
    expect(copied.blocks.first.id, 'p');
    expect(copied.blocks.last.id, isNot('p'));
    final id = copied.blocks.last.id;
    state.undoManager.undo();
    expect(RichDocumentCodec.decode(state.document), text);
    state.undoManager.redo();
    expect(RichDocumentCodec.decode(state.document).blocks.last.id, id);
  });
  test('delete/convert retains retired identity and the exact text', () async {
    final state = create(text);
    final old = state.document.root.children.first;
    final heading = engine.Node(
      type: 'heading',
      attributes: {...old.attributes, 'level': 4},
    );
    final transaction = state.transaction
      ..deleteNode(old)
      ..insertNode([0], heading);
    await state.apply(
      transaction,
      withUpdateSelection: false,
      skipHistoryDebounce: true,
    );
    final converted = RichDocumentCodec.decode(state.document).blocks.single;
    expect(converted.id, 'p');
    expect(converted.level, 4);
    expect(converted.plainText, 'Text');
  });
  test(
    'copied table has distinct row/cell IDs; original grid stays intact',
    () async {
      final original = NoteDocument([fixture.table('table')]);
      final state = create(original);
      await state.apply(
        state.transaction..insertNode([1], state.document.root.children.first),
        withUpdateSelection: false,
        skipHistoryDebounce: true,
      );
      final copied = RichDocumentCodec.decode(state.document);
      expect(copied.blocks.first, original.blocks.single);
      final other = copied.blocks.last;
      expect(other.id, isNot('table'));
      expect(other.rows.first.id, isNot(original.blocks.single.rows.first.id));
      expect(
        other.rows.first.cells.first.id,
        isNot(original.blocks.single.rows.first.cells.first.id),
      );
      expect(other.plainText, original.plainText);
    },
  );
  test('ordinary typing does not inherit equation metadata', () async {
    final doc = NoteDocument([
      DocumentBlock(
        id: 'p',
        kind: DocumentBlockKind.paragraph,
        runs: [DocumentMath('x')],
      ),
    ]);
    final state = create(doc);
    const input = ' Việt 📝';
    final transaction = state.transaction;
    transaction.add(
      engine.UpdateTextOperation(
        [0],
        engine.Delta()
          ..retain(1)
          ..insert(input, attributes: {'m09_math': 'x'}),
        engine.Delta()
          ..retain(1)
          ..delete(input.length),
      ),
    );
    await state.apply(transaction, withUpdateSelection: false);
    final result = RichDocumentCodec.decode(state.document);
    expect(result.plainText, 'x Việt 📝');
    expect(result.blocks.single.runs.first, DocumentMath('x'));
  });
  test('invalid moved data refuses without changing the live tree', () async {
    var rejected = 0;
    final state = create(text, reject: () => rejected++);
    final old = state.document.root.children.first;
    final transaction = state.transaction
      ..moveNode([0], old)
      ..insertNode([1], engine.Node(type: 'page'));
    await state.apply(transaction, withUpdateSelection: false);
    expect(rejected, 1);
    expect(RichDocumentCodec.decode(state.document), text);
  });
}
