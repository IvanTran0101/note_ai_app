import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/domain/users/profile_failure.dart';
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

    test('treats a blank reference as no avatar', () {
      final UserProfile profile = UserProfile.create(
        userId: 'user-42',
        displayName: 'Alex',
        avatarReference: '   ',
      );

      expect(profile.avatarReference, isNull);
    });
  });

  group('UserProfile revision', () {
    test('defaults to 0 for a created profile', () {
      expect(
        UserProfile.create(userId: 'user-42', displayName: 'Alex').revision,
        0,
      );
    });

    test('defaults to 0 for a legacy reconstituted record', () {
      expect(
        UserProfile.reconstitute(userId: 'user-42', displayName: 'Alex')
            .revision,
        0,
      );
    });

    test('keeps an explicit canonical revision', () {
      final UserProfile profile = UserProfile.reconstitute(
        userId: 'user-42',
        displayName: 'Alex',
        revision: 17,
      );

      expect(profile.revision, 17);
    });

    test('stays immutable across name and avatar changes', () {
      final UserProfile profile = UserProfile.reconstitute(
        userId: 'user-42',
        displayName: 'Alex',
        revision: 17,
      );

      profile.changeDisplayName('Taylor');
      profile.changeAvatar('avatar-key');

      expect(profile.revision, 17);
    });

    test('rejects a negative revision', () {
      expect(
        () => UserProfile.create(
          userId: 'user-42',
          displayName: 'Alex',
          revision: -1,
        ),
        throwsArgumentError,
      );
      expect(
        () => UserProfile.reconstitute(
          userId: 'user-42',
          displayName: 'Alex',
          revision: -1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('UserProfile display-name bounds', () {
    test('accepts exactly 100 code points', () {
      final String name = 'a' * UserProfile.maxDisplayNameRunes;

      expect(
        UserProfile.create(userId: 'user-42', displayName: name).displayName,
        name,
      );
    });

    test('rejects 101 code points', () {
      expect(
        () => UserProfile.create(
          userId: 'user-42',
          displayName: 'a' * (UserProfile.maxDisplayNameRunes + 1),
        ),
        throwsArgumentError,
      );
    });

    test('counts code points, not UTF-16 units', () {
      // 100 emoji = 200 UTF-16 units, still a valid 100-code-point name.
      final String name = '👍' * UserProfile.maxDisplayNameRunes;

      expect(name.length, 200);
      expect(
        UserProfile.create(userId: 'user-42', displayName: name).displayName,
        name,
      );
    });

    test('changeDisplayName enforces the same bound', () {
      final UserProfile profile = UserProfile.create(
        userId: 'user-42',
        displayName: 'Alex',
      );

      expect(
        () => profile.changeDisplayName(
          'a' * (UserProfile.maxDisplayNameRunes + 1),
        ),
        throwsArgumentError,
      );
      expect(profile.displayName, 'Alex');
    });
  });

  group('UserProfile.copy', () {
    test('returns an equal but detached profile', () {
      final UserProfile profile = UserProfile.reconstitute(
        userId: 'user-42',
        displayName: 'Alex',
        avatarReference: 'avatar-key',
        revision: 4,
      );

      final UserProfile copy = profile.copy();

      expect(copy, isNot(same(profile)));
      expect(copy.userId, 'user-42');
      expect(copy.displayName, 'Alex');
      expect(copy.avatarReference, 'avatar-key');
      expect(copy.revision, 4);
    });

    test('keeps the observed values when the original is edited', () {
      final UserProfile profile = UserProfile.reconstitute(
        userId: 'user-42',
        displayName: 'Alex',
        revision: 4,
      );

      final UserProfile snapshot = profile.copy();
      profile.changeDisplayName('Taylor');
      profile.changeAvatar('avatar-key');

      expect(snapshot.displayName, 'Alex');
      expect(snapshot.avatarReference, isNull);
      expect(snapshot.revision, 4);
    });

    test('editing the copy leaves the original untouched', () {
      final UserProfile profile = UserProfile.reconstitute(
        userId: 'user-42',
        displayName: 'Alex',
      );

      final UserProfile copy = profile.copy()..changeDisplayName('Taylor');

      expect(copy.displayName, 'Taylor');
      expect(profile.displayName, 'Alex');
    });
  });

  group('ProfileFailure', () {
    test('carries only its stable code in diagnostics', () {
      const ProfileFailure failure = ProfileFailure(
        ProfileFailureCode.conflict,
      );

      expect(failure.code, ProfileFailureCode.conflict);
      expect(failure.toString(), 'ProfileFailure(conflict)');
      expect(failure.toString(), isNot(contains('token')));
    });

    test('exposes the full failure vocabulary', () {
      expect(ProfileFailureCode.values, <ProfileFailureCode>[
        ProfileFailureCode.invalid,
        ProfileFailureCode.conflict,
        ProfileFailureCode.unavailable,
        ProfileFailureCode.unauthorized,
      ]);
    });
  });
}
