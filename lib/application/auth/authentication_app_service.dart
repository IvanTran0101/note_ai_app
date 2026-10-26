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
  ///
  /// A completion that lands after the session moved on — a sign-out, a
  /// provider session expiry, or a newer account taking the session — is
  /// rejected as unauthenticated instead of publishing.
  Future<AuthUserDto> login(LoginInput input);

  /// Signs out and always drops the local session.
  Future<void> logout();

  /// Restores the provider's current identity into the session, if any.
  ///
  /// Like [login], a completion that lands after the session moved on is
  /// rejected as unauthenticated instead of publishing.
  Future<AuthUserDto?> restoreSession();

  /// Emits provider session changes and keeps the local session in sync.
  ///
  /// A delivered signed-out event also invalidates operations still in
  /// flight, even when the local session is already empty.
  Stream<AuthUserDto?> observeAuthState();

  /// Reloads the authenticated identity and publishes it to the session.
  ///
  /// The refreshed identity is published only while the session still holds
  /// the user being refreshed; a refresh completing after a sign-out or an
  /// account switch is rejected as unauthenticated.
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
  AuthenticationAppService({
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

  String? _registrationEmail;
  String? _registrationActor;
  int _authEpoch = 0;

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

    // Validate the profile before Cognito creates an account.
    UserProfile.create(userId: 'validation', displayName: displayName);
    // Beginning a credential-changing operation invalidates older restore and
    // refresh reads before this call awaits the provider. Without this bump an
    // older read captured the same epoch and could publish its stale result.
    final int epoch = ++_authEpoch;
    final generation = currentUserSession.sessionGeneration;
    _registrationEmail = email.toLowerCase();
    try {
      await authenticationService.register(
        email: email,
        password: input.password,
      );
      final identity = await authenticationService.login(
        email: email,
        password: input.password,
      );
      _registrationActor = identity.userId;
      void requireRegistration() {
        if (_authEpoch != epoch ||
            currentUserSession.sessionGeneration != generation) {
          throw const AuthenticationFailure(
            AuthenticationFailureCode.unauthenticated,
          );
        }
      }

      requireRegistration();
      bool profileSetupPending = false;
      try {
        await userProfileRepository.save(
          UserProfile.create(userId: identity.userId, displayName: displayName),
        );
      } on Object {
        requireRegistration();
        // Auth and Profile are separate writes. Keep the signed-in account usable.
        profileSetupPending = true;
      }
      requireRegistration();
      final activeIdentity = await authenticationService.getCurrentIdentity();
      requireRegistration();
      if (activeIdentity == null || activeIdentity.userId != identity.userId) {
        throw const AuthenticationFailure(
          AuthenticationFailureCode.unauthenticated,
        );
      }
      currentUserSession.setIdentity(activeIdentity);
      final dispatch = activeIdentity.isEmailVerified
          ? VerificationDispatchStatus.notRequired
          : await _dispatchEmailVerification();
      if (_authEpoch != epoch || currentUserSession.userId != identity.userId) {
        throw const AuthenticationFailure(
          AuthenticationFailureCode.unauthenticated,
        );
      }
      return RegistrationResult(
        user: AuthUserDto.fromIdentity(activeIdentity),
        verificationDispatchStatus: dispatch,
        profileSetupPending: profileSetupPending,
      );
    } finally {
      _registrationEmail = null;
      _registrationActor = null;
    }
  }

  @override
  Future<AuthUserDto> login(LoginInput input) async {
    final String email = _requireText(
      input.email,
      AuthValidationReason.emailRequired,
    );
    _requirePassword(input.password);

    // Beginning a credential-changing operation invalidates older restore and
    // refresh reads before this call awaits the provider. Without this bump an
    // older read captured the same epoch and could publish its stale result —
    // including a stale null over an initially empty session.
    final int epoch = ++_authEpoch;
    final int generation = currentUserSession.sessionGeneration;
    final AuthIdentity identity = await authenticationService.login(
      email: email,
      password: input.password,
    );
    if (!_sessionUnchanged(epoch, generation, identity.userId)) {
      throw const AuthenticationFailure(
        AuthenticationFailureCode.unauthenticated,
      );
    }
    currentUserSession.setIdentity(identity);
    return AuthUserDto.fromIdentity(identity);
  }

  @override
  Future<void> logout() async {
    _authEpoch++;
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
    final int epoch = _authEpoch;
    final int generation = currentUserSession.sessionGeneration;
    final AuthIdentity? identity = await authenticationService
        .getCurrentIdentity();
    if (!_sessionUnchanged(epoch, generation, identity?.userId)) {
      throw const AuthenticationFailure(
        AuthenticationFailureCode.unauthenticated,
      );
    }
    if (identity == null) {
      currentUserSession.clear();
      return null;
    }
    currentUserSession.setIdentity(identity);
    return AuthUserDto.fromIdentity(identity);
  }

  @override
  Stream<AuthUserDto?> observeAuthState() {
    return authenticationService
        .observeAuthState()
        .where((identity) {
          if (_registrationEmail == null) return true;
          final intended =
              identity != null &&
              identity.email.toLowerCase() == _registrationEmail &&
              (_registrationActor == null ||
                  identity.userId == _registrationActor);
          if (intended) return false;
          _authEpoch++;
          return true;
        })
        .map((identity) {
          if (identity == null) {
            // A delivered sign-out invalidates operations still in flight
            // even when the local session is already empty, so a pending
            // login or restore cannot publish over the expiry.
            _authEpoch++;
            currentUserSession.clear();
            return null;
          }
          currentUserSession.setIdentity(identity);
          return AuthUserDto.fromIdentity(identity);
        });
  }

  @override
  Future<AuthUserDto> refreshIdentity() async {
    _requireAuthenticatedUser();
    final String userId = currentUserSession.requiredUserId;
    final int epoch = _authEpoch;
    final int generation = currentUserSession.sessionGeneration;
    final AuthIdentity identity = await authenticationService.refreshIdentity();
    // `_sessionUnchanged` reduces to "the session still holds the user being
    // refreshed": an unchanged generation implies the same user id, and the
    // user-id branch covers a same-user echo that advanced the generation.
    if (!_sessionUnchanged(epoch, generation, userId)) {
      throw const AuthenticationFailure(
        AuthenticationFailureCode.unauthenticated,
      );
    }
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

  /// Whether an operation that captured [epoch] and [generation] may still
  /// publish [userId] to the session.
  ///
  /// Publishing is stale once a sign-out, a provider session expiry, or a
  /// foreign sign-in event advanced the epoch: the operation would resurrect
  /// the ended session or overwrite a newer account. Otherwise publishing
  /// stays valid when the session never moved (same generation) or when it
  /// already holds [userId]: the operation's own signed-in echo legally
  /// re-records that identity, which advances the generation from an empty or
  /// switched session without invalidating the operation.
  bool _sessionUnchanged(int epoch, int generation, String? userId) {
    if (_authEpoch != epoch) {
      return false;
    }
    final CurrentUserSession session = currentUserSession;
    return session.sessionGeneration == generation || session.userId == userId;
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
