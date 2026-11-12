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
    // Notion inserts a newly added toggle child before the existing children.
    // Callout's existing trailing action keeps appending to its children.
    final childIndex = parent.type == 'm09_toggle' ? 0 : parent.children.length;
    final path = [...parent.path, childIndex];
    final id = parent.attributes['m09_id'] as String;
    final previousExpansion = adapter.expandedToggles[id];
    adapter.expandedToggles[id] = true;
    final transaction = adapter.editor.transaction
      ..insertNode(path, engine.paragraphNode());
    transaction.afterSelection = engine.Selection.collapsed(
      engine.Position(path: path, offset: 0),
    );
    final applied = await adapter.apply(transaction, snapshot);
    if (!applied) {
      if (previousExpansion == null) {
        adapter.expandedToggles.remove(id);
      } else {
        adapter.expandedToggles[id] = previousExpansion;
      }
    }
    return applied;
  }
}
