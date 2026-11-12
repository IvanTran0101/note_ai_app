/// Immutable presentation-facing state of one RAG (ask-my-notes) session.
library;

import '../../domain/note_intelligence/rag_models.dart';

/// Sentinel for [RagState.copyWith], so "keep the current value" and "clear to
/// null" stay distinguishable for nullable fields.
const Object _unset = Object();

/// Everything the UI may render about the current RAG session.
///
/// The state is account-scoped and immutable; the service replaces it instead
/// of mutating it, and every field is safe to display: no note text, question
/// text, answer text, token, or provider payload is stored here beyond the
/// answer the user asked for.
///
/// Two invariants are enforced at construction:
///
/// * [result] and [resultQuestion] travel together. An answer is only ever
///   shown next to the exact question that produced it, so a newer failure can
///   never attach an old answer to a new question.
/// * [consent] is null while it is unknown (never read, read failed, or
///   invalidated by inactivity or a session change); null never means "denied".
///   A read grant with `accepted: false` is the explicit denial.
final class RagState {
  /// Creates a state snapshot.
  ///
  /// Throws [ArgumentError] when [result] and [resultQuestion] are not paired;
  /// a half pair would let the UI attach an old answer to a new question.
  RagState({
    this.consent,
    this.consentLoading = false,
    this.queryRunning = false,
    this.active = true,
    this.scope,
    this.result,
    this.resultQuestion,
    this.failure,
  }) {
    if ((result == null) != (resultQuestion == null)) {
      throw ArgumentError(
        'A result is always paired with the question that produced it.',
      );
    }
  }

  /// The canonical consent grant for the live account, or null when unknown.
  final RagConsent? consent;

  /// True while a canonical consent read or write is in flight.
  final bool consentLoading;

  /// True from the moment a run is admitted until it settles (including
  /// cancellation).
  final bool queryRunning;

  /// False while the app is backgrounded; an inactive app never dispatches.
  final bool active;

  /// The scope of the last admitted (or attempted) question.
  final RagScope? scope;

  /// The current answer or refusal, or the last one that is still valid.
  final RagResult? result;

  /// The exact question [result] answers; null exactly when [result] is null.
  final String? resultQuestion;

  /// The last safe failure, or null when nothing failed.
  final RagFailure? failure;

  /// Whether a query may be started right now.
  bool get canAsk =>
      active && !queryRunning && !consentLoading && (consent?.accepted ?? false);

  /// Whether a grant is known and accepted.
  bool get consentAccepted => consent?.accepted ?? false;

  /// Returns a copy with the given fields replaced.
  ///
  /// Passing null for a nullable field clears it; omitting the argument keeps
  /// the current value.
  RagState copyWith({
    Object? consent = _unset,
    bool? consentLoading,
    bool? queryRunning,
    bool? active,
    Object? scope = _unset,
    Object? result = _unset,
    Object? resultQuestion = _unset,
    Object? failure = _unset,
  }) {
    return RagState(
      consent: identical(consent, _unset) ? this.consent : consent as RagConsent?,
      consentLoading: consentLoading ?? this.consentLoading,
      queryRunning: queryRunning ?? this.queryRunning,
      active: active ?? this.active,
      scope: identical(scope, _unset) ? this.scope : scope as RagScope?,
      result: identical(result, _unset) ? this.result : result as RagResult?,
      resultQuestion: identical(resultQuestion, _unset)
          ? this.resultQuestion
          : resultQuestion as String?,
      failure: identical(failure, _unset) ? this.failure : failure as RagFailure?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RagState &&
      other.consent == consent &&
      other.consentLoading == consentLoading &&
      other.queryRunning == queryRunning &&
      other.active == active &&
      other.scope == scope &&
      other.result == result &&
      other.resultQuestion == resultQuestion &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(
    consent,
    consentLoading,
    queryRunning,
    active,
    scope,
    result,
    resultQuestion,
    failure,
  );

  /// Reports flags and generations only; question and answer text stay out of
  /// logs and crash reports.
  @override
  String toString() {
    return 'RagState(consent: ${consent ?? 'unknown'}, '
        'consentLoading: $consentLoading, queryRunning: $queryRunning, '
        'active: $active, scope: $scope, '
        'result: ${result?.status.name ?? 'none'}, '
        'resultQuestion: ${resultQuestion == null ? 'none' : '<redacted>'}, '
        'failure: ${failure?.code.name ?? 'none'})';
  }
}
