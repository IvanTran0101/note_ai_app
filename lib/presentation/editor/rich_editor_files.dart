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

  /// Applies a canonical attachment removal to the live editor without
  /// replacing any newer text or formatting draft. The File removal is not
  /// undoable because Application already removed its canonical reference.
  Future<bool> removeAttachmentBlocks(Iterable<String> attachmentIds) async {
    if (!editable) return false;
    // A successful canonical removal must eventually clear the visible File
    // reference. Wait for the active IME transaction rather than leaving a
    // tombstone in the editor or applying a structural edit during composition.
    while (composing) {
      if (!editable) return false;
      await Future<void>.delayed(const Duration(milliseconds: 32));
    }
    if (!editable) return false;
    final ids = attachmentIds.toSet();
    if (ids.isEmpty) return true;
    void clearHistory() {
      editor.undoManager.undoStack.clear();
      editor.undoManager.redoStack.clear();
    }

    final targets = <engine.Node>[];
    void visit(engine.Node node) {
      if (node.type == 'm09_file' &&
          ids.contains(node.attributes['m09_attachment_id'])) {
        targets.add(node);
        return;
      }
      for (final child in node.children) {
        visit(child);
      }
    }

    final root = editor.document.root;
    for (final child in root.children) {
      visit(child);
    }
    if (targets.isEmpty) {
      // A prior undo record may restore a File block that is already absent
      // from the current document. The canonical removal makes that history
      // stale even when the live tree needs no structural edit.
      clearHistory();
      return true;
    }

    int comparePathDescending(engine.Node left, engine.Node right) {
      final a = left.path, b = right.path;
      for (var i = 0; i < a.length && i < b.length; i++) {
        if (a[i] != b[i]) return b[i].compareTo(a[i]);
      }
      return b.length.compareTo(a.length);
    }

    targets.sort(comparePathDescending);
    final paths = targets.map((node) => List<int>.of(node.path)).toList();
    bool isWithin(List<int> path, List<int> ancestor) =>
        path.length >= ancestor.length &&
        listEquals(path.take(ancestor.length).toList(), ancestor);
    final before = editor.selection;
    engine.Selection? after = before;
    if (before != null &&
        paths.any(
          (path) =>
              isWithin(before.start.path, path) ||
              isWithin(before.end.path, path),
        )) {
      after = null;
    } else if (before != null) {
      engine.Position shift(engine.Position position) {
        final original = position.path;
        final path = List<int>.of(original);
        for (var depth = 0; depth < original.length; depth++) {
          final parent = original.take(depth).toList();
          final index = original[depth];
          final removedBefore = paths.where((removed) {
            return removed.length == depth + 1 &&
                removed[depth] < index &&
                listEquals(removed.take(depth).toList(), parent);
          }).length;
          path[depth] = index - removedBefore;
        }
        return position.copyWith(path: path);
      }

      after = engine.Selection(
        start: shift(before.start),
        end: shift(before.end),
      );
    }

    final removesEveryRootChild =
        root.children.isNotEmpty &&
        root.children.every(
          (child) => targets.any((target) => identical(target, child)),
        );
    final transaction = editor.transaction..beforeSelection = before;
    transaction.deleteNodes(targets);
    if (removesEveryRootChild) {
      final empty = engine.paragraphNode();
      empty.updateAttributes({
        ...empty.attributes,
        RichDocumentCodec.identity: 'empty-document',
        RichDocumentCodec.virtual: true,
      });
      transaction.insertNodes([0], [empty]);
      after = engine.Selection.collapsed(
        engine.Position(path: [0], offset: 0),
      );
    }
    transaction.afterSelection = after;

    await editor.apply(
      transaction,
      options: const engine.ApplyOptions(recordUndo: false, recordRedo: false),
      skipHistoryDebounce: true,
    );
    if (!editable) return false;

    final remaining = RichDocumentCodec.decode(editor.document);
    if (ids.any(remaining.referencesAttachment)) return false;

    // The structural delete shifts paths in prior operations. The editor
    // engine cannot rebase its old undo/redo records, and undoing a prior File
    // insertion could restore a reference whose binary is already gone. Start
    // a clean history segment after this irreversible canonical mutation.
    clearHistory();
    return true;
  }
}
