import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/note_intelligence/summary_consent_app_service.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/local_sync_store.dart';
import 'package:note_ai_app/application/sync/note_sync_status.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_conflict.dart';
import 'package:note_ai_app/application/sync/sync_conflict_resolver.dart';
import 'package:note_ai_app/application/sync/sync_coordinator.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/application/sync/sync_report.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/application/sync/sync_status.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/note_intelligence/summary_run_context.dart';
import 'package:note_ai_app/presentation/notes/note_detail_localizations.dart';
import 'package:note_ai_app/presentation/notes/note_detail_page.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';
import 'package:note_ai_app/presentation/notes/notes_localizations.dart';
import 'package:note_ai_app/presentation/notes/notes_workspace_page.dart';
import 'package:note_ai_app/presentation/sync/sync_localizations.dart';
import 'package:note_ai_app/presentation/sync/sync_conflict_prompt.dart';
import 'package:note_ai_app/presentation/sync/sync_presentation_controller.dart';
import 'package:note_ai_app/presentation/sync/sync_widgets.dart';
import 'package:note_ai_app/presentation/workspace/workspace_localizations.dart';

final DateTime _time = DateTime.utc(2026, 9, 26, 10);

void main() {
  group('SyncPresentationController', () {
    test(
      'projects account note states and listens to coordinator status',
      () async {
        final _MemoryStore store = _MemoryStore(_stateWithStatuses());
        final _FakeCoordinator coordinator = _FakeCoordinator();
        final SyncPresentationController controller = _controller(
          store,
          coordinator,
        );
        addTearDown(controller.dispose);
        addTearDown(coordinator.close);

        await controller.refresh();

        expect(controller.noteStatusFor('synced'), NoteSyncStatus.synced);
        expect(controller.noteStatusFor('pending'), NoteSyncStatus.pending);
        expect(controller.noteStatusFor('failed'), NoteSyncStatus.failed);
        expect(controller.noteStatusFor('conflict'), NoteSyncStatus.conflict);
        expect(controller.pendingCount, 3);
        expect(controller.conflictCount, 1);

        coordinator.publish(const SyncStatusSnapshot.offline());
        await Future<void>.delayed(Duration.zero);
        expect(controller.status.status, SyncStatus.offline);
      },
    );

    test('does not resolve a conflict object that became stale', () async {
      final SyncConflict oldConflict = _conflict(remoteRevision: 2);
      final SyncConflict latestConflict = _conflict(remoteRevision: 3);
      final _MemoryStore store = _MemoryStore(
        _stateWithConflict(latestConflict),
      );
      final _FakeCoordinator coordinator = _FakeCoordinator();
      final SyncPresentationController controller = _controller(
        store,
        coordinator,
      );
      addTearDown(controller.dispose);
      addTearDown(coordinator.close);

      final bool resolved = await controller.resolveConflict(
        displayedConflict: oldConflict,
        choice: SyncConflictChoice.useRemote,
      );

      expect(resolved, isFalse);
      expect(controller.conflictFor('conflict')?.remote?.revision, 3);
      expect(store.state.conflicts.single, latestConflict);
    });

    test('validates the account before showing persisted sync state', () async {
      final _MemoryStore store = _MemoryStore(
        LocalSyncState(accountUserId: 'different-account'),
      );
      final _FakeCoordinator coordinator = _FakeCoordinator();
      final SyncPresentationController controller = _controller(
        store,
        coordinator,
      );
      addTearDown(controller.dispose);
      addTearDown(coordinator.close);

      await controller.refresh();

      expect(controller.localState, isNull);
      expect(controller.loadError, isA<SyncFailure>());
      expect(
        (controller.loadError as SyncFailure).code,
        SyncErrorCode.forbidden,
      );
    });

    testWidgets('status panel and note badge show text labels', (tester) async {
      final _MemoryStore store = _MemoryStore(_stateWithStatuses());
      final _FakeCoordinator coordinator = _FakeCoordinator();
      final SyncPresentationController controller = _controller(
        store,
        coordinator,
      );
      addTearDown(controller.dispose);
      addTearDown(coordinator.close);
      await controller.refresh();
      coordinator.publish(const SyncStatusSnapshot.offline());

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            SyncCopy.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
          home: Scaffold(
            body: Column(
              children: <Widget>[
                SyncStatusPanel(controller: controller),
                SyncNoteStatusBadge(controller: controller, noteId: 'pending'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('sync-now')), findsOneWidget);
    });

    testWidgets('conflict chooser compares versions and returns the choice', (
      tester,
    ) async {
      SyncConflictChoice? selected;
      final SyncConflict conflict = _conflict(remoteRevision: 2);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            SyncCopy.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => FilledButton(
                onPressed: () async {
                  selected = await showSyncConflictChoices(
                    context: context,
                    conflict: conflict,
                  );
                },
                child: const Text('Open conflict'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open conflict'));
      await tester.pumpAndSettle();
      expect(find.text('conflict title'), findsOneWidget);
      expect(find.text('Remote revision 2'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('sync-conflict-use-remote')),
      );
      await tester.pumpAndSettle();
      expect(selected, SyncConflictChoice.useRemote);
    });

    testWidgets('compact conflict chooser uses a bottom sheet', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            SyncCopy.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => FilledButton(
                onPressed: () => showSyncConflictChoices(
                  context: context,
                  conflict: _conflict(remoteRevision: 2),
                ),
                child: const Text('Open conflict'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open conflict'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Use local'), findsOneWidget);
      expect(find.text('Use remote'), findsOneWidget);
    });

    testWidgets('dirty conflict prompt exposes save, discard, and cancel', (
      tester,
    ) async {
      SyncDirtyDraftChoice? selected;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            SyncCopy.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => FilledButton(
                onPressed: () async {
                  selected = await showSyncDirtyDraftChoices(context: context);
                },
                child: const Text('Open draft prompt'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open draft prompt'));
      await tester.pumpAndSettle();
      expect(find.text('Save as new note'), findsOneWidget);
      expect(find.text('Discard draft and continue'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('sync-draft-cancel')));
      await tester.pumpAndSettle();
      expect(selected, SyncDirtyDraftChoice.cancel);
    });

    testWidgets(
      'dirty draft can be saved as new before using remote conflict',
      (tester) async {
        final SyncConflict conflict = _conflict(remoteRevision: 2);
        final _MemoryStore store = _MemoryStore(_stateWithConflict(conflict));
        final _FakeCoordinator coordinator = _FakeCoordinator();
        final SyncPresentationController sync = _controller(store, coordinator);
        final _FakeNotesController notes = _FakeNotesController(<NoteDto>[
          _noteDto('conflict', 'conflict title', 'conflict body'),
        ]);
        addTearDown(sync.dispose);
        addTearDown(coordinator.close);
        await sync.refresh();
        await _pumpWorkspace(tester, notes, sync);
        await _openConflictNote(tester);
        await tester.enterText(
          find.byKey(NoteDetailPage.contentFieldKey),
          'preserved dirty draft',
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey<String>('note-sync-resolve-conflict')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('sync-draft-save-as-new')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(notes.createdNotes.single.content, 'preserved dirty draft');
        expect(
          find.byKey(const ValueKey<String>('sync-conflict-use-remote')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('sync-conflict-use-remote')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(store.state.conflicts, isEmpty);
        expect(store.state.notes.single.title, 'Remote revision 2');
        expect(
          notes.notes.any(
            (NoteDto note) => note.content == 'preserved dirty draft',
          ),
          isTrue,
        );
      },
    );

    testWidgets('discarding a dirty draft allows an explicit local choice', (
      tester,
    ) async {
      final SyncConflict conflict = _conflict(remoteRevision: 2);
      final _MemoryStore store = _MemoryStore(_stateWithConflict(conflict));
      final _FakeCoordinator coordinator = _FakeCoordinator();
      final SyncPresentationController sync = _controller(store, coordinator);
      final _FakeNotesController notes = _FakeNotesController(<NoteDto>[
        _noteDto('conflict', 'conflict title', 'conflict body'),
      ]);
      addTearDown(sync.dispose);
      addTearDown(coordinator.close);
      await sync.refresh();
      await _pumpWorkspace(tester, notes, sync);
      await _openConflictNote(tester);
      await tester.enterText(
        find.byKey(NoteDetailPage.contentFieldKey),
        'discard this draft',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('note-sync-resolve-conflict')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('sync-draft-discard')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('sync-conflict-use-local')),
      );
      await tester.pumpAndSettle();

      expect(notes.createdNotes, isEmpty);
      expect(store.state.conflicts, isEmpty);
      expect(store.state.outbox.single.noteId, 'conflict');
      expect(store.state.outbox.single.baseRevision, 2);
      expect(store.state.notes.single.content, 'conflict body');
    });
  });
}

Future<void> _pumpWorkspace(
  WidgetTester tester,
  _FakeNotesController notes,
  SyncPresentationController sync,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        NotesCopy.delegate,
        NoteDetailCopy.delegate,
        SyncCopy.delegate,
        WorkspaceCopy.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
      home: NotesWorkspacePage(controller: notes, syncController: sync),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openConflictNote(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('note-conflict')));
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey<String>('note-sync-conflict')),
    findsOneWidget,
  );
}

NoteDto _noteDto(String id, String title, String content) => NoteDto(
  id: id,
  ownerId: 'account-1',
  title: title,
  content: content,
  createdAt: _time,
  updatedAt: _time,
);

SyncPresentationController _controller(
  _MemoryStore store,
  _FakeCoordinator coordinator,
) => SyncPresentationController(
  accountUserId: 'account-1',
  localStore: store,
  coordinator: coordinator,
  conflictResolver: SyncConflictResolver(
    localSyncStore: store,
    generateNoteId: () => 'replacement-note',
    generateMutationId: () => 'replacement-mutation',
    now: () => _time,
  ),
);

LocalSyncState _stateWithStatuses() {
  final LocalNoteState synced = _note('synced', NoteSyncStatus.synced);
  final LocalNoteState pending = _note('pending', NoteSyncStatus.pending);
  final LocalNoteState failed = _note('failed', NoteSyncStatus.failed);
  final SyncConflict conflict = _conflict(remoteRevision: 2);
  final LocalNoteState conflicted = _note('conflict', NoteSyncStatus.conflict);
  return LocalSyncState(
    accountUserId: 'account-1',
    notes: <LocalNoteState>[synced, pending, failed, conflicted],
    outbox: <PendingMutation>[
      _mutation('pending-mutation', 'pending'),
      _mutation('failed-mutation', 'failed', blocked: true),
      conflict.pending,
    ],
    conflicts: <SyncConflict>[conflict],
  );
}

LocalSyncState _stateWithConflict(SyncConflict conflict) => LocalSyncState(
  accountUserId: 'account-1',
  notes: <LocalNoteState>[_note('conflict', NoteSyncStatus.conflict)],
  outbox: <PendingMutation>[conflict.pending],
  conflicts: <SyncConflict>[conflict],
);

LocalNoteState _note(String id, NoteSyncStatus status) => LocalNoteState(
  id: id,
  ownerId: 'account-1',
  title: '$id title',
  content: '$id body',
  createdAt: _time,
  updatedAt: _time,
  serverRevision: status == NoteSyncStatus.synced ? 1 : 0,
  status: status,
);

SyncConflict _conflict({required int remoteRevision}) {
  final LocalNoteState local = _note('conflict', NoteSyncStatus.conflict);
  final PendingMutation pending = _mutation(
    'conflict-mutation',
    'conflict',
    blocked: true,
  );
  return SyncConflict(
    noteId: 'conflict',
    remote: SyncNoteSnapshot(
      id: 'conflict',
      title: 'Remote revision $remoteRevision',
      content: 'Remote body $remoteRevision',
      createdAt: _time,
      serverUpdatedAt: _time.add(Duration(seconds: remoteRevision)),
      revision: remoteRevision,
    ),
    local: local,
    pending: pending,
    detectedAt: _time,
  );
}

PendingMutation _mutation(String id, String noteId, {bool blocked = false}) =>
    PendingMutation(
      mutationId: id,
      noteId: noteId,
      operation: SyncMutationOperation.update,
      baseRevision: 0,
      payload: SyncNotePayload(title: '$noteId title', content: '$noteId body'),
      createdAt: _time,
      retryCount: blocked ? 1 : 0,
      blocked: blocked,
      lastError: blocked ? SyncErrorCode.invalidMutation : null,
    );

final class _MemoryStore implements ILocalSyncStore {
  _MemoryStore(this.state);

  LocalSyncState state;

  @override
  Future<LocalSyncState> read() async => state;

  @override
  Future<LocalSyncState> update(
    LocalSyncState Function(LocalSyncState current) transform,
  ) async => state = transform(state);

  @override
  Future<void> replace(LocalSyncState state) async {
    this.state = state;
  }
}

final class _FakeCoordinator implements ISyncCoordinator {
  final StreamController<SyncStatusSnapshot> _changes =
      StreamController<SyncStatusSnapshot>.broadcast();
  SyncStatusSnapshot _status = const SyncStatusSnapshot.idle();

  @override
  SyncStatusSnapshot get status => _status;

  @override
  Stream<SyncStatusSnapshot> get statusChanges => _changes.stream;

  @override
  Future<SyncReport> syncNow() async => SyncReport();

  void publish(SyncStatusSnapshot value) {
    _status = value;
    _changes.add(value);
  }

  Future<void> close() => _changes.close();
}

final class _FakeNotesController implements NotesApplicationController {
  @override
  SummaryConsentAppService? get summaryConsent => null;

  _FakeNotesController(Iterable<NoteDto> initialNotes)
    : notes = List<NoteDto>.of(initialNotes);

  final List<NoteDto> notes;
  final List<NoteDto> createdNotes = <NoteDto>[];
  int _nextId = 0;

  @override
  Future<List<NoteDto>> listNotes() async => List<NoteDto>.unmodifiable(notes);

  @override
  Future<NoteDto> createNote({
    required String title,
    required String content,
  }) async {
    final NoteDto note = _noteDto('created-${++_nextId}', title, content);
    notes.add(note);
    createdNotes.add(note);
    return note;
  }

  @override
  Future<NoteDto> renameNote({
    required String noteId,
    required String title,
  }) async {
    final NoteDto previous = notes.singleWhere(
      (NoteDto note) => note.id == noteId,
    );
    final NoteDto updated = _noteDto(noteId, title, previous.content);
    notes[notes.indexOf(previous)] = updated;
    return updated;
  }

  @override
  Future<NoteDto> replaceContent({
    required String noteId,
    required String content,
  }) async {
    final NoteDto previous = notes.singleWhere(
      (NoteDto note) => note.id == noteId,
    );
    final NoteDto updated = _noteDto(noteId, previous.title, content);
    notes[notes.indexOf(previous)] = updated;
    return updated;
  }

  @override
  Future<void> deleteNote(String noteId) async {
    notes.removeWhere((NoteDto note) => note.id == noteId);
  }

  @override
  Future<String> summarizeNote(
    String noteId, {
    NoteDto? selectedSnapshot,
    SummaryRunScope? scope,
  }) async => 'summary';
}
