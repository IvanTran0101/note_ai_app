import 'auth_identity.dart';

/// Provider-neutral authentication capability owned by the inward boundary.
///
/// Implementations belong to Infrastructure. Passwords are transient method
/// inputs only; provider tokens, sessions, and provider-specific exceptions do
/// not cross this contract.
abstract interface class IAuthenticationService {
  /// Registers a new account. Registration does not imply an automatic login.
  Future<void> register({required String email, required String password});

  /// Authenticates credentials and returns the resulting identity.
  Future<AuthIdentity> login({required String email, required String password});

  /// Signs out the current authenticated identity.
  Future<void> logout();

  /// Returns the current identity, or `null` when no identity is authenticated.
  Future<AuthIdentity?> getCurrentIdentity();

  /// Emits authentication identity changes, including signed-out `null`.
  Stream<AuthIdentity?> observeAuthState();

  /// Requests verification for the current registered identity.
  Future<void> requestEmailVerification();

  /// Confirms the email verification [code].
  Future<void> confirmEmailVerification({required String code});

  /// Refreshes and returns the current authenticated identity.
  Future<AuthIdentity> refreshIdentity();

  /// Requests a password-reset code for [email].
  Future<void> requestPasswordReset({required String email});

  /// Confirms a password reset with [code] and applies [newPassword].
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  });

  /// Changes the current identity's password.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });
}
