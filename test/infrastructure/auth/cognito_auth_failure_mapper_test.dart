import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/domain/auth/authentication_failure.dart';
import 'package:note_ai_app/infrastructure/auth/cognito_auth_failure_mapper.dart';

void main() {
  const CognitoAuthFailureMapper mapper = CognitoAuthFailureMapper();

  AuthenticationFailureCode codeOf(AuthException error) =>
      mapper.map(error).code;

  group('CognitoAuthFailureMapper credentials', () {
    test('maps a wrong password to invalidCredentials', () {
      expect(
        codeOf(
          const NotAuthorizedServiceException(
            'Incorrect username or password.',
          ),
        ),
        AuthenticationFailureCode.invalidCredentials,
      );
    });

    test('does not distinguish a non-existent email from a wrong password', () {
      final AuthenticationFailureCode missingUser = codeOf(
        const UserNotFoundException('User does not exist.'),
      );
      final AuthenticationFailureCode wrongPassword = codeOf(
        const NotAuthorizedServiceException('Incorrect username or password.'),
      );

      expect(missingUser, AuthenticationFailureCode.invalidCredentials);
      expect(missingUser, wrongPassword);
    });

    test('maps an unauthorized session to invalidCredentials', () {
      expect(
        codeOf(const AuthNotAuthorizedException('Not authorized.')),
        AuthenticationFailureCode.invalidCredentials,
      );
      expect(
        codeOf(const UnauthorizedException('Not authorized.')),
        AuthenticationFailureCode.invalidCredentials,
      );
    });
  });

  group('CognitoAuthFailureMapper registration and passwords', () {
    test('maps an existing account to accountAlreadyExists', () {
      expect(
        codeOf(const UsernameExistsException('User already exists.')),
        AuthenticationFailureCode.accountAlreadyExists,
      );
      expect(
        codeOf(const AliasExistsException('Alias already exists.')),
        AuthenticationFailureCode.accountAlreadyExists,
      );
    });

    test('maps a rejected password policy to passwordRejected', () {
      expect(
        codeOf(const InvalidPasswordException('Password did not conform.')),
        AuthenticationFailureCode.passwordRejected,
      );
      expect(
        codeOf(const PasswordHistoryPolicyViolationException('Reused.')),
        AuthenticationFailureCode.passwordRejected,
      );
    });
  });

  group('CognitoAuthFailureMapper verification codes', () {
    test('maps a wrong code to invalidVerificationCode', () {
      expect(
        codeOf(const CodeMismatchException('Invalid code provided.')),
        AuthenticationFailureCode.invalidVerificationCode,
      );
    });

    test('maps an expired code to expiredVerificationCode', () {
      expect(
        codeOf(const ExpiredCodeException('Code has expired.')),
        AuthenticationFailureCode.expiredVerificationCode,
      );
    });
  });

  group('CognitoAuthFailureMapper challenges and sessions', () {
    test('maps unsupported provider challenges to unsupportedChallenge', () {
      expect(
        codeOf(const UserNotConfirmedException('User is not confirmed.')),
        AuthenticationFailureCode.unsupportedChallenge,
      );
      expect(
        codeOf(const PasswordResetRequiredException('Reset required.')),
        AuthenticationFailureCode.unsupportedChallenge,
      );
      expect(
        codeOf(const MfaMethodNotFoundException('MFA not found.')),
        AuthenticationFailureCode.unsupportedChallenge,
      );
    });

    test('maps a missing or expired session to unauthenticated', () {
      expect(
        codeOf(const SignedOutException('No user is currently signed in.')),
        AuthenticationFailureCode.unauthenticated,
      );
      expect(
        codeOf(const SessionExpiredException('Session expired.')),
        AuthenticationFailureCode.unauthenticated,
      );
      expect(
        codeOf(const UserCancelledException('Cancelled.')),
        AuthenticationFailureCode.unauthenticated,
      );
    });
  });

  group('CognitoAuthFailureMapper availability', () {
    test(
      'maps transport and throttling failures to temporarilyUnavailable',
      () {
        expect(
          codeOf(const NetworkException('The request failed.')),
          AuthenticationFailureCode.temporarilyUnavailable,
        );
        expect(
          codeOf(const InternalErrorException('Internal error.')),
          AuthenticationFailureCode.temporarilyUnavailable,
        );
        expect(
          codeOf(const ExternalServiceException('External service error.')),
          AuthenticationFailureCode.temporarilyUnavailable,
        );
        expect(
          codeOf(const LimitExceededException('Limit exceeded.')),
          AuthenticationFailureCode.temporarilyUnavailable,
        );
        expect(
          codeOf(const TooManyRequestsException('Too many requests.')),
          AuthenticationFailureCode.temporarilyUnavailable,
        );
        expect(
          codeOf(const TooManyFailedAttemptsException('Too many attempts.')),
          AuthenticationFailureCode.temporarilyUnavailable,
        );
      },
    );
  });

  group('CognitoAuthFailureMapper unknown', () {
    test('maps unclassified provider failures to unknown', () {
      expect(
        codeOf(const UnknownServiceException('Unknown service error.')),
        AuthenticationFailureCode.unknown,
      );
      expect(
        codeOf(const UnknownException('An unknown error occurred.')),
        AuthenticationFailureCode.unknown,
      );
      expect(
        codeOf(const AuthValidationException('Invalid input.')),
        AuthenticationFailureCode.unknown,
      );
      expect(
        codeOf(const InvalidParameterException('Invalid parameter.')),
        AuthenticationFailureCode.unknown,
      );
      expect(
        codeOf(const InvalidStateException('Invalid state.')),
        AuthenticationFailureCode.unknown,
      );
    });

    test('keeps provider message and recovery text out of the failure', () {
      const String secretMessage =
          'Incorrect username or password for ada@example.com with hunter2';
      final AuthenticationFailure failure = mapper.map(
        const NotAuthorizedServiceException(
          secretMessage,
          recoverySuggestion: 'Do not log hunter2.',
        ),
      );

      expect(failure.toString(), 'AuthenticationFailure(invalidCredentials)');
      expect(failure.toString(), isNot(contains(secretMessage)));
      expect(failure.toString(), isNot(contains('hunter2')));
      expect(failure.toString(), isNot(contains('ada@example.com')));
    });
  });
}
