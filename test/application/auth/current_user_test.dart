import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/current_user.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';

void main() {
  final AuthIdentity identity = AuthIdentity(
    userId: 'user-1',
    email: 'user@example.com',
    isEmailVerified: true,
  );

  group('StaticCurrentUser', () {
    test('exposes an authenticated identity and user id', () {
      final ICurrentUser currentUser = StaticCurrentUser(identity: identity);

      expect(currentUser.identity, same(identity));
      expect(currentUser.isAuthenticated, isTrue);
      expect(currentUser.userId, 'user-1');
      expect(currentUser.requiredUserId, 'user-1');
    });

    test('requiredUserId throws when unauthenticated', () {
      final ICurrentUser currentUser = _UnauthenticatedCurrentUser();

      expect(currentUser.identity, isNull);
      expect(currentUser.isAuthenticated, isFalse);
      expect(currentUser.userId, isNull);
      expect(
        () => currentUser.requiredUserId,
        throwsA(isA<UnauthenticatedException>()),
      );
    });
  });
}

final class _UnauthenticatedCurrentUser implements ICurrentUser {
  @override
  AuthIdentity? get identity => null;

  @override
  bool get isAuthenticated => false;

  @override
  String? get userId => null;

  @override
  String get requiredUserId => throw const UnauthenticatedException();
}
