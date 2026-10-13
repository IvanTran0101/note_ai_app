/// The Infrastructure boundary for RAG consent and questions.
library;

import 'rag_models.dart';

/// Provider-neutral port for the RAG backend.
///
/// The Infrastructure adapter owns everything the Domain refuses to know about:
/// the HTTP envelope (`wireVersion`, `requestId`, paths), the Cognito access
/// token, JSON parsing, response size bounds, redirects, and transport retries
/// (which do not exist: one call is one attempt). It must throw [RagFailure]
/// with a safe code for every classified backend error and must never leak a
/// payload, message, token, or claim through the exception.
///
/// Rules every implementation keeps:
///
/// * [RagCallContext] is local only. `expectedUserId`, `cancelled`,
///   `beforeDispatch`, and `deadline` are never serialized, echoed, or logged.
/// * The account comes from the verified token; the body never carries an
///   actor, owner id, model, or endpoint.
/// * `beforeDispatch` is awaited immediately before each request is handed to
///   the transport, and `cancelled` aborts an in-flight request. Neither may
///   start another request (that would recurse into a consent read).
/// * The shared deadline covers token acquisition, guard, body, and transport.
/// * A `NOT_ENOUGH_CONTEXT` response is a normal [RagResult], never a failure.
abstract interface class IRagGateway {
  /// Reads the canonical consent grant for the context's account.
  ///
  /// An absent row is `RagConsent.none`, not an error. A refusal by the
  /// server-side pilot policy arrives as
  /// [RagFailureCode.livePolicyNotConfigured].
  Future<RagConsent> readConsent({required RagCallContext context});

  /// Writes one compare-and-set consent decision and returns the stored grant.
  ///
  /// A stale [RagConsentUpdate.expectedGeneration] is
  /// [RagFailureCode.sourceChanged] (409), never a silent overwrite.
  Future<RagConsent> updateConsent(
    RagConsentUpdate update, {
    required RagCallContext context,
  });

  /// Asks one single-turn question and returns the approved answer or refusal.
  ///
  /// No automatic retry, no token-refresh-then-retry, and no retrieval loop:
  /// one call is one attempt.
  Future<RagResult> query(
    RagRequest request, {
    required RagCallContext context,
  });

  /// Releases transport resources.
  ///
  /// The composition root owns the gateway lifetime; the service never closes
  /// a dependency it was handed.
  Future<void> close();
}
