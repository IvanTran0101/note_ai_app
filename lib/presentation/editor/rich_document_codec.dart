import 'package:appflowy_editor/appflowy_editor.dart' as engine;

import '../../domain/notes/note_document.dart';
import 'rich_inline_codec.dart';

part 'rich_document_table.dart';

/// Pure boundary conversion. Editor JSON is never a persistence contract.
abstract final class RichDocumentCodec {
  static const identity = 'm09_id';
  static const rowIdentity = 'm09_row_id';
  static const virtual = 'm09_virtual';
  static const types = {
    DocumentBlockKind.paragraph: 'paragraph',
    DocumentBlockKind.heading: 'heading',
    DocumentBlockKind.bulletedList: 'bulleted_list',
    DocumentBlockKind.numberedList: 'numbered_list',
    DocumentBlockKind.todo: 'todo_list',
    DocumentBlockKind.toggle: 'm09_toggle',
    DocumentBlockKind.callout: 'm09_callout',
    DocumentBlockKind.quote: 'quote',
    DocumentBlockKind.table: 'table',
    DocumentBlockKind.divider: 'divider',
  };

  static engine.Document encode(NoteDocument document) {
    final nodes = document.blocks.map(_node).toList();
    if (nodes.isEmpty) {
      final empty = engine.paragraphNode();
      empty.updateAttributes({
        ...empty.attributes,
        identity: 'empty-document',
        virtual: true,
      });
      nodes.add(empty);
    }
    return engine.Document(root: engine.pageNode(children: nodes));
  }

  static engine.Node encodeBlock(DocumentBlock block) => _node(block);

  /// Legacy plaintext stays virtual until an actual user edit saves a document.
  static engine.Document legacy(String content) {
    final paragraph = engine.paragraphNode(text: content);
    paragraph.updateAttributes({
      ...paragraph.attributes,
      identity: 'legacy-body',
    });
    return engine.Document(root: engine.pageNode(children: [paragraph]));
  }

  static NoteDocument decode(engine.Document document) => NoteDocument([
    for (final node in document.root.children)
      if (document.root.children.length != 1 || !_unchangedEmpty(node))
        _block(node),
  ]);

  static bool _unchangedEmpty(engine.Node node) =>
      node.type == 'paragraph' &&
      node.attributes[virtual] == true &&
      node.delta?.isEmpty == true &&
      node.children.isEmpty;

  static String id(engine.Node node) {
    final value = node.attributes[identity];
    if (value is! String) throw StateError('Editor identity missing.');
    requireDocumentId(value);
    return value;
  }

  static engine.Node _node(DocumentBlock block) {
    if (block.kind == DocumentBlockKind.table) return _tableNode(block);
    return engine.Node(
      type: types[block.kind]!,
      attributes: {
        identity: block.id,
        if (block.kind != DocumentBlockKind.divider)
          'delta': RichInlineCodec.encode(block.runs).toJson(),
        if (block.level != null) 'level': block.level,
        if (block.checked != null) 'checked': block.checked,
        if (block.icon != null) 'm09_icon': block.icon,
        if (block.tone != null) 'm09_tone': block.tone!.name,
      },
      children: block.children.map(_node).toList(),
    );
  }

  static DocumentBlock _block(engine.Node node) {
    final kind = types.entries
        .where((e) => e.value == node.type)
        .firstOrNull
        ?.key;
    if (kind == null) throw StateError('Unsupported editor block.');
    if (kind == DocumentBlockKind.table) return _tableBlock(node);
    return DocumentBlock(
      id: id(node),
      kind: kind,
      runs: kind == DocumentBlockKind.divider
          ? const []
          : RichInlineCodec.decode(node.delta),
      children: node.children.map(_block),
      level: kind == DocumentBlockKind.heading
          ? node.attributes['level'] as int
          : null,
      checked: kind == DocumentBlockKind.todo
          ? node.attributes['checked'] == true
          : null,
      icon: kind == DocumentBlockKind.callout
          ? node.attributes['m09_icon'] as String?
          : null,
      tone: kind == DocumentBlockKind.callout
          ? RichInlineCodec.color(node.attributes['m09_tone'])
          : null,
    );
  }
}
