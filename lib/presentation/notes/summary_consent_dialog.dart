import 'package:flutter/material.dart';

import 'note_detail_localizations.dart';
import 'notes_theme_tokens.dart';

/// Widest the whole dialog may get: content plus the 24dp content paddings.
const double _maxDialogWidth = 320;

/// Content width that keeps the padded dialog at or below [_maxDialogWidth].
const double _maxContentWidth = _maxDialogWidth - (NoteFlowSpacing.xl * 2);

/// Asks the user to allow cloud summarization for the current account and
/// session.
///
/// Returns `true` only for an explicit Allow. Cancel, the Android back gesture,
/// Escape, and a barrier tap all resolve to `false`, so an accidental dismissal
/// can never be read as consent.
///
/// This helper owns no consent behavior: it never reaches the application
/// service, never grants, and never stores a decision. The caller captures its
/// own consent request before showing the dialog and applies it afterwards.
///
/// Copy is resolved inside the dialog builder, so a locale change while the
/// dialog is open re-renders the same dialog in the new language without
/// opening a second intent. The dialog is scrollable and its content stays
/// narrower than 320dp, so large text scaling and narrow phones keep every
/// action reachable.
Future<bool> showSummaryConsentDialog(BuildContext context) async {
  final bool? allowed = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: _buildSummaryConsentDialog,
  );
  return allowed ?? false;
}

Widget _buildSummaryConsentDialog(BuildContext dialogContext) {
  // Read inside the builder: a locale change re-runs this and retranslates the
  // open dialog without touching the caller's pending intent.
  final NoteDetailCopy copy = NoteDetailCopy.of(dialogContext);
  final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(dialogContext);
  final TextTheme textTheme = Theme.of(dialogContext).textTheme;

  return AlertDialog(
    key: const ValueKey<String>('summary-consent-dialog'),
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
    title: Text(copy.summaryCloudTitle),
    content: _SummaryConsentContent(copy: copy, tokens: tokens),
    actions: _buildActions(dialogContext, copy),
  );
}

List<Widget> _buildActions(BuildContext dialogContext, NoteDetailCopy copy) {
  return <Widget>[
    TextButton(
      key: const ValueKey<String>('summary-consent-cancel'),
      onPressed: () => Navigator.of(dialogContext).pop(false),
      child: Text(copy.cancel),
    ),
    FilledButton(
      key: const ValueKey<String>('summary-consent-allow'),
      onPressed: () => Navigator.of(dialogContext).pop(true),
      child: Text(copy.summaryCloudAllow),
    ),
  ];
}

/// Disclosure and scope summary of the consent dialog.
final class _SummaryConsentContent extends StatelessWidget {
  const _SummaryConsentContent({required this.copy, required this.tokens});

  final NoteDetailCopy copy;
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
          Text(copy.summaryCloudDisclosure),
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
                      copy.summaryCloudSessionLabel,
                      style: textTheme.labelLarge?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: NoteFlowSpacing.xs),
                    Text(
                      copy.summaryCloudSessionDescription,
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
