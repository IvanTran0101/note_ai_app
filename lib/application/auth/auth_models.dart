/// Application-facing authentication models for the Phase 3 auth foundation.
///
/// Inputs carry primitive, immutable request fields and results expose only
/// provider-neutral facts, so no Flutter, provider SDK, or Infrastructure type
/// appears here. No model in this library retains a credential beyond the
/// request it describes.
library;

import '../../domain/auth/auth_identity.dart';

/// Registration request as entered by the user.
final class RegisterInput {
  const RegisterInput({
    required this.email,
    required this.displayName,
    required this.password,
    required this.confirmPassword,
  });

  final String email;

  final String displayName;

  final String password;

  /// Repeated password entry, compared against [password] by validation.
  final String confirmPassword;
}

/// Login request as entered by the user.
final class LoginInput {
  const LoginInput({required this.email, required this.password});

  final String email;

  final String password;
}

/// Provider-neutral user facts returned by an authentication operation.
final class AuthUserDto {
  const AuthUserDto({
    required this.userId,
    required this.email,
    required this.isEmailVerified,
  });

  /// Maps a Domain [AuthIdentity] onto its Application-facing representation.
  factory AuthUserDto.fromIdentity(AuthIdentity identity) {
    return AuthUserDto(
      userId: identity.userId,
      email: identity.email,
      isEmailVerified: identity.isEmailVerified,
    );
  }

  final String userId;

  final String email;

  final bool isEmailVerified;
}

/// Whether a registration requires email verification, and whether the
/// verification message has been dispatched.
enum VerificationDispatchStatus {
  /// The provider requires no email verification for this registration.
  notRequired,

  /// The verification message was dispatched as part of this registration.
  requested,

  /// Verification is required but no message has been dispatched yet; the user
  /// must ask for one (for example, a resend).
  pending,
}

/// Outcome of a successful registration.
final class RegistrationResult {
  const RegistrationResult({
    required this.user,
    required this.verificationDispatchStatus,
    this.profileSetupPending = false,
  });

  /// The registered user as reported by the provider.
  final AuthUserDto user;

  /// What happened to this registration's verification message.
  final VerificationDispatchStatus verificationDispatchStatus;

  /// Cognito succeeded, but Profile must be completed without signing up again.
  final bool profileSetupPending;
}

/// Stable reasons why Application-level auth input validation rejected input.
///
/// Presentation maps a reason onto localized prose; the Application layer
/// never carries user-facing copy.
enum AuthValidationReason {
  /// The email field was missing or blank.
  emailRequired,

  /// The display name field was missing or blank.
  displayNameRequired,

  /// The password field was missing or blank.
  passwordRequired,

  /// The confirmation field did not match the password field.
  passwordConfirmationMismatch,

  /// The verification code field was missing or blank.
  verificationCodeRequired,

  /// The current-password field was missing or blank on a change-password.
  currentPasswordRequired,
}

/// Signals that auth input failed Application-level validation.
///
/// Only a [reason] travels with the exception, never the rejected value, so no
/// credential can leak through diagnostics.
final class AuthValidationException implements Exception {
  const AuthValidationException(this.reason);

  /// The validation rule that rejected the input.
  final AuthValidationReason reason;

  @override
  String toString() => 'AuthValidationException(${reason.name})';
}
