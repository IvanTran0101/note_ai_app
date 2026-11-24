/// Theme choices understood by NoteFlow without depending on Flutter.
enum AppThemePreference { system, light, dark }

/// Note editor font-size choices understood by NoteFlow.
enum NoteFontSizePreference { small, medium, large }

/// Persisted notes-workspace layout choices.
enum NoteLayoutPreference { grid, list }

/// Persisted user preferences owned by NoteFlow.
final class UserPreferences {
  UserPreferences._(
    this._userId,
    this._theme,
    this._noteFontSize,
    this._noteColorKey,
    this._noteLayout,
  );

  /// Creates preferences from the supplied domain-neutral values.
  factory UserPreferences.create({
    required String userId,
    required AppThemePreference theme,
    required NoteFontSizePreference noteFontSize,
    String? noteColorKey,
    NoteLayoutPreference noteLayout = NoteLayoutPreference.grid,
  }) => UserPreferences._(
    _requireUserId(userId),
    theme,
    noteFontSize,
    _normalizeColorKey(noteColorKey),
    noteLayout,
  );

  /// Restores preferences from persistence data.
  factory UserPreferences.reconstitute({
    required String userId,
    required AppThemePreference theme,
    required NoteFontSizePreference noteFontSize,
    String? noteColorKey,
    NoteLayoutPreference noteLayout = NoteLayoutPreference.grid,
  }) => UserPreferences._(
    _requireUserId(userId),
    theme,
    noteFontSize,
    _normalizeColorKey(noteColorKey),
    noteLayout,
  );

  final String _userId;
  AppThemePreference _theme;
  NoteFontSizePreference _noteFontSize;
  String? _noteColorKey;
  NoteLayoutPreference _noteLayout;

  String get userId => _userId;
  AppThemePreference get theme => _theme;
  NoteFontSizePreference get noteFontSize => _noteFontSize;
  String? get noteColorKey => _noteColorKey;
  NoteLayoutPreference get noteLayout => _noteLayout;

  void changeTheme(AppThemePreference theme) => _theme = theme;

  void changeNoteFontSize(NoteFontSizePreference noteFontSize) =>
      _noteFontSize = noteFontSize;

  void changeNoteColor(String? noteColorKey) =>
      _noteColorKey = _normalizeColorKey(noteColorKey);

  void changeNoteLayout(NoteLayoutPreference noteLayout) =>
      _noteLayout = noteLayout;

  /// Returns a detached copy for an immutable persistence snapshot.
  UserPreferences copy() => UserPreferences.reconstitute(
    userId: userId,
    theme: theme,
    noteFontSize: noteFontSize,
    noteColorKey: noteColorKey,
    noteLayout: noteLayout,
  );

  @override
  bool operator ==(Object other) =>
      other is UserPreferences &&
      other.userId == userId &&
      other.theme == theme &&
      other.noteFontSize == noteFontSize &&
      other.noteColorKey == noteColorKey &&
      other.noteLayout == noteLayout;

  @override
  int get hashCode =>
      Object.hash(userId, theme, noteFontSize, noteColorKey, noteLayout);
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
