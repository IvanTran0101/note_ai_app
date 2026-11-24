import '../auth/current_user.dart';
import '../auth/current_user_session.dart';
import 'summary_cloud_consent.dart';
import 'summary_run_context.dart';

/// What the active account can do with cloud summarization right now.
///
/// The status is derived, never stored: [SummaryConsentAppService.state]
/// recomputes it from the runtime availability callback, the live account and
/// session, and the consent store.
enum SummaryConsentStatus {
  /// The runtime cannot summarize in the cloud (local mode, missing or
  /// incompatible configuration), or no account is authenticated.
  unavailable,

  /// Cloud summarization is possible, but this exact account and session has no
  /// current grant.
  consentRequired,

  /// A current grant exists for the live account and session generation.
  granted,
}

/// Proof that one consent confirmation was opened for an exact binding.
///
/// A request is issued only by [SummaryConsentAppService.beginConsent], which
/// is the only way to obtain one (there is no public constructor). It captures
/// the account, the session generation, and the global consent generation that
/// were live when the confirmation opened, plus the identity of the issuing
/// service. It carries no note, provider, token, or payload data; [toString]
/// reports the generations only, never the account id.
final class SummaryConsentRequest {
  const SummaryConsentRequest._({
    required this.accountUserId,
    required this.sessionGeneration,
    required this.consentGeneration,
    required this._issuer,
  });

  /// The account the confirmation was opened for.
  final String accountUserId;

  /// The session generation the confirmation was opened for.
  final int sessionGeneration;

  /// The consent store generation at the moment the confirmation opened.
  final int consentGeneration;

  /// The service instance that issued this request.
  final Object _issuer;

  @override
  String toString() {
    return 'SummaryConsentRequest(sessionGeneration: $sessionGeneration, '
        'consentGeneration: $consentGeneration)';
  }
}

/// Application service for the cloud-summarization consent decision.
///
/// It owns no consent state of its own: [SummaryCloudConsent] remains the only
/// store, and every mutation goes through it. The service adds the application
/// rules around it — runtime availability, which account and session a
/// confirmation belongs to, and which outstanding confirmations are still
/// usable.
///
/// One request is valid at most once: a successful grant advances the store
/// generation, so replaying the same [SummaryConsentRequest] (or a request
/// issued for an earlier dialog, revoke, regrant, or a different service
/// instance) is stale and can never grant again.
final class SummaryConsentAppService {
  SummaryConsentAppService({
    required this._currentUser,
    required this._session,
    required this._consent,
    required this._isAvailable,
    required this._cancelActiveRuns,
    this._requiresCloudConsent = true,
  });

  final ICurrentUser _currentUser;
  final SessionGenerationSource _session;
  final SummaryCloudConsent _consent;

  /// Whether the runtime can summarize in the cloud right now.
  final bool Function() _isAvailable;

  /// Cancels every active summary run; the composition root binds this to the
  /// runtime's cancellation with [SummaryRunFailureCode.consentRequired].
  final void Function() _cancelActiveRuns;
  final bool _requiresCloudConsent;

  /// False for local composition; no cloud dialog is needed for local inference.
  bool get requiresCloudConsent => _requiresCloudConsent;

  /// Safe runtime/session reason generation is unavailable in this composition.
  SummaryRunFailureCode? get unavailableReason {
    if (!_isAvailable()) return SummaryRunFailureCode.runtimeUnavailable;
    return _liveAccountUserId == null
        ? SummaryRunFailureCode.unauthorized
        : null;
  }

  final Object _issuer = Object();

  /// The current consent status for the live account and session.
  SummaryConsentStatus get state {
    final String? accountUserId = _liveAccountUserId;
    if (!_requiresCloudConsent || accountUserId == null || !_isAvailable()) {
      return SummaryConsentStatus.unavailable;
    }
    final SummaryCloudConsentSnapshot snapshot = _consent.capture(
      accountUserId: accountUserId,
      sessionGeneration: _session.sessionGeneration,
    );
    return _consent.isCurrent(snapshot)
        ? SummaryConsentStatus.granted
        : SummaryConsentStatus.consentRequired;
  }

  /// Opens one confirmation for the live account, session, and consent
  /// generation.
  ///
  /// Throws [SummaryRunFailure] with [SummaryRunFailureCode.runtimeUnavailable]
  /// when the runtime cannot summarize, or with
  /// [SummaryRunFailureCode.sessionChanged] when no account is authenticated.
  /// Neither case captures or mutates anything, so a refused confirmation can
  /// never be completed later.
  SummaryConsentRequest beginConsent() {
    if (!_requiresCloudConsent || !_isAvailable()) {
      throw const SummaryRunFailure(SummaryRunFailureCode.runtimeUnavailable);
    }
    final String? accountUserId = _liveAccountUserId;
    if (accountUserId == null) {
      throw const SummaryRunFailure(SummaryRunFailureCode.sessionChanged);
    }
    return SummaryConsentRequest._(
      accountUserId: accountUserId,
      sessionGeneration: _session.sessionGeneration,
      consentGeneration: _consent.generation,
      issuer: _issuer,
    );
  }

  /// Applies the confirmation [request] represents.
  ///
  /// Every check is synchronous and runs before any mutation, in this order:
  /// the request must come from this service instance, the live account and
  /// session generation must still be the captured ones, the runtime must still
  /// be available, and the store generation must be unchanged since the
  /// confirmation opened. A mutation happens only when all four hold, and it
  /// grants the captured account and session — never the account that happens
  /// to be live at confirmation time.
  ///
  /// Throws [SummaryRunFailure] with [SummaryRunFailureCode.sessionChanged]
  /// when the account or session generation changed,
  /// [SummaryRunFailureCode.consentRequired] when the request is stale (foreign
  /// issuer, earlier dialog, or already granted/revoked generation), and
  /// [SummaryRunFailureCode.runtimeUnavailable] when the runtime cannot
  /// summarize.
  void grantConsent(SummaryConsentRequest request) {
    if (!identical(request._issuer, _issuer)) {
      throw const SummaryRunFailure(SummaryRunFailureCode.consentRequired);
    }
    final String? accountUserId = _liveAccountUserId;
    if (accountUserId == null ||
        accountUserId != request.accountUserId ||
        _session.sessionGeneration != request.sessionGeneration) {
      throw const SummaryRunFailure(SummaryRunFailureCode.sessionChanged);
    }
    if (!_requiresCloudConsent || !_isAvailable()) {
      throw const SummaryRunFailure(SummaryRunFailureCode.runtimeUnavailable);
    }
    if (_consent.generation != request.consentGeneration) {
      throw const SummaryRunFailure(SummaryRunFailureCode.consentRequired);
    }
    _consent.grant(
      accountUserId: request.accountUserId,
      sessionGeneration: request.sessionGeneration,
    );
  }

  /// Revokes cloud consent for every account and aborts active runs.
  ///
  /// The store is cleared first, then [_cancelActiveRuns] runs, so a cancelled
  /// run can never observe a grant the revocation already removed. Revocation
  /// itself is never duplicated here: cancelling runs is the callback's only
  /// job.
  void revokeConsent() {
    _consent.revoke();
    _cancelActiveRuns();
  }

  String? get _liveAccountUserId {
    if (!_currentUser.isAuthenticated) {
      return null;
    }
    return _currentUser.userId;
  }
}
