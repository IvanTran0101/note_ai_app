import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/note_sync_status.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_conflict.dart';
import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';

import 'rag_test_support.dart';

/// One local change a test applies while a current-note question is between
/// its capture and one of its dispatches.
final class NoteChange {
  const NoteChange(this.name, this.change, this.expected);

  final String name;
  final LocalSyncState Function(LocalNoteState note) change;
  final RagFailureCode expected;
}

/// Every local fact a current-note question must re-check before dispatch.
List<NoteChange> noteChanges() => <NoteChange>[
  NoteChange(
    'content',
    (LocalNoteState note) =>
        localState(notes: <LocalNoteState>[ownedNote(content: 'Other body')]),
    RagFailureCode.sourceChanged,
  ),
  NoteChange(
    'revision',
    (LocalNoteState note) =>
        localState(notes: <LocalNoteState>[ownedNote(serverRevision: 4)]),
    RagFailureCode.sourceChanged,
  ),
  NoteChange(
    'protection',
    (LocalNoteState note) => localState(
      notes: <LocalNoteState>[
        ownedNote(protection: NoteProtection(enabled: true, revision: 1)),
      ],
    ),
    RagFailureCode.sourceUnavailable,
  ),
  NoteChange(
    'deletion',
    (LocalNoteState note) => localState(
      notes: <LocalNoteState>[
        ownedNote(deletedAt: DateTime.utc(2026, 1, 2)),
      ],
    ),
    RagFailureCode.sourceUnavailable,
  ),
  NoteChange(
    'unavailable content',
    (LocalNoteState note) => localState(
      notes: <LocalNoteState>[
        ownedNote(contentAvailable: false, title: '', content: ''),
      ],
    ),
    RagFailureCode.sourceUnavailable,
  ),
  NoteChange(
    'outbox entry',
    (LocalNoteState note) => localState(
      notes: <LocalNoteState>[note],
      outbox: <PendingMutation>[pendingUpdate(noteId: note.id)],
    ),
    RagFailureCode.sourceChanged,
  ),
  NoteChange(
    'conflict status',
    (LocalNoteState note) => localState(
      notes: <LocalNoteState>[ownedNote(status: NoteSyncStatus.conflict)],
    ),
    RagFailureCode.sourceChanged,
  ),
  NoteChange(
    'recorded conflict',
    (LocalNoteState note) => localState(
      notes: <LocalNoteState>[note],
      conflicts: <SyncConflict>[conflictFor(note)],
    ),
    RagFailureCode.sourceChanged,
  ),
  NoteChange(
    'incoming projection',
    (LocalNoteState note) =>
        localState(notes: <LocalNoteState>[incomingNote(id: note.id)]),
    RagFailureCode.sourceUnavailable,
  ),
  NoteChange(
    'account owner',
    (LocalNoteState note) => localState(
      actorId: 'user-2',
      notes: <LocalNoteState>[ownedNote(ownerId: 'user-2')],
    ),
    RagFailureCode.localStateUnavailable,
  ),
];

