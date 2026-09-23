import 'package:flutter/material.dart';

import 'note_detail_confirmation_dialog.dart';
import 'note_detail_localizations.dart';
import 'notes_theme_tokens.dart';

/// Result of the unsaved-changes decision shown before leaving Note Detail.
enum NoteDetailBackDecision { save, discard, cancel }

/// Shows the dirty-back decision without owning editor state.
///
/// Save is offered only when the current target can persist notes. Discard is
/// styled as a quiet destructive text action following the Notion menu grammar.
Future<NoteDetailBackDecision?> showNoteDetailBackConfirmation({
  required BuildContext context,
  required NoteDetailCopy copy,
  bool canSave = true,
}) {
  return showDialog<NoteDetailBackDecision>(
    context: context,
    builder: (BuildContext context) {
      final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
      return buildNoteDetailConfirmationDialog(
        context: context,
        title: Text(canSave ? copy.dirtyBackTitle : copy.unsavedChanges),
        content: Text(
          canSave ? copy.dirtyBackMessage : copy.persistenceUnavailable,
        ),
        actions: <Widget>[
          TextButton(
            key: const ValueKey<String>('note-detail-back-cancel'),
            onPressed: () =>
                Navigator.of(context).pop(NoteDetailBackDecision.cancel),
            child: Text(copy.cancel),
          ),
          TextButton(
            key: const ValueKey<String>('note-detail-back-discard'),
            style: TextButton.styleFrom(foregroundColor: tokens.error),
            onPressed: () =>
                Navigator.of(context).pop(NoteDetailBackDecision.discard),
            child: Text(copy.discard),
          ),
          if (canSave)
            FilledButton(
              key: const ValueKey<String>('note-detail-back-save'),
              onPressed: () =>
                  Navigator.of(context).pop(NoteDetailBackDecision.save),
              child: Text(copy.save),
            ),
        ],
      );
    },
  );
}
