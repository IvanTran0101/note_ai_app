part of 'rich_note_editor.dart';

/// Placement and dismissal of ephemeral UI in the root overlay.
extension _RichNoteEditorOverlays on _RichNoteEditorState {
  Widget _menuOverlay(BuildContext context) {
    final rects = widget.adapter.editor.selectionRects();
    final rect = rects.isEmpty
        ? const Rect.fromLTWH(24, 220, 0, 0)
        : rects.last;
    final popup = EditorPopupArea.of(context);
    // Desktop reference menus start just before the caret and leave16px
    // vertically; place() already supplies the first8px of that gap.
    final anchor = BasicBlockMenu.isCompactDesktop(context)
        ? rect.inflate(8)
        : rect;
    final placed = popup.place(
      anchor,
      BasicBlockMenu.popupSizeFor(context),
      preferBelow: true,
    );
    return Positioned.fromRect(
      rect: placed,
      child: TapRegion(
        onTapOutside: (_) => _dismissTransientEditorUi(),
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
    final desktopPopup = SelectionToolbarLayout.isDesktopPopup(context);
    final nativeDock = !kIsWeb && NoteFlowLayout.isCompact(context);
    final rect = desktopPopup ? rects.last : rects.first;
    final width = math.min(
      nativeDock ? area.size.width : area.size.width - 40,
      SelectionToolbarLayout.widthFor(context),
    );
    final short = NoteFlowLayout.isShortEditor(context);
    final height = SelectionToolbarLayout.heightFor(context);
    final popup = EditorPopupArea.of(context);
    final docked =
        (!kIsWeb && NoteFlowLayout.isCompact(context)) ||
        (short && area.viewInsets.bottom > 0);
    final placed = desktopPopup
        ? _placeDesktopSelectionPopup(popup, rect, Size(width, height))
        : docked
        ? Rect.fromLTWH(
            nativeDock ? area.padding.left : popup.bounds.center.dx - width / 2,
            popup.bounds.bottom +
                (nativeDock ? 12 : 0) -
                math.min(height, popup.bounds.height),
            width,
            math.min(height, popup.bounds.height),
          )
        : popup.place(rect, Size(width, height), centered: true);
    return Positioned.fromRect(
      rect: placed,
      child: TapRegion(
        onTapOutside: (_) => _dismissTransientEditorUi(),
        child: ClipRect(child: SingleChildScrollView(child: child)),
      ),
    );
  }

  Rect _placeDesktopSelectionPopup(
    EditorPopupArea popup,
    Rect globalSelection,
    Size requested,
  ) {
    final bounds = popup.bounds;
    final selection = globalSelection.shift(-popup.origin);
    final width = math.min(requested.width, bounds.width);
    final height = math.min(requested.height, bounds.height);
    // The reference's painted panel starts16px beyond its selection; its
    // transparent hit margin is not part of our compact three-row surface.
    const gap = 16.0;
    final right = selection.right + gap;
    final left = right + width <= bounds.right
        ? right
        : selection.left - width - gap;
    final below = selection.bottom + gap;
    final above = selection.top - height - gap;
    final top = below + height <= bounds.bottom ? below : above;
    return Rect.fromLTWH(
      left.clamp(bounds.left, bounds.right - width).toDouble(),
      top.clamp(bounds.top, bounds.bottom - height).toDouble(),
      width,
      height,
    );
  }
}
