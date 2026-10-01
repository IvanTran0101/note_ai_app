/// Safe failure vocabulary for the remote Summary path (Phase 3.2/3.3).
///
/// This file is the frozen shared contract between the HTTP transport worker and
/// the orchestration worker: both import it and neither changes it. It mirrors
/// `docs/summary_api_contract.md` section 3 - the backend's error envelope codes
/// plus the client-only classes the contract expects (`pipelineTooLarge`,
/// `networkUnavailable`, `unexpected`).
library;

/// Every way one remote Summary stage can fail.
///
/// The names match the backend's `SummaryErrorCode` where a backend code exists,
/// so a wire value can be carried across without a translation table. The three
/// client-only members are:
///
/// - [pipelineTooLarge]: the snapshot needs more chunks than the policy allows,
///   decided before the first generation call.
/// - [networkUnavailable]: the request never reached the API (transport failure).
/// - [unexpected]: anything not classified; the fail-closed default.
enum SummaryApiErrorCode {
  invalidInput,
  inputTooLong,
  pipelineTooLarge,
  unauthorized,
  consentRequired,
  rateLimited,
  providerUnavailable,
  invalidOutput,
  timeout,
  networkUnavailable,
  unexpected,
}

/// A remote Summary failure that is safe to carry and safe to print.
///
/// The type deliberately has no `message`, no `requestId`, and no `cause`: a raw
/// response body, an id, an exception, or a bearer token can never ride along
/// with a failure. [toString] therefore exposes the code and nothing else, which
/// makes it safe in a log line or an assert message.
final class SummaryApiFailure implements Exception {
  /// Creates a failure for [code], with an optional bounded retry hint.
  const SummaryApiFailure({required this.code, this.retryAfterSeconds});

  /// The classified failure.
  final SummaryApiErrorCode code;

  /// Whole seconds the server asked the caller to wait, bounded to `1..3600`.
  ///
  /// Only set for [SummaryApiErrorCode.rateLimited], and only when the response
  /// carried a valid integer `Retry-After` header. It is a hint, not a retry
  /// instruction: this layer never retries on its own.
  final int? retryAfterSeconds;

  @override
  String toString() => 'SummaryApiFailure(${code.name})';
}
