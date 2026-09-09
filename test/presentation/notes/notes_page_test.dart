import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_failure.dart';
import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_state.dart';
import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_status_holder.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/presentation/notes/notes_page.dart';

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
    _FakeNotesApplicationController controller, {
    VoidCallback? onOpenDiagnostics,
    ModelProvisioningStatusHolder? provisioningStatus,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NotesPage(
          controller: controller,
          onOpenDiagnostics: onOpenDiagnostics,
          provisioningReader: provisioningStatus,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('loads an empty state and exposes a new-note editor', (
    WidgetTester tester,
  ) async {
    final _FakeNotesApplicationController controller =
        _FakeNotesApplicationController();

    await pumpPage(tester, controller);

    expect(find.byKey(const ValueKey<String>('notes-empty')), findsOneWidget);
    expect(find.text('New note'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('title-field')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('content-field')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey<String>('save-note')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('shows progress while the initial list is loading', (
    WidgetTester tester,
  ) async {
    final Completer<List<NoteDto>> gate = Completer<List<NoteDto>>();
    final _FakeNotesApplicationController controller =
        _FakeNotesApplicationController(listNotesResult: gate.future);

    await tester.pumpWidget(
      MaterialApp(home: NotesPage(controller: controller)),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey<String>('notes-loading')), findsOneWidget);

    gate.complete(<NoteDto>[]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('notes-empty')), findsOneWidget);
  });

  testWidgets('selects, edits, and saves a note through the application seam', (
    WidgetTester tester,
  ) async {
    final _FakeNotesApplicationController controller =
        _FakeNotesApplicationController(notes: <NoteDto>[buildNote()]);

    await pumpPage(tester, controller);

    expect(find.byKey(const ValueKey<String>('note-note-1')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey<String>('title-field')))
          .controller!
          .text,
      'First note',
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('title-field')),
      'Renamed note',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('content-field')),
      'Updated note body.',
    );
    await tester.tap(find.byKey(const ValueKey<String>('save-note')));
    await tester.pumpAndSettle();

    expect(controller.notes.single.title, 'Renamed note');
    expect(controller.notes.single.content, 'Updated note body.');
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey<String>('title-field')))
          .controller!
          .text,
      'Renamed note',
    );
  });

  testWidgets('creates a note, summarizes it, and keeps summary ephemeral', (
    WidgetTester tester,
  ) async {
    final _FakeNotesApplicationController controller =
        _FakeNotesApplicationController();

    await pumpPage(tester, controller);
    await tester.enterText(
      find.byKey(const ValueKey<String>('title-field')),
      'New note',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('content-field')),
      'Content to summarize',
    );
    await tester.tap(find.byKey(const ValueKey<String>('save-note')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('summarize-note')));
    await tester.pumpAndSettle();

    expect(controller.summarizedNoteId, 'note-1');
    expect(find.byKey(const ValueKey<String>('summary-card')), findsOneWidget);
    expect(find.text('Summary of Content to summarize'), findsOneWidget);
    expect(controller.notes.single.content, 'Content to summarize');
  });

  testWidgets('deletes the selected note', (WidgetTester tester) async {
    final _FakeNotesApplicationController controller =
        _FakeNotesApplicationController(notes: <NoteDto>[buildNote()]);

    await pumpPage(tester, controller);
    await tester.tap(find.byKey(const ValueKey<String>('delete-note')));
    await tester.pumpAndSettle();

    expect(controller.notes, isEmpty);
    expect(find.byKey(const ValueKey<String>('notes-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('summary-card')), findsNothing);
  });

  testWidgets('surfaces application failures and offers retry', (
    WidgetTester tester,
  ) async {
    final _FakeNotesApplicationController controller =
        _FakeNotesApplicationController(
          listNotesError: StateError('storage unavailable'),
        );

    await pumpPage(tester, controller);

    expect(find.byKey(const ValueKey<String>('notes-error')), findsOneWidget);
    expect(find.textContaining('storage unavailable'), findsWidgets);
    expect(find.byKey(const ValueKey<String>('retry-notes')), findsOneWidget);
  });

  testWidgets('shows Diagnostics only when a callback is supplied', (
    WidgetTester tester,
  ) async {
    final _FakeNotesApplicationController controller =
        _FakeNotesApplicationController();
    bool opened = false;

    await pumpPage(tester, controller, onOpenDiagnostics: () => opened = true);

    expect(find.text('Diagnostics'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('open-diagnostics')));
    expect(opened, isTrue);
  });

  testWidgets(
    'shows provisioning state and retries through the application seam',
    (WidgetTester tester) async {
      final _FakeNotesApplicationController controller =
          _FakeNotesApplicationController(notes: <NoteDto>[buildNote()]);
      final ModelProvisioningStatusHolder provisioningStatus =
          ModelProvisioningStatusHolder(
            initial: ModelProvisioningState(
              phase: ModelProvisioningPhase.failed,
              modelId: 'gemma-3-1b-it',
              failure: const ModelProvisioningFailure(
                code: ModelProvisioningFailureCode.downloadFailed,
              ),
              updatedAt: createdAt,
            ),
          );
      addTearDown(provisioningStatus.close);

      await pumpPage(
        tester,
        controller,
        provisioningStatus: provisioningStatus,
      );

      expect(
        find.byKey(const ValueKey<String>('model-provisioning-status')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('model-provisioning-retry')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('model-provisioning-retry')),
      );
      await tester.pumpAndSettle();

      expect(controller.summarizedNoteId, 'note-1');
      expect(
        find.byKey(const ValueKey<String>('summary-card')),
        findsOneWidget,
      );
    },
  );
}

final class _FakeNotesApplicationController
    implements NotesApplicationController {
  _FakeNotesApplicationController({
    List<NoteDto>? notes,
    this.listNotesResult,
    this.listNotesError,
  }) : notes = List<NoteDto>.of(notes ?? <NoteDto>[]);

  final Future<List<NoteDto>>? listNotesResult;
  final Object? listNotesError;
  final List<NoteDto> notes;
  String? summarizedNoteId;
  int _nextId = 1;

  @override
  Future<List<NoteDto>> listNotes() async {
    final Object? error = listNotesError;
    if (error != null) {
      throw error;
    }
    final Future<List<NoteDto>>? result = listNotesResult;
    if (result != null) {
      return result;
    }
    return List<NoteDto>.of(notes);
  }

  @override
  Future<NoteDto> createNote({
    required String title,
    required String content,
  }) async {
    final DateTime now = DateTime.utc(2026, 1, 2);
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
    final NoteDto current = _find(noteId);
    return _replace(
      current,
      title: title,
      updatedAt: current.updatedAt.add(const Duration(minutes: 1)),
    );
  }

  @override
  Future<NoteDto> replaceContent({
    required String noteId,
    required String content,
  }) async {
    final NoteDto current = _find(noteId);
    return _replace(
      current,
      content: content,
      updatedAt: current.updatedAt.add(const Duration(minutes: 1)),
    );
  }

  @override
  Future<void> deleteNote(String noteId) async {
    notes.removeWhere((NoteDto note) => note.id == noteId);
  }

  @override
  Future<String> summarizeNote(String noteId) async {
    final NoteDto current = _find(noteId);
    summarizedNoteId = noteId;
    return 'Summary of ${current.content}';
  }

  NoteDto _find(String noteId) {
    return notes.firstWhere((NoteDto note) => note.id == noteId);
  }

  NoteDto _replace(
    NoteDto current, {
    String? title,
    String? content,
    required DateTime updatedAt,
  }) {
    final NoteDto updated = NoteDto(
      id: current.id,
      ownerId: current.ownerId,
      title: title ?? current.title,
      content: content ?? current.content,
      createdAt: current.createdAt,
      updatedAt: updatedAt,
    );
    final int index = notes.indexOf(current);
    notes[index] = updated;
    return updated;
  }
}
