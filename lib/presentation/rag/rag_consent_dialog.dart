import 'package:flutter/material.dart';

import '../notes/notes_theme_tokens.dart';
import 'rag_copy.dart';

/// Widest the whole dialog may get: content plus the 24dp content paddings.
const double _maxDialogWidth = 360;

/// Content width that keeps the padded dialog at or below [_maxDialogWidth].
const double _maxContentWidth = _maxDialogWidth - (NoteFlowSpacing.xl * 2);

/// Asks the user to allow RAG (ask-my-notes) egress for the current account.
///
/// Returns `true` only for an explicit Allow. Cancel, Escape, the Android back
/// gesture, and a barrier tap all resolve to `false`, so a dismissal can never
/// be read as consent.
///
/// This helper owns no consent behavior: it never reaches the application
/// service, never grants, and never stores a decision. The caller applies the
/// decision only after an explicit Allow.
///
/// Copy is resolved inside the builder, so a locale change while the dialog is
/// open re-renders the same dialog in the new language without opening a second
/// intent. The dialog is scrollable and its content stays narrower than the
/// dialog, so large text scaling and narrow phones keep every action reachable.
Future<bool> showRagConsentDialog(BuildContext context) async {
  final bool? allowed = await showDialog<bool>(
    context: context,
    animationStyle: NoteFlowMotion.dialogStyle(context),
    barrierDismissible: true,
    builder: _buildRagConsentDialog,
  );
  return allowed ?? false;
}

Widget _buildRagConsentDialog(BuildContext dialogContext) {
  final RagCopy copy = RagCopy.of(dialogContext);
  final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(dialogContext);
  final TextTheme textTheme = Theme.of(dialogContext).textTheme;

  return AlertDialog(
    key: const ValueKey<String>('rag-consent-dialog'),
    scrollable: true,
    insetPadding: const EdgeInsets.symmetric(
      horizontal: NoteFlowSpacing.xl,
      vertical: NoteFlowSpacing.xl,
    ),
    backgroundColor: tokens.elevatedSurface,
    surfaceTintColor: Colors.transparent,
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
    title: Text(copy.consentDialogTitle),
    content: _RagConsentContent(copy: copy, tokens: tokens),
    actions: <Widget>[
      TextButton(
        key: const ValueKey<String>('rag-consent-cancel'),
        onPressed: () => Navigator.of(dialogContext).pop(false),
        child: Text(copy.consentDialogCancel),
      ),
      FilledButton(
        key: const ValueKey<String>('rag-consent-allow'),
        onPressed: () => Navigator.of(dialogContext).pop(true),
        child: Text(copy.consentDialogAllow),
      ),
    ],
  );
}

/// Disclosure and account/version scope summary of the consent dialog.
final class _RagConsentContent extends StatelessWidget {
  const _RagConsentContent({required this.copy, required this.tokens});

  final RagCopy copy;
  final NoteFlowUiTokens tokens;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _maxContentWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(copy.consentDisclosure),
          const SizedBox(height: NoteFlowSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.lock_outline, size: 16, color: tokens.textMuted),
              const SizedBox(width: NoteFlowSpacing.sm),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      copy.consentScopeLabel,
                      style: textTheme.labelLarge?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: NoteFlowSpacing.xs),
                    Text(
                      copy.consentScopeDescription,
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
