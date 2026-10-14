import 'note_dto.dart';
import '../../domain/notes/note_document.dart';

/// Retains editor evidence only; never creates a mutation or grants access.
abstract interface class ILocalDraftVault {
  Future<void> retainEditorDraft(
    NoteDto selected,
    String title,
    String content,
  );
}

abstract interface class IRichLocalDraftVault implements ILocalDraftVault {
  Future<void> retainDocumentDraft(
    NoteDto selected,
    String title,
    NoteDocument document,
  );
}
