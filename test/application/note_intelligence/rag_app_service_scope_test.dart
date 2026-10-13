import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';

import 'rag_test_support.dart';

void main() {
  group('RagAppService.selectScope', () {
    test('keeps the state when the scope is unchanged', () async {
      final RagHarness harness = RagHarness(
        queryScript: <Object>[
          answeredResult(<RagSource>[sourceFor(ownedNote())]),
        ],
      );
      await harness.grant();
      await harness.service.ask(
        question: 'Q',
        scope: const RagScope.account(),
      );
      final RagResult? before = harness.service.state.result;
      final int queries = harness.gateway.requests.length;

      harness.service.selectScope(const RagScope.account());

      expect(harness.service.state.result, same(before));
      expect(harness.service.state.resultQuestion, 'Q');
      expect(harness.service.state.scope, const RagScope.account());
      expect(harness.gateway.requests, hasLength(queries));
      expect(harness.gateway.updates, isEmpty);
    });

    test('clears the pair atomically, updates scope, and performs no egress',
        () async {
      final LocalNoteState note = ownedNote(id: 'note-1');
      final RagHarness harness = RagHarness(
        local: localState(notes: <LocalNoteState>[note]),
        queryScript: <Object>[
          answeredResult(<RagSource>[sourceFor(note)]),
        ],
      );
      await harness.grant();
      await harness.service.ask(
        question: 'Q',
        scope: const RagScope.account(),
      );
      expect(harness.service.state.result, isNotNull);
      final RagConsent? grant = harness.service.state.consent;
      final int queries = harness.gateway.requests.length;
      final int updates = harness.gateway.updates.length;
      final List<String> calls = List<String>.of(harness.gateway.calls);

      harness.service.selectScope(RagScope.note('note-1'));

      expect(harness.service.state.scope, RagScope.note('note-1'));
      expect(harness.service.state.result, isNull);
      expect(harness.service.state.resultQuestion, isNull);
      expect(harness.service.state.queryRunning, isFalse);
      // The canonical grant and the account binding survive a scope change.
      expect(harness.service.state.consent, grant);
      expect(harness.service.state.consentAccepted, isTrue);
      expect(harness.gateway.requests, hasLength(queries));
      expect(harness.gateway.updates, hasLength(updates));
      expect(harness.gateway.calls, calls);
    });

    test('cancels the active question so a late answer cannot restore it',
        () async {
      final LocalNoteState note = ownedNote(id: 'note-1');
      final RagHarness harness = RagHarness(
        local: localState(notes: <LocalNoteState>[note]),
      );
      await harness.grant();
      final Completer<RagResult> pending = Completer<RagResult>();
      harness.gateway.pendingQuery = pending;
      final Future<void> run = harness.service.ask(
        question: 'Q',
        scope: const RagScope.account(),
      );
      await pumpEventQueue();
      expect(harness.service.state.queryRunning, isTrue);

      harness.service.selectScope(RagScope.note('note-1'));

      expect(harness.service.state.queryRunning, isFalse);
      expect(harness.service.state.result, isNull);
      expect(harness.service.state.resultQuestion, isNull);

      pending.complete(answeredResult(<RagSource>[sourceFor(note)]));
      await run;

      expect(harness.service.state.queryRunning, isFalse);
      expect(harness.service.state.result, isNull);
      expect(harness.service.state.resultQuestion, isNull);
      expect(harness.service.state.scope, RagScope.note('note-1'));
    });

    test('cancels an in-flight source check', () async {
      final LocalNoteState note = ownedNote();
      final RagSource source = sourceFor(note);
      final RagHarness harness = RagHarness(
        local: localState(notes: <LocalNoteState>[note]),
      );
      await showAnswer(harness, <RagSource>[source]);
      expect(harness.service.state.result, isNotNull);

      final Completer<RagConsent> pending = Completer<RagConsent>();
      harness.gateway.pendingConsentRead = pending;
      final Future<Object> open = harness.service.validateSource(source);
      await pumpEventQueue();

      harness.service.selectScope(RagScope.note(note.id));
      expect(harness.service.state.result, isNull);
      expect(harness.service.state.resultQuestion, isNull);

      pending.complete(RagConsent(accepted: true, generation: 1));
      await expectLater(open, throwsFailure(RagFailureCode.cancelled));
      expect(harness.service.state.result, isNull);
    });

    test('a new question failing on the same scope keeps the old pair', () async {
      final RagHarness harness = RagHarness(
        queryScript: <Object>[
          answeredResult(<RagSource>[sourceFor(ownedNote())], answer: 'A1'),
          const RagFailure(RagFailureCode.rateLimited),
        ],
      );
      await harness.grant();
      await harness.service.ask(
        question: 'Q1',
        scope: const RagScope.account(),
      );
      expect(harness.service.state.result, isNotNull);

      await harness.service.ask(
        question: 'Q2',
        scope: const RagScope.account(),
      );

      expect(harness.service.state.result, isNotNull);
      expect(harness.service.state.resultQuestion, 'Q1');
      expect(harness.service.state.failure?.code, RagFailureCode.rateLimited);

      // An unchanged scope selection keeps the retained pair untouched.
      harness.service.selectScope(const RagScope.account());
      expect(harness.service.state.result, isNotNull);
      expect(harness.service.state.resultQuestion, 'Q1');
    });
  });
}