void main() {
  group('current note TOCTOU', () {
    for (final NoteChange change in noteChanges()) {
      test('a note whose ${change.name} changed before dispatch is not queried',
          () async {
        final LocalNoteState note = ownedNote();
        final RagHarness harness = RagHarness(
          local: localState(notes: <LocalNoteState>[note]),
        );
        await harness.grant();
        final Completer<RagConsent> consentRead = Completer<RagConsent>();
        harness.gateway.pendingConsentRead = consentRead;

        final Future<void> ask = harness.service.ask(
          question: 'This note?',
          scope: RagScope.note(note.id),
        );
        await pumpEventQueue();

        // The run is now inside its admission consent read: the local note
        // changes before the question is handed to the transport.
        harness.local = change.change(note);
        consentRead.complete(RagConsent(accepted: true, generation: 1));
        await ask;

        expect(harness.service.state.failure?.code, change.expected);
        expect(harness.gateway.calls, isNot(contains('query')));
        expect(harness.gateway.requests, isEmpty);
        expect(harness.service.state.result, isNull);
        expect(harness.readLocalStateCalls, greaterThanOrEqualTo(3));
      });
    }

    test('a note changed during the token wait is not queried', () async {
      final LocalNoteState note = ownedNote();
      final RagHarness harness = RagHarness(
        local: localState(notes: <LocalNoteState>[note]),
      );
      await harness.grant();
      final Completer<void> token = Completer<void>();
      harness.gateway.tokenWaits.addAll(<Future<void>>[
        Future<void>.value(),
        token.future,
      ]);

      final Future<void> ask = harness.service.ask(
        question: 'This note?',
        scope: RagScope.note(note.id),
      );
      await pumpEventQueue();

      expect(harness.service.state.queryRunning, isTrue);
      expect(harness.gateway.calls, isNot(contains('query')));
      harness.local = localState(
        notes: <LocalNoteState>[ownedNote(content: 'Changed body')],
      );
      token.complete();
      await ask;

      expect(harness.service.state.failure?.code, RagFailureCode.sourceChanged);
      expect(harness.gateway.calls, isNot(contains('query')));
    });

    test('a note changed while the question was in flight is not applied',
        () async {
      final LocalNoteState note = ownedNote();
      final RagHarness harness = RagHarness(
        local: localState(notes: <LocalNoteState>[note]),
      );
      await harness.grant();
      final Completer<RagResult> pending = Completer<RagResult>();
      harness.gateway.pendingQuery = pending;

      final Future<void> ask = harness.service.ask(
        question: 'This note?',
        scope: RagScope.note(note.id),
      );
      await pumpEventQueue();
      expect(harness.gateway.calls, contains('query'));

      harness.local = localState(
        notes: <LocalNoteState>[ownedNote(content: 'Changed body')],
      );
      pending.complete(
        answeredResult(<RagSource>[sourceFor(note)]),
      );
      await ask;

      expect(harness.service.state.failure?.code, RagFailureCode.sourceChanged);
      expect(harness.service.state.result, isNull);
      expect(harness.service.state.resultQuestion, isNull);
    });

    test('an already ineligible current note is refused before any dispatch',
        () async {
      final LocalNoteState note = ownedNote();
      final RagHarness harness = RagHarness(
        local: localState(
          notes: <LocalNoteState>[note],
          outbox: <PendingMutation>[pendingUpdate(noteId: note.id)],
        ),
      );
      await harness.grant();

      await harness.service.ask(
        question: 'This note?',
        scope: RagScope.note(note.id),
      );

      expect(harness.service.state.failure?.code, RagFailureCode.sourceChanged);
      expect(harness.gateway.calls, isNot(contains('query')));
      expect(harness.gateway.requests, isEmpty);
      expect(harness.service.state.queryRunning, isFalse);
    });

    test('an account question is not denied by a draft that appears mid-run',
        () async {
      final LocalNoteState note = ownedNote();
      final RagHarness harness = RagHarness(
        queryScript: <Object>[
          answeredResult(<RagSource>[sourceFor(note)]),
        ],
        local: localState(notes: <LocalNoteState>[note]),
      );
      await harness.grant();
      final Completer<RagConsent> consentRead = Completer<RagConsent>();
      harness.gateway.pendingConsentRead = consentRead;

      final Future<void> ask = harness.service.ask(
        question: 'Everything?',
        scope: const RagScope.account(),
      );
      await pumpEventQueue();

      harness.local = localState(
        notes: <LocalNoteState>[
          note,
          ownedNote(
            id: 'draft-1',
            title: 'Draft',
            content: 'Unsynced draft',
            serverRevision: 0,
          ),
        ],
        outbox: <PendingMutation>[pendingUpdate(noteId: 'draft-1')],
      );
      consentRead.complete(RagConsent(accepted: true, generation: 1));
      await ask;

      expect(harness.gateway.calls, contains('query'));
      expect(harness.service.state.result?.isAnswered, isTrue);
      expect(harness.service.state.failure, isNull);
    });

    test('an account question is not blocked by an unrelated conflict', () async {
      final LocalNoteState note = ownedNote();
      final LocalNoteState other = ownedNote(id: 'note-2');
      final RagHarness harness = RagHarness(
        queryScript: <Object>[
          answeredResult(<RagSource>[sourceFor(note)]),
        ],
        local: localState(
          notes: <LocalNoteState>[note, other],
          conflicts: <SyncConflict>[conflictFor(other)],
        ),
      );
      await harness.grant();

      await harness.service.ask(
        question: 'Everything?',
        scope: const RagScope.account(),
      );

      expect(harness.service.state.result?.isAnswered, isTrue);
      expect(harness.gateway.requests, hasLength(1));
    });
  });
}
