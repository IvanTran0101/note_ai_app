import 'package:flutter/material.dart';

import 'note_detail_confirmation_dialog.dart';
import 'note_detail_localizations.dart';
import 'notes_theme_tokens.dart';

/// Shows the final confirmation for deleting a note.
///
/// The confirm action is styled as a destructive button and always carries
/// [confirmKey] so tests and semantics can target it.
Future<bool?> showNoteDetailDeleteConfirmation({
  required BuildContext context,
  required NoteDetailCopy copy,
  required Key confirmKey,
}) {
  return showDialog<bool>(
    context: context,
    animationStyle: NoteFlowMotion.dialogStyle(context),
    builder: (BuildContext context) {
      final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
      return buildNoteDetailConfirmationDialog(
        context: context,
        title: Text(copy.deleteTitle),
        content: Text(copy.deleteMessage),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(copy.cancel),
          ),
          FilledButton(
            key: confirmKey,
            style: FilledButton.styleFrom(
              backgroundColor: tokens.error,
              foregroundColor: tokens.onDestructive,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(copy.delete),
          ),
        ],
      );
    },
  );
}
