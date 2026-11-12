/// One RAG HTTP call's shared budget, cancellation, and abort trigger.
library;

import 'dart:async';

import '../../domain/note_intelligence/rag_models.dart';

/// Why one gateway call may no longer run; the first reason wins.
enum RagCallStop {
  /// The owning run was cancelled, invalidated, or logged out.
  cancelled,

  /// The absolute 26-second budget ended.
  timeout,

  /// The gateway was closed while this call was in flight.
  closed,
}

/// One call's absolute deadline, its cancellation race, and its abort trigger.
///
/// The call owns the single budget that covers token acquisition, the local
/// `beforeDispatch` guard, the request, and the response body read, so a hanging
/// token supplier, guard, or stream still settles. Every awaited step goes
/// through [race], which observes the losing future: a late transport error can
/// never become an unhandled async error, and [abortTrigger] ends an in-flight
/// `http.AbortableRequest`.
///
/// `context.cancelled` completes only on cancel/invalidate, never on success, so
/// awaiting it here cannot abort a call that simply finished.
final class RagHttpCall {
  /// Starts the budget of one call against [context].
  ///
  /// [now] is the same clock the gateway uses, so a call admitted after its
  /// absolute deadline never starts a token read or a request.
  RagHttpCall({required RagCallContext context, required DateTime now}) {
    final Duration remaining = context.deadline.difference(now);
    if (remaining <= Duration.zero) {
      _stopWith(RagCallStop.timeout);
    } else {
      _timer = Timer(remaining, () => _stopWith(RagCallStop.timeout));
    }
    unawaited(
      context.cancelled.then<void>(
        (void _) => _stopWith(RagCallStop.cancelled),
        onError: (Object _, StackTrace _) =>
            _stopWith(RagCallStop.cancelled),
      ),
    );
  }

  final Completer<void> _abort = Completer<void>();
  final Completer<void> _transportAbort = Completer<void>();
  Timer? _timer;
  RagCallStop? _stop;
  bool _oversize = false;

  /// Completion aborts the in-flight request; it never completes with an error.
  ///
  /// The transport trigger is deliberately separate from [race]'s logical
  /// abort: an oversize body releases the connection without ending the logical
  /// call, so the caller can still classify the exchange from its status.
  Future<void> get abortTrigger => _transportAbort.future;

  /// The first reason this call may no longer run, or null while it may.
  RagCallStop? get stop => _stop;

  /// Whether cancellation, the deadline, or `close` ended this call.
  bool get isStopped => _stop != null;

  /// Whether the owning run was cancelled.
  bool get isCancelled => _stop == RagCallStop.cancelled;

  /// Whether the absolute budget ended.
  bool get isTimedOut => _stop == RagCallStop.timeout;

  /// Whether the gateway was closed while this call was in flight.
  bool get isClosed => _stop == RagCallStop.closed;

  /// Whether a response body broke the transport cap and was refused.
  bool get isOversize => _oversize;

  /// The safe failure this call ended with; only valid once it stopped.
  RagFailure get failure {
    return switch (_stop) {
      RagCallStop.cancelled || RagCallStop.closed => const RagFailure(
        RagFailureCode.cancelled,
      ),
      RagCallStop.timeout => const RagFailure(RagFailureCode.timeout),
      null =>
        _oversize
            ? const RagFailure(RagFailureCode.invalidProviderOutput)
            : const RagFailure(RagFailureCode.unexpected),
    };
  }

  /// Completes with this call's failure if [pending] does not finish first.
  ///
  /// The losing future stays observed, so a transport error that arrives after
  /// cancellation or after the deadline is discarded instead of escaping as an
  /// unhandled async error.
  Future<T> race<T>(Future<T> pending) {
    unawaited(pending.then<void>((T _) {}, onError: (Object _, StackTrace _) {}));
    return Future.any<T>(<Future<T>>[
      pending,
      _abort.future.then<T>((void _) => throw failure),
    ]);
  }

  /// Throws the call's failure when it may no longer start or read anything.
  void throwIfStopped() {
    if (_stop != null) {
      throw failure;
    }
  }

  /// Marks the response body as refused for breaking the transport cap.
  ///
  /// Only the transport trigger completes here. The logical race stays open so
  /// a `401`/`429`/`5xx` whose body merely broke the cap is still classified
  /// from its status; a `200` overflow still fails as invalid provider output
  /// when the mapper sees no body.
  void abortForOversize() {
    if (_stop != null || _oversize) {
      return;
    }
    _oversize = true;
    _completeTransport();
  }

  /// Ends the call because the gateway was closed.
  void close() => _stopWith(RagCallStop.closed);

  /// Releases the deadline timer. Idempotent; never completes [abortTrigger].
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  void _stopWith(RagCallStop reason) {
    if (_stop != null) {
      return;
    }
    _stop = reason;
    _complete();
    _completeTransport();
  }

  void _complete() {
    if (!_abort.isCompleted) {
      _abort.complete();
    }
  }

  void _completeTransport() {
    if (!_transportAbort.isCompleted) {
      _transportAbort.complete();
    }
  }
}
