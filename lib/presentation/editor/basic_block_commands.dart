import 'package:appflowy_editor/appflowy_editor.dart' as engine;

import '../../domain/notes/note_document.dart';
import 'rich_document_codec.dart';
import 'rich_editor_adapter.dart';

final class BasicBlockChoice {
  const BasicBlockChoice(this.label, this.kind, this.alias, {this.level});
  final String label, alias;
  final DocumentBlockKind kind;
  final int? level;
}

const basicBlockChoices = [
  BasicBlockChoice('Text', DocumentBlockKind.paragraph, 'text paragraph'),
  BasicBlockChoice(
    'Heading 1',
    DocumentBlockKind.heading,
    'h1 heading1',
    level: 1,
  ),
  BasicBlockChoice(
    'Heading 2',
    DocumentBlockKind.heading,
    'h2 heading2',
    level: 2,
  ),
  BasicBlockChoice(
    'Heading 3',
    DocumentBlockKind.heading,
    'h3 heading3',
    level: 3,
  ),
  BasicBlockChoice(
    'Heading 4',
    DocumentBlockKind.heading,
    'h4 heading4',
    level: 4,
  ),
  BasicBlockChoice(
    'Bulleted list',
    DocumentBlockKind.bulletedList,
    'bullet unordered list',
  ),
  BasicBlockChoice(
    'Numbered list',
    DocumentBlockKind.numberedList,
    'number ordered list',
  ),
  BasicBlockChoice('To-do list', DocumentBlockKind.todo, 'todo task checkbox'),
  BasicBlockChoice('Toggle list', DocumentBlockKind.toggle, 'toggle collapse'),
  BasicBlockChoice('Callout', DocumentBlockKind.callout, 'callout'),
  BasicBlockChoice('Quote', DocumentBlockKind.quote, 'quote'),
  BasicBlockChoice('Table', DocumentBlockKind.table, 'table'),
  BasicBlockChoice('Divider', DocumentBlockKind.divider, 'divider rule'),
];

/// Business block conversions use public Delta/Transaction operations.
final class BasicBlockCommands {
  const BasicBlockCommands(this.adapter);
  final RichEditorAdapter adapter;
  bool inCell(engine.Node node) {
    for (var parent = node.parent; parent != null; parent = parent.parent) {
      if (parent.type == engine.TableCellBlockKeys.type) return true;
    }
    return false;
  }

  Future<bool> choose(
    BasicBlockChoice choice,
    RichSelectionSnapshot snapshot, {
    int? slashStart,
    bool popupOwnsFocus = false,
  }) async {
    if (!adapter.accepts(snapshot, popupOwnsFocus: popupOwnsFocus)) {
      return false;
    }
    final selection = snapshot.selection.normalized;
    final node = adapter.editor.document.nodeAtPath(selection.start.path);
    if (node == null || inCell(node) || node.delta == null) return false;
    if (choice.kind == DocumentBlockKind.table ||
        choice.kind == DocumentBlockKind.divider) {
      return _insertStructural(
        choice,
        node,
        snapshot,
        slashStart,
        popupOwnsFocus,
      );
    }
    final nodes = adapter.editor.getNodesInSelection(selection);
    final transaction = adapter.editor.transaction;
    for (final current in nodes) {
      if (current.delta == null || inCell(current)) continue;
      var delta = current.delta!;
      if (identical(current, node) && slashStart != null) {
        delta = delta.compose(
          engine.Delta()
            ..retain(slashStart)
            ..delete(selection.start.offset - slashStart),
        );
      }
      final attributes = {
        ...current.attributes,
        'delta': delta.toJson(),
        'level': choice.level,
        'checked': choice.kind == DocumentBlockKind.todo
            ? current.attributes['checked'] == true
            : null,
        'm09_icon': choice.kind == DocumentBlockKind.callout
            ? (current.attributes['m09_icon'] ?? '💡')
            : null,
        'm09_tone': choice.kind == DocumentBlockKind.callout
            ? (current.attributes['m09_tone'] ?? DocumentColor.gray.name)
            : null,
      };
      transaction.deleteNode(current);
      // This replacement path is already in sequential coordinates after delete.
      // Transaction.insertNode transforms original paths; applying that again
      // would shift every replacement except the first block to its predecessor.
      transaction.add(
        engine.InsertOperation(current.path, [
          engine.Node(
            type: RichDocumentCodec.types[choice.kind]!,
            attributes: attributes,
            children: current.children.map((n) => n.copyWith()).toList(),
          ),
        ]),
        transform: false,
      );
    }
    transaction.afterSelection = slashStart == null
        ? snapshot.selection
        : engine.Selection.collapsed(
            engine.Position(path: node.path, offset: slashStart),
          );
    return adapter.apply(transaction, snapshot, popupOwnsFocus: popupOwnsFocus);
  }

  Future<bool> _insertStructural(
    BasicBlockChoice choice,
    engine.Node node,
    RichSelectionSnapshot snapshot,
    int? slashStart,
    bool popupOwnsFocus,
  ) {
    final transaction = adapter.editor.transaction;
    if (slashStart != null) {
      transaction.deleteText(
        node,
        slashStart,
        snapshot.selection.start.offset - slashStart,
      );
    }
    final id = adapter.newIdentity();
    final block = choice.kind == DocumentBlockKind.divider
        ? DocumentBlock(id: id, kind: DocumentBlockKind.divider)
        : DocumentBlock(
            id: id,
            kind: DocumentBlockKind.table,
            rows: [
              for (var r = 0; r < 2; r++)
                DocumentRow(
                  id: adapter.newIdentity(),
                  cells: [
                    for (var c = 0; c < 2; c++)
                      DocumentCell(id: adapter.newIdentity(), runs: const []),
                  ],
                ),
            ],
          );
    final path = [...node.path];
    path[path.length - 1]++;
    transaction.insertNode(path, RichDocumentCodec.encodeBlock(block));
    if (choice.kind == DocumentBlockKind.table) {
      transaction.afterSelection = engine.Selection.collapsed(
        engine.Position(path: [...path, 0, 0], offset: 0),
      );
    } else {
      final next = [...path];
      next[next.length - 1]++;
      transaction.add(
        engine.InsertOperation(next, [engine.paragraphNode()]),
        transform: false,
      );
      transaction.afterSelection = engine.Selection.collapsed(
        engine.Position(path: next, offset: 0),
      );
    }
    return adapter.apply(transaction, snapshot, popupOwnsFocus: popupOwnsFocus);
  }
}
