/// Phase 4.5 native-side check for the shared local summary latch.
///
/// `flutter_test` runs with `kIsWeb == false`, so the local runtime is available
/// in this host exactly as it is on a native build, and `lib/main.dart` owns the
/// same single latch: one physical native summarization at a time, held until
/// the underlying promise finishes. Cancelling the run may discard the result,
/// but it must never queue a second physical call.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/domain/note_intelligence/summary.dart';
import 'package:note_ai_app/presentation/notes/note_detail_page.dart';
import 'package:note_ai_app/presentation/notes/note_summary_feedback.dart';

import '../../support/summary_phase4_app_harness.dart';
import '../../support/summary_phase4_mock_support.dart';

void main() {
  testWidgets('cancel and page change cannot queue a second physical native '
      'call while the first promise is pending', (WidgetTester tester) async {
    final List<Completer<Summary>> calls = <Completer<Summary>>[];
    final SummaryMockEnvironment environment = await pumpMockRootApp(
      tester,
      localRuntime: true,
      localSummarizer: (String content) {
        final Completer<Summary> call = Completer<Summary>();
        calls.add(call);
        return call.future;
      },
    );
    await openNotesDestination(tester);
    await openSeedNote(tester, environment);

    // Local composition asks for no cloud consent.
    expect(find.byKey(consentDialogKey), findsNothing);
    await tapSummarizeWhileRunning(tester);
    expect(calls, hasLength(1));
    expect(find.byKey(NoteSummaryFeedback.cancelKey), findsOneWidget);

    // Cancel returns the UI to idle while the native promise keeps running.
    await tester.tap(find.byKey(NoteSummaryFeedback.cancelKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(NoteSummaryFeedback.progressKey), findsNothing);

    // A retry is refused by the shared latch instead of starting native work.
    await tapSummarizeWhileRunning(tester);
    expect(
      calls,
      hasLength(1),
      reason: 'cancel must not queue physical native work',
    );
    expectSummaryFailureRow();

    // Leaving and re-entering the editor does not release the latch either.
    await tester.tap(find.byKey(NoteDetailPage.backKey));
    await tester.pumpAndSettle();
    await openSeedNote(tester, environment);
    await tapSummarizeWhileRunning(tester);
    expect(calls, hasLength(1));

    // Finishing the first promise releases the latch; its late answer is
    // discarded because the run that owned it was cancelled.
    calls.single.complete(const Summary('MOCK LOCAL #1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expectNoSummary();
    expect(
      environment.activeStore.state.notes.single.content,
      summaryMockNoteContent,
    );

    // Now a fresh run is allowed and its result is shown.
    await tapSummarizeWhileRunning(tester);
    expect(calls, hasLength(2));
    calls.last.complete(const Summary('MOCK LOCAL #2'));
    await settleRun(tester);

    expect(visibleSummaryText(tester), 'MOCK LOCAL #2');
    expect(
      environment.activeStore.state.notes.single.content,
      summaryMockNoteContent,
    );
  }, skip: kIsWeb);
}
