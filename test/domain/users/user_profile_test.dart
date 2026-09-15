import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/domain/users/user_profile.dart';

void main() {
  group('UserProfile.create', () {
    test('creates a valid profile and exposes every field', () {
      final UserProfile profile = UserProfile.create(
        userId: '  user-42 ',
        displayName: '  Alex  ',
        avatarReference: '  avatar-key  ',
      );

      expect(profile.userId, 'user-42');
      expect(profile.displayName, 'Alex');
      expect(profile.avatarReference, 'avatar-key');
    });

    test('rejects a blank userId', () {
      expect(
        () => UserProfile.create(userId: '  ', displayName: 'Alex'),
        throwsArgumentError,
      );
    });

    test('rejects a blank displayName', () {
      expect(
        () => UserProfile.create(userId: 'user-42', displayName: '  '),
        throwsArgumentError,
      );
    });
  });

  group('UserProfile.reconstitute', () {
    test('restores a profile from persistence data', () {
      final UserProfile profile = UserProfile.reconstitute(
        userId: 'user-42',
        displayName: 'Alex',
        avatarReference: 'avatar-key',
      );

      expect(profile.userId, 'user-42');
      expect(profile.displayName, 'Alex');
      expect(profile.avatarReference, 'avatar-key');
    });
  });

  group('UserProfile.changeDisplayName', () {
    test('normalizes and changes the display name', () {
      final UserProfile profile = UserProfile.create(
        userId: 'user-42',
        displayName: 'Alex',
      );

      profile.changeDisplayName('  Taylor  ');

      expect(profile.displayName, 'Taylor');
      expect(profile.userId, 'user-42');
    });
  });

  group('UserProfile.changeAvatar', () {
    test('changes and clears the avatar reference', () {
      final UserProfile profile = UserProfile.create(
        userId: 'user-42',
        displayName: 'Alex',
      );

      profile.changeAvatar('  avatar-key  ');
      expect(profile.avatarReference, 'avatar-key');

      profile.changeAvatar(null);
      expect(profile.avatarReference, isNull);
    });
  });
}
