import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';

import 'rich_editor_adapter.dart';

/// The public divider renderer keeps selection/keyboard deletion upstream.
/// This touch action gives the same deletion as one undoable transaction.
Widget dividerControls(
  BuildContext context,
  engine.Node node,
  Widget child,
  RichEditorAdapter adapter,
) => Row(
  children: [
    Expanded(child: child),
    if (adapter.editable)
      IconButton(
        tooltip: 'Delete divider',
        onPressed: () => deleteDivider(adapter, node),
        icon: const Icon(Icons.close, size: 18),
      ),
  ],
);

Future<bool> deleteDivider(RichEditorAdapter adapter, engine.Node node) {
  if (!adapter.editable ||
      adapter.composing ||
      node.type != 'divider' ||
      !identical(adapter.editor.document.nodeAtPath(node.path), node)) {
    return Future.value(false);
  }
  adapter.editor.selection = engine.Selection.collapsed(
    engine.Position(path: node.path, offset: 0),
  );
  final snapshot = adapter.capture(range: false);
  if (snapshot == null) return Future.value(false);
  final transaction = adapter.editor.transaction..deleteNode(node);
  final path = node.path;
  transaction.add(
    engine.InsertOperation(path, [engine.paragraphNode()]),
    transform: false,
  );
  transaction.afterSelection = engine.Selection.collapsed(
    engine.Position(path: path, offset: 0),
  );
  return adapter.apply(transaction, snapshot);
}
