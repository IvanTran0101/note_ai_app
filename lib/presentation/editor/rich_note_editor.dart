import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'basic_block_menu.dart';
import 'basic_block_commands.dart';
import 'editor_popup_guard.dart';
import 'editor_popup_area.dart';
import 'editor_shortcuts.dart';
import 'editor_controls.dart';
import 'editor_header_boundary.dart';
import 'editor_renderers.dart';
import 'editor_clipboard.dart';
import 'rich_editor_adapter.dart';
import 'selection_toolbar.dart';
import 'slash_command_controller.dart';

/// Host rendering and menus; persistence stays in the NoteDetail Application port.
final class RichNoteEditor extends StatefulWidget {
  const RichNoteEditor({
    super.key,
    required this.adapter,
    required this.focusNode,
    required this.header,
    this.footer = const SizedBox.shrink(),
  });
  final RichEditorAdapter adapter;
  final FocusNode focusNode;
  final Widget header;
  final Widget footer;
  @override
  State<RichNoteEditor> createState() => _RichNoteEditorState();
}

final class _RichNoteEditorState extends State<RichNoteEditor> {
  late final slash = SlashCommandController(widget.adapter);
  late final scroll = engine.EditorScrollController(
    editorState: widget.adapter.editor,
    // Web semantics retain DOM focus in a stable bounded viewport.
    shrinkWrap: kIsWeb,
  );
  OverlayEntry? _blockMenu;
  bool _touchMenuShowing = false;
  late final header = ValueNotifier<Widget>(widget.header);
  late final footer = ValueNotifier<Widget>(widget.footer);
  Widget? _cachedView;
  ThemeData? _cachedTheme;
  bool? _cachedEditable, _cachedCompact;
  double? _cachedScale;
  VoidCallback? _dismissFormatting;
  @override
  void didUpdateWidget(covariant RichNoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    header.value = widget.header;
    footer.value = widget.footer;
  }

