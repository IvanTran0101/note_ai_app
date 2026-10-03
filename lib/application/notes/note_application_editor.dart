part of 'note_application.dart';

extension NoteEditorUseCase on NoteApplicationService {
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
