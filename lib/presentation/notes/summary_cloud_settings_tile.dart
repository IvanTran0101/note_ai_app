import 'package:flutter/material.dart';

import '../../application/note_intelligence/summary_consent_app_service.dart';
import '../../application/note_intelligence/summary_run_context.dart';
import 'note_detail_localizations.dart';
import 'notes_theme_tokens.dart';
import 'summary_consent_dialog.dart';

/// Settings switch for cloud-summarization consent.
///
/// The tile is hidden entirely when the composition does not require cloud
/// consent (local inference) and disabled with the runtime's safe reason when
/// the service is unavailable. Turning the switch on captures one consent
/// request and then asks for confirmation with [showSummaryConsentDialog];
/// only an explicit Allow applies the request. Turning a grant off revokes it
/// immediately, which is also what cancels active runs.
///
/// The tile performs no network work itself, never persists a choice, and
/// resolves [NoteDetailCopy] inside its own `build`, so a locale change while
/// it is visible retranslates the same state instead of resetting it.
final class SummaryCloudSettingsTile extends StatefulWidget {
  /// Creates the tile over the application consent service.
  const SummaryCloudSettingsTile({super.key, required this.service});

  /// The application service that owns consent state and mutations.
  final SummaryConsentAppService service;

  @override
  State<SummaryCloudSettingsTile> createState() =>
      _SummaryCloudSettingsTileState();
}

final class _SummaryCloudSettingsTileState
    extends State<SummaryCloudSettingsTile> {
  /// True while a confirmation is pending, so a second popup cannot open.
  bool _busy = false;

  /// Safe reason of the last refused consent action, or null.
  SummaryRunFailureCode? _errorCode;

  @override
  Widget build(BuildContext context) {
    final SummaryConsentAppService service = widget.service;
    if (!service.requiresCloudConsent) {
      return const SizedBox.shrink();
    }

    final NoteDetailCopy copy = NoteDetailCopy.of(context);
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final SummaryConsentStatus status = service.state;
    final bool unavailable = status == SummaryConsentStatus.unavailable;
    final SummaryRunFailureCode? unavailableReason = unavailable
        ? service.unavailableReason
        : null;
    final SummaryRunFailureCode? errorCode = _errorCode;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SwitchListTile(
          key: const ValueKey<String>('summary-cloud-consent-switch'),
          contentPadding: EdgeInsets.zero,
          secondary: Icon(
            unavailable ? Icons.cloud_off_outlined : Icons.cloud_outlined,
            color: unavailable ? tokens.textMuted : tokens.textSecondary,
          ),
          title: Text(copy.summaryCloudTitle),
          subtitle: unavailable
              ? Text(
                  unavailableReason == null
                      ? copy.summaryCloudUnavailable
                      : copy.summaryFailureMessage(unavailableReason),
                )
              : _buildSessionSubtitle(copy, tokens, status),
          value: status == SummaryConsentStatus.granted,
          onChanged: unavailable || _busy ? null : _handleChanged,
        ),
        // While the tile is unavailable the subtitle already carries the safe
        // runtime reason, so the same message is not repeated below it.
        if (errorCode != null && !unavailable)
          _buildError(copy, tokens, errorCode),
      ],
    );
  }

  Widget _buildError(
    NoteDetailCopy copy,
    NoteFlowUiTokens tokens,
    SummaryRunFailureCode errorCode,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: NoteFlowSpacing.sm),
      child: Text(
        copy.summaryFailureMessage(errorCode),
        key: const ValueKey<String>('summary-cloud-consent-error'),
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: tokens.error),
      ),
    );
  }

  Widget _buildSessionSubtitle(
    NoteDetailCopy copy,
    NoteFlowUiTokens tokens,
    SummaryConsentStatus status,
  ) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (status == SummaryConsentStatus.granted) ...<Widget>[
          Text(
            copy.summaryCloudSessionLabel,
            style: textTheme.labelMedium?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: NoteFlowSpacing.xs),
        ],
        Text(
          copy.summaryCloudSessionDescription,
          style: textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
        ),
      ],
    );
  }

  Future<void> _handleChanged(bool value) async {
    if (_busy) {
      return;
    }
    if (!value) {
      // Revoke first: the service clears the grant and then cancels runs.
      widget.service.revokeConsent();
      if (!mounted) {
        return;
      }
      setState(() => _errorCode = null);
      return;
    }

    final SummaryConsentRequest request;
    try {
      // Captured before the dialog opens, so the confirmation belongs to the
      // account, session, and consent generation that are live right now.
      request = widget.service.beginConsent();
    } on SummaryRunFailure catch (failure) {
      if (!mounted) {
        return;
      }
      setState(() => _errorCode = failure.code);
      return;
    }

    setState(() {
      _busy = true;
      _errorCode = null;
    });
    final bool allowed = await showSummaryConsentDialog(context);
    if (!mounted) {
      return;
    }
    if (!allowed) {
      setState(() => _busy = false);
      return;
    }

    try {
      widget.service.grantConsent(request);
    } on SummaryRunFailure catch (failure) {
      setState(() {
        _busy = false;
        _errorCode = failure.code;
      });
      return;
    }
    setState(() => _busy = false);
  }
}
