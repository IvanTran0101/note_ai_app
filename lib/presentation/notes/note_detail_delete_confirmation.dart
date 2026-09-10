import 'package:flutter/material.dart';

import 'note_detail_localizations.dart';

/// Shows the final confirmation for deleting a note.
Future<bool?> showNoteDetailDeleteConfirmation({
  required BuildContext context,
  required NoteDetailCopy copy,
  required Key confirmKey,
}) {
  return showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(copy.deleteTitle),
        content: Text(copy.deleteMessage),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(copy.cancel),
          ),
          FilledButton(
            key: confirmKey,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(copy.delete),
          ),
        ],
      );
    },
  );
}
