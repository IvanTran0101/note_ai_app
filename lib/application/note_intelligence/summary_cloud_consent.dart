import '../auth/current_user_session.dart';

/// Immutable snapshot of cloud-summarization consent at one moment.
///
/// A snapshot binds the decision to the exact account and session generation it
/// was captured for, plus the monotonic [consentGeneration] of the matching
/// grant. [SummaryCloudConsent.isCurrent] is the only valid way to revalidate
/// it: a snapshot is never trusted on its own.
final class SummaryCloudConsentSnapshot {
  const SummaryCloudConsentSnapshot._({
    required this.accountUserId,
    required this.sessionGeneration,
    required this.isGranted,
    required this.consentGeneration,
  });

  /// Snapshot for an account that has not granted cloud summarization.
  const SummaryCloudConsentSnapshot.notGranted({
    required String accountUserId,
    required int sessionGeneration,
  }) : this._(
         accountUserId: accountUserId,
         sessionGeneration: sessionGeneration,
         isGranted: false,
         consentGeneration: 0,
       );

  /// The account this snapshot is bound to.
  final String accountUserId;

  /// The session generation this snapshot is bound to.
  final int sessionGeneration;

  /// Whether cloud summarization was granted for this exact binding.
  final bool isGranted;

  /// The monotonic grant generation, or 0 when [isGranted] is false.
  final int consentGeneration;

  @override
  bool operator ==(Object other) {
    return other is SummaryCloudConsentSnapshot &&
        other.accountUserId == accountUserId &&
        other.sessionGeneration == sessionGeneration &&
        other.isGranted == isGranted &&
        other.consentGeneration == consentGeneration;
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    accountUserId,
    sessionGeneration,
    isGranted,
    consentGeneration,
  );

  @override
  String toString() {
    return 'SummaryCloudConsentSnapshot(accountUserId: $accountUserId, '
        'sessionGeneration: $sessionGeneration, isGranted: $isGranted, '
        'consentGeneration: $consentGeneration)';
  }
}

/// In-memory cloud-summarization consent, default off.
///
/// Consent is never persisted in this phase, so a restart, a rebuilt session,
/// or a new [SummaryCloudConsent] always starts from "not granted". A grant is
/// bound to one exact account and session generation; grant and revoke advance
/// the monotonic [generation], and every grant keeps its own generation, so
/// revoking and later regranting never makes an earlier snapshot valid again.
///
/// An optional [SessionGenerationSource] lets [isCurrent] compare a snapshot
/// against the live session, which invalidates snapshots that outlived an
/// account transition even when the grant entry itself was never touched.
final class SummaryCloudConsent {
  /// Creates a store, optionally bound to the live [session].
  SummaryCloudConsent({this.session});

  /// The live session this store revalidates against, when one is wired.
  final SessionGenerationSource? session;
  final Map<String, _CloudConsentGrant> _grants =
      <String, _CloudConsentGrant>{};
  int _generation = 0;
  int _observedSessionGeneration = 0;

  /// Monotonic generation of this store; advances on every grant and revoke.
  int get generation => _generation;

  /// Captures the consent that applies to [accountUserId] and
  /// [sessionGeneration].
  ///
  /// Capture never mutates a grant. When a live session is wired and the
  /// requested binding is already stale, the result is not granted, so a stale
  /// binding can never be presented as consent.
  SummaryCloudConsentSnapshot capture({
    required String accountUserId,
    required int sessionGeneration,
  }) {
    _observe(sessionGeneration);
    if (!_isLiveSession(sessionGeneration)) {
      return SummaryCloudConsentSnapshot.notGranted(
        accountUserId: accountUserId,
        sessionGeneration: sessionGeneration,
      );
    }
    final _CloudConsentGrant? grant = _grants[accountUserId];
    if (grant == null || grant.sessionGeneration != sessionGeneration) {
      return SummaryCloudConsentSnapshot.notGranted(
        accountUserId: accountUserId,
        sessionGeneration: sessionGeneration,
      );
    }
    return SummaryCloudConsentSnapshot._(
      accountUserId: accountUserId,
      sessionGeneration: sessionGeneration,
      isGranted: true,
      consentGeneration: grant.generation,
    );
  }

  /// Grants cloud summarization for one exact account and session generation.
  void grant({required String accountUserId, required int sessionGeneration}) {
    _observe(sessionGeneration);
    _generation++;
    _grants[accountUserId] = _CloudConsentGrant(
      sessionGeneration: sessionGeneration,
      generation: _generation,
    );
  }

  /// Revokes the grant for [accountUserId], or every grant when it is null.
  ///
  /// Revocation always clears the stored grant so no usable grant survives the
  /// call; a targeted revoke leaves grants for other accounts intact.
  void revoke({String? accountUserId}) {
    _generation++;
    if (accountUserId == null) {
      _grants.clear();
    } else {
      _grants.remove(accountUserId);
    }
  }

  /// Whether [snapshot] is still the live consent for its exact binding.
  bool isCurrent(SummaryCloudConsentSnapshot snapshot) {
    if (!snapshot.isGranted) {
      return false;
    }
    if (!_isLiveSession(snapshot.sessionGeneration)) {
      return false;
    }
    final _CloudConsentGrant? grant = _grants[snapshot.accountUserId];
    if (grant == null) {
      return false;
    }
    return grant.sessionGeneration == snapshot.sessionGeneration &&
        grant.generation == snapshot.consentGeneration;
  }

  /// Whether [sessionGeneration] is the newest generation observed here.
  ///
  /// Without a wired live session the newest observed generation is the best
  /// available clock: any later capture, grant, or revalidation raises it, and
  /// a snapshot bound to an older generation stops being current.
  bool _isLiveSession(int sessionGeneration) {
    final SessionGenerationSource? live = session;
    if (live != null) {
      return live.sessionGeneration == sessionGeneration;
    }
    return _observedSessionGeneration == sessionGeneration;
  }

  void _observe(int sessionGeneration) {
    if (sessionGeneration > _observedSessionGeneration) {
      _observedSessionGeneration = sessionGeneration;
    }
  }
}

/// One stored grant: its session binding and its monotonic generation.
final class _CloudConsentGrant {
  const _CloudConsentGrant({
    required this.sessionGeneration,
    required this.generation,
  });

  final int sessionGeneration;
  final int generation;
}
