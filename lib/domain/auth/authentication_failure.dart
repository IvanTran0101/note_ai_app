/// Provider-neutral authentication failure contract for the auth boundary.
///
/// This library owns the stable failure vocabulary of one authentication
/// operation as observed from the Domain boundary. Infrastructure maps its
/// provider exceptions onto [AuthenticationFailureCode]; Application decides
/// what a code means for a use case, and Presentation renders localized prose
/// from the code alone.
///
/// The library is deliberately free of Flutter, provider SDK, and
/// Infrastructure types. A failure carries only its [AuthenticationFailure.code]
/// — never provider text — so no provider message, token, or credential can
/// leak through logs or diagnostics.
library;

/// Stable codes for the failure classes of an authentication operation.
enum AuthenticationFailureCode {
  /// The supplied email/password pair was rejected.
  invalidCredentials,

  /// The account already exists, so registration could not proceed.
  accountAlreadyExists,

  /// The password was rejected by the provider's password policy.
  passwordRejected,

  /// The submitted verification code was wrong.
  invalidVerificationCode,

  /// The submitted verification code was correct but has expired.
  expiredVerificationCode,

  /// The operation requires an authenticated identity, and none is present.
  unauthenticated,

  /// The provider could not be reached or answered. Retrying may succeed.
  temporarilyUnavailable,

  /// The provider requires a challenge NoteFlow does not implement yet.
  unsupportedChallenge,

  /// No identity is available to describe the outcome, e.g. a failed refresh.
  identityUnavailable,

  /// Any failure that did not map to a more specific code.
  unknown,
}

/// Immutable, typed failure that ends one authentication operation.
///
/// Only [code] travels with the failure, so the message stays stable across
/// providers and diagnostics stay free of provider text and secrets.
final class AuthenticationFailure implements Exception {
  /// Creates a failure carrying its stable [code].
  const AuthenticationFailure(this.code);

  /// The stable failure class of this operation.
  final AuthenticationFailureCode code;

  /// Names only the code so no provider message or secret can leak.
  @override
  String toString() => 'AuthenticationFailure(${code.name})';
}
