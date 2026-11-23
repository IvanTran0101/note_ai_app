import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';

import 'rag_test_support.dart';

/// `invalidateNote` is the dirty-note hook the composition root calls: it
/// cancels only a run in that note's own scope and clears only an answer that
/// cites that note. An unrelated note never denies the account, never resets the
/// scope, and never touches the canonical grant.
void main() {
  group('displayed answer', () {
    test('clears the paired answer when it cites the note', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      final RagConsent? grant = displayed.harness.service.state.consent;

      displayed.harness.service.invalidateNote(note.id);

      expect(displayed.harness.service.state.result, isNull);
      expect(displayed.harness.service.state.resultQuestion, isNull);
      expect(
        displayed.harness.service.state.failure?.code,
        RagFailureCode.sourceChanged,
      );
      // The grant is account state, not note state: an edit never resets it.
      expect(displayed.harness.service.state.consent, grant);
      expect(displayed.harness.gateway.calls, isNot(contains('updateConsent')));
    });

    test('keeps an answer that does not cite the note', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      final RagResult? answer = displayed.harness.service.state.result;
      final RagScope? scope = displayed.harness.service.state.scope;
      final int dispatched = displayed.harness.gateway.calls.length;
      displayed.harness.readLocalStateCalls = 0;

      displayed.harness.service.invalidateNote('note-elsewhere');

      expect(displayed.harness.service.state.result, same(answer));
      expect(displayed.harness.service.state.resultQuestion, 'What did I decide?');
      expect(displayed.harness.service.state.scope, scope);
      expect(displayed.harness.service.state.failure, isNull);
      expect(displayed.harness.service.state.canAsk, isTrue);
      expect(displayed.harness.gateway.calls.length, dispatched);
      expect(displayed.harness.readLocalStateCalls, 0);
    });

    test('keeps the account usable for the next question', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);

      displayed.harness.service.invalidateNote('note-elsewhere');
      await displayed.harness.service.ask(
        question: 'Unrelated?',
        scope: const RagScope.account(),
      );

      expect(displayed.harness.service.state.result?.isAnswered, isTrue);
      expect(displayed.harness.service.state.failure, isNull);
    });

    test('does nothing for a blank id', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      final int dispatched = displayed.harness.gateway.calls.length;

      displayed.harness.service.invalidateNote('   ');

      expect(displayed.harness.service.state.result, isNotNull);
      expect(displayed.harness.service.state.failure, isNull);
      expect(displayed.harness.gateway.calls.length, dispatched);
    });

    test('clears account state through the normal binding guard', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);

      displayed.harness.currentUser.signOut();
      displayed.harness.service.invalidateNote(note.id);

      // A signed-out session owns nothing: the actor guard clears it, exactly as
      // it does for every other entry point.
      expect(displayed.harness.service.state.result, isNull);
      expect(displayed.harness.service.state.consent, isNull);
    });
  });

  group('in-flight run', () {
    test('cancels a matching current-note run synchronously', () async {
      final LocalNoteState note = ownedNote();
      final RagHarness harness = RagHarness(
        local: localState(notes: <LocalNoteState>[note]),
      );
      await harness.grant();
      harness.gateway.pendingQuery = Completer<RagResult>();

      final Future<void> ask = harness.service.ask(
        question: 'This note?',
        scope: RagScope.note(note.id),
      );
      await pumpEventQueue();
      expect(harness.service.state.queryRunning, isTrue);

      harness.service.invalidateNote(note.id);

      expect(harness.service.state.queryRunning, isFalse);
      expect(
        harness.service.state.failure?.code,
        RagFailureCode.sourceChanged,
      );

      await ask;
      expect(harness.service.state.result, isNull);
    });

    test('never displays a late result of the cancelled run', () async {
      final LocalNoteState note = ownedNote();
      final RagHarness harness = RagHarness(
        queryScript: <Object>[answeredResult(<RagSource>[sourceFor(note)])],
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

      harness.service.invalidateNote(note.id);
      pending.complete(answeredResult(<RagSource>[sourceFor(note)]));
      await ask;

      expect(harness.service.state.result, isNull);
      expect(harness.service.state.resultQuestion, isNull);
      expect(
        harness.service.state.failure?.code,
        RagFailureCode.sourceChanged,
      );
    });

    test('leaves an account-scope run and an unrelated note run alone', () async {
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

      harness.service.invalidateNote(note.id);
      expect(harness.service.state.queryRunning, isTrue);
      expect(harness.service.state.failure, isNull);

      pending.complete(answeredResult(<RagSource>[sourceFor(note)]));
      await ask;
      expect(harness.service.state.result?.isAnswered, isTrue);
    });

    test('leaves a run scoped to another note alone', () async {
      final LocalNoteState note = ownedNote();
      final RagHarness harness = RagHarness(
        local: localState(
          notes: <LocalNoteState>[note, ownedNote(id: 'note-2')],
        ),
      );
      await harness.grant();
      harness.gateway.pendingQuery = Completer<RagResult>();

      unawaited(
        harness.service.ask(
          question: 'The other note?',
          scope: RagScope.note('note-2'),
        ),
      );
      await pumpEventQueue();

      harness.service.invalidateNote(note.id);

      expect(harness.service.state.queryRunning, isTrue);
      expect(harness.service.state.failure, isNull);
    });
  });
}
