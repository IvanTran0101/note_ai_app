import 'dart:async';

import '../../application/note_intelligence/summary_run_context.dart';
import 'summary_api_failure.dart';

/// One call's deadline, shared by the abort trigger and the pre-send checks.
final class SummaryHttpCall {
  SummaryHttpCall(Duration budget, {this.scope}) {
    _timer = Timer(budget, abortForTimeout);
    if (scope?.isCancelled ?? false) {
      abortForCancellation();
    } else if (scope != null) {
      unawaited(scope!.whenCancelled.then((_) => abortForCancellation()));
    }
  }

  final SummaryRunScope? scope;
  final Completer<void> _abort = Completer<void>();
  late final Timer _timer;
  bool _timedOut = false;
  bool _aborted = false;
  bool _cancelled = false;

  /// Completion aborts the in-flight request; it never completes with an error.
  Future<void> get abortTrigger => _abort.future;

  /// Whether this call may no longer start network activity.
  bool get expired => _timedOut || _aborted || _cancelled;

  /// Whether the deadline, not the response cap, ended this call.
  bool get timedOut => _timedOut;

  /// Whether anything - deadline or cap - aborted this call.
  bool get aborted => _aborted;

  /// Whether the application cancelled this run.
  bool get cancelled => _cancelled;

  /// Completes with run cancellation if the operation has not finished first.
  Future<T> raceScope<T>(Future<T> operation) {
    final SummaryRunScope? runScope = scope;
    if (runScope == null) return operation;
    if (_cancelled || runScope.isCancelled) {
      return Future<T>.error(cancellationFailure());
    }
    return Future.any<T>(<Future<T>>[
      operation,
      runScope.whenCancelled.then<T>((_) => throw cancellationFailure()),
    ]);
  }

  /// Throws the appropriate safe failure after a preceding await.
  void throwIfExpired() {
    if (_cancelled) throw cancellationFailure();
    if (_timedOut) {
      throw const SummaryApiFailure(code: SummaryApiErrorCode.timeout);
    }
    if (_aborted) {
      throw const SummaryApiFailure(code: SummaryApiErrorCode.invalidOutput);
    }
  }

  SummaryRunFailure cancellationFailure() =>
      SummaryRunFailure(scope?.cancelReason ?? SummaryRunFailureCode.cancelled);

  void abortForCancellation() {
    if (_timedOut || _aborted || _cancelled) return;
    _cancelled = true;
    _complete();
  }

  void abortForTimeout() {
    _timedOut = true;
    _complete();
  }

  void abortForOversize() {
    _aborted = true;
    _complete();
  }

  void _complete() {
    if (!_abort.isCompleted) {
      _abort.complete();
    }
  }

  void dispose() => _timer.cancel();
}
