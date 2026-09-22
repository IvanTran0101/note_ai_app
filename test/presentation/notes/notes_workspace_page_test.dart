import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/presentation/notes/note_detail_page.dart';
import 'package:note_ai_app/presentation/notes/notes_workspace_page.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';

final DateTime _baseTime = DateTime.utc(2026, 1, 1);

void main() {
  NoteDto buildNote({
    String id = 'note-1',
    String title = 'First note',
    String content = 'First note content',
  }) {
    return NoteDto(
      id: id,
      ownerId: 'local-user',
      title: title,
      content: content,
      createdAt: _baseTime,
      updatedAt: _baseTime,
    );
  }

  Future<void> pumpWorkspace(
    WidgetTester tester,
    _FakeNotesController controller, {
    required Size size,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: NotesWorkspacePage(controller: controller)),
    );
    await tester.pumpAndSettle();
  }

  for (final int width in <int>[360, 375, 390]) {
    testWidgets('compact list renders without overflow at ${width}dp', (
      WidgetTester tester,
    ) async {
      final _FakeNotesController controller = _FakeNotesController(
        notes: <NoteDto>[
          buildNote(),
          buildNote(
            id: 'note-2',
            title:
                'Second note with a much longer title that must ellipsize '
                'safely on narrow screens',
          ),
        ],
      );
      await pumpWorkspace(
        tester,
        controller,
        size: Size(width.toDouble(), 800),
      );

      expect(find.byKey(const ValueKey<String>('note-note-1')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('note-note-2')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('compact create flow returns to the note list after save', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController();
    await pumpWorkspace(tester, controller, size: const Size(390, 844));

    await tester.tap(find.byKey(const ValueKey<String>('new-note-empty')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('note-detail-title-field')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('note-detail-title-field')),
      'Mobile note',
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('note-detail-content-field')),
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('note-detail-content-field')),
      'Created from the compact workspace',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('note-detail-save')),
      findsNothing,
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(controller.notes.single.title, 'Mobile note');
    final VoidCallback? back = tester
        .widget<IconButton>(find.byKey(NoteDetailPage.backKey))
        .onPressed;
    expect(back, isNotNull);
    back!();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('note-note-1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('note-detail-title-field')),
      findsNothing,
    );
  });

  testWidgets('compact detail keeps exactly one titled AppBar', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController(
      notes: <NoteDto>[buildNote()],
    );
    await pumpWorkspace(tester, controller, size: const Size(390, 844));

    expect(find.byType(AppBar), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('note-note-1')));
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byKey(NoteDetailPage.backKey), findsOneWidget);
    expect(find.text('First note'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'expanded workspace opens the same detail surface beside the list',
    (WidgetTester tester) async {
      final _FakeNotesController controller = _FakeNotesController(
        notes: <NoteDto>[buildNote()],
      );
      await pumpWorkspace(tester, controller, size: const Size(1024, 700));

      expect(
        find.byKey(const ValueKey<String>('responsive-notes-expanded-surface')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('notes-workspace-detail-empty')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey<String>('note-note-1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('note-detail-content-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('responsive-notes-list-pane')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('does not replace a selected note while its detail is dirty', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController(
      notes: <NoteDto>[
        buildNote(),
        buildNote(id: 'note-2', title: 'Second'),
      ],
    );
    await pumpWorkspace(tester, controller, size: const Size(1024, 700));
    await tester.tap(find.byKey(const ValueKey<String>('note-note-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('note-detail-title-field')),
      'Unsaved title',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('note-note-2')));
    await tester.pump();

    expect(
      find.text('Unsaved changes. Save before summarizing or switching notes.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('note-detail-title-field')),
          )
          .controller!
          .text,
      'Unsaved title',
    );
  });

  testWidgets('reload reads fresh notes for the list', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController(
      notes: <NoteDto>[buildNote()],
    );
    await pumpWorkspace(tester, controller, size: const Size(390, 844));

    expect(find.byKey(const ValueKey<String>('note-note-1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('note-note-2')), findsNothing);
    final int callsBefore = controller.listNotesCalls;

    // The data behind the already-mounted page changes.
    controller.notes.add(buildNote(id: 'note-2', title: 'Second'));

    final NotesWorkspacePageState page = tester.state<NotesWorkspacePageState>(
      find.byType(NotesWorkspacePage),
    );
    await page.reload();
    await tester.pumpAndSettle();

    expect(controller.listNotesCalls, greaterThan(callsBefore));
    expect(find.byKey(const ValueKey<String>('note-note-1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('note-note-2')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shares an in-flight reload instead of repeating the request', (
    WidgetTester tester,
  ) async {
    final _FakeNotesController controller = _FakeNotesController(
      notes: <NoteDto>[buildNote()],
    );
    await pumpWorkspace(tester, controller, size: const Size(390, 844));

    final int callsBefore = controller.listNotesCalls;

    // Hold the next request open so both reloads overlap.
    final Completer<void> gate = Completer<void>();
    controller.listNotesGate = gate;
    controller.notes.add(buildNote(id: 'note-2', title: 'Second'));

    final NotesWorkspacePageState page = tester.state<NotesWorkspacePageState>(
      find.byType(NotesWorkspacePage),
    );
    final Future<void> firstReload = page.reload();
    final Future<void> secondReload = page.reload();
    await tester.pump();

    // The second reload joined the first request instead of issuing its own.
    expect(controller.listNotesCalls, callsBefore + 1);

    gate.complete();
    await tester.pumpAndSettle();
    await firstReload;
    await secondReload;

    // One shared request still delivers the fresh data to both callers.
    expect(controller.listNotesCalls, callsBefore + 1);
    expect(find.byKey(const ValueKey<String>('note-note-2')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final class _FakeNotesController implements NotesApplicationController {
  _FakeNotesController({List<NoteDto>? notes})
    : notes = List<NoteDto>.of(notes ?? <NoteDto>[]);

  final List<NoteDto> notes;
  int _nextId = 1;

  /// When set, [listNotes] stays pending until the completer completes so a
  /// test can observe the page while a reload request is in flight.
  Completer<void>? listNotesGate;

  /// Number of [listNotes] calls, used to prove reloads are coalesced.
  int listNotesCalls = 0;

  @override
  Future<List<NoteDto>> listNotes() async {
    listNotesCalls++;
    final Completer<void>? gate = listNotesGate;
    if (gate != null) {
      await gate.future;
    }
    return List<NoteDto>.of(notes);
  }

  @override
  Future<NoteDto> createNote({
    required String title,
    required String content,
  }) async {
    final DateTime now = _baseTime.add(const Duration(days: 1));
    final NoteDto note = NoteDto(
      id: 'note-${_nextId++}',
      ownerId: 'local-user',
      title: title,
      content: content,
      createdAt: now,
      updatedAt: now,
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
  Future<String> summarizeNote(String noteId) async =>
      'Summary of ${_find(noteId).content}';

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
    notes[notes.indexOf(current)] = updated;
    return updated;
  }
}
