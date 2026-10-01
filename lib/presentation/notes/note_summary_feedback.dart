import 'package:flutter/material.dart';

import '../../application/note_intelligence/summary_run_context.dart';
import 'note_detail_localizations.dart';
import 'note_summary_availability.dart';
import 'note_summary_controller.dart';
import 'notes_theme_tokens.dart';

/// Localized text for the shared error row while a Summary failure is shown.
final class NoteSummaryFailureCopy {
  const NoteSummaryFailureCopy({
    required this.message,
    required this.retryLabel,
    required this.retryEnabled,
  });

  /// Safe, localized explanation of the typed or untyped failure.
  final String message;

  /// Label of the explicit user retry, replaced by the bounded countdown while
  /// a rate-limit hint is still pending.
  final String retryLabel;

  /// Whether the retry may dispatch right now.
  final bool retryEnabled;
}

/// Resolves the Summary failure row, or null when none should be presented.
///
/// [suppressed] lets the host keep a failed or cancelled local provisioning
/// notice as the only message, exactly as before this phase. [retryEnabled] is
/// the same eligibility the primary and regenerate actions use, so a retry is
/// never offered while the editor is dirty, conflicted, busy, or cooling down.
/// The text is derived here on every build, so a language change retranslates
/// an error that is already visible without storing copy in the controller.
NoteSummaryFailureCopy? noteSummaryFailureCopy({
  required NoteDetailCopy copy,
  required NoteSummaryController controller,
  required bool suppressed,
  required bool retryEnabled,
}) {
  if (suppressed || !controller.hasFailure) {
    return null;
  }
  final SummaryRunFailureCode? code = controller.failureCode;
  return NoteSummaryFailureCopy(
    message: code == null
        ? copy.summarizeError
        : copy.summaryFailureMessage(code),
    retryLabel: controller.isCoolingDown
        ? copy.summaryRetryAfter(controller.cooldownSeconds)
        : copy.retry,
    retryEnabled: retryEnabled,
  );
}

/// Compact status area for the Summary feature.
///
/// It renders two things the Note Detail editor must always be able to show,
/// in both the embedded and the standalone host:
///
/// * a simple indeterminate progress row with a permanent Cancel action while
///   a generation call is in flight, and
/// * one readable availability notice when the action cannot start (draft,
///   unsaved edits, sync conflict, unavailable runtime, signed-out account) or
///   when it can start only after the user allows cloud summaries.
///
/// It owns no state and resolves no policy: the availability and the running
/// flag come from [NoteSummaryController], and every string is read from
/// [NoteDetailCopy] during build so a locale change retranslates the open
/// editor without rebuilding the page.
final class NoteSummaryFeedback extends StatelessWidget {
  const NoteSummaryFeedback({
    super.key,
    required this.copy,
    required this.availability,
    required this.cloud,
    required this.isRunning,
    this.onCancel,
  });

  /// Key of the availability notice row.
  static const Key availabilityKey = ValueKey<String>(
    'note-detail-summary-availability',
  );

  /// Key of the Cancel action that is visible for the whole run.
  static const Key cancelKey = ValueKey<String>('note-detail-summary-cancel');

  /// Key of the indeterminate progress indicator.
  static const Key progressKey = ValueKey<String>(
    'note-detail-summary-progress',
  );

  final NoteDetailCopy copy;
  final NoteSummaryAvailability availability;
  final bool cloud;
  final bool isRunning;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final String? notice = _availabilityMessage();
    if (!isRunning && notice == null) {
      return const SizedBox.shrink();
    }
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: NoteFlowSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (isRunning) _buildProgress(context, tokens),
          if (notice != null) ...<Widget>[
            if (isRunning) const SizedBox(height: NoteFlowSpacing.sm),
            _buildNotice(context, tokens, notice),
          ],
        ],
      ),
    );
  }

  Widget _buildProgress(BuildContext context, NoteFlowUiTokens tokens) {
    return Row(
      children: <Widget>[
        const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(key: progressKey, strokeWidth: 2),
        ),
        const SizedBox(width: NoteFlowSpacing.sm),
        Expanded(
          child: Text(
            copy.summarizing,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.textSecondary),
          ),
        ),
        TextButton(
          key: cancelKey,
          onPressed: onCancel,
          child: Text(copy.cancel),
        ),
      ],
    );
  }

  Widget _buildNotice(
    BuildContext context,
    NoteFlowUiTokens tokens,
    String notice,
  ) {
    final bool actionable =
        availability == NoteSummaryAvailability.consentRequired;
    return Semantics(
      liveRegion: true,
      label: notice,
      child: Container(
        key: availabilityKey,
        padding: const EdgeInsets.all(NoteFlowSpacing.md),
        decoration: BoxDecoration(
          color: tokens.subtleSurface,
          borderRadius: BorderRadius.circular(NoteFlowRadius.card),
          border: Border.all(color: tokens.divider),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              actionable ? Icons.lock_outline : _availabilityIcon(),
              size: 18,
              color: tokens.textMuted,
            ),
            const SizedBox(width: NoteFlowSpacing.sm),
            Expanded(
              child: Text(
                notice,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: tokens.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _availabilityIcon() {
    return switch (availability) {
      NoteSummaryAvailability.conflict => Icons.compare_arrows,
      NoteSummaryAvailability.unavailable => Icons.cloud_off_outlined,
      NoteSummaryAvailability.signInRequired => Icons.lock_outline,
      NoteSummaryAvailability.draft ||
      NoteSummaryAvailability.dirty => Icons.save_outlined,
      NoteSummaryAvailability.ready ||
      NoteSummaryAvailability.consentRequired => Icons.info_outline,
    };
  }

  /// The localized notice, derived on every build, or null when none applies.
  String? _availabilityMessage() {
    return switch (availability) {
      NoteSummaryAvailability.ready => null,
      NoteSummaryAvailability.consentRequired => copy.summaryConsentRequired,
      NoteSummaryAvailability.draft ||
      NoteSummaryAvailability.dirty => copy.summarySavedRequired,
      NoteSummaryAvailability.conflict => copy.summaryConflictBlocked,
      NoteSummaryAvailability.signInRequired => copy.summarySignInRequired,
      NoteSummaryAvailability.unavailable =>
        cloud ? copy.summaryCloudUnavailable : copy.summaryLocalUnavailable,
    };
  }
}
