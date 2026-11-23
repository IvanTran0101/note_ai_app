import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'editor_clipboard.dart';
import 'native_android_clipboard_menu.dart';
import 'rich_editor_adapter.dart';

/// Shows the platform selection menu for a focused native text range.
///
/// Clipboard access and asynchronous selection validation stay in
/// [EditorClipboard]. This widget only owns the temporary toolbar surface.
final class NativeClipboardToolbar extends StatefulWidget {
  const NativeClipboardToolbar({
    super.key,
    required this.adapter,
    required this.focusNode,
    required this.child,
  });

  final RichEditorAdapter adapter;
  final FocusNode focusNode;
  final Widget child;

  @override
  State<NativeClipboardToolbar> createState() => _NativeClipboardToolbarState();
}

final class _NativeClipboardToolbarState extends State<NativeClipboardToolbar>
    with WidgetsBindingObserver {
  static const _selectionDragModeKey = 'selection_drag_mode';
  static const _leftSelectionHandle =
      'MobileSelectionDragMode.leftSelectionHandle';
  static const _rightSelectionHandle =
      'MobileSelectionDragMode.rightSelectionHandle';

  final _toolbarFocusScope = FocusScopeNode(
    debugLabel: 'Native clipboard selection toolbar',
  );
  OverlayEntry? _entry;
  RichSelectionSnapshot? _snapshot;
  RichSelectionSnapshot? _dismissedSnapshot;
  bool _syncScheduled = false;
  bool _routeIsCurrent = true;
  bool _isNativeMobilePlatform = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    WidgetsBinding.instance.addObserver(this);
    widget.adapter.addListener(_queueSync);
    widget.adapter.active.addListener(_queueSync);
    widget.focusNode.addListener(_queueSync);
    _toolbarFocusScope.addListener(_queueSync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (kIsWeb) return;
    final platform = Theme.of(context).platform;
    _isNativeMobilePlatform =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    _routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    _queueSync();
  }

  @override
  void didUpdateWidget(covariant NativeClipboardToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (kIsWeb) return;
    if (!identical(oldWidget.adapter, widget.adapter)) {
      oldWidget.adapter.removeListener(_queueSync);
      oldWidget.adapter.active.removeListener(_queueSync);
      widget.adapter.addListener(_queueSync);
      widget.adapter.active.addListener(_queueSync);
      _dismissedSnapshot = null;
      _removeEntry();
    }
    if (!identical(oldWidget.focusNode, widget.focusNode)) {
      oldWidget.focusNode.removeListener(_queueSync);
      widget.focusNode.addListener(_queueSync);
      _removeEntry();
    }
    _queueSync();
  }

  @override
  void didChangeMetrics() => _queueSync();

  @override
  void dispose() {
    if (!kIsWeb) {
      WidgetsBinding.instance.removeObserver(this);
      widget.adapter.removeListener(_queueSync);
      widget.adapter.active.removeListener(_queueSync);
      widget.focusNode.removeListener(_queueSync);
      _toolbarFocusScope.removeListener(_queueSync);
      _removeEntry();
    }
    _toolbarFocusScope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => kIsWeb
      ? widget.child
      : NotificationListener<ScrollNotification>(
          onNotification: (_) {
            _removeEntry();
            return false;
          },
          child: widget.child,
        );

  bool get _hasFocus =>
      widget.focusNode.hasFocus || _toolbarFocusScope.hasFocus;

  bool get _isDraggingSelection {
    final mode = widget
        .adapter
        .editor
        .selectionExtraInfo?[_selectionDragModeKey]
        ?.toString();
    return mode == _leftSelectionHandle || mode == _rightSelectionHandle;
  }

  bool get _hasRangeSelection {
    final editor = widget.adapter.editor;
    final selection = editor.selection;
    return selection != null &&
        !selection.isCollapsed &&
        editor.selectionType != engine.SelectionType.block;
  }

  void _queueSync() {
    if (kIsWeb || !mounted || _syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (mounted) _syncEntry();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _syncEntry() {
    if (!_isNativeMobilePlatform ||
        !_routeIsCurrent ||
        !_hasFocus ||
        !_hasRangeSelection ||
        _isDraggingSelection) {
      _removeEntry();
      return;
    }

    if (_entry != null) {
      final snapshot = _snapshot;
      if (snapshot == null) {
        _removeEntry();
        return;
      }
      if (!_acceptsCopy(snapshot)) {
        _removeEntry();
        if (_routeIsCurrent &&
            _hasFocus &&
            _hasRangeSelection &&
            !_isDraggingSelection) {
          _queueSync();
        }
        return;
      }
      if (_anchorsForSelection() == null) {
        _removeEntry();
        return;
      }
      _entry!.markNeedsBuild();
      return;
    }

    final snapshot = widget.adapter.captureForCopy();
    if (snapshot == null) return;
    final dismissed = _dismissedSnapshot;
    if (dismissed != null) {
      if (_acceptsCopy(dismissed)) return;
      _dismissedSnapshot = null;
    }
    if (_anchorsForSelection() == null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _snapshot = snapshot;
    final entry = OverlayEntry(builder: _buildEntry);
    _entry = entry;
    overlay.insert(entry);
  }

  TextSelectionToolbarAnchors? _anchorsForSelection() {
    final rects = widget.adapter.editor
        .selectionRects()
        .where(
          (rect) =>
              rect.left.isFinite &&
              rect.top.isFinite &&
              rect.right.isFinite &&
              rect.bottom.isFinite &&
              !rect.isEmpty,
        )
        .toList();
    if (rects.isEmpty) return null;
    final overlayBox = Overlay.maybeOf(
      context,
      rootOverlay: true,
    )?.context.findRenderObject();
    if (overlayBox is! RenderBox || !overlayBox.hasSize) return null;
    final first = rects.first;
    final last = rects.last;
    return TextSelectionToolbarAnchors(
      primaryAnchor: overlayBox.globalToLocal(first.topCenter),
      secondaryAnchor: overlayBox.globalToLocal(last.bottomCenter),
    );
  }

  Widget _buildEntry(BuildContext context) {
    final snapshot = _snapshot;
    final anchors = _anchorsForSelection();
    if (snapshot == null ||
        anchors == null ||
        !_isNativeMobilePlatform ||
        !_routeIsCurrent ||
        !_hasFocus ||
        !_hasRangeSelection ||
        _isDraggingSelection ||
        !_acceptsCopy(snapshot)) {
      _queueSync();
      return const SizedBox.shrink();
    }

    final buttonItems = _buttonItems(snapshot);
    if (buttonItems.isEmpty) return const SizedBox.shrink();
    return FocusScope(
      node: _toolbarFocusScope,
      child: TapRegion(
        onTapOutside: (_) => _removeEntry(),
        child: Theme.of(context).platform == TargetPlatform.android
            ? NativeAndroidClipboardMenu(
                anchors: anchors,
                buttonItems: buttonItems,
              )
            : AdaptiveTextSelectionToolbar.buttonItems(
                anchors: anchors,
                buttonItems: buttonItems,
              ),
      ),
    );
  }

  List<ContextMenuButtonItem> _buttonItems(RichSelectionSnapshot snapshot) {
    final canCopy = _acceptsCopy(snapshot);
    final canEdit = widget.adapter.accepts(snapshot);
    return [
      if (canEdit && canCopy)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.cut,
          onPressed: () => unawaited(
            _performClipboardAction(_ClipboardAction.cut, snapshot),
          ),
        ),
      if (canCopy)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.copy,
          onPressed: () => unawaited(
            _performClipboardAction(_ClipboardAction.copy, snapshot),
          ),
        ),
      if (canEdit)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.paste,
          onPressed: () => unawaited(
            _performClipboardAction(_ClipboardAction.paste, snapshot),
          ),
        ),
    ];
  }

  Future<void> _performClipboardAction(
    _ClipboardAction action,
    RichSelectionSnapshot snapshot,
  ) async {
    final canCopy = _acceptsCopy(snapshot);
    final canEdit = widget.adapter.accepts(snapshot);
    final allowed = switch (action) {
      _ClipboardAction.copy => canCopy,
      _ClipboardAction.cut => canCopy && canEdit,
      _ClipboardAction.paste => canCopy && canEdit,
    };
    if (!allowed) {
      _removeEntry();
      return;
    }

    _dismissedSnapshot = snapshot;
    final restoreEditorFocus =
        _toolbarFocusScope.hasFocus && !widget.focusNode.hasFocus;
    _removeEntry();
    if (restoreEditorFocus) widget.focusNode.requestFocus();

    final clipboard = EditorClipboard(widget.adapter);
    switch (action) {
      case _ClipboardAction.copy:
        await clipboard.copy();
        break;
      case _ClipboardAction.cut:
        await clipboard.copy(cut: true);
        break;
      case _ClipboardAction.paste:
        await clipboard.read();
        break;
    }
  }

  bool _acceptsCopy(RichSelectionSnapshot snapshot) =>
      widget.adapter.acceptsForCopy(snapshot);

  void _removeEntry() {
    final entry = _entry;
    _entry = null;
    _snapshot = null;
    if (entry == null) return;
    entry.remove();
    entry.dispose();
  }
}

enum _ClipboardAction { cut, copy, paste }
