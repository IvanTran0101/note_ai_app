/// Theme choices understood by NoteFlow without depending on Flutter.
enum AppThemePreference { system, light, dark }

/// Note editor font-size choices understood by NoteFlow.
enum NoteFontSizePreference { small, medium, large }

/// Persisted user preferences owned by NoteFlow.
final class UserPreferences {
  UserPreferences._(
    this._userId,
    this._theme,
    this._noteFontSize,
    this._noteColorKey,
  );

  /// Creates preferences from the supplied domain-neutral values.
  factory UserPreferences.create({
    required String userId,
    required AppThemePreference theme,
    required NoteFontSizePreference noteFontSize,
    String? noteColorKey,
  }) {
    return UserPreferences._(
      _requireUserId(userId),
      theme,
      noteFontSize,
      _normalizeColorKey(noteColorKey),
    );
  }

  /// Restores preferences from persistence data.
  factory UserPreferences.reconstitute({
    required String userId,
    required AppThemePreference theme,
    required NoteFontSizePreference noteFontSize,
    String? noteColorKey,
  }) {
    return UserPreferences._(
      _requireUserId(userId),
      theme,
      noteFontSize,
      _normalizeColorKey(noteColorKey),
    );
  }

  final String _userId;
  AppThemePreference _theme;
  NoteFontSizePreference _noteFontSize;
  String? _noteColorKey;

  /// User identity associated with these preferences.
  String get userId => _userId;

  /// Current theme preference.
  AppThemePreference get theme => _theme;

  /// Current note font-size preference.
  NoteFontSizePreference get noteFontSize => _noteFontSize;

  /// Platform-neutral note color key, or `null` for the default color.
  String? get noteColorKey => _noteColorKey;

  /// Changes the theme preference.
  void changeTheme(AppThemePreference theme) {
    _theme = theme;
  }

  /// Changes the note font-size preference.
  void changeNoteFontSize(NoteFontSizePreference noteFontSize) {
    _noteFontSize = noteFontSize;
  }

  /// Changes or clears the platform-neutral note color key.
  void changeNoteColor(String? noteColorKey) {
    _noteColorKey = _normalizeColorKey(noteColorKey);
  }
}

String _requireUserId(String value) {
  final String normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, 'userId', 'must not be blank');
  }
  return normalized;
}

String? _normalizeColorKey(String? value) {
  final String? normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}
