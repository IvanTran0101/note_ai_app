import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/note_intelligence/summary_consent_app_service.dart';
import 'package:note_ai_app/application/note_intelligence/summary_run_context.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_role.dart';
import 'package:note_ai_app/domain/notes/note_share_grant.dart';
import 'package:note_ai_app/presentation/notes/note_detail_localizations.dart';
import 'package:note_ai_app/presentation/notes/note_detail_page.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';
import 'package:note_ai_app/presentation/notes/notes_workspace_page.dart';

final DateTime _createdAt = DateTime.utc(2026, 1, 1);

NoteDto _note({
  String id = 'note-1',
  String ownerId = 'user-1',
  String title = 'Title',
  String content = 'a😀bcdef',
  int contentRevision = 3,
  bool isProtected = false,
  bool contentAvailable = true,
  NoteShareGrant? share,
}) {
  return NoteDto(
    id: id,
    ownerId: ownerId,
    title: title,
    content: content,
    createdAt: _createdAt,
    updatedAt: _createdAt,
    contentRevision: contentRevision,
    isProtected: isProtected,
    contentAvailable: contentAvailable,
    share: share,
  );
}

NoteShareGrant _share(String noteId) => NoteShareGrant(
  note: NoteIdentity('user-2', noteId),
  recipientId: 'user-1',
  role: NoteRole.viewer,
  sharedAt: _createdAt,
  updatedAt: _createdAt,
  accessRevision: 1,
);

