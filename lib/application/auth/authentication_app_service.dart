/// Application-level authentication use cases for the Phase 3 auth boundary.
///
/// The service owns Application concerns only: blank/equality validation,
/// profile creation for a new registration, and keeping the in-memory
/// [CurrentUserSession] in step with provider-reported identity. Provider SDKs,
/// tokens, persistence, and presentation copy stay outside this layer, and no
/// credential is retained past the call that carries it.
library;

import '../../domain/auth/auth_identity.dart';
import '../../domain/auth/authentication_failure.dart';
import '../../domain/auth/authentication_service.dart';
import '../../domain/users/user_profile.dart';
import '../../domain/users/user_profile_repository.dart';
import 'auth_models.dart';
import 'current_user_session.dart';

/// Authentication use cases offered to Presentation.
abstract interface class IAuthenticationAppService {
  /// Registers [input], signs the new account in, and creates its profile.
  ///
  /// Registration is complete once the profile is saved; only a temporary
  /// verification dispatch failure is reported through the result, while every
  /// other failure still reaches the caller.
  Future<RegistrationResult> register(RegisterInput input);

  /// Authenticates [input] and publishes the identity to the session.
  Future<AuthUserDto> login(LoginInput input);

  /// Signs out and always drops the local session.
  Future<void> logout();

  /// Restores the provider's current identity into the session, if any.
  Future<AuthUserDto?> restoreSession();

  /// Reloads the authenticated identity and publishes it to the session.
  Future<AuthUserDto> refreshIdentity();

  /// Re-requests verification for the authenticated identity.
  Future<void> resendEmailVerification();

  /// Confirms the authenticated identity's email verification [code].
  Future<AuthUserDto> confirmEmailVerification({required String code});

  /// Requests a password-reset code for [email] without signing in.
  Future<void> requestPasswordReset({required String email});

  /// Confirms a password reset without signing in or touching the session.
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
    required String confirmPassword,
  });

  /// Changes the authenticated identity's password.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  });
}

/// Coordinates the authentication provider, the profile store, and the session.
final class AuthenticationAppService implements IAuthenticationAppService {
  /// Creates the service over its three collaborators.
  const AuthenticationAppService({
    required this.authenticationService,
    required this.currentUserSession,
    required this.userProfileRepository,
  });

  /// Provider-neutral authentication capability.
  final IAuthenticationService authenticationService;

  /// Mutable session published to the rest of the application.
  final CurrentUserSession currentUserSession;

  /// NoteFlow-owned profile persistence.
  final IUserProfileRepository userProfileRepository;

  @override
  Future<RegistrationResult> register(RegisterInput input) async {
    final String email = _requireText(
      input.email,
      AuthValidationReason.emailRequired,
    );
    final String displayName = _requireText(
      input.displayName,
      AuthValidationReason.displayNameRequired,
    );
    _requirePassword(input.password);
    _requireMatchingConfirmation(input.password, input.confirmPassword);

    await authenticationService.register(
      email: email,
      password: input.password,
    );
    final AuthIdentity identity = await authenticationService.login(
      email: email,
      password: input.password,
    );

    // The profile owns the display name, so it must exist before the rest of
    // the application can observe an authenticated session.
    await userProfileRepository.save(
      UserProfile.create(userId: identity.userId, displayName: displayName),
    );
    currentUserSession.setIdentity(identity);

    final AuthUserDto user = AuthUserDto.fromIdentity(identity);
    if (identity.isEmailVerified) {
      return RegistrationResult(
        user: user,
        verificationDispatchStatus: VerificationDispatchStatus.notRequired,
      );
    }
    return RegistrationResult(
      user: user,
      verificationDispatchStatus: await _dispatchEmailVerification(),
    );
  }

  @override
  Future<AuthUserDto> login(LoginInput input) async {
    final String email = _requireText(
      input.email,
      AuthValidationReason.emailRequired,
    );
    _requirePassword(input.password);

    final AuthIdentity identity = await authenticationService.login(
      email: email,
      password: input.password,
    );
    currentUserSession.setIdentity(identity);
    return AuthUserDto.fromIdentity(identity);
  }

