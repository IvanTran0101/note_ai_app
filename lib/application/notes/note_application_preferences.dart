part of 'note_application.dart';

extension NoteLayoutUseCases on NoteApplicationService {
  Future<NoteLayoutPreference> getNoteLayout() async {
    final context = _captureContext();
    final saved = await userPreferencesRepository?.findByUserId(context.userId);
    _requireContext(context);
    return saved?.noteLayout ?? NoteLayoutPreference.grid;
  }

  Future<void> setNoteLayout(NoteLayoutPreference layout) async {
    final context = _captureContext();
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
  }
}
