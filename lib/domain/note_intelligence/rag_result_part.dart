// One safe answer or one safe refusal.
part of 'rag_models.dart';

/// The two shapes one RAG answer can have.
enum RagResultStatus {
  /// The backend answered from approved evidence and returned its citations.
  answered,

  /// The backend refused to answer; [RagResult.reason] explains the verdict.
  notEnoughContext,
}

/// One safe answer or one safe refusal.
///
/// The result carries no tokens, no evidence text, and no provider payload:
/// only the answer the user may read and the citations that can be opened.
/// [sources] is copied and exposed read-only, and each source id is unique.
final class RagResult {
  /// An answered result with at least one approved citation.
  RagResult.answered({
    required String requestId,
    required String answer,
    required Iterable<RagSource> sources,
  }) : this._(
         status: RagResultStatus.answered,
         requestId: _requireIdentifier(requestId, 'requestId'),
         answer: _requireAnswer(answer),
         sources: _freezeSources(sources, requireCitation: true),
         reason: null,
       );

  /// A refusal; the reason is one of the canonical verdicts only.
  RagResult.notEnoughContext({
    required String requestId,
    required String reason,
  }) : this._(
         status: RagResultStatus.notEnoughContext,
         requestId: _requireIdentifier(requestId, 'requestId'),
         answer: null,
         sources: const <RagSource>[],
         reason: _requireReason(reason),
       );

  const RagResult._({
    required this.status,
    required this.requestId,
    required this.answer,
    required this.sources,
    required this.reason,
  });

  /// The backend verdict: evidence answered the question, or it did not.
  static const String reasonInsufficientEvidence = 'INSUFFICIENT_EVIDENCE';

  /// The evidence contains an unresolved contradiction.
  static const String reasonUnresolvedConflict = 'UNRESOLVED_CONFLICT';

  /// The evidence is not decisive enough to answer safely.
  static const String reasonUncertain = 'UNCERTAIN';

  /// Every refusal reason the frozen contract can produce.
  static const Set<String> reasons = <String>{
    reasonInsufficientEvidence,
    reasonUnresolvedConflict,
    reasonUncertain,
  };

  /// Which shape this result is.
  final RagResultStatus status;

  /// Server correlation id, never an idempotency key.
  final String requestId;

  /// The answer text for [RagResultStatus.answered], null otherwise.
  final String? answer;

  /// Approved citations, empty for a refusal.
  final List<RagSource> sources;

  /// The canonical verdict token for a refusal, null for an answer.
  final String? reason;

  /// True when evidence answered the question.
  bool get isAnswered => status == RagResultStatus.answered;

  @override
  bool operator ==(Object other) {
    if (other is! RagResult ||
        other.status != status ||
        other.requestId != requestId ||
        other.answer != answer ||
        other.reason != reason ||
        other.sources.length != sources.length) {
      return false;
    }
    for (int index = 0; index < sources.length; index++) {
      if (other.sources[index] != sources[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    status,
    requestId,
    answer,
    reason,
    Object.hashAll(sources),
  );

  @override
  String toString() {
    return 'RagResult(status: ${status.name}, requestId: $requestId, '
        'answer: ${answer == null ? 'none' : '<redacted>'}, '
        'sources: ${sources.length}, reason: ${reason ?? 'none'})';
  }
}
