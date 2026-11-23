import 'package:appflowy_editor/appflowy_editor.dart' as engine;

import 'rich_document_codec.dart';
import 'rich_editor_adapter.dart';
import 'table_grid_edit.dart';
export 'table_grid_edit.dart' show TableChange;

/// Locate/commit table changes through the existing engine transaction owner.
final class TableCommands {
  const TableCommands(this.adapter);
  final RichEditorAdapter adapter;
  engine.Node? tableAt(RichSelectionSnapshot snapshot) {
    var node = adapter.editor.document.nodeAtPath(
      snapshot.selection.start.path,
    );
    while (node != null && node.type != 'table') {
      node = node.parent;
    }
    return node;
  }

  Future<bool> change(
    TableChange change,
    RichSelectionSnapshot snapshot, {
    bool popupOwnsFocus = false,
  }) async {
    if (!adapter.accepts(snapshot, popupOwnsFocus: popupOwnsFocus)) {
      return false;
    }
    final node = tableAt(snapshot);
    if (node == null) return false;
    if (change == TableChange.paragraphAfter) {
      return adapter.apply(
        _paragraphAfter(node),
        snapshot,
        popupOwnsFocus: popupOwnsFocus,
      );
    }
    final block = RichDocumentCodec.decode(
      engine.Document(
        root: engine.pageNode(children: [engine.Node.fromJson(node.toJson())]),
      ),
    ).blocks.single;
    var cell = adapter.editor.document.nodeAtPath(
      snapshot.selection.start.path,
    );
    while (cell != null && cell.parent != node) {
      cell = cell.parent;
    }
    final edit = TableGridEdit(
      block,
      (cell?.attributes['rowPosition'] as int?) ?? 0,
      (cell?.attributes['colPosition'] as int?) ?? 0,
      adapter.newIdentity,
    );
    if (!edit.apply(change)) return false;
    return adapter.apply(
      _replace(
        node,
        RichDocumentCodec.encodeBlock(edit.result(change)),
        row: edit.row,
        column: edit.column,
      ),
      snapshot,
      popupOwnsFocus: popupOwnsFocus,
    );
  }

  engine.Transaction _paragraphAfter(engine.Node node) {
    final path = [...node.path];
    path[path.length - 1]++;
    return adapter.editor.transaction
      ..insertNode(path, engine.paragraphNode())
      ..afterSelection = engine.Selection.collapsed(
        engine.Position(path: path, offset: 0),
      );
  }

  engine.Transaction _replace(
    engine.Node node,
    engine.Node replacement, {
    required int row,
    required int column,
  }) {
    final next = replacement.children.indexWhere(
      (cell) =>
          cell.attributes['rowPosition'] == row &&
          cell.attributes['colPosition'] == column,
    );
    return adapter.editor.transaction
      ..deleteNode(node)
      ..add(engine.InsertOperation(node.path, [replacement]), transform: false)
      ..afterSelection = engine.Selection.collapsed(
        engine.Position(path: [...node.path, next, 0], offset: 0),
      );
  }
}
