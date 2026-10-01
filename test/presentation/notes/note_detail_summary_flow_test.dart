import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/note_intelligence/summary_cloud_consent.dart';
import 'package:note_ai_app/application/note_intelligence/summary_consent_app_service.dart';
import 'package:note_ai_app/application/note_intelligence/summary_run_context.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/presentation/notes/note_detail_localizations.dart';
import 'package:note_ai_app/presentation/notes/note_detail_page.dart';
import 'package:note_ai_app/presentation/notes/note_summary_feedback.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';

part 'note_detail_summary_flow_test_support.dart';

const ValueKey<String> _summarizeKey = ValueKey<String>(
  'note-detail-summarize',
);
const ValueKey<String> _regenerateKey = ValueKey<String>(
  'note-detail-regenerate-summary',
);
const ValueKey<String> _retryKey = ValueKey<String>('note-detail-error-retry');
const ValueKey<String> _dialogKey = ValueKey<String>('summary-consent-dialog');
const ValueKey<String> _allowKey = ValueKey<String>('summary-consent-allow');
const ValueKey<String> _declineKey = ValueKey<String>('summary-consent-cancel');

void main() {
  testWidgets('reverting a draft adopts an incoming saved revision', (
    WidgetTester tester,
  ) async {
    final _Harness harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester, note: _note());
    await tester.enterText(find.byKey(NoteDetailPage.contentFieldKey), 'Draft');
    final NoteDto latest = _note(content: 'New saved revision');
    harness.notes.notes[0] = latest;
    await harness.pump(tester, note: latest);
    expect(
      tester
          .widget<TextField>(find.byKey(NoteDetailPage.contentFieldKey))
          .controller!
          .text,
      'Draft',
    );
    await tester.enterText(
      find.byKey(NoteDetailPage.contentFieldKey),
      'Saved synthetic body',
    );
    await tester.pumpAndSettle();
    await _tapSummarize(tester);
    expect(harness.notes.lastSnapshot, latest);
    expect(find.text('Summary of New saved revision'), findsOneWidget);
  });

  testWidgets('a required disclosure stays actionable and declining is inert', (
    WidgetTester tester,
  ) async {
    final _Harness harness = _Harness(cloudConsent: true);
    addTearDown(harness.dispose);
    await harness.pump(tester, note: _note());

    expect(find.text('Cloud summary permission is required.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(_summarizeKey)).onPressed,
      isNotNull,
    );

    await _tapSummarize(tester);
    expect(find.byKey(_dialogKey), findsOneWidget);
    await tester.tap(find.byKey(_declineKey));
    await tester.pumpAndSettle();

    expect(find.byKey(_dialogKey), findsNothing);
    expect(harness.store.generation, 0);
    expect(harness.notes.summarizeCalls, 0);
    expect(find.byKey(NoteDetailPage.summaryKey), findsNothing);
    expect(find.text('Cloud summary permission is required.'), findsOneWidget);
  });

  testWidgets('accepting grants once, dispatches once, and caches the grant', (
    WidgetTester tester,
  ) async {
    final _Harness harness = _Harness(cloudConsent: true);
    addTearDown(harness.dispose);
    await harness.pump(tester, note: _note());

    await _tapSummarize(tester);
    await tester.tap(find.byKey(_allowKey));
    await tester.pumpAndSettle();

    expect(harness.store.generation, greaterThan(0));
    expect(harness.notes.summarizeCalls, 1);
    expect(harness.notes.lastSnapshot, _note());
    expect(find.byKey(NoteDetailPage.summaryKey), findsOneWidget);
    expect(
      harness.store
          .capture(
            accountUserId: 'account-a',
            sessionGeneration: harness.session.sessionGeneration,
          )
          .isGranted,
      isTrue,
    );

    await _tapSummarize(tester);
    expect(find.byKey(_dialogKey), findsNothing);
    expect(harness.notes.summarizeCalls, 2);
  });

  testWidgets('cancel is visible for the whole run and discards its result', (
    WidgetTester tester,
  ) async {
    final _Harness harness = _Harness();
    addTearDown(harness.dispose);
    harness.notes.pending = Completer<String>();
    await harness.pump(tester, note: _note());

    await tester.tap(find.byKey(_summarizeKey));
    await tester.pump();
    expect(find.byKey(NoteSummaryFeedback.progressKey), findsOneWidget);
    expect(find.byKey(NoteSummaryFeedback.cancelKey), findsOneWidget);

    await tester.tap(find.byKey(NoteSummaryFeedback.cancelKey));
    await tester.pump();
    expect(find.byKey(NoteSummaryFeedback.cancelKey), findsNothing);
    expect(find.text('The local summary was cancelled.'), findsOneWidget);

    harness.notes.pending!.complete('Late result');
    await tester.pump();
    expect(find.byKey(NoteDetailPage.summaryKey), findsNothing);
    expect(find.text('Late result'), findsNothing);
    expect(harness.notes.notes.single.content, 'Saved synthetic body');
  });

  testWidgets(
    'a draft and a dirty editor explain why summarize is unavailable',
    (WidgetTester tester) async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);
      await harness.pump(tester);

      expect(find.byKey(NoteSummaryFeedback.availabilityKey), findsOneWidget);
      expect(find.text('Save the note before summarizing.'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(_summarizeKey)).onPressed,
        isNull,
      );

      await tester.enterText(find.byKey(NoteDetailPage.titleFieldKey), 'Draft');
      await tester.pump();
      expect(find.text('Save the note before summarizing.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(harness.notes.notes, hasLength(1));
      expect(find.byKey(NoteSummaryFeedback.availabilityKey), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byKey(_summarizeKey)).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('an unavailable cloud runtime keeps note CRUD usable', (
    WidgetTester tester,
  ) async {
    final _Harness harness = _Harness(cloudConsent: true, available: false);
    addTearDown(harness.dispose);
    await harness.pump(tester, note: _note());

    expect(
      find.text('Cloud summaries are not available right now.'),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byKey(_summarizeKey)).onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(NoteDetailPage.contentFieldKey),
      'Edited without summaries',
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(harness.notes.notes.single.content, 'Edited without summaries');
    expect(harness.notes.summarizeCalls, 0);
    expect(harness.store.generation, 0);
  });

  testWidgets('a rate-limit hint counts down before retry is offered again', (
    WidgetTester tester,
  ) async {
    final _Harness harness = _Harness();
    addTearDown(harness.dispose);
    harness.notes.failure = const SummaryRunFailure(
      SummaryRunFailureCode.rateLimited,
      retryAfterSeconds: 3,
    );
    await harness.pump(tester, note: _note());

    await tester.tap(find.byKey(_summarizeKey));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Too many requests. Please try again later.'),
      findsOneWidget,
    );
    expect(find.text('Try again in 3 seconds.'), findsOneWidget);
    expect(tester.widget<TextButton>(find.byKey(_retryKey)).onPressed, isNull);
    expect(
      tester.widget<FilledButton>(find.byKey(_summarizeKey)).onPressed,
      isNull,
    );

    await tester.tap(find.byKey(_retryKey));
    await tester.pump();
    expect(harness.notes.summarizeCalls, 1);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Try again in 2 seconds.'), findsOneWidget);

    harness.notes.failure = null;
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester.widget<TextButton>(find.byKey(_retryKey)).onPressed,
      isNotNull,
    );

    await tester.ensureVisible(find.byKey(_retryKey));
    await tester.tap(find.byKey(_retryKey));
    await tester.pumpAndSettle();
    expect(find.byKey(NoteDetailPage.summaryKey), findsOneWidget);
    expect(harness.notes.summarizeCalls, 2);
  });

  testWidgets('a failed regenerate keeps the previous summary displayed', (
    WidgetTester tester,
  ) async {
    final _Harness harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester, note: _note());

    await _tapSummarize(tester);
    expect(find.byKey(NoteDetailPage.summaryKey), findsOneWidget);
    expect(find.text('Summary of Saved synthetic body'), findsOneWidget);

    harness.notes.failure = const SummaryRunFailure(
      SummaryRunFailureCode.serviceUnavailable,
    );
    await tester.ensureVisible(find.byKey(_regenerateKey));
    await tester.tap(find.byKey(_regenerateKey));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'The summary service is temporarily unavailable. Please try again.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(NoteDetailPage.summaryKey), findsOneWidget);
    expect(find.text('Summary of Saved synthetic body'), findsOneWidget);
    expect(harness.notes.lastSnapshot, _note());
  });

  testWidgets('changing the language retranslates an existing failure only', (
    WidgetTester tester,
  ) async {
    final _Harness harness = _Harness(cloudConsent: true);
    addTearDown(harness.dispose);
    harness.notes.error = StateError('synthetic-private-payload');
    await harness.pump(tester, note: _note());

    await _tapSummarize(tester);
    await tester.tap(find.byKey(_allowKey));
    await tester.pumpAndSettle();

    expect(
      find.text('Couldn’t create a summary. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('synthetic-private-payload'), findsNothing);
    final int granted = harness.store.generation;
    expect(granted, greaterThan(0));

    harness.locale.value = const Locale('vi');
    await tester.pumpAndSettle();

    expect(
      find.text('Không thể tạo tóm tắt. Vui lòng thử lại.'),
      findsOneWidget,
    );
    expect(find.byKey(_dialogKey), findsNothing);
    expect(harness.store.generation, granted);
    expect(harness.notes.summarizeCalls, 1);
  });
}
