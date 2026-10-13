import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';

import 'rag_widget_harness.dart';

const Key _allowKey = ValueKey<String>('rag-consent-allow');
const Key _cancelKey = ValueKey<String>('rag-consent-cancel');
const Key _dialogKey = ValueKey<String>('rag-consent-dialog');

AuthIdentity _identity(String userId) => AuthIdentity(
  userId: userId,
  email: '$userId@example.test',
  isEmailVerified: true,
);

/// A tile that denied consent, so an Allow must consult the CAS write path.
RagPresentationHarness _ungrantedHarness() {
  return RagPresentationHarness(consentScript: <Object>[RagConsent.none]);
}

void main() {
  testWidgets('a live account change while the dialog is open grants nothing', (
    WidgetTester tester,
  ) async {
    final RagPresentationHarness harness = _ungrantedHarness();
    await pumpRagConsentTile(tester, harness);
    await tapRagConsentSwitch(tester);
    expect(find.byKey(_dialogKey), findsOneWidget);

    // The user signs into a different account while the disclosure is open.
    harness.session.setIdentity(_identity('user-2'));

    await tester.tap(find.byKey(_allowKey));
    await tester.pumpAndSettle();

    expect(find.byKey(_dialogKey), findsNothing);
    expect(harness.gateway.updates, isEmpty);
    expect(ragConsentSwitchValue(tester), isFalse);
  });

  testWidgets('a sign-out and sign-in of the same user grants nothing', (
    WidgetTester tester,
  ) async {
    final RagPresentationHarness harness = _ungrantedHarness();
    await pumpRagConsentTile(tester, harness);
    await tapRagConsentSwitch(tester);
    expect(find.byKey(_dialogKey), findsOneWidget);

    // Same account id returns, but it is a new session generation.
    harness.session.clear();
    harness.session.setIdentity(_identity('user-1'));

    await tester.tap(find.byKey(_allowKey));
    await tester.pumpAndSettle();

    expect(harness.gateway.updates, isEmpty);
    expect(ragConsentSwitchValue(tester), isFalse);
  });

  testWidgets('replacing the widget service while the dialog is open grants '
      'nothing on either service', (WidgetTester tester) async {
    final RagPresentationHarness first = _ungrantedHarness();
    await pumpRagConsentTile(tester, first);
    await tapRagConsentSwitch(tester);
    expect(find.byKey(_dialogKey), findsOneWidget);

    final RagPresentationHarness second = _ungrantedHarness();
    await pumpRagConsentTile(tester, second);
    expect(find.byKey(_dialogKey), findsOneWidget);

    await tester.tap(find.byKey(_allowKey));
    await tester.pumpAndSettle();

    expect(first.gateway.updates, isEmpty);
    expect(second.gateway.updates, isEmpty);
  });

  testWidgets('an inactive app before Allow grants nothing', (
    WidgetTester tester,
  ) async {
    final RagPresentationHarness harness = _ungrantedHarness();
    await pumpRagConsentTile(tester, harness);
    await tapRagConsentSwitch(tester);
    expect(find.byKey(_dialogKey), findsOneWidget);

    harness.service.onInactive();

    await tester.tap(find.byKey(_allowKey));
    await tester.pumpAndSettle();

    expect(harness.gateway.updates, isEmpty);
  });

  testWidgets('an unchanged binding still writes exactly one grant', (
    WidgetTester tester,
  ) async {
    final RagPresentationHarness harness = _ungrantedHarness();
    await pumpRagConsentTile(tester, harness);
    await tapRagConsentSwitch(tester);

    await tester.tap(find.byKey(_allowKey));
    await tester.pumpAndSettle();

    expect(harness.gateway.updates, hasLength(1));
    expect(harness.gateway.updates.single.accepted, isTrue);
    expect(ragConsentSwitchValue(tester), isTrue);
  });

  testWidgets('a locale change while the dialog is open retranslates it', (
    WidgetTester tester,
  ) async {
    final RagPresentationHarness harness = _ungrantedHarness();
    await pumpRagConsentTile(tester, harness, locale: const Locale('en'));
    await tapRagConsentSwitch(tester);
    expect(find.text('Allow asking your notes?'), findsOneWidget);

    await pumpRagConsentTile(tester, harness, locale: const Locale('vi'));
    await tester.pumpAndSettle();

    expect(find.byKey(_dialogKey), findsOneWidget);
    expect(find.text('Cho phép hỏi ghi chú?'), findsOneWidget);

    await tester.tap(find.byKey(_cancelKey));
    await tester.pumpAndSettle();
    expect(harness.gateway.updates, isEmpty);
  });
}
