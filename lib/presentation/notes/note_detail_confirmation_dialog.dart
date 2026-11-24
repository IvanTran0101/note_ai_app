import 'package:flutter/material.dart';

import 'notes_theme_tokens.dart';

/// Shared Notion-inspired surface for Note Detail confirmation dialogs.
///
/// The caller continues to own the dialog actions and their behavior.
AlertDialog buildNoteDetailConfirmationDialog({
  required BuildContext context,
  required Widget title,
  required Widget content,
  required List<Widget> actions,
}) {
  final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
  final TextTheme textTheme = Theme.of(context).textTheme;

  return AlertDialog(
    title: title,
    content: content,
    actions: actions,
    backgroundColor: tokens.elevatedSurface,
    surfaceTintColor: Colors.transparent,
    insetPadding: const EdgeInsets.symmetric(
      horizontal: NoteFlowSpacing.xl,
      vertical: NoteFlowSpacing.xl,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(NoteFlowRadius.dialog),
      side: BorderSide(color: tokens.divider),
    ),
    titlePadding: const EdgeInsets.fromLTRB(
      NoteFlowSpacing.xl,
      NoteFlowSpacing.xl,
      NoteFlowSpacing.xl,
      0,
    ),
    contentPadding: const EdgeInsets.fromLTRB(
      NoteFlowSpacing.xl,
      NoteFlowSpacing.md,
      NoteFlowSpacing.xl,
      0,
    ),
    actionsPadding: const EdgeInsets.fromLTRB(
      NoteFlowSpacing.lg,
      NoteFlowSpacing.sm,
      NoteFlowSpacing.lg,
      NoteFlowSpacing.lg,
    ),
    titleTextStyle: textTheme.titleMedium?.copyWith(
      color: tokens.textPrimary,
      fontWeight: FontWeight.w600,
    ),
    contentTextStyle: textTheme.bodyMedium?.copyWith(
      color: tokens.textSecondary,
      height: 1.5,
    ),
  );
}
