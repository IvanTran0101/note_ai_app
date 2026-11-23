import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';

import 'rag_test_support.dart';

/// Every await a call owns is raced against its cancellation and its 26-second
/// deadline, so a hanging local read, consent call, or dispatch guard still
/// settles with one controlled failure.
void main() {
  group('shared deadline', () {
    test('a hanging current-note capture read settles as a timeout', () async {
      final LocalNoteState note = ownedNote();
      final RagHarness harness = RagHarness(
        local: localState(notes: <LocalNoteState>[note]),
      );
      await harness.grant();
      harness.clock.step = const Duration(seconds: 30);
      harness.hangNextLocalRead(Completer<LocalSyncState>().future);

      await harness.service.ask(
        question: 'Too slow?',
        scope: RagScope.note(note.id),
      );

      expect(harness.service.state.failure?.code, RagFailureCode.timeout);
      expect(harness.service.state.queryRunning, isFalse);
      expect(harness.gateway.calls, isNot(contains('query')));
    });

    test('a hanging consent read settles as a timeout without dispatch',
        () async {
      final RagHarness harness = RagHarness();
      harness.gateway.pendingConsentRead = Completer<RagConsent>();
      harness.clock.step = const Duration(seconds: 30);

      await harness.service.refreshConsent();

      expect(harness.service.state.consent, isNull);
      expect(harness.service.state.consentLoading, isFalse);
      expect(harness.service.state.failure?.code, RagFailureCode.timeout);
      expect(harness.gateway.calls, isEmpty);
    });

    test('a hanging consent write settles as a timeout', () async {
      final RagHarness harness = RagHarness();
      await showAnswer(harness, <RagSource>[sourceFor(ownedNote())]);
      harness.clock.step = const Duration(seconds: 30);
      harness.gateway.pendingConsentWrite = Completer<RagConsent>();

      await harness.service.setConsent(true);

      expect(harness.service.state.failure?.code, RagFailureCode.timeout);
      expect(harness.service.state.consent, isNull);
      expect(harness.service.state.result, isNull);
      expect(harness.gateway.calls, isNot(contains('updateConsent')));
    });

    test('a hanging source open settles as a timeout', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.clock.step = const Duration(seconds: 30);
      displayed.harness.hangNextLocalRead(Completer<LocalSyncState>().future);

      await expectLater(
        displayed.harness.service.validateSource(displayed.sources.single),
        throwsFailure(RagFailureCode.timeout),
      );

      // A budget that ran out proves nothing about the citation.
      expect(displayed.harness.service.state.result, isNotNull);
    });
  });

  group('cancellation', () {
    test('a hanging capture read settles when the app goes inactive', () async {
      final LocalNoteState note = ownedNote();
      final RagHarness harness = RagHarness(
        local: localState(notes: <LocalNoteState>[note]),
      );
      await harness.grant();
      harness.hangNextLocalRead(Completer<LocalSyncState>().future);

      final Future<void> ask = harness.service.ask(
        question: 'Too slow?',
        scope: RagScope.note(note.id),
      );
      await pumpEventQueue();
      expect(harness.service.state.queryRunning, isTrue);

      harness.service.onInactive();
      await ask;

      expect(harness.service.state.active, isFalse);
      expect(harness.service.state.queryRunning, isFalse);
      expect(harness.service.state.failure?.code, RagFailureCode.cancelled);
      expect(harness.gateway.calls, isNot(contains('query')));
    });

    test('a hanging pre-dispatch guard read settles on cancel', () async {
      final LocalNoteState note = ownedNote();
      final RagHarness harness = RagHarness(
        local: localState(notes: <LocalNoteState>[note]),
      );
      await harness.grant();
      // Read 1 is the capture; read 2 is the guard before the consent GET.
      harness.pendingLocalRead = Completer<LocalSyncState>().future;
      harness.hangLocalReadAt = 2;

      final Future<void> ask = harness.service.ask(
        question: 'This note?',
        scope: RagScope.note(note.id),
      );
      await pumpEventQueue();

      harness.service.cancel();
      await ask;

      expect(harness.service.state.failure?.code, RagFailureCode.cancelled);
      expect(harness.service.state.queryRunning, isFalse);
      expect(harness.gateway.calls, isNot(contains('query')));
    });

    test('a hanging consent read settles when the app goes inactive', () async {
      final RagHarness harness = RagHarness();
      harness.gateway.pendingConsentRead = Completer<RagConsent>();

      final Future<void> refresh = harness.service.refreshConsent();
      await pumpEventQueue();
      expect(harness.service.state.consentLoading, isTrue);

      harness.service.onInactive();
      await refresh;

      expect(harness.service.state.active, isFalse);
      expect(harness.service.state.consent, isNull);
      expect(harness.service.state.consentLoading, isFalse);
      expect(harness.service.state.failure?.code, RagFailureCode.cancelled);
    });

    test('a hanging apply read settles on cancel without a partial answer',
        () async {
      final LocalNoteState note = ownedNote();
      final RagHarness harness = RagHarness(
        queryScript: <Object>[
          answeredResult(<RagSource>[sourceFor(note)]),
        ],
      );
      await harness.grant();
      harness.hangNextLocalRead(Completer<LocalSyncState>().future);

      final Future<void> ask = harness.service.ask(
        question: 'Everything?',
        scope: const RagScope.account(),
      );
      await pumpEventQueue();
      expect(harness.gateway.calls, contains('query'));

      harness.service.cancel();
      await ask;

      expect(harness.service.state.failure?.code, RagFailureCode.cancelled);
      expect(harness.service.state.result, isNull);
      expect(harness.service.state.resultQuestion, isNull);
    });

    test('a hanging source open settles on logout', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.hangNextLocalRead(Completer<LocalSyncState>().future);

      final Future<Object?> open = displayed.harness.service
          .validateSource(displayed.sources.single)
          .then<Object?>((Object? value) => value, onError: (Object error) => error);
      await pumpEventQueue();

      displayed.harness.service.invalidateSession();

      expect(
        await open,
        isA<RagFailure>().having(
          (RagFailure f) => f.code,
          'code',
          RagFailureCode.sessionChanged,
        ),
      );
    });

    test('a hanging source open settles on dispose', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.hangNextLocalRead(Completer<LocalSyncState>().future);

      final Future<void> open = displayed.harness.service.validateSource(
        displayed.sources.single,
      );
      await pumpEventQueue();

      displayed.harness.service.dispose();

      await expectLater(open, throwsFailure(RagFailureCode.cancelled));
    });

    test('a hanging revalidation read is released by logout', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.hangNextLocalRead(Completer<LocalSyncState>().future);

      final Future<void> revalidation =
          displayed.harness.service.onLocalStateChanged();
      await pumpEventQueue();

      displayed.harness.service.invalidateSession();
      await revalidation;

      // The hook never throws; the answer was cleared by the session change.
      expect(displayed.harness.service.state.result, isNull);
    });
  });

  group('late completions', () {
    test('a consent read that errors after cancellation stays observed',
        () async {
      final RagHarness harness = RagHarness();
      final Completer<RagConsent> pending = Completer<RagConsent>();
      harness.gateway.pendingConsentRead = pending;

      final Future<void> refresh = harness.service.refreshConsent();
      await pumpEventQueue();
      harness.service.invalidateSession();
      pending.completeError(
        const RagFailure(RagFailureCode.providerUnavailable),
      );

      await refresh;
      await pumpEventQueue();

      expect(harness.service.state.consent, isNull);
      expect(harness.service.state.consentLoading, isFalse);
    });

    test('a cancelled run ignores a late transport error', () async {
      final RagHarness harness = RagHarness();
      await harness.grant();
      final Completer<RagResult> pending = Completer<RagResult>();
      harness.gateway.pendingQuery = pending;

      final Future<void> ask = harness.service.ask(
        question: 'Everything?',
        scope: const RagScope.account(),
      );
      await pumpEventQueue();
      harness.service.cancel();
      await ask;

      pending.completeError(const RagFailure(RagFailureCode.providerUnavailable));
      await pumpEventQueue();

      expect(harness.service.state.failure?.code, RagFailureCode.cancelled);
      expect(harness.service.state.result, isNull);
      expect(harness.gateway.requests, hasLength(1));
    });
  });
}
