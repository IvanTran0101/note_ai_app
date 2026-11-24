import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/domain/users/user_preferences.dart';

void main() {
  group('UserPreferences.create', () {
    test('creates valid preferences and exposes every field', () {
      final UserPreferences preferences = UserPreferences.create(
        userId: '  user-42 ',
        theme: AppThemePreference.dark,
        noteFontSize: NoteFontSizePreference.large,
        noteColorKey: '  lavender  ',
      );

      expect(preferences.userId, 'user-42');
      expect(preferences.theme, AppThemePreference.dark);
      expect(preferences.noteFontSize, NoteFontSizePreference.large);
      expect(preferences.noteColorKey, 'lavender');
    });

    test('rejects a blank userId', () {
      expect(
        () => UserPreferences.create(
          userId: '  ',
          theme: AppThemePreference.system,
          noteFontSize: NoteFontSizePreference.medium,
        ),
        throwsArgumentError,
      );
    });
  });

  group('UserPreferences.reconstitute', () {
    test('restores preferences from persistence data', () {
      final UserPreferences preferences = UserPreferences.reconstitute(
        userId: 'user-42',
        theme: AppThemePreference.light,
        noteFontSize: NoteFontSizePreference.small,
        noteColorKey: 'warm-gray',
      );

      expect(preferences.userId, 'user-42');
      expect(preferences.theme, AppThemePreference.light);
      expect(preferences.noteFontSize, NoteFontSizePreference.small);
      expect(preferences.noteColorKey, 'warm-gray');
    });
  });

  test('changes the theme preference', () {
    final UserPreferences preferences = UserPreferences.create(
      userId: 'user-42',
      theme: AppThemePreference.system,
      noteFontSize: NoteFontSizePreference.medium,
    );

    preferences.changeTheme(AppThemePreference.dark);

    expect(preferences.theme, AppThemePreference.dark);
  });

  test('changes the note font-size preference', () {
    final UserPreferences preferences = UserPreferences.create(
      userId: 'user-42',
      theme: AppThemePreference.system,
      noteFontSize: NoteFontSizePreference.medium,
    );

    preferences.changeNoteFontSize(NoteFontSizePreference.large);

    expect(preferences.noteFontSize, NoteFontSizePreference.large);
  });

  test('changes and clears the note color key', () {
    final UserPreferences preferences = UserPreferences.create(
      userId: 'user-42',
      theme: AppThemePreference.system,
      noteFontSize: NoteFontSizePreference.medium,
    );

    preferences.changeNoteColor('  lavender  ');
    expect(preferences.noteColorKey, 'lavender');

    preferences.changeNoteColor(null);
    expect(preferences.noteColorKey, isNull);
  });
}
