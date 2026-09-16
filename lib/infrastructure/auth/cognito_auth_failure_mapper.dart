/// Classifies Cognito authentication errors into the Domain failure vocabulary.
///
/// Only the exception *types* the installed Amplify SDK exposes are used, so
/// the classification does not depend on provider message text. Provider
/// messages, recovery suggestions, and underlying exceptions are read as
/// classification input at most; they are never copied into the resulting
/// [AuthenticationFailure], which carries a stable code only. That keeps
/// provider text, tokens, and credentials out of thrown values and app logs.
library;

// The Cognito plugin barrel re-exports the Amplify Core auth exception types
// (`SignedOutException`, `NetworkException`, `AuthValidationException`, ...),
// so this classification needs no separate `amplify_flutter` import.
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';

import '../../domain/auth/authentication_failure.dart';

/// Maps Cognito [AuthException]s onto [AuthenticationFailure] codes.
final class CognitoAuthFailureMapper {
  /// Creates the stateless mapper.
  const CognitoAuthFailureMapper();

  /// The supplied email/password pair was rejected.
  ///
  /// Cognito reports "no such user" and "wrong password" as two different
  /// exceptions; both collapse here so the app cannot be used to discover which
  /// email addresses have accounts.
  static const AuthenticationFailure _invalidCredentials =
      AuthenticationFailure(AuthenticationFailureCode.invalidCredentials);

  /// The account already exists.
  static const AuthenticationFailure _accountAlreadyExists =
      AuthenticationFailure(AuthenticationFailureCode.accountAlreadyExists);

  /// The provider rejected the password itself.
  static const AuthenticationFailure _passwordRejected = AuthenticationFailure(
    AuthenticationFailureCode.passwordRejected,
  );

  /// The verification code was wrong.
  static const AuthenticationFailure _invalidVerificationCode =
      AuthenticationFailure(AuthenticationFailureCode.invalidVerificationCode);

  /// The verification code was right but no longer valid.
  static const AuthenticationFailure _expiredVerificationCode =
      AuthenticationFailure(AuthenticationFailureCode.expiredVerificationCode);

  /// The operation needs an authenticated identity and none is present.
  static const AuthenticationFailure _unauthenticated = AuthenticationFailure(
    AuthenticationFailureCode.unauthenticated,
  );

  /// The provider could not be reached or answered; retrying may succeed.
  static const AuthenticationFailure _temporarilyUnavailable =
      AuthenticationFailure(AuthenticationFailureCode.temporarilyUnavailable);

  /// The provider demands a challenge NoteFlow does not implement.
  static const AuthenticationFailure _unsupportedChallenge =
      AuthenticationFailure(AuthenticationFailureCode.unsupportedChallenge);

  /// The failure did not classify into a more specific code.
  static const AuthenticationFailure _unknown = AuthenticationFailure(
    AuthenticationFailureCode.unknown,
  );

  /// Returns the stable NoteFlow failure for a Cognito [error].
  AuthenticationFailure map(AuthException error) {
    return switch (error) {
      UserNotFoundException() ||
      NotAuthorizedServiceException() ||
      AuthNotAuthorizedException() ||
      UnauthorizedException() => _invalidCredentials,
      UsernameExistsException() ||
      AliasExistsException() => _accountAlreadyExists,
      InvalidPasswordException() ||
      PasswordHistoryPolicyViolationException() => _passwordRejected,
      CodeMismatchException() => _invalidVerificationCode,
      ExpiredCodeException() => _expiredVerificationCode,
      // Cognito is asking for a step this adapter does not drive: confirming a
      // sign-up that the backend did not auto-confirm, forcing a password reset
      // during sign-in, or setting up an MFA method.
      UserNotConfirmedException() ||
      PasswordResetRequiredException() ||
      MfaMethodNotFoundException() => _unsupportedChallenge,
      SignedOutException() ||
      SessionExpiredException() ||
      UserCancelledException() => _unauthenticated,
      NetworkException() ||
      InternalErrorException() ||
      ExternalServiceException() ||
      LimitExceededException() ||
      TooManyRequestsException() ||
      TooManyFailedAttemptsException() => _temporarilyUnavailable,
      _ => _unknown,
    };
  }
}
