import 'package:flutter/material.dart';

import '../common/note_flow_primitives.dart';
import 'note_detail_localizations.dart';
import 'notes_theme_tokens.dart';

/// Shows non-destructive secondary actions for a note as a Notion-style
/// bottom-sheet menu with a destructive-styled delete item.
Future<bool?> showNoteDetailMoreActions({
  required BuildContext context,
  required NoteDetailCopy copy,
  BuildContext? anchorContext,
}) {
  final bool compact =
      MediaQuery.sizeOf(context).width < NoteFlowLayout.compactBreakpoint;
  if (!compact && anchorContext != null) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final RenderBox overlay =
        Overlay.of(anchorContext).context.findRenderObject()! as RenderBox;
    final RenderBox anchor = anchorContext.findRenderObject()! as RenderBox;
    final Offset topLeft = anchor.localToGlobal(Offset.zero, ancestor: overlay);
    final Rect anchorRect = (topLeft & anchor.size).shift(
      Offset(0, anchor.size.height - NoteFlowSpacing.sm),
    );
    return showMenu<bool>(
      context: context,
      position: RelativeRect.fromRect(anchorRect, Offset.zero & overlay.size),
      color: tokens.elevatedSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      popUpAnimationStyle: NoteFlowMotion.dialogStyle(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NoteFlowRadius.card),
        side: BorderSide(color: tokens.divider),
      ),
      items: <PopupMenuEntry<bool>>[
        PopupMenuItem<bool>(
          key: const ValueKey<String>('note-detail-more-delete'),
          value: true,
          height: 48,
          child: SizedBox(
            width: 188,
            child: Row(
              children: <Widget>[
                Icon(Icons.delete_outline, size: 18, color: tokens.error),
                const SizedBox(width: NoteFlowSpacing.sm),
                Text(
                  copy.delete,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: tokens.error),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  return showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    sheetAnimationStyle: NoteFlowMotion.dialogStyle(context),
    builder: (BuildContext context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: NoteFlowSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              NoteFlowMenuItem(
                key: const ValueKey<String>('note-detail-more-delete'),
                label: copy.delete,
                icon: Icons.delete_outline,
                destructive: true,
                onTap: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Runs the selected secondary action after the sheet has been dismissed.
Future<void> runNoteDetailMoreActions({
  required BuildContext context,
  required NoteDetailCopy copy,
  BuildContext? anchorContext,
  required Future<void> Function() onDelete,
}) async {
  final bool? deleteSelected = await showNoteDetailMoreActions(
    context: context,
    copy: copy,
    anchorContext: anchorContext,
  );
  if (deleteSelected == true) {
    await onDelete();
  }
}
