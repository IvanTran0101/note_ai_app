import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/note_intelligence/summary_run_context.dart';

void main() {
  group('SummaryRunFailureCode', () {
    test('exposes exactly the Phase 3 run failure codes', () {
      expect(SummaryRunFailureCode.values, <SummaryRunFailureCode>[
        SummaryRunFailureCode.cancelled,
        SummaryRunFailureCode.alreadyRunning,
        SummaryRunFailureCode.runtimeUnavailable,
        SummaryRunFailureCode.sessionChanged,
        SummaryRunFailureCode.consentRequired,
        SummaryRunFailureCode.noteNotFound,
        SummaryRunFailureCode.noteChanged,
        SummaryRunFailureCode.conflict,
        SummaryRunFailureCode.deadlineExceeded,
      ]);
    });
  });

  group('SummaryRunFailure', () {
    test('is an exception whose toString is code-only', () {
      const SummaryRunFailure failure = SummaryRunFailure(
        SummaryRunFailureCode.noteChanged,
      );

      expect(failure, isA<Exception>());
      expect(failure.code, SummaryRunFailureCode.noteChanged);
      expect(failure.toString(), 'SummaryRunFailure(noteChanged)');
    });

    test('never carries note text or account identifiers', () {
      const String noteBody = 'private-note-body-marker';

      for (final SummaryRunFailureCode code in SummaryRunFailureCode.values) {
        final String text = SummaryRunFailure(code).toString();

        expect(text, isNot(contains(noteBody)));
        expect(text, isNot(contains('local-user')));
        expect(text, 'SummaryRunFailure(${code.name})');
      }
    });

    test('compares by code', () {
      const SummaryRunFailure cancelled = SummaryRunFailure(
        SummaryRunFailureCode.cancelled,
      );

      expect(
        cancelled,
        const SummaryRunFailure(SummaryRunFailureCode.cancelled),
      );
      expect(
        cancelled,
        isNot(const SummaryRunFailure(SummaryRunFailureCode.conflict)),
      );
      expect(
        cancelled.hashCode,
        const SummaryRunFailure(SummaryRunFailureCode.cancelled).hashCode,
      );
    });
  });

  group('SummaryRunScope', () {
    test('starts active and unreleased', () {
      final SummaryRunScope scope = SummaryRunScope();

      expect(scope.isCancelled, isFalse);
      expect(scope.cancelReason, isNull);
      expect(scope.isReleased, isFalse);
    });

    test('cancel defaults to cancelled and completes whenCancelled', () async {
      final SummaryRunScope scope = SummaryRunScope();
      bool notified = false;
      unawaited(
        scope.whenCancelled.then((void _) {
          notified = true;
        }),
      );

      await Future<void>.delayed(Duration.zero);
      expect(notified, isFalse);

      scope.cancel();

      await scope.whenCancelled;
      expect(notified, isTrue);
      expect(scope.isCancelled, isTrue);
      expect(scope.cancelReason, SummaryRunFailureCode.cancelled);
    });

    test('keeps the first cancellation reason', () async {
      final SummaryRunScope scope = SummaryRunScope()
        ..cancel(reason: SummaryRunFailureCode.sessionChanged)
        ..cancel(reason: SummaryRunFailureCode.consentRequired)
        ..cancel();

      await scope.whenCancelled;

      expect(scope.cancelReason, SummaryRunFailureCode.sessionChanged);
      expect(scope.isCancelled, isTrue);
    });

    test('a cancelled scope never becomes active again', () async {
      final SummaryRunScope scope = SummaryRunScope()
        ..cancel(reason: SummaryRunFailureCode.conflict);

      await scope.whenCancelled;
      scope.release();
      scope.release();

      expect(scope.isCancelled, isTrue);
      expect(scope.cancelReason, SummaryRunFailureCode.conflict);
      expect(scope.isReleased, isTrue);
    });

    test('release alone neither cancels nor removes a run', () {
      final SummaryRunScope scope = SummaryRunScope()..release();

      expect(scope.isReleased, isTrue);
      expect(scope.isCancelled, isFalse);
      expect(scope.cancelReason, isNull);
    });

    test('cancel after release still cancels the scope', () {
      final SummaryRunScope scope = SummaryRunScope()..release();

      scope.cancel(reason: SummaryRunFailureCode.deadlineExceeded);

      expect(scope.isReleased, isTrue);
      expect(scope.isCancelled, isTrue);
      expect(scope.cancelReason, SummaryRunFailureCode.deadlineExceeded);
    });

    test('every scope is independent', () async {
      final SummaryRunScope cancelled = SummaryRunScope()..cancel();
      final SummaryRunScope active = SummaryRunScope();

      await cancelled.whenCancelled;

      expect(cancelled.isCancelled, isTrue);
      expect(active.isCancelled, isFalse);
      expect(active.cancelReason, isNull);
    });
  });
}
