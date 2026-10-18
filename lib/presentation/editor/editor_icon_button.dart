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
  });

  final String label;
  final Widget icon;
  final VoidCallback? onPressed;
  final bool? selected;
  final String? value, tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? label,
    excludeFromSemantics: true,
    child: MergeSemantics(
      child: Semantics(
        label: label,
        value: value,
        child: SizedBox.square(
          dimension: 48,
          child: IconButton(
            onPressed: onPressed,
            isSelected: selected,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            visualDensity: VisualDensity.standard,
            icon: ExcludeSemantics(
              child: MediaQuery.withNoTextScaling(child: icon),
            ),
          ),
        ),
      ),
    ),
  );
}
