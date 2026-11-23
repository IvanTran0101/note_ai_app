import 'package:appflowy_editor/appflowy_editor.dart' as engine;

import '../../domain/notes/note_document.dart';
import 'rich_editor_adapter.dart';

/// Equations are atomic inline content; the upstream engine owns selection/history.
final class EquationCommands {
  const EquationCommands(this.adapter);
  final RichEditorAdapter adapter;
  String? initialExpression(RichSelectionSnapshot snapshot) {
    final selection = snapshot.selection.normalized;
    if (!selection.isSingle) return null;
    final node = adapter.editor.document.nodeAtPath(selection.start.path);
    final delta = node?.delta;
    if (delta == null) return null;
    final operations = delta
        .slice(selection.start.offset, selection.end.offset)
        .toList();
    if (operations.length == 1 &&
        operations.first.attributes?['m09_math'] is String) {
      return operations.first.attributes!['m09_math'] as String;
    }
    return delta.toPlainText().substring(
      selection.start.offset,
      selection.end.offset,
    );
  }

  Future<bool> convertToText(RichSelectionSnapshot snapshot) async {
    if (!adapter.accepts(snapshot) || !snapshot.selection.isSingle) {
      return false;
    }
    final selection = snapshot.selection.normalized;
    final node = adapter.editor.document.nodeAtPath(selection.start.path);
    if (node?.delta == null) return false;
    final selected = node!.delta!.slice(
      selection.start.offset,
      selection.end.offset,
    );
    if (selected.isEmpty ||
        selected.any((op) => op.attributes?['m09_math'] == null)) {
      return false;
    }
    final delta = engine.Delta()
      ..retain(selection.start.offset)
      ..delete(selection.end.offset - selection.start.offset);
    var length = 0;
    for (final op in selected) {
      final attrs = {...?op.attributes}..remove('m09_math');
      for (var i = 0; i < op.length; i++) {
        delta.insert(op.attributes!['m09_math'] as String, attributes: attrs);
        length += (op.attributes!['m09_math'] as String).length;
      }
    }
    final transaction = adapter.editor.transaction;
    transaction.updateNode(node, {
      'delta': node.delta!.compose(delta).toJson(),
    });
    transaction.afterSelection = engine.Selection.single(
      path: node.path,
      startOffset: selection.start.offset,
      endOffset: selection.start.offset + length,
    );
    return adapter.apply(transaction, snapshot);
  }

  Future<bool> replace(
    RichSelectionSnapshot snapshot,
    String expression, {
    bool popupOwnsFocus = false,
  }) async {
    DocumentMath(expression);
    if (!adapter.accepts(snapshot, popupOwnsFocus: popupOwnsFocus)) {
      return false;
    }
    final selection = snapshot.selection.normalized;
    if (!selection.isSingle) return false;
    final node = adapter.editor.document.nodeAtPath(selection.start.path);
    if (node?.delta == null) return false;
    final selected = node!.delta!.slice(
      selection.start.offset,
      selection.end.offset,
    );
    final attributes = {
      ...?(selected.firstOrNull?.attributes ??
          node.delta!.sliceAttributes(selection.start.offset)),
      'href': null,
      'code': null,
      'm09_math': expression,
    };
    final transaction = adapter.editor.transaction;
    transaction.deleteText(
      node,
      selection.start.offset,
      selection.end.offset - selection.start.offset,
    );
    transaction.insertText(
      node,
      selection.start.offset,
      '\uFFFC',
      attributes: attributes,
      sliceAttributes: false,
    );
    transaction.afterSelection = engine.Selection.single(
      path: node.path,
      startOffset: selection.start.offset,
      endOffset: selection.start.offset + 1,
    );
    return adapter.apply(transaction, snapshot, popupOwnsFocus: popupOwnsFocus);
  }
}
