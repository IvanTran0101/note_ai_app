import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/domain/auth/auth_identity.dart';

void main() {
  group('AuthIdentity', () {
    test('creates a valid identity and normalizes text values', () {
      final AuthIdentity identity = AuthIdentity(
        userId: '  user-42 ',
        email: '  user@example.com  ',
        isEmailVerified: true,
      );

      expect(identity.userId, 'user-42');
      expect(identity.email, 'user@example.com');
      expect(identity.isEmailVerified, isTrue);
    });

    test('preserves an unverified status', () {
      final AuthIdentity identity = AuthIdentity(
        userId: 'user-42',
        email: 'user@example.com',
        isEmailVerified: false,
      );

      expect(identity.isEmailVerified, isFalse);
    });

    test('rejects a blank userId', () {
      expect(
        () => AuthIdentity(
          userId: '  ',
          email: 'user@example.com',
          isEmailVerified: false,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a blank email', () {
      expect(
        () => AuthIdentity(
          userId: 'user-42',
          email: '  ',
          isEmailVerified: false,
        ),
        throwsArgumentError,
      );
    });

    test('compares identities by value', () {
      final AuthIdentity first = AuthIdentity(
        userId: 'user-42',
        email: 'user@example.com',
        isEmailVerified: true,
      );
      final AuthIdentity second = AuthIdentity(
        userId: 'user-42',
        email: 'user@example.com',
        isEmailVerified: true,
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('does not expose the email in its string representation', () {
      final AuthIdentity identity = AuthIdentity(
        userId: 'user-42',
        email: 'user@example.com',
        isEmailVerified: true,
      );

      expect(identity.toString(), contains('user-42'));
      expect(identity.toString(), isNot(contains('user@example.com')));
      expect(identity.toString(), isNot(contains('password')));
      expect(identity.toString(), isNot(contains('token')));
    });
  });
}
