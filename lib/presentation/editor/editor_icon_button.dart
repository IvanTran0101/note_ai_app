import 'package:flutter/material.dart';

/// One accessible action label, with a full touch target in every editor rail.
/// The IconButton retains keyboard focus, enabled and toggle semantics.
final class EditorIconButton extends StatelessWidget {
  const EditorIconButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.selected,
    this.value,
    this.tooltip,
    this.compact = false,
    this.showTooltip = true,
  });

  final String label;
  final Widget icon;
  final VoidCallback? onPressed;
  final bool? selected;
  final String? value, tooltip;
  final bool compact, showTooltip;

  @override
  Widget build(BuildContext context) {
    final button = MergeSemantics(
      child: Semantics(
        label: label,
        value: value,
        child: SizedBox.square(
          dimension: compact ? 28 : 48,
          child: IconButton(
            onPressed: onPressed,
            isSelected: selected,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(
              minWidth: compact ? 28 : 48,
              minHeight: compact ? 28 : 48,
            ),
            visualDensity: compact
                ? VisualDensity.compact
                : VisualDensity.standard,
            style: IconButton.styleFrom(
              tapTargetSize: compact
                  ? MaterialTapTargetSize.shrinkWrap
                  : MaterialTapTargetSize.padded,
            ),
            icon: ExcludeSemantics(
              child: MediaQuery.withNoTextScaling(child: icon),
            ),
          ),
        ),
      ),
    );
    return showTooltip
        ? Tooltip(
            message: tooltip ?? label,
            excludeFromSemantics: true,
            child: button,
          )
        : button;
  }
}
