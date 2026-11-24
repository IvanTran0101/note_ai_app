import 'user_preferences.dart';

/// Persistence contract for user-specific NoteFlow preferences.
abstract interface class IUserPreferencesRepository {
  /// Returns preferences for [userId], or `null` when none are stored.
  Future<UserPreferences?> findByUserId(String userId);

  /// Creates or replaces the supplied preferences using its user identity.
  Future<void> save(UserPreferences preferences);
}
