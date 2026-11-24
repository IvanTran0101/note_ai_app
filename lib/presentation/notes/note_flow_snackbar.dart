import 'package:flutter/material.dart';

import 'notes_theme_tokens.dart';

/// Builds the shared floating toast used for transient Notes feedback.
///
/// An optional action is passed through unchanged so its existing behavior is
/// owned by the caller.
SnackBar buildNoteFlowSnackBar({
  required BuildContext context,
  required String message,
  SnackBarAction? action,
}) {
  final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
  final TextTheme textTheme = Theme.of(context).textTheme;

  return SnackBar(
    content: Text(
      message,
      style: textTheme.bodyMedium?.copyWith(color: tokens.textPrimary),
    ),
    action: action,
    behavior: SnackBarBehavior.floating,
    backgroundColor: tokens.elevatedSurface,
    elevation: 3,
    margin: const EdgeInsets.all(NoteFlowSpacing.md),
    padding: const EdgeInsets.symmetric(
      horizontal: NoteFlowSpacing.lg,
      vertical: NoteFlowSpacing.md,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(NoteFlowRadius.card),
      side: BorderSide(color: tokens.divider),
    ),
  );
}
