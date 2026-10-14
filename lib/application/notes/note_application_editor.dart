part of 'note_application.dart';

extension NoteEditorUseCase on NoteApplicationService {
  Future<NoteDto> saveDocumentSnapshot(
    NoteDto selected,
    String title,
    NoteDocument document,
  ) async {
    final Object repository = noteRepository;
    if (repository is! INoteDocumentRepository ||
        repository.documentVersion != NoteDocument.version) {
      throw const NoteDocumentStorageUnavailable();
    }
    return _mutateNote(
      selected.reference,
      NoteOperation.edit,
      (note) => note.replaceDocument(title, document, now().toUtc()),
      expected: selected,
    );
  }

  Future<NoteDto> saveEditorSnapshot(
    NoteDto selected,
    String title,
    String content,
  ) => _mutateNote(
    selected.reference,
    NoteOperation.edit,
    (note) => note.replaceText(title, content, now().toUtc()),
    expected: selected,
  );
}
