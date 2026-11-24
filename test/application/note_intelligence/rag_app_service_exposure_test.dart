import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';

import 'rag_test_support.dart';

/// Consent exposure rules: a displayed answer may only stay visible while the
/// canonical grant, account, session, scope, and local evidence still authorize
/// it.
void main() {
  group('revoke', () {
    test('clears the displayed answer before the PUT resolves', () async {
      final RagHarness harness = RagHarness();
      await showAnswer(harness, <RagSource>[sourceFor(ownedNote())]);
      final Completer<RagConsent> pending = Completer<RagConsent>();
      harness.gateway.pendingConsentWrite = pending;

      final Future<void> write = harness.service.setConsent(false);
      await pumpEventQueue();

      expect(harness.service.state.result, isNull);
      expect(harness.service.state.resultQuestion, isNull);
      expect(harness.service.state.consentLoading, isTrue);
      expect(harness.gateway.updates.single.accepted, isFalse);

      pending.complete(RagConsent(accepted: false, generation: 2));
      await write;

      expect(harness.service.state.result, isNull);
      expect(harness.service.state.resultQuestion, isNull);
      expect(
        harness.service.state.consent,
        RagConsent(accepted: false, generation: 2),
      );
    });

    test('a failing revoke never restores the withdrawn answer', () async {
      final RagHarness harness = RagHarness();
      await showAnswer(harness, <RagSource>[sourceFor(ownedNote())]);
      harness.gateway.writeScript.add(
        const RagFailure(RagFailureCode.sourceChanged),
      );

      await harness.service.setConsent(false);

      expect(harness.service.state.failure?.code, RagFailureCode.sourceChanged);
      expect(harness.service.state.result, isNull);
      expect(harness.service.state.resultQuestion, isNull);
      expect(harness.service.state.consent, isNull);
      expect(harness.service.state.consentLoading, isFalse);
    });

    test('a revoke that is superseded by a newer call stays cleared', () async {
      final RagHarness harness = RagHarness();
      await showAnswer(harness, <RagSource>[sourceFor(ownedNote())]);
      final Completer<RagConsent> pending = Completer<RagConsent>();
      harness.gateway.pendingConsentWrite = pending;

      final Future<void> write = harness.service.setConsent(false);
      await pumpEventQueue();
      harness.service.invalidateSession();
      pending.complete(RagConsent(accepted: false, generation: 2));
      await write;

      expect(harness.service.state.result, isNull);
      expect(harness.service.state.resultQuestion, isNull);
      expect(harness.service.state.consent, isNull);
    });
  });

  group('grant refresh', () {
    test('an unchanged grant keeps the displayed answer', () async {
      final RagHarness harness = RagHarness();
      await showAnswer(harness, <RagSource>[sourceFor(ownedNote())]);
      harness.gateway.consentScript
        ..clear()
        ..add(RagConsent(accepted: true, generation: 1));

      await harness.service.refreshConsent();

      expect(harness.service.state.result, isNotNull);
      expect(harness.service.state.resultQuestion, 'What did I decide?');
      expect(
        harness.service.state.consent,
        RagConsent(accepted: true, generation: 1),
      );
    });

    test('a moved grant clears the displayed answer', () async {
      final RagHarness harness = RagHarness();
      await showAnswer(harness, <RagSource>[sourceFor(ownedNote())]);
      harness.gateway.consentScript
        ..clear()
        ..add(RagConsent(accepted: true, generation: 2));

      await harness.service.refreshConsent();

      expect(
        harness.service.state.consent,
        RagConsent(accepted: true, generation: 2),
      );
      expect(harness.service.state.result, isNull);
      expect(harness.service.state.resultQuestion, isNull);
    });

    test('an unknown grant clears the displayed answer', () async {
      final RagHarness harness = RagHarness();
      await showAnswer(harness, <RagSource>[sourceFor(ownedNote())]);
      harness.gateway.consentScript
        ..clear()
        ..add(const RagFailure(RagFailureCode.providerUnavailable));

      await harness.service.refreshConsent();

      expect(harness.service.state.consent, isNull);
      expect(harness.service.state.result, isNull);
      expect(harness.service.state.resultQuestion, isNull);
      expect(
        harness.service.state.failure?.code,
        RagFailureCode.providerUnavailable,
      );
    });

    test('a grant that moved during a run clears the old answer', () async {
      final LocalNoteState note = ownedNote();
      final RagHarness harness = RagHarness(
        queryScript: <Object>[
          answeredResult(<RagSource>[sourceFor(note)]),
        ],
      );
      await harness.grant();
      await harness.service.ask(
        question: 'First?',
        scope: const RagScope.account(),
      );
      expect(harness.service.state.result, isNotNull);

      harness.gateway.consentScript
        ..clear()
        ..addAll(<Object>[
          RagConsent(accepted: true, generation: 1),
          RagConsent(accepted: true, generation: 2),
        ]);
      await harness.service.ask(
        question: 'Second?',
        scope: const RagScope.account(),
      );

      expect(harness.service.state.failure?.code, RagFailureCode.consentRequired);
      expect(
        harness.service.state.consent,
        RagConsent(accepted: true, generation: 2),
      );
      expect(harness.service.state.result, isNull);
      expect(harness.service.state.resultQuestion, isNull);
    });

    test('a fresh re-grant with a new generation clears the old answer',
        () async {
      final RagHarness harness = RagHarness();
      await showAnswer(harness, <RagSource>[sourceFor(ownedNote())]);
      harness.gateway.writeScript.add(
        RagConsent(accepted: true, generation: 2),
      );

      await harness.service.setConsent(true);

      expect(harness.service.state.result, isNull);
      expect(harness.service.state.resultQuestion, isNull);
      expect(
        harness.service.state.consent,
        RagConsent(accepted: true, generation: 2),
      );
    });
  });

  group('inactivity', () {
    test('clears the answer and resume never resurrects it', () async {
      final RagHarness harness = RagHarness();
      await showAnswer(harness, <RagSource>[sourceFor(ownedNote())]);
      expect(harness.service.state.result, isNotNull);

      harness.service.onInactive();

      expect(harness.service.state.active, isFalse);
      expect(harness.service.state.result, isNull);
      expect(harness.service.state.resultQuestion, isNull);

      harness.gateway.consentScript
        ..clear()
        ..add(RagConsent(accepted: true, generation: 1));
      await harness.service.onResume();

      expect(harness.service.state.active, isTrue);
      expect(harness.service.state.consentAccepted, isTrue);
      expect(harness.service.state.result, isNull);
      expect(harness.service.state.resultQuestion, isNull);
      expect(harness.gateway.requests, hasLength(1));
    });

    test('a resumed grant cannot make an old source clickable again', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      final RagSource source = displayed.sources.single;
      displayed.harness.service.onInactive();
      displayed.harness.gateway.consentScript
        ..clear()
        ..add(RagConsent(accepted: true, generation: 1));

      await displayed.harness.service.onResume();

      expect(displayed.harness.service.state.result, isNull);
      await expectLater(
        displayed.harness.service.validateSource(source),
        throwsFailure(RagFailureCode.sourceChanged),
      );
    });
  });

  group('logout', () {
    test('never writes a revoke and leaves nothing displayed', () async {
      final RagHarness harness = RagHarness();
      await showAnswer(harness, <RagSource>[sourceFor(ownedNote())]);

      harness.service.invalidateSession();

      expect(harness.gateway.calls, isNot(contains('updateConsent')));
      expect(harness.service.state.consent, isNull);
      expect(harness.service.state.result, isNull);
      expect(harness.service.state.resultQuestion, isNull);
      expect(harness.service.state.scope, isNull);
    });
  });
}
