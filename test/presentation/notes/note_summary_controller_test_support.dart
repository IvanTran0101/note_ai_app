part of 'note_summary_controller_test.dart';

final DateTime _time = DateTime.utc(2026, 10, 1);

NoteDto _note({String content = 'Saved synthetic body'}) => NoteDto(
  id: 'note-a',
  ownerId: 'account-a',
  title: 'Selected note',
  content: content,
  createdAt: _time,
  updatedAt: _time,
);

final class _FakeNotesController implements NotesApplicationController {
  _FakeNotesController({this.summaryConsent, List<NoteDto>? notes})
    : notes = List<NoteDto>.of(notes ?? const <NoteDto>[]);

  @override
  final SummaryConsentAppService? summaryConsent;

  final List<NoteDto> notes;
  int summarizeCalls = 0;
  NoteDto? lastSnapshot;
  Completer<String>? pending;
  SummaryRunFailure? failure;
  Object? readError;
  Completer<List<NoteDto>>? pendingRead;

  @override
  Future<List<NoteDto>> listNotes() async {
    if (readError != null) throw readError!;
    final pending = pendingRead;
    if (pending != null) return pending.future;
    return List<NoteDto>.of(notes);
  }

  @override
  Future<String> summarizeNote(
    String noteId, {
    NoteDto? selectedSnapshot,
    SummaryRunScope? scope,
  }) {
    summarizeCalls++;
    lastSnapshot = selectedSnapshot;
    final SummaryRunFailure? error = failure;
    if (error != null) {
      return Future<String>.error(error);
    }
    final Completer<String>? completer = pending;
    if (completer != null) {
      return completer.future;
    }
    return Future<String>.value('Summary of ${selectedSnapshot?.content}');
  }

  @override
  Future<NoteDto> createNote({
    required String title,
    required String content,
  }) => throw UnimplementedError();

  @override
  Future<NoteDto> renameNote({required String noteId, required String title}) =>
      throw UnimplementedError();

  @override
  Future<NoteDto> replaceContent({
    required String noteId,
    required String content,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteNote(String noteId) => throw UnimplementedError();
}

/// One controller under test plus the mutable facts a run revalidates.
final class _Rig {
  _Rig._(this.session, this.store, this.notes);

  factory _Rig({bool cloudConsent = false, bool available = true}) {
    final CurrentUserSession session = CurrentUserSession()
      ..setIdentity(
        AuthIdentity(
          userId: 'account-a',
          email: 'a@example.test',
          isEmailVerified: true,
        ),
      );
    final SummaryCloudConsent store = SummaryCloudConsent(session: session);
    final NoteDto seed = _note();
    final _Rig rig = _Rig._(
      session,
      store,
      _FakeNotesController(
        summaryConsent: cloudConsent
            ? SummaryConsentAppService(
                currentUser: session,
                session: session,
                consent: store,
                isAvailable: () => available,
                cancelActiveRuns: () {},
              )
            : null,
        notes: <NoteDto>[seed],
      ),
    );
    rig.note = seed;
    return rig;
  }

  final CurrentUserSession session;
  final SummaryCloudConsent store;
  final _FakeNotesController notes;
  NoteDto? note = _note();
  bool dirty = false;
  bool conflicted = false;
  NotesApplicationController? replacement;
  Completer<bool>? decision;
  int dialogs = 0;
  Object? dialogError;

  NoteSummaryController build() {
    final NoteSummaryController controller = NoteSummaryController(
      notesController: () => replacement ?? notes,
      editorFacts: () => NoteSummaryEditorFacts(
        note: note,
        isDirty: dirty,
        hasConflict: conflicted,
      ),
      confirmConsent: () {
        if (dialogError != null) throw dialogError!;
        dialogs++;
        final Completer<bool>? pending = decision;
        return pending == null ? Future<bool>.value(true) : pending.future;
      },
    );
    addTearDown(controller.dispose);
    return controller;
  }
}
