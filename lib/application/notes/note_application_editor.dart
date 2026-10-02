part of 'note_application.dart';

extension NoteEditorUseCase on NoteApplicationService {
  Future<NoteDto> saveEditorSnapshot(
    NoteDto selected,
    String title,
    String content,
  ) async {
    final context = _captureContext();
    final current = await _requireOwnedNote(
      selected.reference,
      context,
      NoteOperation.edit,
    );
    if (NoteDto.fromDomain(current) != selected) {
      throw NoteEditorChanged(NoteDto.fromDomain(current));
    }
    final changed = Note.reconstitute(
      id: current.id,
      ownerId: current.ownerId,
      title: current.title,
      content: current.content,
      createdAt: current.createdAt,
      updatedAt: current.updatedAt,
      protection: current.protection,
      contentRevision: current.contentRevision,
      share: current.share,
    );
    final timestamp = now().toUtc();
    changed.rename(title, timestamp);
    changed.replaceContent(content, timestamp);
    final Object repository = noteRepository;
    try {
      if (repository is INoteSnapshotRepository) {
        await repository.saveSnapshot(changed, current);
      } else {
        await noteRepository.save(changed);
      }
    } on NoteSnapshotChanged {
      final fresh = await _requireOwnedNote(
        selected.reference,
        context,
        NoteOperation.edit,
      );
      throw NoteEditorChanged(NoteDto.fromDomain(fresh));
    }
    _requireContext(context);
    _requireAccess(changed, NoteOperation.edit);
    requestSync?.call(context.userId);
    return NoteDto.fromDomain(changed);
  }
}
