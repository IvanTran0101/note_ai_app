/// Provider-neutral identity for an authenticated NoteFlow user.
///
/// Credentials and provider/session tokens are deliberately not part of this
/// domain model. Infrastructure adapters map provider identity claims into
/// this type.
final class AuthIdentity {
  /// Creates an authenticated identity from normalized non-blank values.
  AuthIdentity({
    required String userId,
    required String email,
    required this.isEmailVerified,
  }) : userId = _requireText(userId, 'userId'),
       email = _requireText(email, 'email');

  /// Stable identity used by NoteFlow ownership boundaries.
  final String userId;

  /// Email associated with the authenticated identity.
  final String email;

  /// Whether the identity's email has been verified by the authentication
  /// provider.
  final bool isEmailVerified;

  @override
  bool operator ==(Object other) {
    return other is AuthIdentity &&
        other.userId == userId &&
        other.email == email &&
        other.isEmailVerified == isEmailVerified;
  }

  @override
  int get hashCode => Object.hash(runtimeType, userId, email, isEmailVerified);

  /// Omits the email so identity values are safer to include in diagnostics.
  @override
  String toString() =>
      'AuthIdentity(userId: $userId, email: <redacted>, '
      'isEmailVerified: $isEmailVerified)';
}

String _requireText(String value, String fieldName) {
  final String normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, fieldName, 'must not be blank');
  }
  return normalized;
}
