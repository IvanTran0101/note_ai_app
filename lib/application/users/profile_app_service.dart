/// Application use cases for the signed-in account's cloud profile/avatar.
///
/// The service owns the account-scoping rule: every operation captures the
/// active [CurrentUserSession] binding (user id plus session generation) before
/// its first await, and re-checks that binding after every await. A result that
/// was produced for a session that has since been cleared or switched is
/// discarded with [ProfileFailureCode.unauthorized] instead of being applied to
/// the new account — the same user id returning after a sign-out is a different
/// session.
///
/// Edits are conditional on the revision that was loaded, never on a blind
/// "last write wins": [saveName] and [removeAvatar] send the loaded revision,
/// and [uploadAvatar] sends it as the intent's `expectedRevision`.
library;

import 'dart:typed_data';

import '../../domain/users/profile_avatar_gateway.dart';
import '../../domain/users/profile_failure.dart';
import '../../domain/users/user_profile.dart';
import '../../domain/users/user_profile_repository.dart';
import '../auth/current_user_session.dart';
import 'profile_snapshot.dart';

/// Coordinates the profile repository, the avatar gateway, and the session.
final class ProfileAppService {
  /// Creates the service over its three collaborators.
  ProfileAppService({
    required this.repository,
    required this.avatarGateway,
    required this.session,
  });

  /// NoteFlow-owned profile persistence (cloud HTTP in production).
  final IUserProfileRepository repository;

  /// Private avatar binary I/O for the signed-in account.
  final IProfileAvatarGateway avatarGateway;

  /// The live session the profile is scoped to.
  final CurrentUserSession session;

  ProfileSnapshot? _current;
  String? _currentUserId;
  int? _currentGeneration;

  /// The last snapshot loaded for the live session, or `null` when there is
  /// none for the current binding.
  ///
  /// It never exposes a snapshot captured for an earlier session generation, so
  /// a signed-out or switched account cannot read the previous account's
  /// profile.
  ProfileSnapshot? get current {
    final String? userId = _currentUserId;
    final int? generation = _currentGeneration;
    if (userId == null || generation == null) {
      return null;
    }
    final snapshot = _current;
    if (!_isLive(userId, generation) || snapshot == null) return null;
    return ProfileSnapshot(
      profile: snapshot.profile?.copy(),
      avatarBytes: snapshot.avatarBytes,
    );
  }

  /// Loads the canonical profile and its avatar bytes for the signed-in user.
  ///
  /// A missing profile is returned as `ProfileSnapshot(profile: null,
  /// avatarBytes: null)`: it means "setup required", not a failure.
  Future<ProfileSnapshot> load() async {
    final _Binding binding = _requireBinding();
    final UserProfile? profile = await repository.findByUserId(binding.userId);
    _recheck(binding);
    final Uint8List? avatarBytes = profile?.avatarReference == null
        ? null
        : await avatarGateway.getAvatar(binding.userId);
    _recheck(binding);
    return _remember(binding, profile, avatarBytes);
  }

  /// Saves [name] as the display name and returns the reloaded canonical state.
  ///
  /// An account with no stored profile gets an explicit revision-0 profile
  /// created from [name]; nothing is migrated from a legacy local record. The
  /// loaded revision is preserved so a concurrent edit on another device is
  /// refused with [ProfileFailureCode.conflict] rather than overwritten.
  Future<ProfileSnapshot> saveName(String name) async {
    final _Binding binding = _requireBinding();
    // Validates before any network work, and doubles as the create candidate.
    final UserProfile created = UserProfile.create(
      userId: binding.userId,
      displayName: name,
    );
    final UserProfile? base = await _baseProfile(binding);
    final UserProfile candidate = base == null
        ? created
        : (base.copy()..changeDisplayName(name));
    await repository.save(candidate);
    _recheck(binding);
    return load();
  }

  /// Uploads [bytes] as the avatar and returns the reloaded canonical state.
  ///
  /// [mime] must be PNG or JPEG and [bytes] at most
  /// [ProfileAvatarRules.maxBytes]; anything else fails with
  /// [ProfileFailureCode.invalid] before a request is made. The account's
  /// currently loaded revision is sent as `expectedRevision`, so a concurrent
  /// profile edit is refused instead of being overwritten. The name must be saved
  /// before an avatar can be associated.
  Future<ProfileSnapshot> uploadAvatar(Uint8List bytes, String mime) async {
    final _Binding binding = _requireBinding();
    ProfileAvatarRules.validateInput(bytes: bytes, mime: mime);
    final UserProfile? base = await _baseProfile(binding);
    if (base == null) throw const ProfileFailure(ProfileFailureCode.invalid);
    await avatarGateway.uploadAvatar(
      userId: binding.userId,
      expectedRevision: base.revision,
      bytes: bytes,
      mime: mime,
    );
    _recheck(binding);
    return load();
  }

  /// Clears the avatar reference and returns the reloaded canonical state.
  ///
  /// The stored avatar object is left to server-side cleanup; only the
  /// association is removed. The loaded revision is preserved so a concurrent
  /// edit is refused rather than overwritten.
  Future<ProfileSnapshot> removeAvatar() async {
    final _Binding binding = _requireBinding();
    final UserProfile? base = await _baseProfile(binding);
    if (base == null) {
      // Nothing is associated with an account that has no profile.
      return load();
    }
    final UserProfile candidate = base.copy()..changeAvatar(null);
    await repository.save(candidate);
    _recheck(binding);
    return load();
  }

  _Binding _requireBinding() {
    final String? userId = session.userId;
    if (userId == null) {
      throw const ProfileFailure(ProfileFailureCode.unauthorized);
    }
    return _Binding(userId, session.sessionGeneration);
  }

  void _recheck(_Binding binding) {
    if (!_isLive(binding.userId, binding.generation)) {
      throw const ProfileFailure(ProfileFailureCode.unauthorized);
    }
  }

  bool _isLive(String userId, int generation) {
    return session.userId == userId && session.sessionGeneration == generation;
  }

  /// The profile to edit from: the loaded snapshot for this exact binding when
  /// one exists, otherwise a fresh canonical read. Reusing the loaded revision
  /// is what makes the write conditional instead of a blind overwrite.
  Future<UserProfile?> _baseProfile(_Binding binding) async {
    final ProfileSnapshot? current = _current;
    if (current != null &&
        _currentUserId == binding.userId &&
        _currentGeneration == binding.generation) {
      return current.profile;
    }
    final UserProfile? profile = await repository.findByUserId(binding.userId);
    _recheck(binding);
    return profile;
  }

  ProfileSnapshot _remember(
    _Binding binding,
    UserProfile? profile,
    Uint8List? avatarBytes,
  ) {
    final ProfileSnapshot stored = ProfileSnapshot(
      profile: profile?.copy(),
      avatarBytes: avatarBytes,
    );
    _current = stored;
    _currentUserId = binding.userId;
    _currentGeneration = binding.generation;
    // Hand the caller its own detached profile so mutating the returned value
    // cannot rewrite the snapshot the next edit is derived from.
    return ProfileSnapshot(
      profile: stored.profile?.copy(),
      avatarBytes: stored.avatarBytes,
    );
  }
}

/// The session binding one operation is scoped to.
final class _Binding {
  const _Binding(this.userId, this.generation);

  final String userId;
  final int generation;
}
