import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A single existing action in the compact workspace popup.
class CompactWorkspaceMenuItem<T> {
  const CompactWorkspaceMenuItem({
    required this.label,
    required this.icon,
    required this.value,
    this.key,
    this.aliasKey,
    this.selected = false,
    this.dividerBefore = false,
  });

  final String label;
  final IconData icon;
  final T value;
  final Key? key;
  final Key? aliasKey;
  final bool selected;
  final bool dividerBefore;
}

/// Shows a compact menu anchored to a painted avatar's global rectangle.
///
/// Selection and dismissal are returned to the caller. This helper never runs
/// an action associated with an item.
Future<T?> showCompactWorkspaceMenu<T>({
  required BuildContext context,
  required Rect globalAnchor,
  required List<CompactWorkspaceMenuItem<T>> items,
  required String semanticLabel,
}) {
  if (items.isEmpty) {
    return Future<T?>.value();
  }

  final OverlayState rootOverlay = Overlay.of(context, rootOverlay: true);
  final RenderObject? renderObject = rootOverlay.context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) {
    return Future<T?>.value();
  }

  final RenderBox overlayBox = renderObject;
  final Size overlaySize = overlayBox.size;
  final MediaQueryData mediaQuery = MediaQuery.of(rootOverlay.context);
  final EdgeInsets safePadding = mediaQuery.padding;
  const double viewportGutter = 8;
  const double maximumMenuWidth = 288;
  final double availableWidth = math
      .max(0, overlaySize.width - safePadding.horizontal - (viewportGutter * 2))
      .toDouble();
  final double menuWidth = math
      .min(maximumMenuWidth, availableWidth)
      .toDouble();

  final Offset localAnchor = overlayBox.globalToLocal(
    Offset(globalAnchor.left + 4, globalAnchor.bottom - 4),
  );
  final double safeBottomInset = math
      .max(safePadding.bottom, mediaQuery.viewInsets.bottom)
      .toDouble();
  final double safeBottom = overlaySize.height - safeBottomInset;
  final double menuTop = math
      .max(localAnchor.dy, safePadding.top + viewportGutter)
      .toDouble();
  final double availableHeight = math
      .max(0, safeBottom - menuTop - viewportGutter)
      .toDouble();

  if (menuWidth <= 0 || availableHeight <= 0) {
    return Future<T?>.value();
  }

  final ThemeData theme = Theme.of(context);
  final List<PopupMenuEntry<T>> entries = <PopupMenuEntry<T>>[];
  for (final CompactWorkspaceMenuItem<T> item in items) {
    if (item.dividerBefore && entries.isNotEmpty) {
      entries.add(const PopupMenuDivider(height: 16));
    }

    final TextStyle labelStyle =
        (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
          color: theme.colorScheme.onSurface,
          fontSize: 16,
          fontWeight: item.selected ? FontWeight.w600 : FontWeight.normal,
        );
    Widget content = Row(
      children: <Widget>[
        Icon(
          item.icon,
          size: 22,
          color: item.selected
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(item.label, style: labelStyle)),
      ],
    );
    if (item.aliasKey != null) {
      content = KeyedSubtree(key: item.aliasKey, child: content);
    }
    if (entries.isEmpty) {
      content = _DismissMenuOnMetricsChange(child: content);
    }

    entries.add(
      PopupMenuItem<T>(
        key: item.key,
        value: item.value,
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: content,
      ),
    );
  }

  final Rect anchorPoint = Rect.fromLTWH(localAnchor.dx, localAnchor.dy, 0, 0);
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(anchorPoint, Offset.zero & overlaySize),
    items: entries,
    constraints: BoxConstraints(
      minWidth: menuWidth,
      maxWidth: menuWidth,
      maxHeight: availableHeight,
    ),
    elevation: 2,
    color: theme.colorScheme.surface,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    clipBehavior: Clip.antiAlias,
    menuPadding: EdgeInsets.zero,
    semanticLabel: semanticLabel,
    useRootNavigator: true,
  );
}

/// A changed viewport invalidates the captured avatar anchor and safe bounds.
/// Close only this popup, so rotation/IME changes cannot strand it off-screen.
class _DismissMenuOnMetricsChange extends StatefulWidget {
  const _DismissMenuOnMetricsChange({required this.child});

  final Widget child;

  @override
  State<_DismissMenuOnMetricsChange> createState() =>
      _DismissMenuOnMetricsChangeState();
}

class _DismissMenuOnMetricsChangeState
    extends State<_DismissMenuOnMetricsChange>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
