import 'package:flutter/material.dart';

/// Quiet block affordance for Web; history remains available in the page menu.
final class WebEditorControls extends StatefulWidget {
  const WebEditorControls({
    super.key,
    required this.focusNode,
    required this.child,
  });

  final FocusNode focusNode;
  final Widget child;

  @override
  State<WebEditorControls> createState() => _WebEditorControlsState();
}

final class _WebEditorControlsState extends State<WebEditorControls> {
  bool _hovered = false, _controlFocused = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.focusNode,
    builder: (context, _) {
      final compact = MediaQuery.sizeOf(context).width < 720;
      final scaledText = MediaQuery.textScalerOf(context).scale(14) > 14;
      final accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
      final visible =
          compact ||
          _hovered ||
          _controlFocused ||
          widget.focusNode.hasFocus ||
          accessibleNavigation ||
          scaledText;
      return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (value) => setState(() => _controlFocused = value),
          child: ExcludeSemantics(
            excluding: !visible,
            child: IgnorePointer(
              ignoring: !visible,
              child: Opacity(opacity: visible ? 1 : 0, child: widget.child),
            ),
          ),
        ),
      );
    },
  );
}
