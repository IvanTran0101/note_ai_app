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

/// Media choices stay in the slash/block picker without changing the thirteen
/// existing Basic blocks.
const mediaBlockChoices = [
  BasicBlockChoice(
    'File',
    DocumentBlockKind.attachment,
    'file attachment tep tin dinh kem',
  ),
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
    if (choice.kind == DocumentBlockKind.attachment) {
      return _insertFile(node, snapshot, slashStart, popupOwnsFocus);
    }
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

  Future<bool> _insertFile(
    engine.Node node,
    RichSelectionSnapshot snapshot,
    int? slashStart,
    bool popupOwnsFocus,
  ) async {
    final selection = snapshot.selection.normalized;
    if (!selection.isCollapsed || node.delta == null) return false;
    final caret = selection.start.offset;
    final delta = node.delta!;
    final length = delta.length;
    final start = slashStart ?? caret;
    if (start < 0 || start > caret || caret > length) return false;

    // Keep the original styled Delta on both sides of the insertion. In a
    // slash command the command text itself is consumed; any following text is
    // moved into a paragraph after the File block.
    final prefixContent = delta.slice(0, start);
    final before = engine.Delta()..addAll(prefixContent);
    final after = delta.slice(caret, length);
    final hasPrefix = prefixContent.isNotEmpty;
    final hasSuffix = after.isNotEmpty;
    final blockId = adapter.newIdentity();
    final file = RichDocumentCodec.encodeBlock(
      DocumentBlock(id: blockId, kind: DocumentBlockKind.attachment),
    );
    final trailingDelta = hasSuffix ? after : engine.Delta();
    final trailing = engine.paragraphNode(delta: trailingDelta);
    final transaction = adapter.editor.transaction;
    final preserveCurrentNode = hasPrefix || node.children.isNotEmpty;
    late final List<int> trailingPath;

    if (preserveCurrentNode) {
      final edit = delta.diff(before);
      transaction.add(
        engine.UpdateTextOperation(node.path, edit, edit.invert(delta)),
      );
      final insertionPath = [...node.path];
      insertionPath[insertionPath.length - 1]++;
      transaction.insertNodes(insertionPath, [file, trailing]);
      trailingPath = [...insertionPath];
      trailingPath[trailingPath.length - 1]++;
      transaction.afterSelection = engine.Selection.collapsed(
        engine.Position(path: trailingPath, offset: 0),
      );
    } else {
      // Replacing an empty prefix avoids leaving a visually empty text block
      // before the newly inserted File block.
      transaction.deleteNode(node);
      transaction.add(
        engine.InsertOperation(node.path, [file, trailing]),
        transform: false,
      );
      trailingPath = [...node.path];
      trailingPath[trailingPath.length - 1]++;
      transaction.afterSelection = engine.Selection.collapsed(
        engine.Position(path: trailingPath, offset: 0),
      );
    }

    final document = adapter.editor.document;
    if (document.root.attributes['m09_inline_attachments'] != true) {
      transaction.updateNode(document.root, {'m09_inline_attachments': true});
      // Import the old attachment list only when enabling inline File blocks.
      // Once inline mode is active, legacy IDs may include refs whose File
      // blocks were intentionally deleted and must not be resurrected.
      final presentIds = <String>{};
      void visit(engine.Node current) {
        final attachmentId = current.attributes['m09_attachment_id'];
        if (attachmentId is String) presentIds.add(attachmentId);
        for (final child in current.children) {
          visit(child);
        }
      }

      visit(document.root);
      final legacyNodes = [
        for (final attachmentId in adapter.legacyAttachmentIds)
          if (presentIds.add(attachmentId))
            RichDocumentCodec.encodeBlock(
              DocumentBlock(
                id: adapter.newIdentity(),
                kind: DocumentBlockKind.attachment,
                attachmentId: attachmentId,
              ),
            ),
      ];
      if (legacyNodes.isNotEmpty) {
        transaction.insertNodes([document.root.children.length], legacyNodes);
      }
    }

    final applied = await adapter.apply(
      transaction,
      snapshot,
      popupOwnsFocus: popupOwnsFocus,
    );
    if (applied) adapter.onFileInserted?.call(blockId);
    return applied;
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
