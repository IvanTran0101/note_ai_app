import 'package:flutter/material.dart';

import '../common/note_flow_primitives.dart';
import 'note_detail_localizations.dart';
import 'notes_theme_tokens.dart';

/// Shows non-destructive secondary actions for a note as a Notion-style
/// bottom-sheet menu with a destructive-styled delete item.
Future<bool?> showNoteDetailMoreActions({
  required BuildContext context,
  required NoteDetailCopy copy,
}) {
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
  required Future<void> Function() onDelete,
}) async {
  final bool? deleteSelected = await showNoteDetailMoreActions(
    context: context,
    copy: copy,
  );
  if (deleteSelected == true) {
    await onDelete();
  }
}
