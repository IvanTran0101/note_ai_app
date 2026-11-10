import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'editor_popup_area.dart';

/// Compact Android selection actions sized for touch and placed in the root
/// overlay. [anchors] are expressed in that overlay's local coordinates.
///
/// The caller owns action authorization, callbacks, and dismissal behavior.
final class NativeAndroidClipboardMenu extends StatelessWidget {
  const NativeAndroidClipboardMenu({
    super.key,
    required this.anchors,
    required this.buttonItems,
  });

  final TextSelectionToolbarAnchors anchors;
  final List<ContextMenuButtonItem> buttonItems;

  @override
  Widget build(BuildContext context) {
    final area = EditorPopupArea.of(context);
    final globalAnchor = _selectionAnchorRect(anchors).shift(area.origin);

    return CustomSingleChildLayout(
      delegate: _ClipboardMenuLayoutDelegate(
        area: area,
        globalAnchor: globalAnchor,
      ),
      child: _ClipboardMenuPill(buttonItems: buttonItems),
    );
  }

  Rect _selectionAnchorRect(TextSelectionToolbarAnchors anchors) {
    final points = [anchors.primaryAnchor];
    final secondary = anchors.secondaryAnchor;
    if (secondary != null) points.add(secondary);
    points.removeWhere((point) => !point.dx.isFinite || !point.dy.isFinite);
    if (points.isEmpty) return Rect.zero;
    if (points.length == 1) {
      return Rect.fromCenter(center: points.single, width: 0, height: 0);
    }
    return Rect.fromLTRB(
      math.min(points[0].dx, points[1].dx),
      math.min(points[0].dy, points[1].dy),
      math.max(points[0].dx, points[1].dx),
      math.max(points[0].dy, points[1].dy),
    );
  }
}

final class _ClipboardMenuLayoutDelegate extends SingleChildLayoutDelegate {
  const _ClipboardMenuLayoutDelegate({
    required this.area,
    required this.globalAnchor,
  });

  final EditorPopupArea area;
  final Rect globalAnchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.min(area.bounds.width, constraints.maxWidth),
        maxHeight: math.min(area.bounds.height, constraints.maxHeight),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      area.place(globalAnchor, childSize, centered: true).topLeft;

  @override
  bool shouldRelayout(covariant _ClipboardMenuLayoutDelegate oldDelegate) =>
      area.origin != oldDelegate.area.origin ||
      area.bounds != oldDelegate.area.bounds ||
      globalAnchor != oldDelegate.globalAnchor;
}

final class _ClipboardMenuPill extends StatelessWidget {
  const _ClipboardMenuPill({required this.buttonItems});

  final List<ContextMenuButtonItem> buttonItems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      key: const ValueKey('native-android-clipboard-menu'),
      // The inspected Android system capsule stays light on a dark document.
      color: const Color(0xFFE5E4EA),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: SingleChildScrollView(
          primary: false,
          child: Wrap(
            alignment: WrapAlignment.center,
            runAlignment: WrapAlignment.center,
            runSpacing: 2,
            children: [
              for (final item in buttonItems)
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF292929),
                    minimumSize: const Size(48, 48),
                    visualDensity: VisualDensity.standard,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    tapTargetSize: MaterialTapTargetSize.padded,
                    textStyle: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w400,
                    ),
                    shape: const StadiumBorder(),
                  ),
                  onPressed: item.onPressed,
                  child: Text(
                    AdaptiveTextSelectionToolbar.getButtonLabel(context, item),
                    textAlign: TextAlign.center,
                    softWrap: true,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
