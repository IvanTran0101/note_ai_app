import '../../domain/auth/auth_identity.dart';

/// Signals that an authenticated user is required for the current operation.
final class UnauthenticatedException implements Exception {
  const UnauthenticatedException();

  @override
  String toString() => 'UnauthenticatedException';
}

/// Provides the identity of the currently authenticated user.
abstract interface class ICurrentUser {
  AuthIdentity? get identity;

  bool get isAuthenticated;

  String? get userId;

  String get requiredUserId;
}

/// Immutable current-user implementation for a fixed identity.
final class StaticCurrentUser implements ICurrentUser {
  const StaticCurrentUser({required this.identity});

  @override
  final AuthIdentity identity;

  @override
  bool get isAuthenticated => true;

  @override
  String get userId => identity.userId;

  @override
  String get requiredUserId => userId;
}
