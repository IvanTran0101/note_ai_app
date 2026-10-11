/// NoteFlow-owned profile data, separate from authentication identity.
///
/// The display name is the only user-authored value here, so it is validated
/// with the same semantic on every platform: trimmed, non-blank, and at most
/// [maxDisplayNameRunes] Unicode code points. [revision] is the canonical
/// concurrency token of the shared cloud profile: it is immutable for the
/// lifetime of one instance and `0` means "no stored profile yet", so a save
/// built from a loaded profile carries the revision it was loaded with instead
/// of blindly overwriting a newer server state.
final class UserProfile {
  UserProfile._(
    this._userId,
    this._displayName,
    this._avatarReference,
    this._revision,
  );

  /// Creates a profile from user-owned values.
  ///
  /// [revision] defaults to `0`, which is the create case: a profile that does
  /// not exist on the server yet.
  factory UserProfile.create({
    required String userId,
    required String displayName,
    String? avatarReference,
    int revision = 0,
  }) {
    return UserProfile._(
      _requireText(userId, 'userId'),
      _requireDisplayName(displayName),
      _normalizeReference(avatarReference),
      _requireRevision(revision),
    );
  }

  /// Restores a profile from persistence data.
  ///
  /// [revision] defaults to `0` so legacy native/local records that predate the
  /// cloud revision still load unchanged.
  factory UserProfile.reconstitute({
    required String userId,
    required String displayName,
    String? avatarReference,
    int revision = 0,
  }) {
    return UserProfile._(
      _requireText(userId, 'userId'),
      _requireDisplayName(displayName),
      _normalizeReference(avatarReference),
      _requireRevision(revision),
    );
  }

  /// Longest accepted display name, in Unicode code points.
  static const int maxDisplayNameRunes = 100;

  final String _userId;
  String _displayName;
  String? _avatarReference;
  final int _revision;

  /// Authenticated/application owner identity for this profile.
  String get userId => _userId;

  /// Current display name.
  String get displayName => _displayName;

  /// Provider-neutral avatar reference, or `null` for the default avatar.
  String? get avatarReference => _avatarReference;

  /// Canonical concurrency token; `0` means the profile is not stored yet.
  int get revision => _revision;

  /// Returns an independent copy with the same values.
  ///
  /// Snapshot holders use this so a later [changeDisplayName] or
  /// [changeAvatar] on the instance they were handed cannot rewrite what they
  /// already observed.
  UserProfile copy() {
    return UserProfile._(_userId, _displayName, _avatarReference, _revision);
  }

  /// Changes and normalizes the display name.
  void changeDisplayName(String displayName) {
    _displayName = _requireDisplayName(displayName);
  }

  /// Changes or clears the provider-neutral avatar reference.
  void changeAvatar(String? avatarReference) {
    _avatarReference = _normalizeReference(avatarReference);
  }
}

String _requireText(String value, String fieldName) {
  final String normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, fieldName, 'must not be blank');
  }
  return normalized;
}

String _requireDisplayName(String value) {
  final String normalized = _requireText(value, 'displayName');
  if (normalized.runes.length > UserProfile.maxDisplayNameRunes) {
    throw ArgumentError.value(
      value,
      'displayName',
      'must be at most ${UserProfile.maxDisplayNameRunes} code points',
    );
  }
  return normalized;
}

int _requireRevision(int revision) {
  if (revision < 0) {
    throw ArgumentError.value(revision, 'revision', 'must not be negative');
  }
  return revision;
}

String? _normalizeReference(String? value) {
  final String? normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}
