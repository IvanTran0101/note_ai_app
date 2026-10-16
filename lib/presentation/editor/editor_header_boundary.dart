import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';

import 'rich_editor_adapter.dart';

/// Interactive header fields are outside document selection. The public
/// gesture interceptor stops nearest-block selection from stealing title input.
final class EditorHeaderBoundary extends StatefulWidget {
  const EditorHeaderBoundary({
    super.key,
    required this.adapter,
    required this.child,
  });
  final RichEditorAdapter adapter;
  final Widget child;
  @override
  State<EditorHeaderBoundary> createState() => _EditorHeaderBoundaryState();
}

final class _EditorHeaderBoundaryState extends State<EditorHeaderBoundary> {
  final bounds = GlobalKey();
  late final interceptor = engine.SelectionGestureInterceptor(
    key: 'm09 header $hashCode',
    canTap: (details) => _outside(details.globalPosition),
    canDoubleTap: (details) => _outside(details.globalPosition),
    canTripleTap: (details) => _outside(details.globalPosition),
    canPanStart: (details) => _outside(details.globalPosition),
  );
  engine.AppFlowySelectionService? service;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      service = widget.adapter.editor.service.selectionService;
      service!.registerGestureInterceptor(interceptor);
    });
  }

  bool _outside(Offset position) {
    final box = bounds.currentContext?.findRenderObject();
    return box is! RenderBox ||
        !(box.localToGlobal(Offset.zero) & box.size).contains(position);
  }

  void _focus(bool focused) {
    final keyboard = widget.adapter.editor.service.keyboardService;
    if (focused) {
      keyboard?.disableShortcuts();
    } else {
      keyboard?.enableShortcuts();
    }
  }

  @override
  void dispose() {
    service?.unregisterGestureInterceptor(interceptor.key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: _focus,
    child: Semantics(
      container: true,
      explicitChildNodes: true,
      child: SizedBox(key: bounds, child: widget.child),
    ),
  );
}
