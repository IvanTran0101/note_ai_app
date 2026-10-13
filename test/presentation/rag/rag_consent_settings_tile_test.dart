import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';
import 'package:note_ai_app/presentation/rag/rag_consent_settings_tile.dart';

import 'rag_widget_harness.dart';

const Key _allowKey = ValueKey<String>('rag-consent-allow');
const Key _cancelKey = ValueKey<String>('rag-consent-cancel');
const Key _dialogKey = ValueKey<String>('rag-consent-dialog');

void main() {
  testWidgets('shows unknown state with no automatic read or grant', (
    WidgetTester tester,
  ) async {
    final RagPresentationHarness harness = RagPresentationHarness();
    await pumpRagConsentTile(tester, harness);

    expect(ragConsentSwitchValue(tester), isFalse);
    expect(find.byKey(RagConsentSettingsTile.refreshKey), findsOneWidget);
    expect(find.byKey(RagConsentSettingsTile.statusKey), findsOneWidget);
    expect(harness.gateway.calls, isEmpty);
    expect(harness.gateway.updates, isEmpty);
  });

  testWidgets('manual refresh performs one consent read and no query', (
    WidgetTester tester,
  ) async {
    final RagPresentationHarness harness = RagPresentationHarness();
    harness.gateway.consentScript.add(
      RagConsent(accepted: true, generation: 1),
    );
    await pumpRagConsentTile(tester, harness);

    await tester.tap(find.byKey(RagConsentSettingsTile.refreshKey));
    await tester.pumpAndSettle();

    expect(harness.gateway.calls, contains('readConsent'));
    expect(harness.gateway.calls, isNot(contains('query')));
    expect(ragConsentSwitchValue(tester), isTrue);
  });

  testWidgets('turning on requires an explicit Allow; Cancel grants nothing', (
    WidgetTester tester,
  ) async {
    final RagPresentationHarness harness = RagPresentationHarness(
      consentScript: <Object>[RagConsent.none],
    );
    await pumpRagConsentTile(tester, harness);

    await tapRagConsentSwitch(tester);
    expect(find.byKey(_dialogKey), findsOneWidget);
    expect(find.textContaining('Cohere'), findsOneWidget);

    await tester.tap(find.byKey(_cancelKey));
    await tester.pumpAndSettle();

    expect(find.byKey(_dialogKey), findsNothing);
    expect(harness.gateway.updates, isEmpty);
    expect(ragConsentSwitchValue(tester), isFalse);
  });

  testWidgets('explicit Allow writes the accepted grant', (
    WidgetTester tester,
  ) async {
    final RagPresentationHarness harness = RagPresentationHarness(
      consentScript: <Object>[RagConsent.none],
    );
    await pumpRagConsentTile(tester, harness);

    await tapRagConsentSwitch(tester);
    await tester.tap(find.byKey(_allowKey));
    await tester.pumpAndSettle();

    expect(harness.gateway.updates, hasLength(1));
    expect(harness.gateway.updates.single.accepted, isTrue);
    expect(ragConsentSwitchValue(tester), isTrue);
  });

  testWidgets('turning off revokes immediately and clears the answer', (
    WidgetTester tester,
  ) async {
    final LocalNoteState note = ownedNote();
    final RagSource source = sourceFor(note);
    final RagPresentationHarness harness = RagPresentationHarness(
      local: localState(notes: <LocalNoteState>[note]),
    );
    await harness.grant();
    harness.gateway.queryScript.add(
      answeredResult(<RagSource>[source], answer: 'Answer'),
    );
    await harness.service.ask(
      question: 'Q',
      scope: const RagScope.account(),
    );
    expect(harness.service.state.result, isNotNull);

    await pumpRagConsentTile(tester, harness);
    expect(ragConsentSwitchValue(tester), isTrue);

    await tester.tap(find.byKey(RagConsentSettingsTile.switchKey));
    await tester.pumpAndSettle();

    expect(harness.gateway.updates.single.accepted, isFalse);
    expect(harness.service.state.result, isNull);
    expect(ragConsentSwitchValue(tester), isFalse);
  });

  testWidgets('a failed read keeps the grant unknown and offers refresh', (
    WidgetTester tester,
  ) async {
    final RagPresentationHarness harness = RagPresentationHarness();
    final Completer<RagConsent> pending = Completer<RagConsent>();
    harness.gateway.pendingConsentRead = pending;
    await pumpRagConsentTile(tester, harness);

    await tester.tap(find.byKey(RagConsentSettingsTile.refreshKey));
    await tester.pump();

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(RagConsentSettingsTile.switchKey),
          )
          .onChanged,
      isNull,
    );

    pending.completeError(const RagFailure(RagFailureCode.network));
    await tester.pumpAndSettle();

    expect(find.byKey(RagConsentSettingsTile.errorKey), findsOneWidget);
    expect(find.byKey(RagConsentSettingsTile.refreshKey), findsOneWidget);
    expect(ragConsentSwitchValue(tester), isFalse);
  });

  testWidgets('a locale change retranslates without resetting the grant', (
    WidgetTester tester,
  ) async {
    final RagPresentationHarness harness = RagPresentationHarness();
    await pumpRagConsentTile(tester, harness, locale: const Locale('en'));
    await harness.grant();
    await tester.pumpAndSettle();

    expect(ragConsentSwitchValue(tester), isTrue);
    expect(find.text('Ask-notes permission'), findsOneWidget);

    await pumpRagConsentTile(tester, harness, locale: const Locale('vi'));

    expect(ragConsentSwitchValue(tester), isTrue);
    expect(find.text('Quyền hỏi ghi chú'), findsOneWidget);
  });

  testWidgets('tile disposal never cancels a question owned by another screen', (
    WidgetTester tester,
  ) async {
    final RagPresentationHarness harness = RagPresentationHarness();
    await harness.grant();
    final Completer<RagResult> pending = Completer<RagResult>();
    harness.gateway.pendingQuery = pending;
    await pumpRagConsentTile(tester, harness);

    final Future<void> run = harness.service.ask(
      question: 'pending',
      scope: const RagScope.account(),
    );
    await tester.pump();
    expect(harness.service.state.queryRunning, isTrue);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(harness.service.state.queryRunning, isTrue);
    pending.complete(notEnoughContextResult());
    await run;
    expect(tester.takeException(), isNull);
  });
}
