import 'note_dto.dart';

/// Retains editor evidence only; never creates a mutation or grants access.
abstract interface class ILocalDraftVault {
  Future<void> retainEditorDraft(
    NoteDto selected,
    String title,
    String content,
  );
}
