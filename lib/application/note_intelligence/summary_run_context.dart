import 'dart:async';

/// Why one summary run was refused, cancelled, or discarded.
///
/// The codes are provider-neutral: they describe the application decision, not
/// what a backend, transport, or model reported. A run that fails after an
/// asynchronous step is reported with the same code the caller can act on
/// before any cloud request is started.
enum SummaryRunFailureCode {
  /// The owning scope cancelled the run (logout, account switch, note edit or
  /// deletion, conflict, or widget disposal).
  cancelled,

  /// Another Summary pipeline is already active in this app session.
  alreadyRunning,

  /// The requested runtime is unavailable or incompatible with the auth mode.
  runtimeUnavailable,

  /// The account or its session generation changed since the run started.
  sessionChanged,

  /// Cloud summarization is not consented for this exact account and session.
  consentRequired,

  /// The note is missing, or it is not owned by the captured account.
  noteNotFound,

  /// The saved revision differs from the revision the UI selected.
  noteChanged,

  /// A sync conflict blocks the run.
  conflict,

  /// The run outlived its deadline.
  deadlineExceeded,
}

/// Safe, typed failure for one summary run.
///
/// The exception carries a [code] and nothing else: note text, titles, provider
/// payloads, and token material must never travel through an exception, so
/// [toString] reports the code only.
final class SummaryRunFailure implements Exception {
  /// Creates a failure for [code].
  const SummaryRunFailure(this.code);

  /// The application-level reason the run did not produce an accepted result.
  final SummaryRunFailureCode code;

  @override
  bool operator ==(Object other) {
    return other is SummaryRunFailure && other.code == code;
  }

  @override
  int get hashCode => Object.hash(runtimeType, code);

  @override
  String toString() => 'SummaryRunFailure(${code.name})';
}

/// Cancellation handle for exactly one summary run.
///
/// The owner of a run (the Notes UI) creates one scope per invocation and
/// cancels it when the run stops being meaningful: sign-out, account switch,
/// note edit, note deletion, a sync conflict, or widget disposal. Cancellation
/// is terminal — a cancelled scope never becomes active again — and it is the
/// signal the dispatcher, the gateway, and the application service all recheck
/// before they send, accept, or display anything.
final class SummaryRunScope {
  /// Creates an active scope for one run.
  SummaryRunScope();

  final Completer<void> _cancelled = Completer<void>();
  SummaryRunFailureCode? _cancelReason;
  bool _isReleased = false;

  /// Whether the run was cancelled; once true it never returns to false.
  bool get isCancelled => _cancelReason != null;

  /// The first cancellation reason, or null while the scope is active.
  SummaryRunFailureCode? get cancelReason => _cancelReason;

  /// Whether the UI already released this scope after displaying a result.
  bool get isReleased => _isReleased;

  /// Completes when the run is cancelled; never completes while it is active.
  Future<void> get whenCancelled => _cancelled.future;

  /// Cancels the run. The first reason wins and later calls are ignored.
  void cancel({
    SummaryRunFailureCode reason = SummaryRunFailureCode.cancelled,
  }) {
    if (_cancelReason != null) {
      return;
    }
    _cancelReason = reason;
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }

  /// Releases the scope once the UI has displayed or discarded the result.
  ///
  /// Release is idempotent and never reactivates a cancelled scope: it only
  /// records that nothing is waiting on this run any more.
  void release() {
    _isReleased = true;
  }
}
