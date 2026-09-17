import 'user_profile.dart';

/// Persistence contract for NoteFlow-owned user profiles.
abstract interface class IUserProfileRepository {
  /// Returns the profile for [userId], or `null` when it is not stored.
  Future<UserProfile?> findByUserId(String userId);

  /// Creates or replaces the supplied profile using [UserProfile.userId].
  Future<void> save(UserProfile profile);
}
