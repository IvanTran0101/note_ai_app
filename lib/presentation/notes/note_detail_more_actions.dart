import 'package:flutter/material.dart';

import 'note_detail_localizations.dart';

/// Shows non-destructive secondary actions for a note.
Future<bool?> showNoteDetailMoreActions({
  required BuildContext context,
  required NoteDetailCopy copy,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    builder: (BuildContext context) {
      return SafeArea(
        child: ListTile(
          key: const ValueKey<String>('note-detail-more-delete'),
          leading: const Icon(Icons.delete_outline),
          title: Text(copy.delete),
          onTap: () => Navigator.of(context).pop(true),
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
