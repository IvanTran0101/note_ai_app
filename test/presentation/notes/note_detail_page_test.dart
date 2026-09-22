import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/presentation/notes/note_detail_localizations.dart';
import 'package:note_ai_app/presentation/notes/note_detail_page.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';

void main() {
  final DateTime createdAt = DateTime.utc(2026, 1, 1);

  NoteDto buildNote({
    String id = 'note-1',
    String title = 'First note',
    String content = 'The first note body.',
  }) {
    return NoteDto(
      id: id,
      ownerId: 'local-user',
      title: title,
      content: content,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  Future<void> pumpPage(
    WidgetTester tester,
    _FakeNotesController controller, {
    NoteDto? note,
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          NoteDetailCopy.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
        home: NoteDetailPage(notesController: controller, note: note),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('creates a new note through the application seam', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController();
    await pumpPage(tester, controller);

    await tester.enterText(
      find.byKey(NoteDetailPage.titleFieldKey),
      'A new note',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(NoteDetailPage.contentFieldKey));
    await tester.enterText(
      find.byKey(NoteDetailPage.contentFieldKey),
      'A new note body',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('note-detail-save')),
      findsNothing,
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(controller.notes.single.title, 'A new note');
    expect(controller.notes.single.content, 'A new note body');
    expect(find.text('Note saved.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('note-detail-summarize')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('updates only changed fields on an existing note', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController(
      notes: <NoteDto>[buildNote()],
    );
    await pumpPage(tester, controller, note: controller.notes.single);

    await tester.enterText(
      find.byKey(NoteDetailPage.titleFieldKey),
      'Renamed note',
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(NoteDetailPage.titleFieldKey))
          .controller!
          .text,
      'Renamed note',
    );
    expect(find.byKey(NoteDetailPage.dirtyKey), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('note-detail-save')),
      findsNothing,
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(controller.renameCalls, 1);
    expect(controller.replaceContentCalls, 0);
    expect(controller.notes.single.title, 'Renamed note');
    expect(controller.notes.single.content, 'The first note body.');
  });

  testWidgets(
    'requires a clean saved note before summarizing and marks stale',
    (WidgetTester tester) async {
      final _FakeNotesController controller = _FakeNotesController(
        notes: <NoteDto>[buildNote()],
      );
      await pumpPage(tester, controller, note: controller.notes.single);

      await tester.enterText(
        find.byKey(NoteDetailPage.contentFieldKey),
        'Changed body',
      );
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(NoteDetailPage.contentFieldKey))
            .controller!
            .text,
        'Changed body',
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey<String>('note-detail-summarize')),
            )
            .onPressed,
        isNull,
      );

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('note-detail-summarize')),
      );
      await tester.pumpAndSettle();

      expect(controller.summarizedNoteId, 'note-1');
      expect(find.byKey(NoteDetailPage.summaryKey), findsOneWidget);

      await tester.enterText(
        find.byKey(NoteDetailPage.contentFieldKey),
        'Changed again',
      );
      await tester.pump();
      expect(
        find.text('This summary is out of date because the note changed.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('summary exposes copy and regenerate actions', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController(
      notes: <NoteDto>[buildNote()],
    );
    await pumpPage(tester, controller, note: controller.notes.single);

    await tester.tap(
      find.byKey(const ValueKey<String>('note-detail-summarize')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('note-detail-copy-summary')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('note-detail-regenerate-summary')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('note-detail-copy-summary')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('note-detail-copy-summary')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('note-detail-status')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('note-detail-regenerate-summary')),
    );
    await tester.pumpAndSettle();
    expect(controller.summarizeCalls, 2);
  });

  testWidgets('summary failure exposes a retry action', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController(
      notes: <NoteDto>[buildNote()],
    )..summarizeFailuresRemaining = 1;
    await pumpPage(tester, controller, note: controller.notes.single);

    await tester.tap(
      find.byKey(const ValueKey<String>('note-detail-summarize')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Couldn’t create a summary. Please try again.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('note-detail-error-retry')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('note-detail-error-retry')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(NoteDetailPage.summaryKey), findsOneWidget);
    expect(controller.summarizeCalls, 2);
  });

  testWidgets('autosaves when both editor fields lose focus', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController(
      notes: <NoteDto>[buildNote()],
    );
    await pumpPage(tester, controller, note: controller.notes.single);

    await tester.enterText(
      find.byKey(NoteDetailPage.titleFieldKey),
      'Saved after focus loss',
    );
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(controller.renameCalls, 1);
    expect(controller.notes.single.title, 'Saved after focus loss');
  });

  testWidgets('dirty back offers Cancel and Discard', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController(
      notes: <NoteDto>[buildNote()],
    );
    await pumpPage(tester, controller, note: controller.notes.single);
    await tester.enterText(
      find.byKey(NoteDetailPage.titleFieldKey),
      'Unsaved title',
    );
    await tester.pump();
    expect(controller.renameCalls, 0);
    expect(
      tester.widget<IconButton>(find.byKey(NoteDetailPage.backKey)).onPressed,
      isNotNull,
    );

    final VoidCallback? back = tester
        .widget<IconButton>(find.byKey(NoteDetailPage.backKey))
        .onPressed;
    expect(back, isNotNull);
    back!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Save changes before leaving?'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('note-detail-back-cancel')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(NoteDetailPage.titleFieldKey), findsOneWidget);
    expect(controller.renameCalls, 0);

    final VoidCallback? backAgain = tester
        .widget<IconButton>(find.byKey(NoteDetailPage.backKey))
        .onPressed;
    expect(backAgain, isNotNull);
    backAgain!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.renameCalls, 0);
    await tester.tap(
      find.byKey(const ValueKey<String>('note-detail-back-discard')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(NoteDetailPage.titleFieldKey), findsNothing);
    expect(controller.notes.single.title, 'First note');
  });

  testWidgets('dirty back Save persists before leaving', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController();
    await pumpPage(tester, controller);
    await tester.enterText(
      find.byKey(NoteDetailPage.titleFieldKey),
      'Saved from back',
    );
    await tester.pump();
    final VoidCallback? back = tester
        .widget<IconButton>(find.byKey(NoteDetailPage.backKey))
        .onPressed;
    expect(back, isNotNull);
    back!();
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('note-detail-back-save')),
    );
    await tester.pumpAndSettle();

    expect(controller.notes.single.title, 'Saved from back');
    expect(find.byKey(NoteDetailPage.titleFieldKey), findsNothing);
  });

  testWidgets('deletes an existing note after confirmation', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController(
      notes: <NoteDto>[buildNote()],
    );
    await pumpPage(tester, controller, note: controller.notes.single);

    await tester.tap(find.byKey(const ValueKey<String>('note-detail-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(NoteDetailPage.moreDeleteKey));
    await tester.pumpAndSettle();
    expect(find.text('Delete note?'), findsOneWidget);
    await tester.tap(find.byKey(NoteDetailPage.deleteKey));
    await tester.pumpAndSettle();

    expect(controller.notes, isEmpty);
    expect(find.byKey(NoteDetailPage.titleFieldKey), findsNothing);
  });

  testWidgets('more sheet and delete dialog dismiss without side effects', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController(
      notes: <NoteDto>[buildNote()],
    );
    await pumpPage(tester, controller, note: controller.notes.single);

    await tester.tap(find.byKey(const ValueKey<String>('note-detail-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(NoteDetailPage.moreDeleteKey), findsOneWidget);

    // Tapping the barrier dismisses the sheet without running any action.
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.byKey(NoteDetailPage.moreDeleteKey), findsNothing);
    expect(controller.notes, hasLength(1));

    // The delete confirmation can be cancelled from its dialog.
    await tester.tap(find.byKey(const ValueKey<String>('note-detail-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(NoteDetailPage.moreDeleteKey));
    await tester.pumpAndSettle();
    expect(find.text('Delete note?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Delete note?'), findsNothing);
    expect(find.byKey(NoteDetailPage.titleFieldKey), findsOneWidget);
    expect(controller.notes, hasLength(1));
  });

  testWidgets('renders Vietnamese detail copy', (WidgetTester tester) async {
    await pumpPage(tester, _FakeNotesController(), locale: const Locale('vi'));

    expect(find.text('Ghi chú mới'), findsOneWidget);
    expect(find.text('Tiêu đề'), findsOneWidget);
    expect(find.text('Nội dung'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('note-detail-save')),
      findsNothing,
    );
  });
}

final class _FakeNotesController implements NotesApplicationController {
  _FakeNotesController({List<NoteDto>? notes})
    : notes = List<NoteDto>.of(notes ?? <NoteDto>[]);

  final List<NoteDto> notes;
  int renameCalls = 0;
  int replaceContentCalls = 0;
  String? summarizedNoteId;
  int summarizeCalls = 0;
  int summarizeFailuresRemaining = 0;
  int _nextId = 1;

  @override
  Future<List<NoteDto>> listNotes() async => List<NoteDto>.of(notes);

  @override
  Future<NoteDto> createNote({
    required String title,
    required String content,
  }) async {
    final DateTime now = DateTime.utc(2026, 1, 2);
    final NoteDto created = NoteDto(
      id: 'note-${_nextId++}',
      ownerId: 'local-user',
      title: title,
      content: content,
      createdAt: now,
      updatedAt: now,
    );
    notes.add(created);
    return created;
  }

  @override
  Future<NoteDto> renameNote({
    required String noteId,
    required String title,
  }) async {
    renameCalls++;
    return _replace(_find(noteId), title: title);
  }

  @override
  Future<NoteDto> replaceContent({
    required String noteId,
    required String content,
  }) async {
    replaceContentCalls++;
    return _replace(_find(noteId), content: content);
  }

  @override
  Future<void> deleteNote(String noteId) async {
    notes.removeWhere((NoteDto note) => note.id == noteId);
  }

  @override
  Future<String> summarizeNote(String noteId) async {
    final NoteDto note = _find(noteId);
    summarizeCalls++;
    summarizedNoteId = noteId;
    if (summarizeFailuresRemaining > 0) {
      summarizeFailuresRemaining--;
      throw StateError('summary unavailable');
    }
    return 'Summary of ${note.content}';
  }

  NoteDto _find(String id) => notes.firstWhere((NoteDto note) => note.id == id);

  NoteDto _replace(NoteDto current, {String? title, String? content}) {
    final NoteDto updated = NoteDto(
      id: current.id,
      ownerId: current.ownerId,
      title: title ?? current.title,
      content: content ?? current.content,
      createdAt: current.createdAt,
      updatedAt: current.updatedAt.add(const Duration(minutes: 1)),
    );
    final int index = notes.indexOf(current);
    notes[index] = updated;
    return updated;
  }
}
