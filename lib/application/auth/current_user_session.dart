import '../../domain/auth/auth_identity.dart';
import 'current_user.dart';

/// Mutable in-memory [ICurrentUser] for the running application session.
///
/// The session starts unauthenticated and only ever holds the current
/// [AuthIdentity]: credentials and provider tokens stay in Infrastructure, and
/// nothing is persisted, so session restore remains an Infrastructure concern.
final class CurrentUserSession implements ICurrentUser {
  AuthIdentity? _identity;

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
  void setIdentity(AuthIdentity identity) {
    _identity = identity;
  }

  /// Drops the current identity, e.g. on sign-out.
  void clear() {
    _identity = null;
  }
}