  @override
  void initState() {
    super.initState();
    slash.addListener(menuChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.adapter.bindKeyboard();
    });
  }

  void menuChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (slash.touchOpen && !kIsWeb) {
        _closeBlockMenu();
        if (!_touchMenuShowing) unawaited(_showTouchMenu());
        return;
      }
      if (slash.visible) {
        if (_blockMenu == null) {
          _blockMenu = OverlayEntry(builder: _menuOverlay);
          Overlay.of(context, rootOverlay: true).insert(_blockMenu!);
        } else {
          _blockMenu!.markNeedsBuild();
        }
      } else {
        _closeBlockMenu();
      }
    });
    // A touch open/close can occur while the document has no active animation
    // or input repaint. A post-frame callback alone does not request a frame.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _showTouchMenu() async {
    final snapshot = slash.snapshot;
    if (snapshot == null) return;
    _touchMenuShowing = true;
    try {
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      if (!mounted || !widget.adapter.accepts(snapshot, popupOwnsFocus: true)) {
        return;
      }
      final choice = await guardedEditorSheet<BasicBlockChoice>(
        context,
        widget.adapter,
        snapshot,
        (context) => BasicBlockMenu(
          controller: slash,
          sheet: true,
          onClose: () => Navigator.pop(context),
          onChoose: (choice) => Navigator.pop(context, choice),
        ),
      );
      if (!mounted) return;
      if (choice == null) {
        slash.close(cancel: true);
      } else {
        await slash.choose(choice);
      }
    } finally {
      _touchMenuShowing = false;
    }
  }

  @override
  void dispose() {
    widget.adapter.editor.autoScroller?.stopAutoScroll();
    _closeBlockMenu();
    slash.removeListener(menuChanged);
    slash.dispose();
    scroll.dispose();
    header.dispose();
    footer.dispose();
    super.dispose();
  }

  void _closeBlockMenu() {
    _blockMenu?.remove();
    _blockMenu?.dispose();
    _blockMenu = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), editable = widget.adapter.editable;
    final compact = MediaQuery.sizeOf(context).width < 720;
    final scale = MediaQuery.textScalerOf(context).scale(16);
    // Keep the engine widget and its input service stable across editor/header
    // notifications. Public Node listeners own text repaint; UI menus listen
    // separately. Replacing its services on each keystroke loses Web IME focus.
    if (_cachedView == null ||
        _cachedTheme != theme ||
        _cachedEditable != editable ||
        _cachedCompact != compact ||
        _cachedScale != scale) {
      _cachedTheme = theme;
      _cachedEditable = editable;
      _cachedCompact = compact;
      _cachedScale = scale;
      _cachedView = _buildEditor(context);
    }
    return _cachedView!;
  }

  Widget _buildEditor(BuildContext context) {
    final adapter = widget.adapter, colors = Theme.of(context).colorScheme;
    final editor = engine.AppFlowyEditor(
      editorState: adapter.editor,
      focusNode: widget.focusNode,
      editorScrollController: scroll,
      shrinkWrap: true,
      header: _header(),
      footer: _footer(colors),
      editable: adapter.editable,
      contextMenuBuilder: EditorClipboard(adapter).contextMenu,
      // Keep upstream block/list/heading Enter behavior. Slash and unsupported
      // markdown/media conversions are owned/excluded by the host menu.
      characterShortcutEvents: engine.standardCharacterShortcutEvents
          .where((event) => event.character == '\n')
          .toList(),
      commandShortcutEvents: richEditorShortcuts(adapter, slash),
      editorStyle: documentEditorStyle(context),
      blockComponentBuilders: documentBlockBuilders(
        context,
        adapter,
        widget.focusNode,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [Expanded(child: _toolbar(context, editor))],
    );
  }

  Widget _header() => EditorHeaderBoundary(
    adapter: widget.adapter,
    child: Column(
      children: [
        ValueListenableBuilder<Widget>(
          valueListenable: header,
          builder: (_, value, _) => value,
        ),
        ListenableBuilder(
          listenable: widget.adapter,
          builder: (_, _) => widget.adapter.editable
              ? EditorControls(adapter: widget.adapter, slash: slash)
              : const SizedBox.shrink(),
        ),
      ],
    ),
  );
  Widget _footer(ColorScheme colors) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ValueListenableBuilder<Widget>(
        valueListenable: footer,
        builder: (_, value, _) =>
            EditorHeaderBoundary(adapter: widget.adapter, child: value),
      ),
      ListenableBuilder(
        listenable: widget.adapter,
        builder: (context, _) => widget.adapter.error == null
            ? const SizedBox(height: 120)
            : Semantics(
                liveRegion: true,
                child: Text(
                  widget.adapter.error!,
                  style: TextStyle(color: colors.error),
                ),
              ),
      ),
    ],
  );
  Widget _toolbar(BuildContext context, Widget editor) {
    final adapter = widget.adapter, colors = Theme.of(context).colorScheme;
    return engine.FloatingToolbar(
      toolbarBuilder: _formattingOverlay,
      editorState: adapter.editor,
      editorScrollController: scroll,
      textDirection: Directionality.of(context),
      floatingToolbarHeight: MediaQuery.sizeOf(context).width < 720 ? 144 : 96,
      style: engine.FloatingToolbarStyle(
        backgroundColor: colors.surface,
        toolbarActiveColor: colors.primary,
        toolbarIconColor: colors.onSurface,
        toolbarElevation: 8,
      ),
      items: [
        engine.ToolbarItem(
          id: 'm09-selection',
          group: 0,
          isActive: (_) => adapter.capture() != null,
          builder: (_, _, _, _, _) => SelectionToolbar(
            adapter: adapter,
            dialogContext: context,
            onPopupOpen: () => _dismissFormatting?.call(),
          ),
        ),
      ],
      child: editor,
    );
  }

  Widget _menuOverlay(BuildContext context) {
    final rects = widget.adapter.editor.selectionRects();
    final rect = rects.isEmpty
        ? const Rect.fromLTWH(24, 220, 0, 0)
        : rects.last;
    final placed = EditorPopupArea.of(context)
        .place(rect, const Size(320, 320), preferBelow: true);
    return Positioned.fromRect(
      rect: placed,
      child: TapRegion(
        onTapOutside: (_) => slash.close(cancel: true),
        child: BasicBlockMenu(controller: slash),
      ),
    );
  }

  Widget _formattingOverlay(
    BuildContext context,
    Widget child,
    VoidCallback close,
    bool metricsChanged,
  ) {
    _dismissFormatting = close;
    final area = MediaQuery.of(context),
        rects = widget.adapter.editor.selectionRects();
    if (rects.isEmpty) return const SizedBox.shrink();
    final rect = rects.first, width = math.min(area.size.width - 40, 686.0);
    final height = area.size.width < 720 ? 144.0 : 96.0;
    final placed = EditorPopupArea.of(context)
        .place(rect, Size(width, height), centered: true);
    return Positioned.fromRect(
      rect: placed,
      child: ClipRect(child: SingleChildScrollView(child: child)),
    );
  }
}
