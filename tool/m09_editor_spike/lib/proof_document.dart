import 'package:appflowy_editor/appflowy_editor.dart';

/// Synthetic only. Never reads or writes the production actor store.
Document proofDocument() {
  final text = Delta()
    ..insert('Tiếng Việt 📝 — select text, type, undo. ')
    ..insert(
      'B/I/U/S',
      attributes: {
        'bold': true,
        'italic': true,
        'underline': true,
        'strikethrough': true,
      },
    )
    ..insert(' size24 ', attributes: {'font_size': 24.0})
    ..insert('\uFFFC', attributes: {'m09_math': r'\sqrt{x^2+1}'})
    ..insert(' end.');
  final nodes = <Node>[
    paragraphNode(delta: text),
    for (var level = 1; level <= 4; level++)
      headingNode(level: level, delta: Delta()..insert('Heading $level')),
    bulletedListNode(
      text: 'Bullet',
      children: [paragraphNode(text: 'Nested paragraph')],
    ),
    numberedListNode(delta: Delta()..insert('Numbered')),
    todoListNode(checked: false, text: 'To-do'),
    Node(
      type: 'm09_toggle',
      attributes: {'delta': (Delta()..insert('Toggle')).toJson()},
      children: [paragraphNode(text: 'Toggle child preserved')],
    ),
    Node(
      type: 'm09_callout',
      attributes: {'delta': (Delta()..insert('Callout')).toJson()},
      children: [paragraphNode(text: 'Callout child')],
    ),
    quoteNode(delta: Delta()..insert('Quote')),
    TableNode.fromList<String>([
      ['A1', 'A2'],
      ['B1', 'B2'],
    ]).node,
    dividerNode(),
  ];
  var id = 0;
  void identify(Node node) {
    node.updateAttributes({...node.attributes, 'm09_id': 'proof-${id++}'});
    for (final child in node.children) {
      identify(child);
    }
  }

  for (final node in nodes) {
    identify(node);
  }
  return Document(root: pageNode(children: nodes));
}
