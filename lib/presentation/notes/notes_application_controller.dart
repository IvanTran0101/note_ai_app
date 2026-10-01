import '../../application/notes/note_application.dart';
import '../../application/note_intelligence/summary_run_context.dart';
import '../../application/note_intelligence/summary_consent_app_service.dart';
import '../../domain/users/user_preferences.dart';

/// A narrow Presentation seam around the Note application use cases.
///
/// The concrete application service is the default production dependency.
/// This seam keeps widget tests independent from repositories, file storage,
/// and the local-LLM implementation.
abstract interface class NotesApplicationController {
  /// Optional session consent actions; unavailable for unwired/local test seams.
  SummaryConsentAppService? get summaryConsent;

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
  Future<String> summarizeNote(
    String noteId, {
    NoteDto? selectedSnapshot,
    SummaryRunScope? scope,
  });
}

/// Optional Module 02 operations used by the production editor and dashboard.
/// The older test seam remains usable without implementing the new flows.
abstract interface class NotesModule02Controller {
  Future<NoteDto> updateNote({
    required String noteId,
    required String title,
    required String content,
  });

  Future<NoteDto> setPinned({required String noteId, required bool pinned});

  Future<NoteLayoutPreference> getNoteLayout();

  Future<void> setNoteLayout(NoteLayoutPreference layout);
}

/// Presentation adapter for the Application service.
///
/// It intentionally contains no Infrastructure knowledge. The root can pass
/// [NoteApplicationService] directly to [NotesPage], while tests can inject a
/// [NotesApplicationController] fake.
final class NoteApplicationServiceController
    implements NotesApplicationController, NotesModule02Controller {
  const NoteApplicationServiceController(this._service, {this.summaryConsent});

  final NoteApplicationService _service;

  @override
  final SummaryConsentAppService? summaryConsent;

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
  Future<NoteDto> updateNote({
    required String noteId,
    required String title,
    required String content,
  }) => _service.updateNote(noteId: noteId, title: title, content: content);

  @override
  Future<NoteDto> setPinned({required String noteId, required bool pinned}) =>
      _service.setPinned(noteId: noteId, pinned: pinned);

  @override
  Future<NoteLayoutPreference> getNoteLayout() => _service.getNoteLayout();

  @override
  Future<void> setNoteLayout(NoteLayoutPreference layout) =>
      _service.setNoteLayout(layout);

  @override
  Future<void> deleteNote(String noteId) => _service.deleteNote(noteId);

  @override
  Future<String> summarizeNote(
    String noteId, {
    NoteDto? selectedSnapshot,
    SummaryRunScope? scope,
  }) async {
    try {
      final summary = await _service.summarizeNote(
        noteId,
        selectedSnapshot: selectedSnapshot,
        scope: scope,
      );
      return summary.text;
    } on SummaryRunFailure {
      rethrow;
    } on Object {
      throw const SummaryRunFailure(SummaryRunFailureCode.unexpected);
    }
  }
}
