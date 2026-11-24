// Verifies the conditional user-profile repository facade without importing
// dart:io, so it compiles and runs for the Web target too.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/users/user_profile.dart';
import 'package:note_ai_app/infrastructure/users/user_profile_repository.dart';

void main() {
  test('Web facade exposes an unavailable user-profile repository', () {
    if (!kIsWeb) {
      return;
    }

    final IUserProfileRepository repository = createUserProfileRepository();
    final UserProfile profile = UserProfile.create(
      userId: 'user-1',
      displayName: 'Ada Lovelace',
    );

    expect(() => repository.findByUserId('user-1'), throwsUnsupportedError);
    expect(() => repository.save(profile), throwsUnsupportedError);
  });
}
