import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';

import '../../domain/notes/note_document.dart';
import 'rich_editor_adapter.dart';

/// Range formatting delegates mutations, inversion and history to the engine.
final class SelectionFormattingController {
  const SelectionFormattingController(this.adapter);
  final RichEditorAdapter adapter;
  static const keys = [
    'bold',
    'italic',
    'underline',
    'strikethrough',
    'code',
    'href',
    'font_size',
    'm09_color',
    'm09_highlight',
  ];

  List<_TextRange> _ranges(RichSelectionSnapshot snapshot) {
    final selection = snapshot.selection.normalized;
    final result = <_TextRange>[];
    for (final node in adapter.editor.getNodesInSelection(selection)) {
      final delta = node.delta;
      if (delta == null) continue;
      final start = listEquals(node.path, selection.start.path)
          ? selection.start.offset
          : 0;
      final end = listEquals(node.path, selection.end.path)
          ? selection.end.offset
          : delta.length;
      final text = delta.toPlainText();
      final from = _graphemeBoundary(text, start, startBoundary: true);
      final to = _graphemeBoundary(text, end, startBoundary: false);
      if (to > from) result.add(_TextRange(node, from, to));
    }
    return result;
  }

  FormatValue state(RichSelectionSnapshot snapshot, String key) {
    Object? first;
    var found = false, mixed = false;
    for (final range in _ranges(snapshot)) {
      for (final operation in range.node.delta!.slice(range.start, range.end)) {
        final value =
            operation.attributes?[key] ??
            (const [
                  'bold',
                  'italic',
                  'underline',
                  'strikethrough',
                  'code',
                ].contains(key)
                ? false
                : null);
        if (!found) {
          first = value;
          found = true;
        } else if (value != first) {
          mixed = true;
        }
      }
    }
    return FormatValue(first, mixed);
  }

  bool containsMath(RichSelectionSnapshot snapshot) => _ranges(snapshot).any(
    (range) => range.node.delta!
        .slice(range.start, range.end)
        .any((op) => op.attributes?['m09_math'] != null),
  );

  Future<bool> toggle(RichSelectionSnapshot snapshot, String key) => apply(
    snapshot,
    {key: !(state(snapshot, key).value == true && !state(snapshot, key).mixed)},
  );
  Future<bool> size(
    RichSelectionSnapshot snapshot,
    double? size, {
    bool popupOwnsFocus = false,
  }) {
    DocumentMarks(fontSize: size);
    return apply(snapshot, {'font_size': size}, popupOwnsFocus: popupOwnsFocus);
  }

  Future<bool> color(
    RichSelectionSnapshot snapshot,
    DocumentColor? color, {
    bool highlight = false,
    bool popupOwnsFocus = false,
  }) => apply(snapshot, {
    highlight ? 'm09_highlight' : 'm09_color': color?.name,
  }, popupOwnsFocus: popupOwnsFocus);
  Future<bool> link(
    RichSelectionSnapshot snapshot,
    String? link, {
    bool popupOwnsFocus = false,
  }) {
    DocumentMarks(link: link);
    return apply(snapshot, {'href': link}, popupOwnsFocus: popupOwnsFocus);
  }

  Future<bool> clear(RichSelectionSnapshot snapshot) =>
      apply(snapshot, {for (final key in keys) key: null});

  Future<bool> apply(
    RichSelectionSnapshot snapshot,
    Map<String, dynamic> attributes, {
    bool popupOwnsFocus = false,
  }) async {
    if (attributes.keys.any((k) => !keys.contains(k)) ||
        !adapter.accepts(snapshot, popupOwnsFocus: popupOwnsFocus)) {
      return false;
    }
    if ((attributes['code'] == true || attributes['href'] != null) &&
        containsMath(snapshot)) {
      return false;
    }
    final selected = _ranges(snapshot);
    if (selected.isEmpty) return false;
    final transaction = adapter.editor.transaction;
    for (final range in selected) {
      transaction.formatText(
        range.node,
        range.start,
        range.end - range.start,
        attributes,
      );
    }
    transaction.afterSelection = engine.Selection(
      start: engine.Position(
        path: selected.first.node.path,
        offset: selected.first.start,
      ),
      end: engine.Position(
        path: selected.last.node.path,
        offset: selected.last.end,
      ),
    );
    return adapter.apply(transaction, snapshot, popupOwnsFocus: popupOwnsFocus);
  }
}

final class FormatValue {
  const FormatValue(this.value, this.mixed);
  final Object? value;
  final bool mixed;
}

final class _TextRange {
  const _TextRange(this.node, this.start, this.end);
  final engine.Node node;
  final int start, end;
}

int _graphemeBoundary(String text, int offset, {required bool startBoundary}) {
  if (offset < 0 || offset > text.length) {
    throw StateError('Invalid editor range.');
  }
  var position = 0;
  for (final grapheme in text.characters) {
    final next = position + grapheme.length;
    if (offset == position || offset == next) return offset;
    if (offset < next) return startBoundary ? position : next;
    position = next;
  }
  return text.length;
}
