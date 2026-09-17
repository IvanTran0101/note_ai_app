import '../../../application/auth/auth_models.dart';

/// Lifecycle state used by the authentication Presentation boundary.
enum AuthStatus { initializing, unauthenticated, authenticated }

/// Stable Presentation-level error categories.
///
/// The controller maps Application/Domain failures to this enum so widgets do
/// not need to know provider exception types or display raw exception text.
enum AuthPresentationErrorCode {
  emailRequired,
  displayNameRequired,
  passwordRequired,
  passwordConfirmationMismatch,
  verificationCodeRequired,
  currentPasswordRequired,
  invalidCredentials,
  accountAlreadyExists,
  passwordRejected,
  invalidVerificationCode,
  expiredVerificationCode,
  temporarilyUnavailable,
  unauthenticated,
  unsupportedChallenge,
  identityUnavailable,
  unknown,
}

/// An error safe to retain in Presentation state.
final class AuthPresentationError {
  const AuthPresentationError(this.code);

  final AuthPresentationErrorCode code;

  @override
  bool operator ==(Object other) {
    return other is AuthPresentationError && other.code == code;
  }

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'AuthPresentationError(${code.name})';
}

/// Immutable state exposed by [AuthController].
///
/// Passwords and raw exceptions are deliberately absent. An authenticated
/// state always carries the provider-neutral [AuthUserDto].
final class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.isBusy = false,
    this.error,
  }) : assert(
         (status == AuthStatus.authenticated) == (user != null),
         'Authenticated state requires a user; other states do not.',
       );

  const AuthState.initializing({
    bool isBusy = false,
    AuthPresentationError? error,
  }) : this(status: AuthStatus.initializing, isBusy: isBusy, error: error);

  const AuthState.unauthenticated({
    bool isBusy = false,
    AuthPresentationError? error,
  }) : this(status: AuthStatus.unauthenticated, isBusy: isBusy, error: error);

  const AuthState.authenticated({
    required AuthUserDto user,
    bool isBusy = false,
    AuthPresentationError? error,
  }) : this(
         status: AuthStatus.authenticated,
         user: user,
         isBusy: isBusy,
         error: error,
       );

  final AuthStatus status;
  final AuthUserDto? user;
  final bool isBusy;
  final AuthPresentationError? error;

  bool get isAuthenticated => status == AuthStatus.authenticated;
}
