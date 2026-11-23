import 'package:flutter/material.dart';

import 'editor_popup_area.dart';
import 'rich_editor_adapter.dart';

/// Keeps existing touch controls above IME even inside nested workspace frames.
/// Selection formatting owns that same slot while a range is selected.
final class NativeEditorRail extends StatefulWidget {
  const NativeEditorRail({
    super.key,
    required this.adapter,
    required this.focusNode,
    required this.controls,
  });
  final RichEditorAdapter adapter;
  final FocusNode focusNode;
  final Widget controls;
  @override
  State<NativeEditorRail> createState() => _NativeEditorRailState();
}

final class _NativeEditorRailState extends State<NativeEditorRail>
    with WidgetsBindingObserver {
  OverlayEntry? entry;
  bool requested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closeOverlay();
    super.dispose();
  }

  void _closeOverlay() {
    entry?.remove();
    entry?.dispose();
    entry = null;
  }

  void _requestOverlay(bool show) {
    requested = show;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || requested != show) return;
      if (!show) {
        _closeOverlay();
      } else if (entry == null) {
        entry = OverlayEntry(builder: _overlay);
        Overlay.of(context, rootOverlay: true).insert(entry!);
      } else {
        entry!.markNeedsBuild();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = View.of(context).viewInsets.bottom > 0;
    final currentRoute = ModalRoute.of(context)?.isCurrent ?? true;
    // Rebuild for keyboard metrics as well as focus/selection/access changes.
    MediaQuery.viewInsetsOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([widget.adapter, widget.focusNode]),
      builder: (context, _) {
        final selection = widget.adapter.editor.selection;
        final show =
            keyboard &&
            currentRoute &&
            widget.adapter.editable &&
            widget.focusNode.hasFocus &&
            (selection == null || selection.isCollapsed);
        _requestOverlay(show);
        // A root entry retains semantics while the inline slot is below IME.
        // Native Notion exposes this rail while editing above IME. The same
        // commands become available on focus; an idle note keeps its canvas.
        return SizedBox(height: keyboard && widget.adapter.editable ? 48 : 0);
      },
    );
  }

  Widget _overlay(BuildContext context) {
    final popup = EditorPopupArea.of(context);
    final area = MediaQuery.of(context);
    final colors = Theme.of(context).colorScheme;
    final bottom = popup.bounds.bottom + 12;
    return Positioned(
      left: area.padding.left,
      right: area.padding.right,
      top: (bottom - 48).clamp(popup.bounds.top, bottom).toDouble(),
      height: 48,
      child: Material(
        color: colors.surface,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.outlineVariant)),
          ),
          child: widget.controls,
        ),
      ),
    );
  }
}
