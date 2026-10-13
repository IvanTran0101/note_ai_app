import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';

import 'rag_test_support.dart';

/// The `onLocalStateChanged` hook revalidates what is displayed and what is in
/// flight with one read, and clears or cancels only what its own identity owns.
void main() {
  group('onLocalStateChanged display', () {
    test('clears the displayed answer when a cited note changed', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.local = localState(
        notes: <LocalNoteState>[ownedNote(content: 'Changed body')],
      );

      await displayed.harness.service.onLocalStateChanged();

      expect(displayed.harness.service.state.result, isNull);
      expect(displayed.harness.service.state.resultQuestion, isNull);
      expect(
        displayed.harness.service.state.failure?.code,
        RagFailureCode.sourceChanged,
      );
    });

    test('clears the displayed answer when a cited note was deleted', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.local = localState(
        notes: <LocalNoteState>[
          ownedNote(deletedAt: DateTime.utc(2026, 1, 2)),
        ],
      );

      await displayed.harness.service.onLocalStateChanged();

      expect(displayed.harness.service.state.result, isNull);
      expect(
        displayed.harness.service.state.failure?.code,
        RagFailureCode.sourceUnavailable,
      );
    });

    test('keeps the answer when only an unrelated note changed', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.local = localState(
        notes: <LocalNoteState>[
          note,
          ownedNote(id: 'note-2', content: 'Changed elsewhere'),
        ],
      );

      await displayed.harness.service.onLocalStateChanged();

      expect(displayed.harness.service.state.result, isNotNull);
      expect(displayed.harness.service.state.failure, isNull);
    });

    test('keeps an account answer when an unrelated draft appears', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.local = localState(
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

      await displayed.harness.service.onLocalStateChanged();

      expect(displayed.harness.service.state.result, isNotNull);
    });

    test('a read failure proves nothing and keeps the answer', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.localStateError = StateError('storage offline');

      await displayed.harness.service.onLocalStateChanged();

      expect(displayed.harness.service.state.result, isNotNull);
    });
  });

  group('onLocalStateChanged run', () {
    test('cancels an in-flight current-note question whose note changed',
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
      expect(harness.service.state.queryRunning, isTrue);

      harness.local = localState(
        notes: <LocalNoteState>[ownedNote(content: 'Changed body')],
      );
      await harness.service.onLocalStateChanged();
      await ask;

      expect(harness.service.state.failure?.code, RagFailureCode.sourceChanged);
      expect(harness.service.state.queryRunning, isFalse);
      expect(harness.service.state.result, isNull);
    });

    test('keeps an in-flight current-note question whose note is unchanged',
        () async {
      final LocalNoteState note = ownedNote();
      final RagHarness harness = RagHarness(
        queryScript: <Object>[
          answeredResult(<RagSource>[sourceFor(note)]),
        ],
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

      await harness.service.onLocalStateChanged();

      expect(harness.service.state.queryRunning, isTrue);
      pending.complete(answeredResult(<RagSource>[sourceFor(note)]));
      await ask;
      expect(harness.service.state.result?.isAnswered, isTrue);
    });

    test('keeps an in-flight account question running through local changes',
        () async {
      final LocalNoteState note = ownedNote();
      final RagHarness harness = RagHarness(
        local: localState(notes: <LocalNoteState>[note]),
      );
      await harness.grant();
      final Completer<RagResult> pending = Completer<RagResult>();
      harness.gateway.pendingQuery = pending;

      final Future<void> ask = harness.service.ask(
        question: 'Everything?',
        scope: const RagScope.account(),
      );
      await pumpEventQueue();

      harness.local = localState(
        notes: <LocalNoteState>[ownedNote(content: 'Changed body')],
      );
      await harness.service.onLocalStateChanged();
      await pumpEventQueue();
      expect(harness.service.state.queryRunning, isTrue);

      pending.complete(
        answeredResult(<RagSource>[
          sourceFor(ownedNote(content: 'Changed body')),
        ]),
      );
      await ask;

      expect(harness.service.state.result?.isAnswered, isTrue);
      expect(harness.service.state.failure, isNull);
    });
  });

  group('onLocalStateChanged cost', () {
    test('uses one read, no gateway call, and no question', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      final int reads = displayed.harness.readLocalStateCalls;
      final int dispatched = displayed.harness.gateway.calls.length;

      await displayed.harness.service.onLocalStateChanged();

      expect(displayed.harness.readLocalStateCalls, reads + 1);
      expect(displayed.harness.gateway.calls.length, dispatched);
      expect(displayed.harness.service.state.result, isNotNull);
    });

    test('does nothing when no answer is displayed and no run is active',
        () async {
      final RagHarness harness = RagHarness();
      await harness.grant();

      await harness.service.onLocalStateChanged();

      expect(harness.readLocalStateCalls, 0);
      expect(harness.service.state.result, isNull);
      expect(harness.service.state.failure, isNull);
    });
  });
}
