import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Popup coordinates belong to the root overlay, not the window.
/// The overlay can start below a status bar or the local development marker.
final class EditorPopupArea {
  const EditorPopupArea({required this.origin, required this.bounds});

  factory EditorPopupArea.of(BuildContext context) {
    final box =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()!
            as RenderBox;
    final area = MediaQuery.of(context);
    final top = area.padding.top + 8;
    return EditorPopupArea(
      origin: box.localToGlobal(Offset.zero),
      bounds: Rect.fromLTRB(
        16,
        top,
        math.max(16, box.size.width - 16),
        math.max(
          top,
          box.size.height - area.viewInsets.bottom - area.padding.bottom - 12,
        ),
      ),
    );
  }

  final Offset origin;
  final Rect bounds;

  Rect place(
    Rect globalAnchor,
    Size requested, {
    bool preferBelow = false,
    bool centered = false,
  }) {
    final anchor = globalAnchor.shift(-origin);
    final width = math.min(requested.width, bounds.width);
    final height = math.min(requested.height, bounds.height);
    final above = anchor.top - height - 8;
    final below = anchor.bottom + 8;
    final top = preferBelow
        ? (below + height <= bounds.bottom ? below : above)
        : (above >= bounds.top ? above : below);
    final left = centered ? anchor.center.dx - width / 2 : anchor.left;
    return Rect.fromLTWH(
      left.clamp(bounds.left, bounds.right - width),
      top.clamp(bounds.top, bounds.bottom - height),
      width,
      height,
    );
  }
}
