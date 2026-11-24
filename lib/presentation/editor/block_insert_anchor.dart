import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/rendering.dart';

/// Align the gutter with the first editable line, not the padded block box.
/// The engine owns text layout, including headings, inline sizes and scaling.
Offset blockInsertAnchor(engine.Node node, RenderBox target) {
  return Offset(-28, blockInsertLine(node, target).center.dy - 13);
}

/// Local first-line hit area, also excluding a container's nested children.
Rect blockInsertLine(engine.Node node, RenderBox target) {
  engine.Node? firstText(engine.Node candidate) {
    if (candidate.delta != null) return candidate;
    for (final child in candidate.children) {
      final found = firstText(child);
      if (found != null) return found;
    }
    return null;
  }

  final text = firstText(node);
  final selectable = text?.selectable;
  if (text != null && selectable != null) {
    final cursor = selectable.getCursorRectInPosition(
      engine.Position(path: text.path, offset: 0),
    );
    if (cursor != null && cursor.height > 0 && cursor.height.isFinite) {
      final center = target.globalToLocal(
        selectable.localToGlobal(cursor.center),
      );
      if (center.dy.isFinite) {
        return Rect.fromLTWH(
          0,
          center.dy - cursor.height / 2,
          target.size.width,
          cursor.height,
        );
      }
    }
  }
  // Non-text blocks keep a centered gutter without inspecting their contents.
  final height = target.size.height.clamp(0.0, 52.0);
  return Rect.fromLTWH(0, 0, target.size.width, height);
}
