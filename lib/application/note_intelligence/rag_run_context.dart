/// Captured application call state for one RAG query or one consent call.
///
/// Every value here is captured synchronously before the first `await` of a
/// call and rechecked after every await, so a late completion can never apply
/// to a different account, session, consent generation, or scope.
library;

import 'dart:async';

import '../../domain/note_intelligence/rag_models.dart';

/// Cancellation and deadline handle shared by one captured application call.
///
/// [cancel] completes [whenCancelled] exactly once and never un-completes it;
/// [dispose] only stops the deadline timer and never completes the future, so
/// "the run is over" and "the run was cancelled" stay distinguishable and a
/// gateway can safely await [whenCancelled] to abort an in-flight request.
base class RagCallScope {
  /// Creates a scope whose budget ends at [deadline].
  RagCallScope({required this.deadline});

  /// The instant the shared request budget ends.
  final DateTime deadline;

  final Completer<void> _cancelled = Completer<void>();
  RagFailureCode? _cancelReason;
  Timer? _deadlineTimer;

  /// Whether this call was cancelled; once true it never returns to false.
  bool get isCancelled => _cancelReason != null;

  /// The first cancellation reason, or null while the call is live.
  RagFailureCode? get cancelReason => _cancelReason;

  /// Completes when the call is cancelled or invalidated, never on success.
  Future<void> get whenCancelled => _cancelled.future;

  /// Races one awaited call against this scope's cancellation and deadline.
  ///
  /// Every await a scope owns goes through here — local reads, consent reads
  /// and writes, the question itself, and source validation — so a call that
  /// never settles still ends when it is cancelled or when the 26-second
  /// budget expires. The losing future stays observed, so a late transport
  /// error can never become an unhandled async error and can never reach
  /// service state.
  Future<T> race<T>(Future<T> pending) {
    unawaited(pending.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    return Future.any<T>(<Future<T>>[
      pending,
      whenCancelled.then<T>(
        (_) => throw RagFailure(_cancelReason ?? RagFailureCode.cancelled),
      ),
    ]);
  }

  /// Cancels the call. The first reason wins and later calls are ignored.
  void cancel(RagFailureCode reason) {
    if (_cancelReason != null) {
      return;
    }
    _cancelReason = reason;
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }

  /// Whether [now] is at or past [deadline].
  bool isExpired(DateTime now) => !now.isBefore(deadline);

  /// Arms the deadline backstop once; [onExpired] usually cancels the call.
  void armDeadline(Duration remaining, void Function() onExpired) {
    _deadlineTimer ??= Timer(
      remaining.isNegative ? Duration.zero : remaining,
      onExpired,
    );
  }

  /// Releases the deadline timer. Idempotent; never completes [whenCancelled].
  void dispose() {
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
  }
}

/// One in-flight question, captured before the first await of `ask`.
///
/// The run owns the facts that decide whether a late answer may still be
/// applied: the actor, the session generation, the canonical consent generation
/// the question was admitted under, the scope, and the shared deadline. The
/// question text is kept for the retained question/answer pair and is never
/// logged.
final class RagRunContext extends RagCallScope {
  /// Creates the capture for one question.
  RagRunContext({
    required String actorId,
    required this.sessionGeneration,
    required this.consentGeneration,
    required this.scope,
    required this.question,
    required super.deadline,
  }) : actorId = _requireText(actorId, 'actorId');

  /// The account the question was admitted for.
  final String actorId;

  /// The session generation live at admission.
  final int sessionGeneration;

  /// The canonical consent generation the question was admitted under.
  final int consentGeneration;

  /// The evidence scope of the question.
  final RagScope scope;

  /// The exact question, retained for the result pairing.
  final String question;

  /// Whether the captured actor and session are still the live ones.
  bool matchesBinding({
    required String actorId,
    required int sessionGeneration,
  }) => this.actorId == actorId && this.sessionGeneration == sessionGeneration;

  @override
  String toString() {
    return 'RagRunContext(scope: $scope, sessionGeneration: $sessionGeneration, '
        'consentGeneration: $consentGeneration)';
  }
}

/// One in-flight canonical consent read or write, captured the same way.
///
/// [wasDispatched] is set by the guard that runs immediately before the request
/// leaves the process, so a superseded write can be told apart from one that
/// never reached the server.
final class RagConsentCall extends RagCallScope {
  /// Creates the capture for one consent read ([isWrite] false) or write.
  RagConsentCall({
    required String actorId,
    required this.sessionGeneration,
    required super.deadline,
    this.isWrite = false,
  }) : actorId = _requireText(actorId, 'actorId');

  /// The account the consent call was captured for.
  final String actorId;

  /// The session generation live at capture time.
  final int sessionGeneration;

  /// True for a compare-and-set write, false for a canonical read.
  final bool isWrite;

  bool _dispatched = false;

  /// Whether the request was already handed to the transport.
  bool get wasDispatched => _dispatched;

  /// Records that the request is about to leave the process.
  void markDispatched() => _dispatched = true;

  @override
  String toString() {
    return 'RagConsentCall(isWrite: $isWrite, '
        'sessionGeneration: $sessionGeneration, dispatched: $wasDispatched)';
  }
}

String _requireText(String value, String fieldName) {
  if (value.trim().isEmpty) {
    throw ArgumentError('$fieldName must not be blank');
  }
  return value;
}
