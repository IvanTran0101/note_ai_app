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
  noteLocked,

  /// A sync conflict blocks the run.
  conflict,

  /// The run outlived its deadline, including an API-side timeout.
  deadlineExceeded,

  /// The API refused the request because its content or shape was invalid.
  invalidInput,

  /// One stage's input, or its encoded body, exceeds the policy budget.
  inputTooLong,

  /// The snapshot would need more generation calls than the policy allows.
  pipelineTooLarge,

  /// The account is not authorized for the Summary API (missing or foreign
  /// token, refused by the authorizer).
  unauthorized,

  /// The API asked the caller to wait before trying again.
  ///
  /// A usable hint travels in [SummaryRunFailure.retryAfterSeconds]; nothing
  /// retries on its own.
  rateLimited,

  /// The provider or the API gateway is temporarily unavailable.
  serviceUnavailable,

  /// The API answered with something that is not a valid summary.
  invalidOutput,

  /// The request never reached the API (transport-level failure).
  networkUnavailable,

  /// Anything not classified; the fail-closed default.
  unexpected,
}

/// Safe, typed failure for one summary run.
///
/// The exception carries a [code] and, at most, a bounded retry hint: note
/// text, titles, provider payloads, and token material must never travel
/// through an exception, so [toString] reports the code only.
final class SummaryRunFailure implements Exception {
  /// Creates a failure for [code].
  ///
  /// [retryAfterSeconds] is stored as given and sanitized on read: it is
  /// non-null only for [SummaryRunFailureCode.rateLimited] and only inside
  /// `1..3600`, so an invalid hint is dropped rather than clamped or rounded.
  const SummaryRunFailure(this.code, {this._retryAfterSeconds});

  /// The only hint range a caller may act on, mirroring the API contract.
  static const int _maxRetryAfterSeconds = 3600;

  /// The application-level reason the run did not produce an accepted result.
  final SummaryRunFailureCode code;

  /// The hint exactly as constructed; [retryAfterSeconds] applies the rule.
  final int? _retryAfterSeconds;

  /// Whole seconds the API asked the caller to wait, or null when there is no
  /// usable hint.
  ///
  /// It is a hint, never an instruction: this layer never retries on its own.
  /// The raw value is kept in a private field so the constructor stays `const`.
  int? get retryAfterSeconds {
    final int? hint = _retryAfterSeconds;
    if (code != SummaryRunFailureCode.rateLimited ||
        hint == null ||
        hint < 1 ||
        hint > _maxRetryAfterSeconds) {
      return null;
    }
    return hint;
  }

  @override
  bool operator ==(Object other) {
    return other is SummaryRunFailure &&
        other.code == code &&
        other.retryAfterSeconds == retryAfterSeconds;
  }

  @override
  int get hashCode => Object.hash(runtimeType, code, retryAfterSeconds);

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
