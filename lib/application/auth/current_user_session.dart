import '../../domain/auth/auth_identity.dart';
import 'current_user.dart';

/// Exposes the monotonic generation of the active identity binding.
///
/// Consumers that hold account-scoped work (summary runs, consent, staged
/// uploads) compare the generation they captured with the live one instead of
/// trusting an account id alone: the same user id can return after a sign-out,
/// and that is a different session.
abstract interface class SessionGenerationSource {
  /// Monotonic generation of the current identity binding.
  int get sessionGeneration;
}

/// Reads the monotonic generation of the current session identity.
///
/// Lets a service take the generation from a [SessionGenerationSource] or from
/// an injected callback without depending on a concrete session type.
typedef SessionGenerationReader = int Function();

/// Mutable in-memory [ICurrentUser] for the running application session.
///
/// The session starts unauthenticated and only ever holds the current
/// [AuthIdentity]: credentials and provider tokens stay in Infrastructure, and
/// nothing is persisted, so session restore remains an Infrastructure concern.
///
/// [sessionGeneration] is monotonic and advances only on a real identity
/// transition — null to user, user id change, or active to clear. A passive
/// same-user update (restore, identity stream, token refresh, or sign-in of the
/// user who is already active) keeps the generation stable, because it does not
/// invalidate anything the running session captured.
final class CurrentUserSession
    implements ICurrentUser, SessionGenerationSource {
  AuthIdentity? _identity;
  int _generation = 0;

  @override
  int get sessionGeneration => _generation;

  @override
  AuthIdentity? get identity => _identity;

  @override
  bool get isAuthenticated => _identity != null;

  @override
  String? get userId => _identity?.userId;

  @override
  String get requiredUserId {
    final AuthIdentity? identity = _identity;
    if (identity == null) {
      throw const UnauthenticatedException();
    }
    return identity.userId;
  }

  /// Records the identity produced by a successful authentication.
  ///
  /// The generation advances when this call is a real transition: the first
  /// identity of an empty session, or a different user id. Re-recording the
  /// active user leaves the generation unchanged.
  void setIdentity(AuthIdentity identity) {
    final AuthIdentity? previous = _identity;
    if (previous == null || previous.userId != identity.userId) {
      _generation++;
    }
    _identity = identity;
  }

  /// Drops the current identity, e.g. on sign-out.
  ///
  /// Clearing an authenticated session advances the generation, so an account
  /// that signs back in never validates anything captured before the clear.
  /// Clearing an already empty session changes nothing.
  void clear() {
    if (_identity == null) {
      return;
    }
    _identity = null;
    _generation++;
  }
}
