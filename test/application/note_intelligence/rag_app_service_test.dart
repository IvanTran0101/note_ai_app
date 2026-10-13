import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/note_intelligence/rag_state.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';

import 'rag_test_support.dart';

void main() {
  group('consent gating', () {
    test('refreshConsent adopts the canonical grant and then allows a query',
        () async {
      final RagHarness harness = RagHarness(
        consentScript: <Object>[RagConsent(accepted: true, generation: 1)],
        queryScript: <Object>[
          answeredResult(<RagSource>[sourceFor(ownedNote())]),
        ],
      );

      await harness.service.refreshConsent();

      expect(harness.service.state.consent, RagConsent(accepted: true, generation: 1));
      expect(harness.service.state.consentLoading, isFalse);
      expect(harness.service.state.failure, isNull);
      expect(harness.service.state.canAsk, isTrue);

      await harness.service.ask(
        question: 'What did I decide?',
        scope: const RagScope.account(),
      );

      expect(harness.gateway.requests, hasLength(1));
      expect(harness.gateway.requests.single.question, 'What did I decide?');
      expect(harness.gateway.requests.single.scope, const RagScope.account());
      expect(harness.service.state.result?.isAnswered, isTrue);
      expect(harness.service.state.resultQuestion, 'What did I decide?');
      expect(harness.service.state.failure, isNull);
      expect(harness.service.state.queryRunning, isFalse);
    });

    test('the default grant is refused and never reaches the query', () async {
      final RagHarness harness = RagHarness();

      await harness.service.refreshConsent();

      expect(harness.service.state.consent, RagConsent.none);
      expect(harness.service.state.consentAccepted, isFalse);

      await harness.service.ask(
        question: 'Anything?',
        scope: const RagScope.account(),
      );

      expect(harness.service.state.failure?.code, RagFailureCode.consentRequired);
      expect(harness.gateway.calls, isNot(contains('query')));
    });

    test('a failed consent read leaves the grant unknown and blocks queries',
        () async {
      final RagHarness harness = RagHarness(
        consentScript: <Object>[
          const RagFailure(RagFailureCode.livePolicyNotConfigured),
        ],
      );

      await harness.service.refreshConsent();

      expect(harness.service.state.consent, isNull);
      expect(
        harness.service.state.failure?.code,
        RagFailureCode.livePolicyNotConfigured,
      );

      await harness.service.ask(
        question: 'Anything?',
        scope: const RagScope.account(),
      );

      expect(harness.service.state.failure?.code, RagFailureCode.consentUnknown);
      expect(harness.gateway.calls, isNot(contains('query')));
    });

    test('a never-read grant blocks queries without touching the gateway',
        () async {
      final RagHarness harness = RagHarness();

      await harness.service.ask(
        question: 'Anything?',
        scope: const RagScope.account(),
      );

      expect(harness.service.state.failure?.code, RagFailureCode.consentUnknown);
      expect(harness.gateway.calls, isEmpty);
    });

    test('a grant still loading blocks queries', () async {
      final RagHarness harness = RagHarness();
      final Completer<RagConsent> pending = Completer<RagConsent>();
      harness.gateway.pendingConsentRead = pending;

      final Future<void> refresh = harness.service.refreshConsent();
      await pumpEventQueue();

      expect(harness.service.state.consentLoading, isTrue);
      await harness.service.ask(
        question: 'Anything?',
        scope: const RagScope.account(),
      );
      expect(harness.service.state.failure?.code, RagFailureCode.consentUnknown);
      expect(harness.gateway.calls, isNot(contains('query')));

      pending.complete(RagConsent(accepted: true, generation: 4));
      await refresh;
      expect(harness.service.state.consent, RagConsent(accepted: true, generation: 4));
      expect(harness.service.state.consentLoading, isFalse);
    });

    test('setConsent writes the read generation and adopts the new one',
        () async {
      final RagHarness harness = RagHarness();
      await harness.service.refreshConsent();

      await harness.service.setConsent(true);

      expect(harness.gateway.updates.single.accepted, isTrue);
      expect(harness.gateway.updates.single.expectedGeneration, 0);
      expect(harness.gateway.updates.single.version, 'rag-consent.v1');
      expect(harness.service.state.consent, RagConsent(accepted: true, generation: 1));
      expect(harness.service.state.consentLoading, isFalse);
      expect(harness.service.state.failure, isNull);
    });

    test('a compare-and-set conflict leaves the grant unknown', () async {
      final RagHarness harness = RagHarness(
        writeScript: <Object>[const RagFailure(RagFailureCode.sourceChanged)],
      );
      await harness.service.refreshConsent();

      await harness.service.setConsent(true);

      expect(harness.service.state.failure?.code, RagFailureCode.sourceChanged);
      expect(harness.service.state.consent, isNull);
      expect(harness.service.state.consentLoading, isFalse);

      await harness.service.ask(
        question: 'Anything?',
        scope: const RagScope.account(),
      );
      expect(harness.service.state.failure?.code, RagFailureCode.consentUnknown);
      expect(harness.gateway.calls, isNot(contains('query')));
    });

    test('the same accepted value with a new grant generation is stale',
        () async {
      final RagHarness harness = RagHarness(
        writeScript: <Object>[RagConsent(accepted: true, generation: 5)],
      );
      await harness.service.refreshConsent();

      await harness.service.setConsent(true);

      expect(harness.service.state.failure?.code, RagFailureCode.sourceChanged);
      expect(harness.service.state.consent, isNull);
    });

    test('an explicit revoke increments the generation and clears the answer',
        () async {
      final RagHarness harness = RagHarness(
        queryScript: <Object>[
          answeredResult(<RagSource>[sourceFor(ownedNote())]),
        ],
      );
      await harness.grant();
      await harness.service.ask(
        question: 'First?',
        scope: const RagScope.account(),
      );
      expect(harness.service.state.result, isNotNull);

      harness.gateway.writeScript.add(
        RagConsent(accepted: false, generation: 2),
      );
      await harness.service.setConsent(false);

      expect(harness.gateway.updates.single.accepted, isFalse);
      expect(harness.gateway.updates.single.expectedGeneration, 1);
      expect(harness.service.state.consent, RagConsent(accepted: false, generation: 2));
      expect(harness.service.state.result, isNull);
      expect(harness.service.state.resultQuestion, isNull);
      expect(harness.service.state.canAsk, isFalse);
    });

    test('logout clears everything and never writes a revoke', () async {
      final RagHarness harness = RagHarness(
        queryScript: <Object>[
          answeredResult(<RagSource>[sourceFor(ownedNote())]),
        ],
      );
      await harness.grant();
      await harness.service.ask(
        question: 'First?',
        scope: const RagScope.account(),
      );

      harness.service.invalidateSession();

      expect(harness.gateway.calls, isNot(contains('updateConsent')));
      expect(harness.service.state.consent, isNull);
      expect(harness.service.state.result, isNull);
      expect(harness.service.state.resultQuestion, isNull);
      expect(harness.service.state.scope, isNull);
      expect(harness.service.state.queryRunning, isFalse);
      expect(harness.service.state.failure, isNull);
    });

    test('a consent read that lands after an account switch is discarded',
        () async {
      final RagHarness harness = RagHarness();
      final Completer<RagConsent> pending = Completer<RagConsent>();
      harness.gateway.pendingConsentRead = pending;

      final Future<void> refresh = harness.service.refreshConsent();
      await pumpEventQueue();

      harness.currentUser.signIn('user-2');
      harness.session.advance();
      pending.complete(RagConsent(accepted: true, generation: 7));
      await refresh;

      expect(harness.service.state.consent, isNull);
      await harness.service.ask(
        question: 'Anything?',
        scope: const RagScope.account(),
      );
      expect(harness.gateway.calls, isNot(contains('query')));
    });

    test('a consent write that lands after an account switch is discarded',
        () async {
      final RagHarness harness = RagHarness();
      await harness.grant();
      final Completer<RagConsent> pending = Completer<RagConsent>();
      harness.gateway.pendingConsentWrite = pending;

      final Future<void> write = harness.service.setConsent(true);
      await pumpEventQueue();
      harness.currentUser.signIn('user-2');
      harness.session.advance();
      pending.complete(RagConsent(accepted: true, generation: 2));
      await write;

      expect(harness.service.state.consent, isNull);
      expect(harness.service.state.consentAccepted, isFalse);
    });

    test('logout and relogin of the same account starts a new session', () async {
      final RagHarness harness = RagHarness(
        queryScript: <Object>[
          answeredResult(<RagSource>[sourceFor(ownedNote())]),
        ],
      );
      await harness.grant();
      harness.service.invalidateSession();
      harness.session.advance();

      await harness.service.ask(
        question: 'Anything?',
        scope: const RagScope.account(),
      );
      expect(harness.service.state.failure?.code, RagFailureCode.consentUnknown);
      expect(harness.gateway.calls, isNot(contains('query')));
      expect(harness.gateway.calls, isNot(contains('updateConsent')));

      await harness.grant();
      await harness.service.ask(
        question: 'Anything now?',
        scope: const RagScope.account(),
      );
      expect(harness.service.state.result?.isAnswered, isTrue);
      expect(harness.service.state.failure, isNull);
    });
  });

  group('question runs', () {
    test('passes the frozen context and awaits the pre-send guard', () async {
      final RagHarness harness = RagHarness(
        queryScript: <Object>[
          answeredResult(<RagSource>[sourceFor(ownedNote())]),
        ],
      );
      await harness.grant();

      await harness.service.ask(
        question: 'What did I decide?',
        scope: const RagScope.account(),
      );

      expect(harness.gateway.calls, <String>[
        'readConsent',
        'readConsent',
        'query',
        'readConsent',
      ]);
      expect(harness.gateway.dispatchGuards, 4);
      expect(
        harness.gateway.contexts.map((RagCallContext c) => c.expectedUserId),
        everyElement('user-1'),
      );
      expect(
        harness.gateway.contexts.map((RagCallContext c) => c.deadline),
        everyElement(DateTime.utc(2026, 1, 1).add(const Duration(seconds: 26))),
      );
      expect(harness.gateway.closes, 0);
    });

    test('the cancellation future stays open on normal completion', () async {
      final RagHarness harness = RagHarness(
        queryScript: <Object>[
          answeredResult(<RagSource>[sourceFor(ownedNote())]),
        ],
      );
      await harness.grant();

      await harness.service.ask(
        question: 'What did I decide?',
        scope: const RagScope.account(),
      );

      bool cancelled = false;
      unawaited(
        harness.gateway.contexts.first.cancelled.then((_) => cancelled = true),
      );
      await pumpEventQueue();
      expect(cancelled, isFalse);
      expect(harness.service.state.result?.isAnswered, isTrue);
    });

    test('an account switch clears the previous answer and scope', () async {
      final RagHarness harness = RagHarness(
        queryScript: <Object>[
          answeredResult(<RagSource>[sourceFor(ownedNote())]),
        ],
      );
      await harness.grant();
      await harness.service.ask(
        question: 'First?',
        scope: const RagScope.account(),
      );
      expect(harness.service.state.result, isNotNull);

      harness.currentUser.signIn('user-2');
      harness.session.advance();
      await harness.service.refreshConsent();

      expect(harness.service.state.result, isNull);
      expect(harness.service.state.resultQuestion, isNull);
      expect(harness.service.state.scope, isNull);
      expect(harness.gateway.requests, hasLength(1));
    });

    test('a remote grant change before the answer is applied discards it',
        () async {
      final RagHarness harness = RagHarness(
        consentScript: <Object>[
          RagConsent(accepted: true, generation: 1),
          RagConsent(accepted: true, generation: 1),
          RagConsent(accepted: true, generation: 2),
        ],
        queryScript: <Object>[
          answeredResult(<RagSource>[sourceFor(ownedNote())]),
        ],
      );
      await harness.service.refreshConsent();

      await harness.service.ask(
        question: 'What did I decide?',
        scope: const RagScope.account(),
      );

      expect(harness.service.state.result, isNull);
      expect(harness.service.state.failure?.code, RagFailureCode.consentRequired);
      expect(harness.service.state.consent, RagConsent(accepted: true, generation: 2));
    });

    test('an answered result whose citation is stale is not applied', () async {
      final LocalNoteState note = ownedNote();
      final RagHarness harness = RagHarness(
        queryScript: <Object>[
          answeredResult(<RagSource>[sourceFor(note, quote: 'Body')]),
        ],
      );
      await harness.grant();
      harness.local = localState(
        notes: <LocalNoteState>[ownedNote(content: 'Changed text')],
      );

      await harness.service.ask(
        question: 'What did I decide?',
        scope: const RagScope.account(),
      );

      expect(harness.service.state.result, isNull);
      expect(harness.service.state.failure?.code, RagFailureCode.sourceChanged);
      expect(harness.readLocalStateCalls, 1);
    });

    test('a second question is refused while one is running', () async {
      final RagHarness harness = RagHarness();
      await harness.grant();
      final Completer<RagResult> pending = Completer<RagResult>();
      harness.gateway.pendingQuery = pending;

      final Future<void> first = harness.service.ask(
        question: 'First?',
        scope: const RagScope.account(),
      );
      await pumpEventQueue();
      expect(harness.service.state.queryRunning, isTrue);

      await harness.service.ask(
        question: 'Second?',
        scope: const RagScope.account(),
      );
      expect(harness.service.state.failure?.code, RagFailureCode.alreadyRunning);
      expect(harness.gateway.requests, hasLength(1));

      pending.complete(
        answeredResult(<RagSource>[sourceFor(ownedNote())]),
      );
      await first;
      expect(harness.service.state.resultQuestion, 'First?');
    });

    test('cancel releases the slot while the transport stays unsettled',
        () async {
      final RagHarness harness = RagHarness();
      await harness.grant();
      final Completer<RagResult> pending = Completer<RagResult>();
      harness.gateway.pendingQuery = pending;

      final Future<void> ask = harness.service.ask(
        question: 'First?',
        scope: const RagScope.account(),
      );
      await pumpEventQueue();
      final RagCallContext queryContext = harness.gateway.contexts.last;

      harness.service.cancel();
      await ask;

      expect(harness.service.state.queryRunning, isFalse);
      expect(harness.service.state.failure?.code, RagFailureCode.cancelled);
      await queryContext.cancelled;

      pending.completeError(const RagFailure(RagFailureCode.providerUnavailable));
      await pumpEventQueue();

      expect(harness.service.state.failure?.code, RagFailureCode.cancelled);
      expect(harness.service.state.result, isNull);
      expect(harness.gateway.requests, hasLength(1));

      await harness.service.ask(
        question: 'Again?',
        scope: const RagScope.account(),
      );
      expect(harness.gateway.requests, hasLength(2));
    });

    test('a transport failure keeps the old question and answer pair', () async {
      final RagResult first = answeredResult(
        <RagSource>[sourceFor(ownedNote())],
        answer: 'First answer',
      );
      final RagHarness harness = RagHarness(
        queryScript: <Object>[first, const RagFailure(RagFailureCode.timeout)],
      );
      await harness.grant();
      await harness.service.ask(
        question: 'First?',
        scope: const RagScope.account(),
      );

      await harness.service.ask(
        question: 'Second?',
        scope: const RagScope.account(),
      );

      expect(harness.service.state.failure?.code, RagFailureCode.timeout);
      expect(harness.service.state.result, first);
      expect(harness.service.state.resultQuestion, 'First?');
      expect(harness.gateway.requests, hasLength(2));
    });

    test('NOT_ENOUGH_CONTEXT replaces the old answer with the new refusal',
        () async {
      final RagHarness harness = RagHarness(
        queryScript: <Object>[
          answeredResult(<RagSource>[sourceFor(ownedNote())]),
          notEnoughContextResult(requestId: 'req-2'),
        ],
      );
      await harness.grant();
      await harness.service.ask(
        question: 'First?',
        scope: const RagScope.account(),
      );

      await harness.service.ask(
        question: 'Second?',
        scope: const RagScope.account(),
      );

      expect(harness.service.state.result?.status, RagResultStatus.notEnoughContext);
      expect(
        harness.service.state.result?.reason,
        RagResult.reasonInsufficientEvidence,
      );
      expect(harness.service.state.resultQuestion, 'Second?');
      expect(harness.service.state.failure, isNull);
    });

    test('a scope change clears the old answer', () async {
      final RagHarness harness = RagHarness(
        queryScript: <Object>[
          answeredResult(<RagSource>[sourceFor(ownedNote())]),
          const RagFailure(RagFailureCode.timeout),
        ],
      );
      await harness.grant();
      await harness.service.ask(
        question: 'Account question?',
        scope: const RagScope.account(),
      );
      expect(harness.service.state.result, isNotNull);

      await harness.service.ask(
        question: 'Note question?',
        scope: RagScope.note('note-1'),
      );

      expect(harness.service.state.scope, RagScope.note('note-1'));
      expect(harness.service.state.result, isNull);
      expect(harness.service.state.resultQuestion, isNull);
      expect(harness.service.state.failure?.code, RagFailureCode.timeout);
    });

    test('the shared deadline fails the run before the query is dispatched',
        () async {
      final RagHarness harness = RagHarness();
      await harness.grant();
      final Completer<RagConsent> pending = Completer<RagConsent>();
      harness.gateway.pendingConsentRead = pending;

      final Future<void> ask = harness.service.ask(
        question: 'Too slow?',
        scope: const RagScope.account(),
      );
      await pumpEventQueue();
      harness.clock.advance(const Duration(seconds: 27));
      pending.complete(RagConsent(accepted: true, generation: 1));
      await ask;

      expect(harness.service.state.failure?.code, RagFailureCode.timeout);
      expect(harness.gateway.calls, isNot(contains('query')));
      expect(harness.service.state.queryRunning, isFalse);
    });

    test('an account query is not denied by an unrelated local draft', () async {
      final RagHarness harness = RagHarness(
        queryScript: <Object>[
          answeredResult(<RagSource>[sourceFor(ownedNote())]),
        ],
      );
      harness.local = localState(
        notes: <LocalNoteState>[
          ownedNote(),
          ownedNote(
            id: 'draft-1',
            title: 'Draft',
            content: 'Unsynced draft',
            serverRevision: 0,
          ),
        ],
      );
      await harness.grant();

      await harness.service.ask(
        question: 'What did I decide?',
        scope: const RagScope.account(),
      );

      expect(harness.service.state.result?.isAnswered, isTrue);
      expect(harness.service.state.failure, isNull);
      expect(harness.gateway.requests, hasLength(1));
    });

    test('a pending current note is refused before any dispatch', () async {
      final RagHarness harness = RagHarness();
      final LocalNoteState note = ownedNote();
      harness.local = localState(
        notes: <LocalNoteState>[note],
        outbox: <PendingMutation>[pendingUpdate(noteId: note.id)],
      );
      await harness.grant();

      await harness.service.ask(
        question: 'This note?',
        scope: RagScope.note(note.id),
      );

      expect(harness.service.state.failure?.code, RagFailureCode.sourceChanged);
      expect(harness.gateway.calls, isNot(contains('query')));
    });

    test('an invalid question never reaches the gateway', () async {
      final RagHarness harness = RagHarness();
      await harness.grant();

      await harness.service.ask(
        question: '   ',
        scope: const RagScope.account(),
      );
      expect(harness.service.state.failure?.code, RagFailureCode.invalidInput);

      await harness.service.ask(
        question: 'a' * (RagRequest.maxQuestionCodePoints + 1),
        scope: const RagScope.account(),
      );
      expect(harness.service.state.failure?.code, RagFailureCode.inputTooLong);

      expect(harness.gateway.calls.where((String c) => c == 'query'), isEmpty);
    });

    test('an unauthenticated ask is refused locally', () async {
      final RagHarness harness = RagHarness();
      harness.currentUser.signOut();

      await harness.service.ask(
        question: 'Anything?',
        scope: const RagScope.account(),
      );

      expect(harness.service.state.failure?.code, RagFailureCode.unauthorized);
      expect(harness.gateway.calls, isEmpty);
    });

    test('an inactive app cancels the run and dispatches nothing', () async {
      final RagHarness harness = RagHarness();
      await harness.grant();

      harness.service.onInactive();

      expect(harness.service.state.active, isFalse);
      expect(harness.service.state.consent, isNull);

      await harness.service.ask(
        question: 'Anything?',
        scope: const RagScope.account(),
      );
      expect(harness.service.state.failure?.code, RagFailureCode.cancelled);
      expect(harness.gateway.calls.where((String c) => c == 'query'), isEmpty);
    });

    test('inactive cancels an in-flight question and resume never resends it',
        () async {
      final RagHarness harness = RagHarness();
      await harness.grant();
      final Completer<RagResult> pending = Completer<RagResult>();
      harness.gateway.pendingQuery = pending;

      final Future<void> ask = harness.service.ask(
        question: 'First?',
        scope: const RagScope.account(),
      );
      await pumpEventQueue();
      expect(harness.service.state.queryRunning, isTrue);

      harness.service.onInactive();
      await ask;
      expect(harness.service.state.queryRunning, isFalse);
      expect(harness.service.state.failure?.code, RagFailureCode.cancelled);

      harness.gateway.pendingQuery = null;
      await harness.service.onResume();

      expect(harness.service.state.active, isTrue);
      expect(harness.service.state.consentAccepted, isTrue);
      expect(harness.gateway.requests, hasLength(1));
      expect(harness.service.state.queryRunning, isFalse);
    });

    test('state privacy keeps question and answer text out of toString',
        () async {
      final RagHarness harness = RagHarness(
        queryScript: <Object>[
          answeredResult(
            <RagSource>[sourceFor(ownedNote())],
            answer: 'Secret answer',
          ),
        ],
      );
      await harness.grant();
      await harness.service.ask(
        question: 'Secret question',
        scope: const RagScope.account(),
      );

      expect(harness.service.state.toString(), isNot(contains('Secret question')));
      expect(harness.service.state.toString(), isNot(contains('Secret answer')));
      expect(harness.service.state.result.toString(), isNot(contains('Secret answer')));
      expect(harness.service.state.toString(), contains('queryRunning: false'));
    });

    test('the state stream observes the whole transition', () async {
      final RagHarness harness = RagHarness(
        queryScript: <Object>[
          answeredResult(<RagSource>[sourceFor(ownedNote())]),
        ],
      );
      final List<RagState> seen = <RagState>[];
      final StreamSubscription<RagState> subscription =
          harness.service.stateStream.listen(seen.add);

      await harness.grant();
      await harness.service.ask(
        question: 'First?',
        scope: const RagScope.account(),
      );
      await pumpEventQueue();
      await subscription.cancel();

      expect(seen.any((RagState s) => s.consentLoading), isTrue);
      expect(seen.any((RagState s) => s.queryRunning), isTrue);
      expect(seen.last.result?.isAnswered, isTrue);
      expect(seen.last, harness.service.state);
    });

    test('dispose cancels the run and closes the stream', () async {
      final RagHarness harness = RagHarness();
      await harness.grant();
      final Completer<RagResult> pending = Completer<RagResult>();
      harness.gateway.pendingQuery = pending;

      final Future<void> ask = harness.service.ask(
        question: 'First?',
        scope: const RagScope.account(),
      );
      await pumpEventQueue();

      harness.service.dispose();
      await ask;

      expect(harness.service.state.queryRunning, isFalse);
      expect(harness.gateway.closes, 0);
      expect(harness.service.stateStream.isBroadcast, isTrue);
    });
  });
}
