import 'dart:typed_data';

import '../../domain/users/user_profile.dart';

/// One observed state of the signed-in account's canonical profile.
///
/// [profile] is `null` when the account has no stored profile yet — a canonical
/// "setup required" state, not an error. [avatarBytes] is `null` when the
/// profile has no avatar reference or the account has no profile.
///
/// The snapshot is detached from the repository instance that produced it, so a
/// later edit on another copy cannot rewrite what this snapshot reported.
final class ProfileSnapshot {
  /// Creates a snapshot of one loaded profile state.
  const ProfileSnapshot({required this.profile, required this.avatarBytes});

  /// Canonical profile, or `null` when the account has none stored.
  final UserProfile? profile;

  /// Avatar bytes for [profile], or `null` when there is no avatar.
  final Uint8List? avatarBytes;
}
