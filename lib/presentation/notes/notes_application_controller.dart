import '../../application/notes/note_application.dart';

/// A narrow Presentation seam around the Note application use cases.
///
/// The concrete application service is the default production dependency.
/// This seam keeps widget tests independent from repositories, file storage,
/// and the local-LLM implementation.
abstract interface class NotesApplicationController {
  Future<List<NoteDto>> listNotes();

  Future<NoteDto> createNote({required String title, required String content});

  Future<NoteDto> renameNote({required String noteId, required String title});

  Future<NoteDto> replaceContent({
    required String noteId,
    required String content,
  });

  Future<void> deleteNote(String noteId);

  /// Returns summary text instead of exposing the Domain [Summary] type to
  /// the widget.
  Future<String> summarizeNote(String noteId);
}

/// Presentation adapter for the Application service.
///
/// It intentionally contains no Infrastructure knowledge. The root can pass
/// [NoteApplicationService] directly to [NotesPage], while tests can inject a
/// [NotesApplicationController] fake.
final class NoteApplicationServiceController
    implements NotesApplicationController {
  const NoteApplicationServiceController(this._service);

  final NoteApplicationService _service;

  @override
  Future<List<NoteDto>> listNotes() => _service.listNotes();

  @override
  Future<NoteDto> createNote({required String title, required String content}) {
    return _service.createNote(title: title, content: content);
  }

  @override
  Future<NoteDto> renameNote({required String noteId, required String title}) {
    return _service.renameNote(noteId: noteId, title: title);
  }

  @override
  Future<NoteDto> replaceContent({
    required String noteId,
    required String content,
  }) {
    return _service.replaceContent(noteId: noteId, content: content);
  }

  @override
  Future<void> deleteNote(String noteId) => _service.deleteNote(noteId);

  @override
  Future<String> summarizeNote(String noteId) async {
    final summary = await _service.summarizeNote(noteId);
    return summary.text;
  }
}
