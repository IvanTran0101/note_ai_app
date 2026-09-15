/// NoteFlow-owned profile data, separate from authentication identity.
final class UserProfile {
  UserProfile._(this._userId, this._displayName, this._avatarReference);

  /// Creates a profile from user-owned values.
  factory UserProfile.create({
    required String userId,
    required String displayName,
    String? avatarReference,
  }) {
    return UserProfile._(
      _requireText(userId, 'userId'),
      _requireText(displayName, 'displayName'),
      _normalizeReference(avatarReference),
    );
  }

  /// Restores a profile from persistence data.
  factory UserProfile.reconstitute({
    required String userId,
    required String displayName,
    String? avatarReference,
  }) {
    return UserProfile._(
      _requireText(userId, 'userId'),
      _requireText(displayName, 'displayName'),
      _normalizeReference(avatarReference),
    );
  }

  final String _userId;
  String _displayName;
  String? _avatarReference;

  /// Authenticated/application owner identity for this profile.
  String get userId => _userId;

  /// Current display name.
  String get displayName => _displayName;

  /// Provider-neutral avatar reference, or `null` for the default avatar.
  String? get avatarReference => _avatarReference;

  /// Changes and normalizes the display name.
  void changeDisplayName(String displayName) {
    _displayName = _requireText(displayName, 'displayName');
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

String? _normalizeReference(String? value) {
  final String? normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}