Future<void> _pumpDetail(
  WidgetTester tester, {
  required NoteDto note,
  NoteDetailSelectionRequest? selection,
  ValueChanged<NoteDto>? onNoteEdited,
  ValueChanged<NoteDto>? onOpenNoteRag,
  _FakeNotesController? controller,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        NoteDetailCopy.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
      home: NoteDetailPage(
        notesController: controller ?? _FakeNotesController(notes: <NoteDto>[note]),
        note: note,
        initialContentSelection: selection,
        onNoteEdited: onNoteEdited,
        onOpenNoteRag: onOpenNoteRag,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('reveals a citation span without a draft edit or report', (
    tester,
  ) async {
    final NoteDto note = _note();
    final List<NoteDto> reports = <NoteDto>[];
    await _pumpDetail(
      tester,
      note: note,
      selection: NoteDetailSelectionRequest(
        const TextSelection(baseOffset: 3, extentOffset: 5),
      ),
      onNoteEdited: reports.add,
    );

    final TextEditingController content = tester
        .widget<TextField>(find.byKey(NoteDetailPage.contentFieldKey))
        .controller!;
    expect(
      content.selection,
      const TextSelection(baseOffset: 3, extentOffset: 5),
    );
    expect(content.text.substring(3, 5), 'bc');
    expect(find.byKey(NoteDetailPage.dirtyKey), findsNothing);
    expect(reports, isEmpty);
  });

  testWidgets('a selection move is not an edit; a text change is', (
    tester,
  ) async {
    final NoteDto note = _note(content: 'abcdef');
    final List<NoteDto> reports = <NoteDto>[];
    await _pumpDetail(tester, note: note, onNoteEdited: reports.add);

    final TextEditingController content = tester
        .widget<TextField>(find.byKey(NoteDetailPage.contentFieldKey))
        .controller!;
    content.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();
    expect(reports, isEmpty);
    expect(find.byKey(NoteDetailPage.dirtyKey), findsNothing);

    content.text = 'abcdefg';
    await tester.pump();
    expect(reports, hasLength(1));
    expect(reports.single.id, note.id);
    expect(find.byKey(NoteDetailPage.dirtyKey), findsOneWidget);

    // Reverting clears the timer and the dirty state before the test ends.
    content.text = 'abcdef';
    await tester.pump();
    expect(find.byKey(NoteDetailPage.dirtyKey), findsNothing);
  });

  testWidgets('ask-notes action is offered for a clean eligible note', (
    tester,
  ) async {
    final NoteDto note = _note();
    NoteDto? requested;
    await _pumpDetail(tester, note: note, onOpenNoteRag: (NoteDto n) => requested = n);
    expect(find.byKey(NoteDetailPage.askNotesKey), findsOneWidget);
    await tester.tap(find.byKey(NoteDetailPage.askNotesKey));
    await tester.pump();
    expect(requested?.id, note.id);
  });

  testWidgets('ask-notes action is hidden when the note is ineligible', (
    tester,
  ) async {
    for (final NoteDto note in <NoteDto>[
      _note(contentRevision: 0),
      _note(isProtected: true, contentAvailable: false),
      _note(share: _share('note-1')),
    ]) {
      await _pumpDetail(tester, note: note, onOpenNoteRag: (_) {});
      expect(
        find.byKey(NoteDetailPage.askNotesKey),
        findsNothing,
        reason: 'ineligible note should not offer ask-notes',
      );
    }
  });

  testWidgets('ask-notes action disappears once the editor is dirty', (
    tester,
  ) async {
    final NoteDto note = _note(content: 'abcdef');
    await _pumpDetail(tester, note: note, onOpenNoteRag: (_) {});
    expect(find.byKey(NoteDetailPage.askNotesKey), findsOneWidget);
    final TextEditingController content = tester
        .widget<TextField>(find.byKey(NoteDetailPage.contentFieldKey))
        .controller!;
    content.text = 'changed';
    await tester.pump();
    expect(find.byKey(NoteDetailPage.askNotesKey), findsNothing);
    content.text = 'abcdef';
    await tester.pump();
  });

  testWidgets('openSource reveals again on the same already-open note', (
    tester,
  ) async {
    final NoteDto note = _note(content: 'abcdefgh');
    final GlobalKey<NotesWorkspacePageState> pageKey =
        GlobalKey<NotesWorkspacePageState>();
    await tester.pumpWidget(
      MaterialApp(
        home: NotesWorkspacePage(
          key: pageKey,
          controller: _FakeNotesController(notes: <NoteDto>[note]),
          embeddedInWorkspace: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      pageKey.currentState!.openSource(
        note,
        const TextSelection(baseOffset: 1, extentOffset: 3),
      ),
      isTrue,
    );
    await tester.pumpAndSettle();
    TextEditingController content = tester
        .widget<TextField>(find.byKey(NoteDetailPage.contentFieldKey))
        .controller!;
    expect(content.selection, const TextSelection(baseOffset: 1, extentOffset: 3));

    // The same note stays open (same key); a new request must still reveal it.
    expect(
      pageKey.currentState!.openSource(
        note,
        const TextSelection(baseOffset: 4, extentOffset: 6),
      ),
      isTrue,
    );
    await tester.pumpAndSettle();
    content = tester
        .widget<TextField>(find.byKey(NoteDetailPage.contentFieldKey))
        .controller!;
    expect(content.selection, const TextSelection(baseOffset: 4, extentOffset: 6));
    expect(find.byKey(NoteDetailPage.dirtyKey), findsNothing);
  });

  testWidgets('a moved revision before the reveal frame is not highlighted', (
    tester,
  ) async {
    final NoteDto note = _note(content: 'abcdefgh', contentRevision: 3);
    final GlobalKey<NotesWorkspacePageState> pageKey =
        GlobalKey<NotesWorkspacePageState>();
    await tester.pumpWidget(
      MaterialApp(
        home: NotesWorkspacePage(
          key: pageKey,
          controller: _FakeNotesController(notes: <NoteDto>[note]),
          embeddedInWorkspace: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      pageKey.currentState!.openSource(
        note,
        const TextSelection(baseOffset: 1, extentOffset: 3),
      ),
      isTrue,
    );
    await tester.pumpAndSettle();
    final TextEditingController content = tester
        .widget<TextField>(find.byKey(NoteDetailPage.contentFieldKey))
        .controller!;
    content.selection = const TextSelection.collapsed(offset: 7);
    await tester.pump();

    // The same note identity advances its revision in the same build that
    // carries the new request; the reveal must refuse the stale captured span.
    final NoteDto moved = _note(content: 'abcdefgh', contentRevision: 4);
    expect(
      pageKey.currentState!.openSource(
        moved,
        const TextSelection(baseOffset: 2, extentOffset: 5),
      ),
      isTrue,
    );
    await tester.pumpAndSettle();

    expect(content.selection, isNot(const TextSelection(baseOffset: 2, extentOffset: 5)));
    expect(find.byKey(NoteDetailPage.dirtyKey), findsNothing);
  });

  testWidgets('changed content before the reveal frame is not highlighted', (
    tester,
  ) async {
    final NoteDto note = _note(content: 'abcdefgh', contentRevision: 3);
    final GlobalKey<NotesWorkspacePageState> pageKey =
        GlobalKey<NotesWorkspacePageState>();
    await tester.pumpWidget(
      MaterialApp(
        home: NotesWorkspacePage(
          key: pageKey,
          controller: _FakeNotesController(notes: <NoteDto>[note]),
          embeddedInWorkspace: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      pageKey.currentState!.openSource(
        note,
        const TextSelection(baseOffset: 1, extentOffset: 3),
      ),
      isTrue,
    );
    await tester.pumpAndSettle();

    // The same offsets now name different text; the equal-content guard must
    // refuse rather than highlight an arbitrary new span.
    final NoteDto moved = _note(content: 'abcdefghij', contentRevision: 3);
    expect(
      pageKey.currentState!.openSource(
        moved,
        const TextSelection(baseOffset: 2, extentOffset: 5),
      ),
      isTrue,
    );
    await tester.pumpAndSettle();
    final TextEditingController content = tester
        .widget<TextField>(find.byKey(NoteDetailPage.contentFieldKey))
        .controller!;
    expect(content.selection, isNot(const TextSelection(baseOffset: 2, extentOffset: 5)));
    expect(find.byKey(NoteDetailPage.dirtyKey), findsNothing);
  });

  testWidgets('changed title before the reveal frame is not highlighted', (
    tester,
  ) async {
    final NoteDto note = _note(content: 'abcdefgh', contentRevision: 3);
    final GlobalKey<NotesWorkspacePageState> pageKey =
        GlobalKey<NotesWorkspacePageState>();
    await tester.pumpWidget(
      MaterialApp(
        home: NotesWorkspacePage(
          key: pageKey,
          controller: _FakeNotesController(notes: <NoteDto>[note]),
          embeddedInWorkspace: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      pageKey.currentState!.openSource(
        note,
        const TextSelection(baseOffset: 1, extentOffset: 3),
      ),
      isTrue,
    );
    await tester.pumpAndSettle();
    final TextEditingController content = tester
        .widget<TextField>(find.byKey(NoteDetailPage.contentFieldKey))
        .controller!;
    expect(content.selection, const TextSelection(baseOffset: 1, extentOffset: 3));

    // Content, revision, and protection are identical; only the title moved, so
    // every other currentness guard still passes. The reveal captured the
    // pre-frame title and must refuse rather than highlight offsets that no
    // longer belong to the note snapshot it resolved the citation against.
    final NoteDto moved = _note(
      title: 'New title',
      content: 'abcdefgh',
      contentRevision: 3,
    );
    expect(
      pageKey.currentState!.openSource(
        moved,
        const TextSelection(baseOffset: 2, extentOffset: 5),
      ),
      isTrue,
    );
    await tester.pumpAndSettle();

    expect(
      content.selection,
      isNot(const TextSelection(baseOffset: 2, extentOffset: 5)),
    );
    expect(find.byKey(NoteDetailPage.dirtyKey), findsNothing);
  });

  testWidgets('a changed owner before the reveal frame is refused', (
    tester,
  ) async {
    final NoteDto note = _note();
    final _FakeNotesController controller = _FakeNotesController(
      notes: <NoteDto>[note],
    );
    final GlobalKey<_DetailHostState> hostKey = GlobalKey<_DetailHostState>();
    await tester.pumpWidget(_DetailHost(key: hostKey, controller: controller, note: note));
    await tester.pumpAndSettle();

    hostKey.currentState!.apply(
      note: _note(ownerId: 'user-2'),
      selection: NoteDetailSelectionRequest(
        const TextSelection(baseOffset: 3, extentOffset: 5),
      ),
    );
    await tester.pumpAndSettle();

    final TextEditingController content = tester
        .widget<TextField>(find.byKey(NoteDetailPage.contentFieldKey))
        .controller!;
    expect(content.selection, isNot(const TextSelection(baseOffset: 3, extentOffset: 5)));
    expect(find.byKey(NoteDetailPage.dirtyKey), findsNothing);
  });

  testWidgets('a draft made before the reveal frame preserves the draft', (
    tester,
  ) async {
    final NoteDto note = _note(content: 'abcdef');
    final _FakeNotesController controller = _FakeNotesController(
      notes: <NoteDto>[note],
    );
    final GlobalKey<_DetailHostState> hostKey = GlobalKey<_DetailHostState>();
    await tester.pumpWidget(_DetailHost(key: hostKey, controller: controller, note: note));
    await tester.pumpAndSettle();

    final TextEditingController content = tester
        .widget<TextField>(find.byKey(NoteDetailPage.contentFieldKey))
        .controller!;
    content.text = 'abcdef-draft';
    await tester.pump();
    expect(find.byKey(NoteDetailPage.dirtyKey), findsOneWidget);

    hostKey.currentState!.apply(
      note: note,
      selection: NoteDetailSelectionRequest(
        const TextSelection(baseOffset: 1, extentOffset: 3),
      ),
    );
    await tester.pumpAndSettle();

    expect(content.text, 'abcdef-draft');
    expect(content.selection, isNot(const TextSelection(baseOffset: 1, extentOffset: 3)));
    expect(find.byKey(NoteDetailPage.dirtyKey), findsOneWidget);

    // Revert so the pending autosave timer is cancelled before teardown.
    content.text = 'abcdef';
    await tester.pump();
    expect(find.byKey(NoteDetailPage.dirtyKey), findsNothing);
  });
}

/// Stateful host that can swap the note and add a fresh citation request in a
/// single build, which is how a real note transition and reveal race.
final class _DetailHost extends StatefulWidget {
  const _DetailHost({
    super.key,
    required this.controller,
    required this.note,
  });

  final _FakeNotesController controller;
  final NoteDto note;

  @override
  State<_DetailHost> createState() => _DetailHostState();
}

final class _DetailHostState extends State<_DetailHost> {
  late NoteDto _note = widget.note;
  NoteDetailSelectionRequest? _selection;

  void apply({
    required NoteDto note,
    required NoteDetailSelectionRequest selection,
  }) {
    setState(() {
      _note = note;
      _selection = selection;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        NoteDetailCopy.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
      home: NoteDetailPage(
        notesController: widget.controller,
        note: _note,
        initialContentSelection: _selection,
      ),
    );
  }
}

final class _FakeNotesController implements NotesApplicationController {
  _FakeNotesController({List<NoteDto>? notes})
    : notes = List<NoteDto>.of(notes ?? <NoteDto>[]);

  final List<NoteDto> notes;

  @override
  Future<List<NoteDto>> listNotes() async => List<NoteDto>.of(notes);

  @override
  Future<NoteDto> createNote({
    required String title,
    required String content,
  }) async {
    final NoteDto note = NoteDto(
      id: 'note-${notes.length + 1}',
      ownerId: 'user-1',
      title: title,
      content: content,
      createdAt: _createdAt,
      updatedAt: _createdAt,
    );
    notes.add(note);
    return note;
  }

  @override
  Future<NoteDto> renameNote({
    required String noteId,
    required String title,
  }) async {
    return _replace(_find(noteId), title: title);
  }

  @override
  Future<NoteDto> replaceContent({
    required String noteId,
    required String content,
  }) async {
    return _replace(_find(noteId), content: content);
  }

  @override
  Future<void> deleteNote(String noteId) async {
    notes.removeWhere((NoteDto note) => note.id == noteId);
  }

  @override
  SummaryConsentAppService? get summaryConsent => null;

  @override
  Future<String> summarizeNote(
    String noteId, {
    NoteDto? selectedSnapshot,
    SummaryRunScope? scope,
  }) async => 'summary';

  NoteDto _find(String id) => notes.firstWhere((NoteDto note) => note.id == id);

  NoteDto _replace(NoteDto current, {String? title, String? content}) {
    final NoteDto updated = NoteDto(
      id: current.id,
      ownerId: current.ownerId,
      title: title ?? current.title,
      content: content ?? current.content,
      createdAt: current.createdAt,
      updatedAt: current.updatedAt.add(const Duration(minutes: 1)),
      contentRevision: current.contentRevision,
      isProtected: current.isProtected,
      contentAvailable: current.contentAvailable,
      share: current.share,
    );
    notes[notes.indexOf(current)] = updated;
    return updated;
  }
}
