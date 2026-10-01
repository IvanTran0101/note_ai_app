import '../../application/note_intelligence/summary_run_context.dart';
import 'summary_api_failure.dart';

/// Translates any remote Summary error into the application's safe failure.
///
/// One rule per source:
///
/// - a [SummaryRunFailure] is already the application's vocabulary, so the same
///   instance is returned and its cancellation reason survives untouched;
/// - a [SummaryApiFailure] is translated code for code (see [_appCode]) with its
///   sanitized retry hint preserved;
/// - anything else - a policy `FormatException`, a store error, a transport
///   `ClientException`, or a bug - becomes [SummaryRunFailureCode.unexpected],
///   with no message, cause, or raw payload retained.
SummaryRunFailure mapSummaryFailure(Object error) => switch (error) {
  SummaryRunFailure failure => failure,
  SummaryApiFailure failure => _fromApiFailure(failure),
  _ => const SummaryRunFailure(SummaryRunFailureCode.unexpected),
};

/// Runs [operation] behind [mapSummaryFailure].
///
/// The callback is invoked and awaited inside the `try`, so both a synchronous
/// throw and a rejected future are mapped, and no Infrastructure exception
/// escapes the boundary. [operation] is neither retried nor cancelled here: the
/// caller keeps its own scope and cancellation semantics.
Future<T> withSummaryFailureBoundary<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } on Object catch (error, stackTrace) {
    // The original trace is kept: an `unexpected` failure carries no message, so
    // the trace is the only thing that can say where it came from.
    Error.throwWithStackTrace(mapSummaryFailure(error), stackTrace);
  }
}

SummaryRunFailure _fromApiFailure(SummaryApiFailure failure) =>
    SummaryRunFailure(
      _appCode(failure.code),
      retryAfterSeconds: failure.retryAfterSeconds,
    );

/// The API -> application code table, exhaustive on purpose: a new API code
/// must be classified here before the app can build.
SummaryRunFailureCode _appCode(SummaryApiErrorCode code) => switch (code) {
  SummaryApiErrorCode.invalidInput => SummaryRunFailureCode.invalidInput,
  SummaryApiErrorCode.inputTooLong => SummaryRunFailureCode.inputTooLong,
  SummaryApiErrorCode.pipelineTooLarge =>
    SummaryRunFailureCode.pipelineTooLarge,
  SummaryApiErrorCode.unauthorized => SummaryRunFailureCode.unauthorized,
  SummaryApiErrorCode.consentRequired => SummaryRunFailureCode.consentRequired,
  SummaryApiErrorCode.rateLimited => SummaryRunFailureCode.rateLimited,
  SummaryApiErrorCode.providerUnavailable =>
    SummaryRunFailureCode.serviceUnavailable,
  SummaryApiErrorCode.invalidOutput => SummaryRunFailureCode.invalidOutput,
  SummaryApiErrorCode.timeout => SummaryRunFailureCode.deadlineExceeded,
  SummaryApiErrorCode.networkUnavailable =>
    SummaryRunFailureCode.networkUnavailable,
  SummaryApiErrorCode.unexpected => SummaryRunFailureCode.unexpected,
};
