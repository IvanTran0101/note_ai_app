part of 'note_application.dart';

extension NoteLayoutUseCases on NoteApplicationService {
  Future<NoteLayoutPreference> getNoteLayout() async {
    final context = _captureContext();
    final saved = await userPreferencesRepository?.findByUserId(context.userId);
    _requireContext(context);
    return saved?.noteLayout ?? NoteLayoutPreference.grid;
  }

  Future<void> setNoteLayout(NoteLayoutPreference layout) {
    final context = _captureContext();
    return _writePreference(() async {
      _requireContext(context);
      final repository = userPreferencesRepository;
      if (repository == null) return;
      final saved =
          await repository.findByUserId(context.userId) ??
          UserPreferences.create(
            userId: context.userId,
            theme: AppThemePreference.system,
            noteFontSize: NoteFontSizePreference.medium,
          );
      _requireContext(context);
      saved.changeNoteLayout(layout);
      await repository.save(saved);
      _requireContext(context);
    });
  }

  /// Reads the theme saved for the active account.
  ///
  /// With no repository or no stored record the answer is
  /// [AppThemePreference.system], which is what the app starts from: a missing
  /// preference is never an error and never blocks the notes workspace.
  Future<AppThemePreference> getTheme() async {
    final context = _captureContext();
    final saved = await userPreferencesRepository?.findByUserId(context.userId);
    _requireContext(context);
    return saved?.theme ?? AppThemePreference.system;
  }

  /// Saves [theme] for the active account through the atomic preferences
  /// repository, preserving every other stored preference.
  Future<void> setTheme(AppThemePreference theme) {
    final context = _captureContext();
    return _writePreference(() async {
      _requireContext(context);
      final repository = userPreferencesRepository;
      if (repository == null) return;
      final saved =
          await repository.findByUserId(context.userId) ??
          UserPreferences.create(
            userId: context.userId,
            theme: AppThemePreference.system,
            noteFontSize: NoteFontSizePreference.medium,
          );
      _requireContext(context);
      saved.changeTheme(theme);
      await repository.save(saved);
      _requireContext(context);
    });
  }
}