  @override
  Future<void> logout() async {
    try {
      await authenticationService.logout();
    } finally {
      // The local session is dropped even when the provider sign-out fails, so
      // the application never keeps showing a signed-in user.
      currentUserSession.clear();
    }
  }

  @override
  Future<AuthUserDto?> restoreSession() async {
    final AuthIdentity? identity = await authenticationService
        .getCurrentIdentity();
    if (identity == null) {
      currentUserSession.clear();
      return null;
    }
    currentUserSession.setIdentity(identity);
    return AuthUserDto.fromIdentity(identity);
  }

  @override
  Future<AuthUserDto> refreshIdentity() async {
    _requireAuthenticatedUser();
    final AuthIdentity identity = await authenticationService.refreshIdentity();
    currentUserSession.setIdentity(identity);
    return AuthUserDto.fromIdentity(identity);
  }

  @override
  Future<void> resendEmailVerification() async {
    _requireAuthenticatedUser();
    await authenticationService.requestEmailVerification();
  }

  @override
  Future<AuthUserDto> confirmEmailVerification({required String code}) async {
    final String trimmedCode = _requireText(
      code,
      AuthValidationReason.verificationCodeRequired,
    );
    _requireAuthenticatedUser();
    await authenticationService.confirmEmailVerification(code: trimmedCode);
    // Confirmation changes provider-side verification facts, so the session is
    // republished from a fresh identity rather than patched locally.
    return refreshIdentity();
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    // Unauthenticated by design: a signed-out user is the one who needs it.
    await authenticationService.requestPasswordReset(
      email: _requireText(email, AuthValidationReason.emailRequired),
    );
  }

  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final String trimmedEmail = _requireText(
      email,
      AuthValidationReason.emailRequired,
    );
    final String trimmedCode = _requireText(
      code,
      AuthValidationReason.verificationCodeRequired,
    );
    _requirePassword(newPassword);
    _requireMatchingConfirmation(newPassword, confirmPassword);

    // No session mutation: confirming a reset is not a sign-in.
    await authenticationService.confirmPasswordReset(
      email: trimmedEmail,
      code: trimmedCode,
      newPassword: newPassword,
    );
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    _requireText(currentPassword, AuthValidationReason.currentPasswordRequired);
    _requirePassword(newPassword);
    _requireMatchingConfirmation(newPassword, confirmPassword);
    _requireAuthenticatedUser();

    // The confirmation is an input check only; it never reaches the provider.
    await authenticationService.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  /// Maps the verification dispatch outcome without failing the registration.
  ///
  /// Only [AuthenticationFailureCode.temporarilyUnavailable] is known to clear
  /// on its own, so only that code degrades to
  /// [VerificationDispatchStatus.pending]. Every other typed failure, untyped
  /// failure, and [Error] reaches the caller unchanged.
  Future<VerificationDispatchStatus> _dispatchEmailVerification() async {
    try {
      await authenticationService.requestEmailVerification();
      return VerificationDispatchStatus.requested;
    } on AuthenticationFailure catch (failure) {
      if (failure.code == AuthenticationFailureCode.temporarilyUnavailable) {
        return VerificationDispatchStatus.pending;
      }
      rethrow;
    }
  }

  /// Rejects the call when no user is signed in, before any provider call.
  void _requireAuthenticatedUser() {
    currentUserSession.requiredUserId;
  }
}

String _requireText(String value, AuthValidationReason reason) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw AuthValidationException(reason);
  }
  return trimmed;
}

/// Rejects a blank password without normalizing the value itself.
void _requirePassword(String password) {
  if (password.trim().isEmpty) {
    throw const AuthValidationException(AuthValidationReason.passwordRequired);
  }
}

/// Rejects a confirmation field that is not exactly the password field.
void _requireMatchingConfirmation(String password, String confirmPassword) {
  if (password != confirmPassword) {
    throw const AuthValidationException(
      AuthValidationReason.passwordConfirmationMismatch,
    );
  }
}
