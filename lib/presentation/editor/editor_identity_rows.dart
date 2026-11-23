part of 'editor_identity_normalizer.dart';

/// Existing cells anchor row identity across inserted/deleted rows/columns.
/// A copied row/table receives fresh IDs; moves/conversions/undo reuse retired IDs.
List<engine.UpdateOperation> _normalizeRows(
  engine.Document document,
  Map<String, String> previousRows,
  String Function() generate,
) {
  final groups = <List<engine.Node>>[];
  final nodeIds = <String>{};
  void visit(engine.Node node) {
    if (node.attributes[RichDocumentCodec.identity] is String) {
      nodeIds.add(RichDocumentCodec.id(node));
    }
    if (node.type == engine.TableBlockKeys.type) {
      final rows = node.attributes[engine.TableBlockKeys.rowsLen] as int;
      for (var row = 0; row < rows; row++) {
        groups.add(
          node.children
              .where(
                (c) =>
                    c.attributes[engine.TableCellBlockKeys.rowPosition] == row,
              )
              .toList(),
        );
      }
    }
    for (final child in node.children) {
      visit(child);
    }
  }

  visit(document.root);
  final stable = <int, String>{};
  final reserved = <String>{...nodeIds};
  for (var i = 0; i < groups.length; i++) {
    final candidates = {
      for (final cell in groups[i])
        if (previousRows[RichDocumentCodec.id(cell)] case final String id) id,
    };
    if (candidates.length > 1) {
      throw StateError('Ambiguous editor row identity.');
    }
    if (candidates.isNotEmpty) {
      final id = candidates.single;
      if (!reserved.add(id)) throw StateError('Duplicate editor row identity.');
      stable[i] = id;
    }
  }
  final patches = <engine.UpdateOperation>[];
  for (var i = 0; i < groups.length; i++) {
    final cells = groups[i];
    if (cells.isEmpty) throw StateError('Empty editor row.');
    var rowId = stable[i];
    if (rowId == null) {
      final candidate = cells.first.attributes[RichDocumentCodec.rowIdentity];
      rowId = candidate is String && !reserved.contains(candidate)
          ? candidate
          : _freshId(reserved, generate);
      reserved.add(rowId);
    }
    for (final cell in cells) {
      if (cell.attributes[RichDocumentCodec.rowIdentity] == rowId) continue;
      final attributes = {RichDocumentCodec.rowIdentity: rowId};
      patches.add(
        engine.UpdateOperation(cell.path, attributes, {
          RichDocumentCodec.rowIdentity:
              cell.attributes[RichDocumentCodec.rowIdentity],
        }),
      );
      cell.updateAttributes({...cell.attributes, ...attributes});
    }
  }
  return patches;
}
