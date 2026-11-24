// Question, evidence scope, and the single-turn request.
part of 'rag_models.dart';

/// Which of the caller's own notes one question may read.
enum RagScopeType { account, note }

/// The evidence scope of one question: the whole account or one note.
///
/// The scope is built by the caller (Presentation) and travels to the backend;
/// it never carries an actor, an owner id, or a revision.
final class RagScope {
  /// Every synced, unprotected, owned note of the account.
  const RagScope.account() : type = RagScopeType.account, noteId = null;

  /// One owned note of the account, identified by its canonical note id.
  RagScope.note(String noteId)
    : this._(RagScopeType.note, _requireIdentifier(noteId, 'noteId'));

  const RagScope._(this.type, this.noteId);

  /// Which scope shape this is.
  final RagScopeType type;

  /// The canonical note id for [RagScopeType.note], null for an account scope.
  final String? noteId;

  /// True for an account-wide scope.
  bool get isAccount => type == RagScopeType.account;

  @override
  bool operator ==(Object other) =>
      other is RagScope && other.type == type && other.noteId == noteId;

  @override
  int get hashCode => Object.hash(type, noteId);

  @override
  String toString() =>
      isAccount ? 'RagScope.account()' : 'RagScope.note($noteId)';
}

/// Why a question cannot be sent on the wire.
enum RagQuestionProblem {
  /// The question is empty or only whitespace.
  blank,

  /// The question is not well-formed UTF-16 (a lone surrogate would be
  /// silently replaced on UTF-8 egress, so it is refused instead).
  malformed,

  /// The question exceeds the frozen code-point or UTF-8 byte budget.
  tooLong,
}

/// One single-turn question with its evidence scope.
final class RagRequest {
  /// Creates a validated request.
  ///
  /// Throws [ArgumentError] when [question] does not satisfy
  /// [questionProblem]; callers that need a typed reason use that helper first.
  RagRequest({required String question, required this.scope})
    : question = _requireQuestion(question);

  /// Wire version of the request envelope.
  static const int wireVersion = ragWireVersion;

  /// Maximum UTF-8 bytes of one question (`questionMaxUtf8Bytes`).
  static const int maxQuestionUtf8Bytes = 4096;

  /// Maximum Unicode code points of one question (`questionMaxCodePoints`).
  static const int maxQuestionCodePoints = 2048;

  /// The exact user question, unmodified.
  final String question;

  /// The evidence scope the question is allowed to read.
  final RagScope scope;

  /// The safe reason [question] cannot be sent, or null when it can.
  static RagQuestionProblem? questionProblem(String question) {
    if (question.trim().isEmpty) {
      return RagQuestionProblem.blank;
    }
    if (!_isWellFormed(question)) {
      return RagQuestionProblem.malformed;
    }
    if (_codePointCount(question) > maxQuestionCodePoints ||
        utf8.encode(question).length > maxQuestionUtf8Bytes) {
      return RagQuestionProblem.tooLong;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is RagRequest && other.question == question && other.scope == scope;

  @override
  int get hashCode => Object.hash(question, scope);

  @override
  String toString() => 'RagRequest(scope: $scope, question: <redacted>)';
}
