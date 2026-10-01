/// Shared widget-test harness for the Phase 4.5 mock acceptance runs.
///
/// It pumps the real production root (`NoteFlowApp`) over the offline mock
/// environment. The policy loader is injected as the existing
/// `loadSummaryTestPolicy` helper on purpose: Chrome's `flutter test` harness
/// cannot read bundled assets (Flutter #159879), while the tool entrypoint does
/// use the real asset loader. That difference is evidence, not a shortcut.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/main.dart';
import 'package:note_ai_app/presentation/notes/note_summary_feedback.dart';
import 'package:note_ai_app/presentation/workspace/workspace_shell.dart';

import '../infrastructure/note_intelligence/summary_policy_test_support.dart';
import 'summary_phase4_mock_support.dart';

/// The primary Summary action in the editor action bar.
const ValueKey<String> summarizeKey = ValueKey<String>('note-detail-summarize');

/// The regenerate action shown once a summary is displayed.
const ValueKey<String> regenerateKey = ValueKey<String>(
  'note-detail-regenerate-summary',
);

/// The explicit retry next to a presented Summary failure.
const ValueKey<String> summaryRetryKey = ValueKey<String>(
  'note-detail-error-retry',
);

/// The typewriter body of the displayed summary.
const ValueKey<String> summaryTextKey = ValueKey<String>(
  'note-detail-summary-text',
);

/// The inline editor status line (`summarized`, `summaryCancelExplanation`).
const ValueKey<String> statusKey = ValueKey<String>('note-detail-status');

/// The consent dialog and its two actions.
const ValueKey<String> consentDialogKey = ValueKey<String>(
  'summary-consent-dialog',
);
const ValueKey<String> consentAllowKey = ValueKey<String>(
  'summary-consent-allow',
);
const ValueKey<String> consentDeclineKey = ValueKey<String>(
  'summary-consent-cancel',
);

/// The Settings switch that grants or revokes cloud summarization.
const ValueKey<String> consentSwitchKey = ValueKey<String>(
  'summary-cloud-consent-switch',
);

/// The note title field of the open editor.
const ValueKey<String> titleFieldKey = ValueKey<String>(
  'note-detail-title-field',
);

/// Pumps the production root app over a fresh offline mock environment.
///
/// The default surface is wide enough for the expanded workspace sidebar, so
/// every test drives the same desktop composition the manual smoke uses.
Future<SummaryMockEnvironment> pumpMockRootApp(
  WidgetTester tester, {
  Size size = const Size(1400, 1000),
  Duration delay = const Duration(seconds: 30),
  bool localRuntime = false,
  SummarizeNoteContent? localSummarizer,
  String locale = 'en',
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.localeTestValue = Locale(locale);
  addTearDown(tester.platformDispatcher.clearLocaleTestValue);

  final SummaryMockEnvironment environment = createSummaryMockEnvironment(
    loadPolicy: loadSummaryTestPolicy,
    delay: delay,
    localRuntime: localRuntime,
  );
  addTearDown(environment.dispose);

  await tester.pumpWidget(
    NoteFlowApp(
      authController: environment.authController,
      currentUserSession: environment.session,
      summaryRuntime: environment.runtime,
      localSyncStoreFactory: environment.storeFor,
      localSummarizer: localSummarizer,
      enableSync: false,
    ),
  );
  await tester.pumpAndSettle();
  return environment;
}

/// Opens the Notes destination of the workspace shell.
Future<void> openNotesDestination(WidgetTester tester) async {
  await tester.tap(find.byKey(WorkspaceShell.notesDestinationKey));
  await tester.pumpAndSettle();
}

/// Opens the one synthetic note the mock account store holds.
Future<void> openSeedNote(
  WidgetTester tester,
  SummaryMockEnvironment environment,
) async {
  await tester.tap(
    find.byKey(ValueKey<String>('note-${environment.seedNoteId}')),
  );
  await tester.pumpAndSettle();
}

/// Opens the appearance/language settings sheet.
Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(WorkspaceShell.settingsKey));
  await tester.pumpAndSettle();
}

/// The language dropdown of the settings sheet.
///
/// Its value type is private to `lib/main.dart`, so it is matched as "the
/// dropdown that is not the theme one" instead of naming that type.
Finder languageDropdown() => find.byWidgetPredicate(
  (Widget widget) =>
      widget is DropdownButtonFormField<Object?> &&
      widget.key is! ValueKey<ThemeMode>,
);

/// Selects [label] in the open settings language dropdown.
Future<void> selectLanguage(WidgetTester tester, String label) async {
  await tester.tap(languageDropdown());
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// Dismisses the open modal sheet through its barrier.
Future<void> dismissSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(4, 4));
  await tester.pumpAndSettle();
}

/// Taps the primary Summary action.
Future<void> tapSummarize(WidgetTester tester) async {
  await tester.tap(find.byKey(summarizeKey));
  await tester.pumpAndSettle();
}

/// Taps the primary Summary action without settling an active progress row.
Future<void> tapSummarizeWhileRunning(WidgetTester tester) async {
  await tester.tap(find.byKey(summarizeKey));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

/// Settles a run: short pumps first, so an indeterminate progress row cannot
/// keep `pumpAndSettle` spinning.
Future<void> settleRun(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pumpAndSettle();
}

/// Answers the consent dialog with [allowed].
Future<void> answerConsent(WidgetTester tester, {required bool allowed}) async {
  await tester.tap(find.byKey(allowed ? consentAllowKey : consentDeclineKey));
  await settleRun(tester);
}

/// The exact `NoteDto` the mock store persists for the seeded note.
NoteDto seedSnapshot(SummaryMockEnvironment environment) {
  final LocalNoteState note = environment.activeStore.state.notes.first;
  return NoteDto(
    id: note.id,
    ownerId: note.ownerId,
    title: note.title,
    content: note.content,
    createdAt: note.createdAt,
    updatedAt: note.updatedAt,
  );
}

/// The text the typewriter has revealed so far.
String? visibleSummaryText(WidgetTester tester) {
  final Finder finder = find.byKey(summaryTextKey);
  if (finder.evaluate().isEmpty) {
    return null;
  }
  return tester.widget<SelectableText>(finder).data;
}

/// Asserts the Summary failure row is presented with retry.
void expectSummaryFailureRow() {
  expect(find.byKey(summaryRetryKey), findsOneWidget);
}

/// Asserts nothing is presented that claims a summary exists.
void expectNoSummary() {
  expect(find.byKey(summaryTextKey), findsNothing);
  expect(find.byKey(NoteSummaryFeedback.progressKey), findsNothing);
}
