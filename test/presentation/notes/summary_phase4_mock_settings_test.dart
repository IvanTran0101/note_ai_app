/// Phase 4.5 acceptance for Settings revocation and session lifetime.
///
/// Both cases drive the real root app: the Settings sheet renders the real
/// `SummaryCloudSettingsTile` over the app's own `SummaryConsentAppService`,
/// and the sign-out/sign-in dance goes through the injected
/// `IAuthenticationAppService`, so the router, the session generation, and the
/// consent store behave exactly as they do in production.
///
/// The policy loader is the disclosed injected seam (Chrome's test harness
/// cannot read bundled assets); the tool run covers the real asset loader.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/presentation/auth/auth_pages.dart';

import '../../support/summary_phase4_app_harness.dart';
import '../../support/summary_phase4_mock_support.dart';

void main() {
  testWidgets('revoking consent in Settings makes the next run ask again', (
    WidgetTester tester,
  ) async {
    final SummaryMockEnvironment environment = await pumpMockRootApp(tester);
    await openNotesDestination(tester);
    await openSeedNote(tester, environment);
    await tapSummarize(tester);
    await answerConsent(tester, allowed: true);
    expect(environment.control.requestCount.value, 1);

    await openSettings(tester);
    final Finder consentSwitch = find.byKey(consentSwitchKey);
    expect(
      tester.widget<SwitchListTile>(consentSwitch).value,
      isTrue,
      reason: 'the grant is reflected in Settings',
    );
    await tester.ensureVisible(consentSwitch);
    await tester.pumpAndSettle();
    await tester.tap(consentSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(consentSwitch).value, isFalse);

    await dismissSheet(tester);
    await tapSummarize(tester);
    expect(
      find.byKey(consentDialogKey),
      findsOneWidget,
      reason: 'a revoked grant must be asked for again',
    );
    expect(
      environment.control.requestCount.value,
      1,
      reason: 'no request is dispatched before consent is granted again',
    );
    await answerConsent(tester, allowed: false);
    expect(environment.control.requestCount.value, 1);
  });

  testWidgets('signing out and back in drops the previous session grant', (
    WidgetTester tester,
  ) async {
    final SummaryMockEnvironment environment = await pumpMockRootApp(tester);
    await openNotesDestination(tester);
    await openSeedNote(tester, environment);
    await tapSummarize(tester);
    await answerConsent(tester, allowed: true);
    expect(environment.control.requestCount.value, 1);
    final int grantedGeneration = environment.session.sessionGeneration;

    // Sign out from the same sheet the user sees.
    await openSettings(tester);
    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    expect(environment.auth.signOutCount, 1);
    expect(environment.session.isAuthenticated, isFalse);
    expect(
      find.byKey(LoginPage.emailFieldKey),
      findsOneWidget,
      reason: 'the router returns to the public sign-in route',
    );

    // A new session for the same account is a new generation.
    await environment.auth.signIn();
    await tester.pumpAndSettle();
    expect(environment.session.isAuthenticated, isTrue);
    expect(
      environment.session.sessionGeneration,
      greaterThan(grantedGeneration),
    );

    // The note is still there, but the cloud grant died with the old session.
    await openNotesDestination(tester);
    await openSeedNote(tester, environment);
    await tapSummarize(tester);
    expect(find.byKey(consentDialogKey), findsOneWidget);
    expect(environment.control.requestCount.value, 1);
    await answerConsent(tester, allowed: true);
    expect(environment.control.requestCount.value, 2);
  });
}
