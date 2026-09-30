import 'dart:async';

/// One call's deadline, shared by the abort trigger and the pre-send checks.
final class SummaryHttpCall {
  SummaryHttpCall(Duration budget) {
    _timer = Timer(budget, abortForTimeout);
  }

  final Completer<void> _abort = Completer<void>();
  late final Timer _timer;
  bool _timedOut = false;
  bool _aborted = false;

  /// Completion aborts the in-flight request; it never completes with an error.
  Future<void> get abortTrigger => _abort.future;

  /// Whether this call may no longer start network activity.
  bool get expired => _timedOut || _aborted;

  /// Whether the deadline, not the response cap, ended this call.
  bool get timedOut => _timedOut;

  /// Whether anything - deadline or cap - aborted this call.
  bool get aborted => _aborted;

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
