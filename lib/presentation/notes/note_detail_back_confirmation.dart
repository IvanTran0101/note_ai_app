import 'package:flutter/material.dart';

import 'note_detail_localizations.dart';

/// Result of the unsaved-changes decision shown before leaving Note Detail.
enum NoteDetailBackDecision { save, discard, cancel }

/// Shows the mobile dirty-back decision without owning editor state.
Future<NoteDetailBackDecision?> showNoteDetailBackConfirmation({
  required BuildContext context,
  required NoteDetailCopy copy,
}) {
  return showDialog<NoteDetailBackDecision>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(copy.dirtyBackTitle),
        content: Text(copy.dirtyBackMessage),
        actions: <Widget>[
          TextButton(
            key: const ValueKey<String>('note-detail-back-cancel'),
            onPressed: () =>
                Navigator.of(context).pop(NoteDetailBackDecision.cancel),
            child: Text(copy.cancel),
          ),
          TextButton(
            key: const ValueKey<String>('note-detail-back-discard'),
            onPressed: () =>
                Navigator.of(context).pop(NoteDetailBackDecision.discard),
            child: Text(copy.discard),
          ),
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
