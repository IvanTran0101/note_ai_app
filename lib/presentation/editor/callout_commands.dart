import 'package:appflowy_editor/appflowy_editor.dart' as engine;

import '../../domain/notes/note_document.dart';
import 'rich_editor_adapter.dart';

/// Callout metadata uses the same guarded transaction/history as its text.
final class CalloutCommands {
  const CalloutCommands(this.adapter);
  final RichEditorAdapter adapter;

  RichSelectionSnapshot? capture(engine.Node node) {
    if (!adapter.editable ||
        adapter.composing ||
        node.type != 'm09_callout' ||
        !identical(adapter.editor.document.nodeAtPath(node.path), node)) {
      return null;
    }
    adapter.editor.selection = engine.Selection.collapsed(
      engine.Position(path: node.path, offset: 0),
    );
    return adapter.capture(range: false);
  }

  Future<bool> change(
    engine.Node node,
    RichSelectionSnapshot snapshot, {
    required String icon,
    required DocumentColor tone,
  }) {
    DocumentBlock(
      id: node.attributes['m09_id'] as String,
      kind: DocumentBlockKind.callout,
      icon: icon,
      tone: tone,
    );
    if (!adapter.accepts(snapshot, popupOwnsFocus: true) ||
        !identical(adapter.editor.document.nodeAtPath(node.path), node)) {
      return Future.value(false);
    }
    final transaction = adapter.editor.transaction
      ..updateNode(node, {'m09_icon': icon, 'm09_tone': tone.name});
    transaction.afterSelection = snapshot.selection;
    return adapter.apply(transaction, snapshot, popupOwnsFocus: true);
  }
}
