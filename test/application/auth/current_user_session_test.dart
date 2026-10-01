import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/auth_models.dart';
import 'package:note_ai_app/application/auth/current_user.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';

void main() {
  final AuthIdentity identity = AuthIdentity(
    userId: 'user-1',
    email: 'user@example.com',
    isEmailVerified: true,
  );

  group('CurrentUserSession', () {
    test('starts unauthenticated and requires an identity', () {
      final ICurrentUser session = CurrentUserSession();

      expect(session.identity, isNull);
      expect(session.isAuthenticated, isFalse);
      expect(session.userId, isNull);
      expect(
        () => session.requiredUserId,
        throwsA(isA<UnauthenticatedException>()),
      );
    });

    test('setIdentity authenticates the session', () {
      final CurrentUserSession session = CurrentUserSession();

      session.setIdentity(identity);

      expect(session.identity, same(identity));
      expect(session.isAuthenticated, isTrue);
      expect(session.userId, 'user-1');
      expect(session.requiredUserId, 'user-1');
    });

    test('clear returns the session to unauthenticated', () {
      final CurrentUserSession session = CurrentUserSession()
        ..setIdentity(identity);

      session.clear();

      expect(session.identity, isNull);
      expect(session.isAuthenticated, isFalse);
      expect(session.userId, isNull);
      expect(
        () => session.requiredUserId,
        throwsA(isA<UnauthenticatedException>()),
      );
    });

    test('setIdentity replaces a previous identity after a clear', () {
      final CurrentUserSession session = CurrentUserSession()
        ..setIdentity(identity)
        ..clear();
      final AuthIdentity replacement = AuthIdentity(
        userId: 'user-2',
        email: 'second@example.com',
        isEmailVerified: false,
      );

      session.setIdentity(replacement);

      expect(session.identity, same(replacement));
      expect(session.isAuthenticated, isTrue);
      expect(session.userId, 'user-2');
      expect(session.requiredUserId, 'user-2');
    });
  });

  group('CurrentUserSession generation', () {
    test('starts at 0 and is exposed through the source contract', () {
      final CurrentUserSession session = CurrentUserSession();
      final SessionGenerationSource source = session;

      expect(session.sessionGeneration, 0);
      expect(source.sessionGeneration, 0);
    });

    test('advances on null to user', () {
      final CurrentUserSession session = CurrentUserSession();

      session.setIdentity(identity);

      expect(session.sessionGeneration, 1);
    });

    test('stays put for a same-user restore, observe, or refresh', () {
      final CurrentUserSession session = CurrentUserSession()
        ..setIdentity(identity);
      final int afterLogin = session.sessionGeneration;

      session.setIdentity(identity);
      session.setIdentity(
        AuthIdentity(
          userId: 'user-1',
          email: 'refreshed@example.com',
          isEmailVerified: false,
        ),
      );
      session.setIdentity(
        AuthIdentity(
          userId: 'user-1',
          email: 'user@example.com',
          isEmailVerified: true,
        ),
      );

      expect(session.sessionGeneration, afterLogin);
      expect(session.identity?.email, 'user@example.com');
    });

    test('advances on a user ID change', () {
      final CurrentUserSession session = CurrentUserSession()
        ..setIdentity(identity);
      final int afterLogin = session.sessionGeneration;

      session.setIdentity(
        AuthIdentity(
          userId: 'user-2',
          email: 'second@example.com',
          isEmailVerified: true,
        ),
      );

      expect(session.sessionGeneration, afterLogin + 1);
    });

    test('advances on active to clear', () {
      final CurrentUserSession session = CurrentUserSession()
        ..setIdentity(identity);
      final int afterLogin = session.sessionGeneration;

      session.clear();

      expect(session.sessionGeneration, afterLogin + 1);
    });

    test('does not advance when an empty session is cleared', () {
      final CurrentUserSession session = CurrentUserSession();

      session.clear();
      session.clear();

      expect(session.sessionGeneration, 0);
    });

    test('never repeats a generation when a user signs back in', () {
      final CurrentUserSession session = CurrentUserSession()
        ..setIdentity(identity);
      final int firstLogin = session.sessionGeneration;

      session.clear();
      session.setIdentity(identity);

      expect(session.sessionGeneration, greaterThan(firstLogin + 1));
      expect(session.sessionGeneration, isNot(firstLogin));
      expect(session.userId, 'user-1');
    });

    test('advances once for a direct switch to another user', () {
      final CurrentUserSession session = CurrentUserSession()
        ..setIdentity(identity);

      session.setIdentity(
        AuthIdentity(
          userId: 'user-2',
          email: 'second@example.com',
          isEmailVerified: true,
        ),
      );
      session.setIdentity(
        AuthIdentity(
          userId: 'user-2',
          email: 'second@example.com',
          isEmailVerified: false,
        ),
      );

      expect(session.sessionGeneration, 2);
    });
  });

  group('auth inputs', () {
    test('RegisterInput holds immutable primitive request fields', () {
      const RegisterInput input = RegisterInput(
        email: 'new@example.com',
        displayName: 'New User',
        password: 'secret-1',
        confirmPassword: 'secret-1',
      );

      expect(input.email, 'new@example.com');
      expect(input.displayName, 'New User');
      expect(input.password, 'secret-1');
      expect(input.confirmPassword, 'secret-1');
    });

    test('LoginInput holds immutable primitive request fields', () {
      const LoginInput input = LoginInput(
        email: 'new@example.com',
        password: 'secret-1',
      );

      expect(input.email, 'new@example.com');
      expect(input.password, 'secret-1');
    });
  });

  group('AuthUserDto', () {
    test('fromIdentity copies the domain identity fields', () {
      final AuthUserDto user = AuthUserDto.fromIdentity(identity);

      expect(user.userId, 'user-1');
      expect(user.email, 'user@example.com');
      expect(user.isEmailVerified, isTrue);
    });

    test('can be built directly from provider facts', () {
      const AuthUserDto user = AuthUserDto(
        userId: 'user-9',
        email: 'direct@example.com',
        isEmailVerified: false,
      );

      expect(user.userId, 'user-9');
      expect(user.email, 'direct@example.com');
      expect(user.isEmailVerified, isFalse);
    });
  });

  group('RegistrationResult', () {
    test('pairs the registered user with the dispatch status', () {
      const RegistrationResult result = RegistrationResult(
        user: AuthUserDto(
          userId: 'user-1',
          email: 'user@example.com',
          isEmailVerified: false,
        ),
        verificationDispatchStatus: VerificationDispatchStatus.requested,
      );

      expect(result.user.userId, 'user-1');
      expect(result.user.isEmailVerified, isFalse);
      expect(
        result.verificationDispatchStatus,
        VerificationDispatchStatus.requested,
      );
    });

    test('exposes exactly the three dispatch statuses', () {
      expect(VerificationDispatchStatus.values, <VerificationDispatchStatus>[
        VerificationDispatchStatus.notRequired,
        VerificationDispatchStatus.requested,
        VerificationDispatchStatus.pending,
      ]);
    });
  });

  group('AuthValidationException', () {
    test('carries only the rejection reason', () {
      const AuthValidationException exception = AuthValidationException(
        AuthValidationReason.passwordConfirmationMismatch,
      );

      expect(
        exception.reason,
        AuthValidationReason.passwordConfirmationMismatch,
      );
      expect(exception, isA<Exception>());
      expect(
        exception.toString(),
        'AuthValidationException(passwordConfirmationMismatch)',
      );
    });

    test('exposes exactly the Phase 3 validation reasons', () {
      expect(AuthValidationReason.values, <AuthValidationReason>[
        AuthValidationReason.emailRequired,
        AuthValidationReason.displayNameRequired,
        AuthValidationReason.passwordRequired,
        AuthValidationReason.passwordConfirmationMismatch,
        AuthValidationReason.verificationCodeRequired,
        AuthValidationReason.currentPasswordRequired,
      ]);
    });
  });
}
