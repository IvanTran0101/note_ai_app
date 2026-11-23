// Everything one gateway call needs, and nothing that may go on the wire.
part of 'rag_models.dart';

/// Everything one gateway call needs, and nothing that may go on the wire.
///
/// [expectedUserId] is the account the caller captured; the gateway must refuse
/// to send when the live account differs. [cancelled] completes only when the
/// owning run is cancelled or invalidated — never on normal completion — so a
/// transport can abort an in-flight request. [beforeDispatch] is awaited
/// immediately before every dispatch; it is a local/session/liveness guard only
/// and must never perform another network read. [deadline] is the shared
/// 26-second budget captured when the run started.
final class RagCallContext {
  /// Creates a call context for one captured account and deadline.
  RagCallContext({
    required String expectedUserId,
    required this.cancelled,
    required this.beforeDispatch,
    required this.deadline,
  }) : expectedUserId = _requireIdentifier(expectedUserId, 'expectedUserId');

  /// The shared end-to-end budget of one RAG call (`requestTimeoutMs`).
  static const Duration requestBudget = Duration(seconds: 26);

  /// The account this call was captured for.
  final String expectedUserId;

  /// Completes when the call is cancelled or invalidated, never on success.
  final Future<void> cancelled;

  /// Local guard awaited immediately before the request is dispatched.
  final Future<void> Function() beforeDispatch;

  /// The instant the shared budget ends.
  final DateTime deadline;

  @override
  String toString() {
    return 'RagCallContext(expectedUserId: $expectedUserId, '
        'deadline: $deadline)';
  }
}
