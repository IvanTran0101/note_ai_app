// Safe classification of one failed RAG call.
part of 'rag_models.dart';

/// Why a RAG call could not produce a usable result.
///
/// The first group mirrors the frozen backend contract one-to-one; the second
/// group is decided locally by the application service and can never arrive
/// from the wire. A refusal (`NOT_ENOUGH_CONTEXT`) is a result status, not a
/// failure, and is never guessed from an error.
enum RagFailureCode {
  /// The run was cancelled locally (user cancel, logout, inactivity, scope or
  /// grant change, or disposal).
  cancelled,

  /// The account or its session generation changed while the call was running.
  sessionChanged,

  /// The request never reached the API (transport-level failure).
  network,

  /// A query is already active; the frozen contract allows one at a time.
  alreadyRunning,

  /// No canonical grant has been read yet, or the read failed or was
  /// invalidated. Consent is never assumed.
  consentUnknown,

  /// The canonical grant exists and is not accepted for this account/version.
  consentRequired,

  /// A citation no longer matches the local note (revision, quote, span, or a
  /// pending local change) and cannot be opened or applied.
  sourceChanged,

  /// The cited note is missing, deleted, content-unavailable, incoming, or
  /// protected, so the citation cannot be opened at all.
  sourceUnavailable,

  /// The local sync state could not be read safely.
  localStateUnavailable,

  /// The API refused the request because its content or shape was invalid.
  invalidInput,

  /// The question exceeds the frozen wire budget.
  inputTooLong,

  /// The account is not authorized for the RAG API.
  unauthorized,

  /// The API refused the scope.
  scopeDenied,

  /// The index for the account is not ready yet.
  indexNotReady,

  /// The API (or the server-side pilot budget) asked the caller to wait.
  ///
  /// A usable hint travels in [RagFailure.retryAfterSeconds]; nothing retries
  /// on its own.
  rateLimited,

  /// The evidence validator was unavailable, so no answer could be approved.
  evidenceValidationUnavailable,

  /// The provider or the API gateway is temporarily unavailable.
  providerUnavailable,

  /// The API answered with something that is not a valid result.
  invalidProviderOutput,

  /// The run outlived the shared request deadline.
  timeout,

  /// The server-side pilot policy is disabled or does not list this account.
  livePolicyNotConfigured,

  /// Anything not classified; the fail-closed default.
  unexpected;

  /// Maps one backend contract code to the safe application code.
  ///
  /// Returns null for a code this build does not know, so a caller can fail
  /// closed instead of inventing a classification.
  static RagFailureCode? fromWireCode(String? code) {
    return switch (code) {
      'INVALID_INPUT' => RagFailureCode.invalidInput,
      'INPUT_TOO_LONG' => RagFailureCode.inputTooLong,
      'UNAUTHORIZED' => RagFailureCode.unauthorized,
      'CONSENT_REQUIRED' => RagFailureCode.consentRequired,
      'SCOPE_DENIED' => RagFailureCode.scopeDenied,
      'INDEX_NOT_READY' => RagFailureCode.indexNotReady,
      'SOURCE_CHANGED' => RagFailureCode.sourceChanged,
      'RATE_LIMITED' => RagFailureCode.rateLimited,
      'EVIDENCE_VALIDATION_UNAVAILABLE' =>
        RagFailureCode.evidenceValidationUnavailable,
      'PROVIDER_UNAVAILABLE' => RagFailureCode.providerUnavailable,
      'INVALID_PROVIDER_OUTPUT' => RagFailureCode.invalidProviderOutput,
      'TIMEOUT' => RagFailureCode.timeout,
      'LIVE_POLICY_NOT_CONFIGURED' => RagFailureCode.livePolicyNotConfigured,
      _ => null,
    };
  }

  /// The backend contract code this value mirrors, or null for a local code.
  String? get wireCode {
    return switch (this) {
      RagFailureCode.invalidInput => 'INVALID_INPUT',
      RagFailureCode.inputTooLong => 'INPUT_TOO_LONG',
      RagFailureCode.unauthorized => 'UNAUTHORIZED',
      RagFailureCode.consentRequired => 'CONSENT_REQUIRED',
      RagFailureCode.scopeDenied => 'SCOPE_DENIED',
      RagFailureCode.indexNotReady => 'INDEX_NOT_READY',
      RagFailureCode.sourceChanged => 'SOURCE_CHANGED',
      RagFailureCode.rateLimited => 'RATE_LIMITED',
      RagFailureCode.evidenceValidationUnavailable =>
        'EVIDENCE_VALIDATION_UNAVAILABLE',
      RagFailureCode.providerUnavailable => 'PROVIDER_UNAVAILABLE',
      RagFailureCode.invalidProviderOutput => 'INVALID_PROVIDER_OUTPUT',
      RagFailureCode.timeout => 'TIMEOUT',
      RagFailureCode.livePolicyNotConfigured => 'LIVE_POLICY_NOT_CONFIGURED',
      RagFailureCode.cancelled ||
      RagFailureCode.sessionChanged ||
      RagFailureCode.network ||
      RagFailureCode.alreadyRunning ||
      RagFailureCode.consentUnknown ||
      RagFailureCode.sourceUnavailable ||
      RagFailureCode.localStateUnavailable ||
      RagFailureCode.unexpected => null,
    };
  }
}

/// Safe, typed failure for one RAG call.
///
/// The exception carries a [code] and, at most, a bounded retry hint. Note
/// text, question text, answers, provider payloads, and token material never
/// travel through an exception, so [toString] reports the code only.
final class RagFailure implements Exception {
  /// Creates a failure for [code].
  ///
  /// [retryAfterSeconds] is sanitized on read: it is non-null only for
  /// [RagFailureCode.rateLimited] and only inside `1..3600`, so an invalid hint
  /// is dropped rather than clamped.
  const RagFailure(this.code, {int? retryAfterSeconds})
    // The public hint name and the private const field differ on purpose: the
    // raw value stays unvalidated in the field and is sanitized by the getter.
    // ignore: prefer_initializing_formals
    : _retryAfterSeconds = retryAfterSeconds;

  /// The only hint range a caller may act on, mirroring the API contract.
  static const int maxRetryAfterSeconds = 3600;

  /// Builds the safe failure for one backend error envelope.
  ///
  /// An unknown or missing code becomes [RagFailureCode.unexpected]; it is
  /// never mapped onto a refusal or onto another code.
  factory RagFailure.fromWire(String? code, {int? retryAfterSeconds}) {
    return RagFailure(
      RagFailureCode.fromWireCode(code) ?? RagFailureCode.unexpected,
      retryAfterSeconds: retryAfterSeconds,
    );
  }

  /// The application-level reason the call produced no usable result.
  final RagFailureCode code;

  /// The hint exactly as constructed; [retryAfterSeconds] applies the rule.
  final int? _retryAfterSeconds;

  /// Whole seconds the API asked the caller to wait, or null when there is no
  /// usable hint. It is a hint, never an instruction: nothing retries on its
  /// own.
  int? get retryAfterSeconds {
    final int? hint = _retryAfterSeconds;
    if (code != RagFailureCode.rateLimited ||
        hint == null ||
        hint < 1 ||
        hint > maxRetryAfterSeconds) {
      return null;
    }
    return hint;
  }

  @override
  bool operator ==(Object other) =>
      other is RagFailure &&
      other.code == code &&
      other.retryAfterSeconds == retryAfterSeconds;

  @override
  int get hashCode => Object.hash(runtimeType, code, retryAfterSeconds);

  @override
  String toString() => 'RagFailure(${code.name})';
}
