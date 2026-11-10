import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../notes/notes_theme_tokens.dart';
import 'basic_block_menu.dart';
import 'basic_block_commands.dart';
import 'block_filter_input.dart';
import 'editor_popup_guard.dart';
import 'editor_popup_area.dart';
import 'editor_shortcuts.dart';
import 'editor_controls.dart';
import 'editor_copy.dart';
import 'native_editor_rail.dart';
import 'native_clipboard_toolbar.dart';
import 'editor_header_boundary.dart';
import 'editor_renderers.dart';
import 'editor_clipboard.dart';
import 'editor_input_focus.dart';
import 'rich_editor_adapter.dart';
import 'selection_toolbar.dart';
import 'selection_toolbar_layout.dart';
import 'slash_command_controller.dart';

part 'rich_note_editor_overlays.dart';
part 'rich_note_editor_blocks.dart';
part 'rich_note_editor_focus.dart';

/// Host rendering and menus; persistence stays in the NoteDetail Application port.
final class RichNoteEditor extends StatefulWidget {
  const RichNoteEditor({
    super.key,
    required this.adapter,
    required this.focusNode,
    required this.header,
    this.footer = const SizedBox.shrink(),
    this.fileBlockBuilder,
  });
  final RichEditorAdapter adapter;
  final FocusNode focusNode;
  final Widget header;
  final Widget footer;
  final Widget Function(String blockId, String? attachmentId)? fileBlockBuilder;
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
  final _blockPortal = OverlayPortalController();
  bool _touchMenuShowing = false;
  late final header = ValueNotifier<Widget>(widget.header);
  late final footer = ValueNotifier<Widget>(widget.footer);
  Widget? _cachedView;
  ThemeData? _cachedTheme;
  bool? _cachedEditable, _cachedCompact;
  bool? _cachedShort;
  double? _cachedScale;
  VoidCallback? _dismissFormatting;
  Rect? _blockFilterAnchor;
  ModalRoute<dynamic>? _editorRoute;
  bool _editorRouteCurrent = true;
  void Function(VoidCallback reconnect, bool forceReconnect)? _lastInputFocus;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    final routeIsCurrent = route?.isCurrent ?? true;
    final routeChanged =
        _editorRoute != null && !identical(route, _editorRoute);
    final lostCurrentRoute = _editorRouteCurrent && !routeIsCurrent;
    _editorRoute = route;
    _editorRouteCurrent = routeIsCurrent;
    if (routeChanged || lostCurrentRoute) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _dismissTransientEditorUi();
      });
    }
  }

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
    final restoreInput = kIsWeb && !slash.touchOpen && !widget.adapter.composing
        ? (captureEditorInputFocus() ?? _lastInputFocus)
        : null;
    final inputSelection = widget.adapter.capture(range: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (slash.touchOpen && !kIsWeb) {
        _closeBlockMenu();
        if (!_touchMenuShowing) unawaited(_showTouchMenu());
        return;
      }
      final changedVisibility = slash.visible != _blockPortal.isShowing;
      if (slash.visible) {
        if (!_blockPortal.isShowing) _blockPortal.show();
      } else {
        _closeBlockMenu();
        _lastInputFocus = null;
        _blockFilterAnchor = null;
      }
      if (restoreInput != null && inputSelection != null) {
        _restoreMenuInput(restoreInput, changedVisibility, inputSelection);
      }
    });
    // A touch open/close can occur while the document has no active animation
    // or input repaint. A post-frame callback alone does not request a frame.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _showTouchMenu() async {
    final snapshot = slash.snapshot;
    final slashStart = slash.slashStart;
    if (snapshot == null) return;
    _touchMenuShowing = true;
    try {
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      if (!mounted || !widget.adapter.accepts(snapshot, popupOwnsFocus: true)) {
        if (mounted) slash.close(cancel: true);
        return;
      }
      final choice = await guardedEditorSheet<BasicBlockChoice>(
        context,
        widget.adapter,
        snapshot,
        _touchMenuSurface,
        barrierColor: Colors.transparent,
        // Let the route resolve width again on rotation instead of retaining
        // the width of the portrait editor that opened it.
        constraints: const BoxConstraints(maxWidth: double.infinity),
      );
      if (!mounted) return;
      if (choice == null) {
        slash.close(cancel: true);
      } else {
        // This route owns its original guarded selection across focus changes.
        slash.close();
        await BasicBlockCommands(widget.adapter).choose(
          choice,
          snapshot,
          slashStart: slashStart,
          popupOwnsFocus: true,
        );
      }
    } finally {
      _touchMenuShowing = false;
    }
  }

  Widget _touchMenuSurface(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Material(
        color: Theme.of(context).colorScheme.surface,
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              Expanded(
                child: _controls(onBlocks: () => Navigator.pop(context)),
              ),
              IconButton(
                tooltip: editorText(context, 'Close block menu'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.cancel_outlined, size: 24),
              ),
            ],
          ),
        ),
      ),
      Flexible(
        child: BasicBlockMenu(
          controller: slash,
          sheet: true,
          toolbarOwnsClose: true,
          onClose: () => Navigator.pop(context),
          onChoose: (choice) => Navigator.pop(context, choice),
        ),
      ),
    ],
  );

  @override
  void dispose() {
    widget.adapter.editor.autoScroller?.stopAutoScroll();
    slash.removeListener(menuChanged);
    slash.dispose();
    scroll.dispose();
    header.dispose();
    footer.dispose();
    super.dispose();
  }

  void _closeBlockMenu() {
    if (_blockPortal.isShowing) _blockPortal.hide();
  }

  void _dismissFormattingOverlay() {
    final dismiss = _dismissFormatting;
    _dismissFormatting = null;
    dismiss?.call();
  }

  /// Dismisses only ephemeral overlay UI; the editor selection snapshot remains
  /// available to guarded formatting dialogs opened by this editor.
  void _dismissTransientEditorUi() {
    _dismissFormattingOverlay();
    // Its guarded native sheet owns this snapshot until the choice returns.
    if (!_touchMenuShowing && (slash.visible || slash.touchOpen)) {
      slash.close(cancel: true);
    }
    _closeBlockMenu();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), editable = widget.adapter.editable;
    final compact = MediaQuery.sizeOf(context).width < 720;
    final short = NoteFlowLayout.isShortEditor(context);
    final scale = MediaQuery.textScalerOf(context).scale(16);
    // Keep the engine widget and its input service stable across editor/header
    // notifications. Public Node listeners own text repaint; UI menus listen
    // separately. Replacing its services on each keystroke loses Web IME focus.
    if (_cachedView == null ||
        _cachedTheme != theme ||
        _cachedEditable != editable ||
        _cachedCompact != compact ||
        _cachedShort != short ||
        _cachedScale != scale) {
      _cachedTheme = theme;
      _cachedEditable = editable;
      _cachedCompact = compact;
      _cachedShort = short;
      _cachedScale = scale;
      _cachedView = _buildEditor(context);
    }
    // Keep popup semantics under this owner. A separate root OverlayEntry can
    // reparent the route's Web DOM subtree and blur its active text field.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onKeyEvent: (_, event) {
        if (kIsWeb && event is KeyDownEvent && !widget.adapter.composing) {
          _lastInputFocus = captureEditorInputFocus() ?? _lastInputFocus;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: OverlayPortal(
          overlayLocation: OverlayChildLocation.rootOverlay,
          controller: _blockPortal,
          overlayChildBuilder: (context) => ListenableBuilder(
            listenable: slash,
            builder: (context, _) => _menuOverlay(context),
          ),
          child: _cachedView!,
        ),
      ),
    );
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
        fileBlockBuilder: (block, attachment) =>
            widget.fileBlockBuilder?.call(block, attachment) ??
            const SizedBox.shrink(),
        onAddBlock: _openAfterBlock,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: NativeClipboardToolbar(
            adapter: adapter,
            focusNode: widget.focusNode,
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              child: _toolbar(context, editor),
            ),
          ),
        ),
        if (!kIsWeb) _nativeControls(context),
      ],
    );
  }

  Widget _toolbar(BuildContext context, Widget editor) {
    final adapter = widget.adapter, colors = Theme.of(context).colorScheme;
    return engine.FloatingToolbar(
      toolbarBuilder: _formattingOverlay,
      editorState: adapter.editor,
      editorScrollController: scroll,
      textDirection: Directionality.of(context),
      floatingToolbarHeight: SelectionToolbarLayout.heightFor(context),
      padding: EdgeInsets.zero,
      style: engine.FloatingToolbarStyle(
        backgroundColor: colors.surface,
        toolbarActiveColor: colors.primary,
        toolbarIconColor: colors.onSurface,
        toolbarElevation: !kIsWeb && NoteFlowLayout.isCompact(context) ? 0 : 8,
      ),
      decoration: !kIsWeb && NoteFlowLayout.isCompact(context)
          ? BoxDecoration(
              color: colors.surface,
              border: Border(top: BorderSide(color: colors.outlineVariant)),
            )
          : null,
      items: [
        engine.ToolbarItem(
          id: 'm09-selection',
          group: 0,
          isActive: (_) => adapter.capture() != null,
          builder: (_, _, _, _, _) => SelectionToolbar(
            adapter: adapter,
            dialogContext: context,
            onPopupOpen: _dismissFormattingOverlay,
          ),
        ),
      ],
      child: editor,
    );
  }
}
