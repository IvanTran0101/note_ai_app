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
  bool allowDelete = true,
  List<Widget> Function(BuildContext)? additionalActions,
  double? additionalActionsHeight,
}) {
  final bool compact = NoteFlowLayout.isCompact(context);
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NoteFlowRadius.card),
        side: BorderSide(color: tokens.divider),
      ),
      items: <PopupMenuEntry<bool>>[
        if (additionalActions != null)
          _NoteDetailActionGroupEntry(
            key: const ValueKey<String>('note-detail-more-actions'),
            builder: additionalActions,
            estimatedHeight: additionalActionsHeight ?? 48,
          ),
        if (allowDelete && additionalActions != null)
          PopupMenuDivider(color: tokens.divider),
        if (allowDelete)
          PopupMenuItem<bool>(
            key: const ValueKey<String>('note-detail-more-delete'),
            value: true,
            height: 44,
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
    builder: (BuildContext context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: NoteFlowSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ...?additionalActions?.call(context),
              if (allowDelete)
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

/// Builds secondary actions in the menu route so each row receives the right
/// Navigator context. Its children own their taps; this entry never returns a
/// menu value or intercepts a child tap.
final class _NoteDetailActionGroupEntry extends PopupMenuEntry<bool> {
  const _NoteDetailActionGroupEntry({
    super.key,
    required this.builder,
    required this.estimatedHeight,
  });

  final List<Widget> Function(BuildContext) builder;
  final double estimatedHeight;

  @override
  double get height => estimatedHeight;

  @override
  bool represents(bool? value) => false;

  @override
  State<_NoteDetailActionGroupEntry> createState() =>
      _NoteDetailActionGroupEntryState();
}

final class _NoteDetailActionGroupEntryState
    extends State<_NoteDetailActionGroupEntry> {
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final Widget action in widget.builder(context))
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: NoteFlowLayout.isCompact(context) ? 48 : 44,
            ),
            child: action,
          ),
      ],
    ),
  );
}

/// Runs the selected secondary action after the sheet has been dismissed.
Future<void> runNoteDetailMoreActions({
  required BuildContext context,
  required NoteDetailCopy copy,
  BuildContext? anchorContext,
  required Future<void> Function() onDelete,
  bool allowDelete = true,
  List<Widget> Function(BuildContext)? additionalActions,
  double? additionalActionsHeight,
}) async {
  final bool? deleteSelected = await showNoteDetailMoreActions(
    context: context,
    copy: copy,
    anchorContext: anchorContext,
    allowDelete: allowDelete,
    additionalActions: additionalActions,
    additionalActionsHeight: additionalActionsHeight,
  );
  if (deleteSelected == true) {
    await onDelete();
  }
}
