import 'package:flutter/material.dart';

import '../../application/note_intelligence/rag_app_service.dart';
import '../../application/note_intelligence/rag_state.dart';
import '../../domain/note_intelligence/rag_models.dart';
import '../notes/notes_theme_tokens.dart';
import 'rag_consent_dialog.dart';
import 'rag_controller.dart';
import 'rag_copy.dart';

/// Canonical RAG consent control for Settings and for the ask-notes screen.
///
/// The service is not a [ChangeNotifier], so this tile subscribes to its state
/// stream through a [RagController] (which reads the current snapshot before
/// subscribing). It performs no network work itself, never persists a choice,
/// and never guesses an unverified grant.
///
/// Turning the switch on opens the disclosure dialog first and applies
/// `setConsent(true)` only after an explicit Allow. Turning a grant off applies
/// `setConsent(false)` immediately, which is also what stops new questions and
/// clears a displayed answer. When the canonical grant is unknown or a read
/// failed, a manual Refresh performs one consent read and never resends a
/// question.
///
/// Copy is resolved inside `build` and inside the dialog builder, so a locale
/// change while the tile is visible retranslates the same state instead of
/// resetting it.
final class RagConsentSettingsTile extends StatefulWidget {
  /// Creates the tile over the application service.
  const RagConsentSettingsTile({super.key, required this.service});

  /// The application service that owns consent state and mutations.
  final RagAppService service;

  /// Key of the consent switch.
  static const Key switchKey = ValueKey<String>('rag-consent-switch');

  /// Key of the consent status text.
  static const Key statusKey = ValueKey<String>('rag-consent-status');

  /// Key of the manual permission refresh action.
  static const Key refreshKey = ValueKey<String>('rag-consent-refresh');

  /// Key of the consent error text.
  static const Key errorKey = ValueKey<String>('rag-consent-error');

  @override
  State<RagConsentSettingsTile> createState() =>
      _RagConsentSettingsTileState();
}

final class _RagConsentSettingsTileState extends State<RagConsentSettingsTile> {
  late RagController _controller;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = RagController(widget.service);
  }

  @override
  void didUpdateWidget(RagConsentSettingsTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service)) {
      _controller.dispose();
      _controller = RagController(widget.service);
    }
  }

  @override
  void dispose() {
    // Cancels only this tile's subscription: the shared service, any active
    // question it owns, and its gateway lifetime are untouched.
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final RagCopy copy = RagCopy.of(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, Widget? _) {
        final RagState state = _controller.state;
        final RagConsent? consent = state.consent;
        final bool loading = state.consentLoading;
        final bool granted = consent?.accepted ?? false;
        final RagFailure? failure = state.failure;
        final bool busy = loading || _dialogOpen;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SwitchListTile(
              key: RagConsentSettingsTile.switchKey,
              contentPadding: EdgeInsets.zero,
              secondary: _buildLeading(context, loading, granted),
              title: Text(copy.consentTitle),
              subtitle: Text(
                _statusText(copy, loading: loading, consent: consent),
                key: RagConsentSettingsTile.statusKey,
              ),
              value: granted,
              onChanged: busy ? null : _handleChanged,
            ),
            if (!loading && consent == null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: RagConsentSettingsTile.refreshKey,
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(copy.consentRefresh),
                ),
              ),
            // Only surfaced while the grant is unknown: a query failure on a
            // still-valid grant belongs to the ask screen, not this tile.
            if (!loading && consent == null && failure != null)
              _buildError(context, copy, failure),
          ],
        );
      },
    );
  }

  Widget _buildLeading(BuildContext context, bool loading, bool granted) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    if (loading) {
      return SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: tokens.textMuted),
      );
    }
    return Icon(
      granted ? Icons.shield_outlined : Icons.lock_outline,
      color: tokens.textSecondary,
    );
  }

  Widget _buildError(BuildContext context, RagCopy copy, RagFailure failure) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: NoteFlowSpacing.sm),
      child: Text(
        copy.failureMessage(failure),
        key: RagConsentSettingsTile.errorKey,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: tokens.error),
      ),
    );
  }

  String _statusText(
    RagCopy copy, {
    required bool loading,
    required RagConsent? consent,
  }) {
    if (loading) {
      return copy.consentStatusLoading;
    }
    if (consent == null) {
      return copy.consentStatusUnknown;
    }
    return consent.accepted
        ? copy.consentStatusAllowed
        : copy.consentStatusDenied;
  }

  void _refresh() {
    widget.service.refreshConsent();
  }

  Future<void> _handleChanged(bool value) async {
    if (_dialogOpen) {
      return;
    }
    if (!value) {
      // Explicit revoke takes effect immediately: the service clears the grant
      // and the displayed answer before its write is attempted.
      await widget.service.setConsent(false);
      return;
    }

    // Capture the exact account/session/service the user is consenting for
    // before the disclosure opens. The Allow may only apply to that same
    // binding; a grant must never migrate to an account, session, or service
    // that appeared while the dialog was open.
    final _ConsentIntent? intent = _captureConsentIntent();
    if (intent == null) {
      return;
    }

    setState(() => _dialogOpen = true);
    final bool allowed = await showRagConsentDialog(context);
    if (!mounted) {
      return;
    }
    if (allowed && _intentStillLive(intent)) {
      await widget.service.setConsent(true);
    }
    if (!mounted) {
      return;
    }
    setState(() => _dialogOpen = false);
  }

  /// The live binding an Allow would consent for, or null when there is
  /// nothing to bind to (unauthenticated or inactive).
  _ConsentIntent? _captureConsentIntent() {
    final RagAppService service = widget.service;
    final String? actorId = service.currentUser.userId;
    if (!service.currentUser.isAuthenticated || actorId == null) {
      return null;
    }
    if (!service.state.active) {
      return null;
    }
    return _ConsentIntent(
      service: service,
      actorId: actorId,
      sessionGeneration: service.session.sessionGeneration,
    );
  }

  /// Whether an Allow still applies to the binding it was opened for.
  ///
  /// The application service still compare-and-sets the write itself; this only
  /// stops an intent from being *started* for a different account, generation,
  /// or service after the await.
  bool _intentStillLive(_ConsentIntent intent) {
    final RagAppService service = widget.service;
    return identical(intent.service, service) &&
        service.currentUser.isAuthenticated &&
        service.currentUser.userId == intent.actorId &&
        service.session.sessionGeneration == intent.sessionGeneration &&
        service.state.active;
  }
}

/// The live binding one pending Allow was opened for.
final class _ConsentIntent {
  const _ConsentIntent({
    required this.service,
    required this.actorId,
    required this.sessionGeneration,
  });

  final RagAppService service;
  final String actorId;
  final int sessionGeneration;
}
