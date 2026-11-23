part of 'note_application.dart';

extension NoteMutationUseCases on NoteApplicationService {
  Future<NoteDto> renameNote({required String noteId, required String title}) =>
      _mutateNote(
        noteId,
        NoteOperation.edit,
        (note) => note.rename(title, now().toUtc()),
      );

  Future<NoteDto> replaceContent({
    required String noteId,
    required String content,
  }) => _mutateNote(
    noteId,
    NoteOperation.edit,
    (note) => note.replaceContent(content, now().toUtc()),
  );

  Future<NoteDto> updateNote({
    required String noteId,
    required String title,
    required String content,
  }) => _mutateNote(
    noteId,
    NoteOperation.edit,
    (note) => note.replaceText(title, content, now().toUtc()),
  );

  Future<NoteDto> setPinned({required String noteId, required bool pinned}) =>
      _mutateNote(
        noteId,
        NoteOperation.manage,
        (note) => pinned ? note.pin(now().toUtc()) : note.unpin(now().toUtc()),
      );

  Future<NoteDto> _mutateNote(
    String reference,
    NoteOperation operation,
    void Function(Note) apply, {
    NoteDto? expected,
  }) async {
    final context = _captureContext();
    final previous = await _requireOwnedNote(reference, context, operation);
    NoteDto? before;
    final saved = await noteRepository.updateById(
      noteId: previous.id,
      ownerId: previous.ownerId,
      expectedAccountUserId: context.userId,
      canCommit: () =>
          currentUser.userId == context.userId &&
          _sessionGeneration() == context.session &&
          (security?.accessGeneration ?? 0) == context.access,
      change: (fresh) {
        _requireContext(context);
        _requireAccess(fresh, operation);
        before = NoteDto.fromDomain(fresh);
        if (expected != null && before != expected) {
          throw NoteEditorChanged(before!);
        }
        apply(fresh);
        return fresh;
      },
    );
    _requireContext(context);
    _requireAccess(saved, operation);
    if (before != NoteDto.fromDomain(saved)) requestSync?.call(context.userId);
    return NoteDto.fromDomain(saved);
  }
}
