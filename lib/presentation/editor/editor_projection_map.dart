import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/foundation.dart';

/// Read-only mapping from the canonical AI/search projection to editor positions.
/// An equation expression maps to one whole atom, never into its placeholder.
final class EditorProjectionMap {
  EditorProjectionMap(engine.Document document) {
    for (var i = 0; i < document.root.children.length; i++) {
      if (i > 0) _text.write('\n');
      _block(document.root.children[i]);
    }
  }
  final _text = StringBuffer();
  final _segments = <_ProjectionSegment>[];
  final _anchors = <String, int>{};
  String get plainText => _text.toString();
  void _block(engine.Node node) {
    if (node.type == 'table') {
      final rows = node.attributes['rowsLen'] as int,
          cols = node.attributes['colsLen'] as int;
      for (var row = 0; row < rows; row++) {
        if (row > 0) _text.write('\n');
        for (var col = 0; col < cols; col++) {
          if (col > 0) _text.write('\t');
          final cell = node.children.firstWhere(
            (n) =>
                n.attributes['rowPosition'] == row &&
                n.attributes['colPosition'] == col,
          );
          for (var p = 0; p < cell.children.length; p++) {
            if (p > 0) _text.write('\n');
            _runs(cell.children[p]);
          }
        }
      }
      return;
    }
    _runs(node);
    for (final child in node.children) {
      _text.write('\n');
      _block(child);
    }
  }

  void _runs(engine.Node node) {
    _anchors[node.path.join('/')] = _text.length;
    var offset = 0;
    for (final operation in node.delta ?? engine.Delta()) {
      if (operation is! engine.TextInsert) {
        continue;
      }
      final math = operation.attributes?['m09_math'];
      if (math is String) {
        for (var i = 0; i < operation.text.length; i++) {
          _segments.add(
            _ProjectionSegment(
              _text.length,
              math.length,
              node.path.toList(),
              offset + i,
              true,
            ),
          );
          _text.write(math);
        }
      } else {
        _segments.add(
          _ProjectionSegment(
            _text.length,
            operation.text.length,
            node.path.toList(),
            offset,
            false,
          ),
        );
        _text.write(operation.text);
      }
      offset += operation.text.length;
    }
  }

  engine.Selection? selection(int start, int end) {
    if (start < 0 || end > _text.length || end <= start || _segments.isEmpty) {
      return null;
    }
    final first = _segments
        .where((s) => s.start + s.length > start)
        .firstOrNull;
    final last = _segments.where((s) => s.start < end).lastOrNull;
    if (first == null || last == null) return null;
    return engine.Selection(
      start: first.position(start, end: false),
      end: last.position(end, end: true),
    );
  }

  int? plainOffset(engine.Position position) {
    final candidates = _segments.where(
      (s) => listEquals(s.path, position.path),
    );
    for (final s in candidates) {
      final length = s.math ? 1 : s.length;
      if (position.offset >= s.offset && position.offset <= s.offset + length) {
        return s.start +
            (s.math
                ? (position.offset == s.offset ? 0 : s.length)
                : position.offset - s.offset);
      }
    }
    return _anchors[position.path.join('/')];
  }

  String? selectedText(engine.Selection selection) {
    final start = plainOffset(selection.start),
        end = plainOffset(selection.end);
    if (start == null || end == null) return null;
    return plainText.substring(
      start < end ? start : end,
      start < end ? end : start,
    );
  }
}

final class _ProjectionSegment {
  const _ProjectionSegment(
    this.start,
    this.length,
    this.path,
    this.offset,
    this.math,
  );
  final int start, length, offset;
  final List<int> path;
  final bool math;
  engine.Position position(int point, {required bool end}) => engine.Position(
    path: path,
    offset: offset + (math ? (end ? 1 : 0) : (point - start).clamp(0, length)),
  );
}
