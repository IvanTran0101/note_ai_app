part of 'note_detail_summary_flow_test.dart';

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
  Object? error;
  int _sequence = 0;

  @override
  Future<List<NoteDto>> listNotes() async => List<NoteDto>.of(notes);

  @override
  Future<String> summarizeNote(
    String noteId, {
    NoteDto? selectedSnapshot,
    SummaryRunScope? scope,
  }) {
    summarizeCalls++;
    lastSnapshot = selectedSnapshot;
    final Object? untyped = error;
    if (untyped != null) {
      return Future<String>.error(untyped);
    }
    final SummaryRunFailure? typed = failure;
    if (typed != null) {
      return Future<String>.error(typed);
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
  }) async {
    final NoteDto created = NoteDto(
      id: 'note-${++_sequence}',
      ownerId: 'account-a',
      title: title,
      content: content,
      createdAt: _time,
      updatedAt: _time,
    );
    notes.add(created);
    return created;
  }

  @override
  Future<NoteDto> renameNote({
    required String noteId,
    required String title,
  }) async => _replace(noteId, title: title);

  @override
  Future<NoteDto> replaceContent({
    required String noteId,
    required String content,
  }) async => _replace(noteId, content: content);

  @override
  Future<void> deleteNote(String noteId) async {
    notes.removeWhere((NoteDto note) => note.id == noteId);
  }

  NoteDto _replace(String noteId, {String? title, String? content}) {
    final NoteDto current = notes.firstWhere(
      (NoteDto note) => note.id == noteId,
    );
    final NoteDto updated = NoteDto(
      id: current.id,
      ownerId: current.ownerId,
      title: title ?? current.title,
      content: content ?? current.content,
      createdAt: current.createdAt,
      updatedAt: current.updatedAt.add(const Duration(minutes: 1)),
    );
    notes[notes.indexOf(current)] = updated;
    return updated;
  }
}

/// One page under test with its own session, consent store, and note seam.
final class _Harness {
  _Harness({this.cloudConsent = false, this.available = true});

  final bool cloudConsent;
  final bool available;
  final ValueNotifier<Locale?> locale = ValueNotifier<Locale?>(
    const Locale('en'),
  );

  late final CurrentUserSession session = CurrentUserSession()
    ..setIdentity(
      AuthIdentity(
        userId: 'account-a',
        email: 'a@example.test',
        isEmailVerified: true,
      ),
    );
  late final SummaryCloudConsent store = SummaryCloudConsent(session: session);
  late final SummaryConsentAppService? consent = cloudConsent
      ? SummaryConsentAppService(
          currentUser: session,
          session: session,
          consent: store,
          isAvailable: () => available,
          cancelActiveRuns: () {},
        )
      : null;
  late final _FakeNotesController notes = _FakeNotesController(
    summaryConsent: consent,
  );

  void dispose() {
    locale.dispose();
  }

  Future<void> pump(WidgetTester tester, {NoteDto? note}) async {
    if (note != null &&
        !notes.notes.any((NoteDto saved) => saved.id == note.id)) {
      notes.notes.add(note);
    }
    await tester.pumpWidget(
      ValueListenableBuilder<Locale?>(
        valueListenable: locale,
        builder: (BuildContext context, Locale? value, Widget? child) {
          return MaterialApp(
            locale: value,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              NoteDetailCopy.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
            home: NoteDetailPage(notesController: notes, note: note),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _tapSummarize(WidgetTester tester) async {
  await tester.tap(find.byKey(_summarizeKey));
  await tester.pumpAndSettle();
}
