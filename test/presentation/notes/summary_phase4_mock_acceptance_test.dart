/// Phase 4.5 acceptance over the real production root (`NoteFlowApp`).
///
/// Every case pumps the actual composition — real router, workspace, notes
/// controller, consent service, Summary runtime, and asset-declared policy —
/// over the in-memory mock transport. No provider, network, or credential is
/// involved. The fixture root disables background sync, independently of any
/// compile-time endpoint values, so bare targeted test commands remain safe.
///
/// The policy loader is the one injected seam: Chrome's `flutter test` harness
/// cannot read bundled assets (Flutter #159879), so these cases use the
/// existing `loadSummaryTestPolicy` helper while the tool entrypoint loads the
/// real `assets/summary_policy.json` through `SummaryRequestPolicy.load`. The
/// manual tool run is the separate evidence for the real asset path.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/presentation/notes/note_summary_feedback.dart';

import '../../support/summary_phase4_app_harness.dart';
import '../../support/summary_phase4_mock_support.dart';

void main() {
  testWidgets('the root app answers the Summary UI in English by default', (
    WidgetTester tester,
  ) async {
    final SummaryMockEnvironment environment = await pumpMockRootApp(tester);

    await openNotesDestination(tester);
    await openSeedNote(tester, environment);

    // The embedded editor shows the Summary action as an icon with a tooltip,
    // so the label is asserted through the tooltip rather than a button text.
    expect(find.byTooltip('Summarize'), findsOneWidget);
    expect(
      find.text('No summary yet. Select Summarize to create one.'),
      findsOneWidget,
    );
    expect(find.text('Cloud summary permission is required.'), findsOneWidget);
    expect(find.byKey(NoteSummaryFeedback.availabilityKey), findsOneWidget);
  });

  testWidgets('Settings switches the whole app, including summary copy, to '
      'Vietnamese', (WidgetTester tester) async {
    final SummaryMockEnvironment environment = await pumpMockRootApp(tester);

    await openNotesDestination(tester);
    await openSeedNote(tester, environment);
    expect(find.byTooltip('Summarize'), findsOneWidget);

    await openSettings(tester);
    expect(find.text('Cloud summaries'), findsOneWidget);
    await selectLanguage(tester, 'Vietnamese');
    // The tile resolves its copy inside its own build, so the open sheet
    // retranslates with the app locale.
    expect(find.text('Tóm tắt trên đám mây'), findsOneWidget);

    await dismissSheet(tester);
    expect(find.byTooltip('Tóm tắt'), findsOneWidget);
    expect(
      find.text('Chưa có tóm tắt. Chọn Tóm tắt để tạo một bản.'),
      findsOneWidget,
    );
    expect(find.text('Cần quyền tóm tắt trên đám mây.'), findsOneWidget);
  });

  testWidgets('declining the consent dialog sends no request and leaves the '
      'action available', (WidgetTester tester) async {
    final SummaryMockEnvironment environment = await pumpMockRootApp(tester);
    await openNotesDestination(tester);
    await openSeedNote(tester, environment);

    await tapSummarize(tester);
    expect(find.byKey(consentDialogKey), findsOneWidget);

    await answerConsent(tester, allowed: false);
    expect(find.byKey(consentDialogKey), findsNothing);
    expect(environment.control.requestCount.value, 0);
    expect(environment.client.requests, isEmpty);
    expectNoSummary();
    // Still offered: declining is not a dead end.
    expect(find.byKey(NoteSummaryFeedback.availabilityKey), findsOneWidget);

    await tapSummarize(tester);
    expect(find.byKey(consentDialogKey), findsOneWidget);
    await answerConsent(tester, allowed: false);
  });

  testWidgets('allowing consent runs exactly one direct request and shows the '
      'served summary', (WidgetTester tester) async {
    final SummaryMockEnvironment environment = await pumpMockRootApp(tester);
    await openNotesDestination(tester);
    await openSeedNote(tester, environment);

    await tapSummarize(tester);
    await answerConsent(tester, allowed: true);

    expect(environment.control.requestCount.value, 1);
    final SummaryMockRequest request = environment.client.requests.single;
    expect(request.stage, 'direct');
    expect(request.inputs.single, summaryMockNoteContent);
    expect(request.consentAccepted, isTrue);
    expect(
      visibleSummaryText(tester),
      summaryMockText('direct', 1),
      reason: tester.allWidgets
          .whereType<Text>()
          .map((widget) => widget.data)
          .whereType<String>()
          .join(' | '),
    );
    expect(find.byKey(regenerateKey), findsOneWidget);
    expect(
      environment.activeStore.state.notes.single.content,
      summaryMockNoteContent,
    );

    // The grant is visible in Settings and survives until it is revoked.
    await openSettings(tester);
    expect(
      tester.widget<SwitchListTile>(find.byKey(consentSwitchKey)).value,
      isTrue,
    );
  });

  testWidgets('cancelling a pending run aborts the mock request and keeps the '
      'accepted summary', (WidgetTester tester) async {
    final SummaryMockEnvironment environment = await pumpMockRootApp(tester);
    await openNotesDestination(tester);
    await openSeedNote(tester, environment);

    await tapSummarize(tester);
    await answerConsent(tester, allowed: true);
    expect(visibleSummaryText(tester), summaryMockText('direct', 1));

    // The second run is held by the transport, so it can be cancelled.
    environment.control.mode.value = SummaryMockMode.delayed;
    await tapSummarizeWhileRunning(tester);
    expect(find.byKey(NoteSummaryFeedback.cancelKey), findsOneWidget);
    expect(environment.client.hasPendingCall, isTrue);

    await tester.tap(find.byKey(NoteSummaryFeedback.cancelKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(NoteSummaryFeedback.cancelKey), findsNothing);
    expect(find.byKey(NoteSummaryFeedback.progressKey), findsNothing);

    // The abort has already ended this held call; releasing it cannot replace
    // the accepted result. Late successful replies are covered by controller tests.
    environment.client.releaseHeld();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(environment.control.requestCount.value, 2);
    expect(visibleSummaryText(tester), summaryMockText('direct', 1));
    expect(
      environment.activeStore.state.notes.single.content,
      summaryMockNoteContent,
    );
    expect(environment.activeStore.state.notes.single.title, 'Mock note');
  });

  testWidgets('a failed regenerate keeps the summary, the note, and does not '
      'write storage', (WidgetTester tester) async {
    final SummaryMockEnvironment environment = await pumpMockRootApp(tester);
    await openNotesDestination(tester);
    await openSeedNote(tester, environment);
    await tapSummarize(tester);
    await answerConsent(tester, allowed: true);
    expect(visibleSummaryText(tester), summaryMockText('direct', 1));

    final int writesBefore = environment.activeStore.writeCount;
    environment.control.mode.value = SummaryMockMode.providerUnavailable;
    await tester.tap(find.byKey(regenerateKey));
    await settleRun(tester);

    expect(environment.control.requestCount.value, 2);
    expectSummaryFailureRow();
    expect(visibleSummaryText(tester), summaryMockText('direct', 1));
    expect(
      environment.activeStore.state.notes.single.content,
      summaryMockNoteContent,
    );
    expect(environment.activeStore.writeCount, writesBefore);
  });
}
