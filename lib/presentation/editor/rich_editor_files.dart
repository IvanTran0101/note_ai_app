part of 'rich_editor_adapter.dart';

/// Associates already staged canonical files with an existing visual block.
/// No bytes, filename or second persistence writer enter the document.
extension RichEditorFiles on RichEditorAdapter {
  engine.Node? fileBlock(String blockId) {
    engine.Node? find(engine.Node node) {
      if (node.type == 'm09_file' &&
          node.attributes[RichDocumentCodec.identity] == blockId) {
        return node;
      }
      for (final child in node.children) {
        final result = find(child);
        if (result != null) return result;
      }
      return null;
    }

    return find(editor.document.root);
  }

  Future<bool> bindFiles(String blockId, List<String> attachmentIds) async {
    if (!editable || composing || attachmentIds.isEmpty) return false;
    final node = fileBlock(blockId);
    if (node == null || node.attributes['m09_attachment_id'] != null) {
      return false;
    }
    final ids = attachmentIds.toSet().toList();
    for (final id in ids) {
      try {
        requireDocumentId(id);
      } on Object {
        return false;
      }
    }
    final previous = editor.selection;
    editor.selection ??= engine.Selection.collapsed(
      engine.Position(path: node.path, offset: 0),
    );
    final snapshot = capture(range: false);
    if (snapshot == null) return false;
    final transaction = editor.transaction;
    transaction.updateNode(node, {'m09_attachment_id': ids.first});
    if (ids.length > 1) {
      final path = List<int>.of(node.path);
      path[path.length - 1]++;
      transaction.insertNodes(path, [
        for (final id in ids.skip(1))
          engine.Node(
            type: 'm09_file',
            attributes: {
              RichDocumentCodec.identity: newIdentity(),
              'm09_attachment_id': id,
            },
          ),
      ]);
    }
    final selection = previous ?? snapshot.selection;
    engine.Position shifted(engine.Position position) {
      final path = List<int>.of(position.path), anchor = node.path;
      if (ids.length > 1 &&
          path.length >= anchor.length &&
          listEquals(
            path.take(anchor.length - 1).toList(),
            anchor.take(anchor.length - 1).toList(),
          ) &&
          path[anchor.length - 1] > anchor.last) {
        path[anchor.length - 1] += ids.length - 1;
      }
      return position.copyWith(path: path);
    }

    transaction.afterSelection = engine.Selection(
      start: shifted(selection.start),
      end: shifted(selection.end),
    );
    return apply(transaction, snapshot);
  }
}
