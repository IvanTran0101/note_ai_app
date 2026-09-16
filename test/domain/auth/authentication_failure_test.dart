import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/domain/auth/authentication_failure.dart';

void main() {
  group('AuthenticationFailureCode', () {
    test('exposes exactly the agreed failure codes in a stable order', () {
      expect(AuthenticationFailureCode.values, <AuthenticationFailureCode>[
        AuthenticationFailureCode.invalidCredentials,
        AuthenticationFailureCode.accountAlreadyExists,
        AuthenticationFailureCode.passwordRejected,
        AuthenticationFailureCode.invalidVerificationCode,
        AuthenticationFailureCode.expiredVerificationCode,
        AuthenticationFailureCode.unauthenticated,
        AuthenticationFailureCode.temporarilyUnavailable,
        AuthenticationFailureCode.unsupportedChallenge,
        AuthenticationFailureCode.identityUnavailable,
        AuthenticationFailureCode.unknown,
      ]);
    });
  });

  group('AuthenticationFailure', () {
    const AuthenticationFailure failure = AuthenticationFailure(
      AuthenticationFailureCode.invalidCredentials,
    );

    test('carries its code and is an Exception', () {
      expect(failure.code, AuthenticationFailureCode.invalidCredentials);
      expect(failure, isA<Exception>());
    });

    test('round-trips every code', () {
      expect(
        AuthenticationFailureCode.values.map(
          (AuthenticationFailureCode code) => AuthenticationFailure(code).code,
        ),
        AuthenticationFailureCode.values,
      );
    });

    test('names only the code in its string representation', () {
      expect(failure.toString(), 'AuthenticationFailure(invalidCredentials)');
      expect(failure.toString(), isNot(contains('password')));
      expect(failure.toString(), isNot(contains('token')));
      expect(failure.toString(), isNot(contains('secret')));
    });
  });
}
