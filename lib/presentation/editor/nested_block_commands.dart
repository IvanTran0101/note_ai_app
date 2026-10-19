import 'package:appflowy_editor/appflowy_editor.dart' as engine;

import 'rich_editor_adapter.dart';

/// Add a same-note child block using the engine's structural transaction/history.
final class NestedBlockCommands {
  const NestedBlockCommands(this.adapter);
  final RichEditorAdapter adapter;
  Future<bool> addChild(engine.Node parent) async {
    if (!adapter.editable ||
        !const ['m09_toggle', 'm09_callout'].contains(parent.type) ||
        !identical(adapter.editor.document.nodeAtPath(parent.path), parent)) {
      return false;
    }
    adapter.editor.selection ??= engine.Selection.collapsed(
      engine.Position(path: parent.path, offset: parent.delta?.length ?? 0),
    );
    final snapshot = adapter.capture(range: false);
    if (snapshot == null) return false;
    final path = [...parent.path, parent.children.length];
    adapter.expandedToggles[parent.attributes['m09_id'] as String] = true;
    final transaction = adapter.editor.transaction
      ..insertNode(path, engine.paragraphNode());
    transaction.afterSelection = engine.Selection.collapsed(
      engine.Position(path: path, offset: 0),
    );
    return adapter.apply(transaction, snapshot);
  }
}
