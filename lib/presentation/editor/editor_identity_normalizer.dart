import 'dart:async';
import 'dart:math';

import 'package:appflowy_editor/appflowy_editor.dart' as engine;

import 'rich_document_codec.dart';

part 'editor_identity_rows.dart';

/// Public synchronous before-transaction hook. IDs enter the original history
/// operation; no async repair, persisted engine JSON or second editor writer.
final class EditorIdentityNormalizer {
  EditorIdentityNormalizer(
    this.editor, {
    required this.onRejected,
    String Function()? generateId,
  }) : _generateId = generateId ?? _randomId {
    final seen = <String>{
      for (final node in _walk(editor.document.root))
        if (node.attributes[RichDocumentCodec.rowIdentity] is String)
          node.attributes[RichDocumentCodec.rowIdentity] as String,
    };
    for (final node in editor.document.root.children) {
      _claim(node, seen);
    }
    _normalizeRows(editor.document, const {}, _generateId);
    _subscription = editor.transactionStream.listen((event) {
      if (event.$1 != engine.TransactionTime.before) return;
      try {
        _normalize(event.$2);
      } on Object {
        event.$2.operations = [];
        event.$2.afterSelection = event.$2.beforeSelection;
        onRejected();
      }
    });
  }
  final engine.EditorState editor;
  final void Function() onRejected;
  final String Function() _generateId;
  late final StreamSubscription<engine.EditorTransactionValue> _subscription;
  static final _random = Random.secure();
  static String _randomId() =>
      'b_${List.generate(16, (_) => _random.nextInt(16).toRadixString(16)).join()}';
  void dispose() => _subscription.cancel();
  String allocateIdentity() =>
      _freshId(_ids(editor.document.root), _generateId);

  Iterable<engine.Node> _walk(engine.Node node) sync* {
    yield node;
    for (final child in node.children) {
      yield* _walk(child);
    }
  }

  Set<String> _ids(engine.Node root) => {
    for (final node in _walk(root)) ...[
      if (node.attributes[RichDocumentCodec.identity] is String)
        node.attributes[RichDocumentCodec.identity] as String,
      if (node.attributes[RichDocumentCodec.rowIdentity] is String)
        node.attributes[RichDocumentCodec.rowIdentity] as String,
    ],
  };
  void _claim(engine.Node node, Set<String> used) {
    final old = node.attributes[RichDocumentCodec.identity];
    String id;
    if (old is String &&
        RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(old) &&
        !used.contains(old)) {
      id = old;
    } else {
      id = _freshId(used, _generateId);
    }
    used.add(id);
    node.updateAttributes({...node.attributes, RichDocumentCodec.identity: id});
    for (final child in node.children) {
      _claim(child, used);
    }
  }

  void _normalize(engine.Transaction transaction) {
    // Move operations may contain live nodes. Work on detached copies until
    // validation succeeds; a refused transaction cannot mutate the old tree.
    final operations = transaction.operations
        .map(
          (operation) => operation is engine.InsertOperation
              ? engine.InsertOperation(
                  operation.path,
                  operation.nodes.map(_copy).toList(),
                )
              : operation,
        )
        .toList();
    final used = _ids(editor.document.root);
    final previousRows = <String, String>{
      for (final node in _walk(editor.document.root))
        if (node.attributes[RichDocumentCodec.rowIdentity] is String)
          RichDocumentCodec.id(node):
              node.attributes[RichDocumentCodec.rowIdentity] as String,
    };
    for (final operation in operations.whereType<engine.DeleteOperation>()) {
      for (final node in operation.nodes) {
        used.removeAll(_ids(node));
        for (final removed in _walk(node)) {
          previousRows.remove(removed.attributes[RichDocumentCodec.identity]);
        }
      }
    }
    final inserted = <String, engine.Node>{};
    for (final operation in operations.whereType<engine.InsertOperation>()) {
      for (final node in operation.nodes) {
        _claim(node, used);
        for (final added in _walk(node)) {
          inserted[RichDocumentCodec.id(added)] = added;
        }
      }
    }
    final normalized = operations.map(_textOperation).toList();
    final preview = engine.Document.fromJson(editor.document.toJson());
    try {
      for (final operation in normalized) {
        _preview(preview, operation);
      }
      final patches = _normalizeRows(preview, previousRows, _generateId);
      for (final patch in patches) {
        final node = preview.nodeAtPath(patch.path)!;
        final added = inserted[RichDocumentCodec.id(node)];
        if (added != null) {
          added.updateAttributes({...added.attributes, ...patch.attributes});
        } else {
          normalized.add(patch);
        }
      }
      // Pure Domain shape/count/projection validation before any real change.
      RichDocumentCodec.decode(preview);
      transaction.operations = normalized;
    } finally {
      preview.dispose();
    }
  }

  engine.Node _copy(engine.Node node) => engine.Node(
    type: node.type,
    id: node.id,
    attributes: {...node.attributes},
    children: node.children.map(_copy).toList(),
  );

  engine.Operation _textOperation(engine.Operation operation) {
    if (operation is! engine.UpdateTextOperation) return operation;
    final delta = engine.Delta();
    for (final part in operation.delta) {
      if (part is! engine.TextInsert || part.attributes?['m09_math'] == null) {
        delta.add(part);
        continue;
      }
      final ordinary = {...?part.attributes}..remove('m09_math');
      final buffer = StringBuffer();
      void flush() {
        if (buffer.isNotEmpty) {
          delta.insert(buffer.toString(), attributes: ordinary);
        }
        buffer.clear();
      }

      for (final unit in part.text.codeUnits) {
        if (unit == 0xFFFC) {
          flush();
          delta.insert('\uFFFC', attributes: part.attributes);
        } else {
          buffer.writeCharCode(unit);
        }
      }
      flush();
    }
    return engine.UpdateTextOperation(
      operation.path,
      delta,
      operation.inverted,
    );
  }

  void _preview(engine.Document document, engine.Operation operation) {
    if (operation is engine.InsertOperation) {
      document.insert(
        operation.path,
        operation.nodes.map((n) => engine.Node.fromJson(n.toJson())),
      );
    } else if (operation is engine.DeleteOperation) {
      document.delete(operation.path, operation.nodes.length);
    } else if (operation is engine.UpdateOperation) {
      document.update(operation.path, operation.attributes);
    } else if (operation is engine.UpdateTextOperation) {
      document.updateText(operation.path, operation.delta);
    }
  }
}

String _freshId(Set<String> used, String Function() generate) {
  for (var attempt = 0; attempt < 100; attempt++) {
    final id = generate();
    if (RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id) && used.add(id)) {
      return id;
    }
  }
  throw StateError('Cannot allocate editor identity.');
}
