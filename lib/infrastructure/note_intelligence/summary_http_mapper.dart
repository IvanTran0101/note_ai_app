import 'dart:convert';
import 'dart:typed_data';

import 'summary_api_failure.dart';
import 'summary_request_policy.dart';

/// Turns one completed Summary HTTP exchange into validated stage text.
///
/// The mapper is the only place that reads a response body, so it is also the
/// only place that can turn one into a failure. It is strict on success and
/// forgiving on failure:
///
/// - `HTTP 200` must carry exactly `summary`, `requestId`, and `usage`, with a
///   non-blank text, a non-blank id, and two safe whole token counts inside the
///   policy bounds. Anything else - including a well-formed error envelope
///   served with a `200`, an invalid UTF-8 body, or extra fields - is
///   [SummaryApiErrorCode.invalidOutput], never a partial summary.
/// - Every other status is classified from the contract's status table, which
///   stays authoritative: a `401` is always [SummaryApiErrorCode.unauthorized]
///   (so at most one refresh can follow), and a status outside the table is
///   [SummaryApiErrorCode.unexpected]. The body's `error.code` is consulted only
///   for the one ambiguous status (`502`, which the contract allows to mean
///   either `providerUnavailable` or `invalidOutput`), and only when it names a
///   code the contract permits for that status.
///
/// Nothing from the body - neither the text, the `requestId`, nor a malformed
/// payload - is ever attached to the returned failure, and no failure path
/// retries. The `Retry-After` header is read only for `429` and only when it is
/// a valid bounded whole number of seconds.
final class SummaryHttpMapper {
  /// Creates a mapper that validates against [policy].
  const SummaryHttpMapper({required this.policy});

  /// The shared budget/prompt policy; success bounds come from here.
  final SummaryRequestPolicy policy;

  /// Upper bound for a served retry hint, mirroring the backend clamp.
  static const int maxRetryAfterSeconds = 3600;

  /// `2^53 - 1`, the largest integer JSON can carry without precision loss.
  static const int _maxSafeInteger = 9007199254740991;

  /// The contract's status -> code table (`docs/summary_api_contract.md` 3).
  ///
  /// A status missing here is `unexpected` on purpose: a proxy error page, a
  /// redirect, or a status the contract never defined must fail closed instead
  /// of being reported as a classified server decision.
  static const Map<int, SummaryApiErrorCode> _statusFallback =
      <int, SummaryApiErrorCode>{
        400: SummaryApiErrorCode.invalidInput,
        401: SummaryApiErrorCode.unauthorized,
        403: SummaryApiErrorCode.consentRequired,
        413: SummaryApiErrorCode.inputTooLong,
        429: SummaryApiErrorCode.rateLimited,
        500: SummaryApiErrorCode.unexpected,
        502: SummaryApiErrorCode.providerUnavailable,
        504: SummaryApiErrorCode.timeout,
      };

  /// The only body codes the contract allows for each status.
  ///
  /// Only `502` is ambiguous on its own (it serves `providerUnavailable` and
  /// `invalidOutput`); every other status has exactly one permitted code, which
  /// is what keeps the status - not the body - in charge of classification.
  static const Map<int, Set<SummaryApiErrorCode>> _statusBodyCodes =
      <int, Set<SummaryApiErrorCode>>{
        400: <SummaryApiErrorCode>{SummaryApiErrorCode.invalidInput},
        401: <SummaryApiErrorCode>{SummaryApiErrorCode.unauthorized},
        403: <SummaryApiErrorCode>{SummaryApiErrorCode.consentRequired},
        413: <SummaryApiErrorCode>{SummaryApiErrorCode.inputTooLong},
        429: <SummaryApiErrorCode>{SummaryApiErrorCode.rateLimited},
        500: <SummaryApiErrorCode>{SummaryApiErrorCode.unexpected},
        502: <SummaryApiErrorCode>{
          SummaryApiErrorCode.providerUnavailable,
          SummaryApiErrorCode.invalidOutput,
        },
        504: <SummaryApiErrorCode>{SummaryApiErrorCode.timeout},
      };

  /// Success fields, exactly; a missing or extra field is a schema defect.
  static const Set<String> _successFields = <String>{
    'summary',
    'requestId',
    'usage',
  };

  /// Usage fields, exactly; no other shape is accepted.
  static const Set<String> _usageFields = <String>{
    'inputTokens',
    'outputTokens',
  };

  /// Returns the final text of a `200` response, or throws the mapped failure.
  ///
  /// The returned text is the served `summary` value unchanged: validation only
  /// decides whether it is usable, it never rewrites what the reader will see.
  ///
  /// [stage] selects the output-token bound; [statusCode], [bodyBytes], and
  /// [headers] are the raw exchange as received, so this call is pure and
  /// testable without a client.
  ///
  /// @throws SummaryApiFailure `invalidOutput` for a malformed success, or the
  /// classified code for every other status.
  String mapResponse({
    required SummaryStage stage,
    required int statusCode,
    required Uint8List bodyBytes,
    required Map<String, String> headers,
  }) {
    if (statusCode == 200) {
      return _readSuccess(stage, bodyBytes);
    }
    throw _failureFor(statusCode, headers, _envelopeCode(bodyBytes));
  }

  /// Validates the exact success envelope and returns its summary text.
  String _readSuccess(SummaryStage stage, Uint8List bodyBytes) {
    final Object? decoded = _decode(bodyBytes);
    if (decoded is! Map<String, dynamic> ||
        !_hasExactFields(decoded, _successFields)) {
      _fail(SummaryApiErrorCode.invalidOutput);
    }

    final Object? summary = decoded['summary'];
    if (summary is! String ||
        SummaryRequestPolicy.normalizeInput(summary).isEmpty) {
      _fail(SummaryApiErrorCode.invalidOutput);
    }
    final Object? requestId = decoded['requestId'];
    if (requestId is! String ||
        SummaryRequestPolicy.normalizeInput(requestId).isEmpty) {
      _fail(SummaryApiErrorCode.invalidOutput);
    }

    final Object? usage = decoded['usage'];
    if (usage is! Map<String, dynamic> ||
        !_hasExactFields(usage, _usageFields)) {
      _fail(SummaryApiErrorCode.invalidOutput);
    }
    final int? inputTokens = _safeCount(usage['inputTokens']);
    final int? outputTokens = _safeCount(usage['outputTokens']);
    if (inputTokens == null ||
        outputTokens == null ||
        inputTokens > policy.maxInputEstimate ||
        outputTokens > policy.maxOutputTokens(stage)) {
      _fail(SummaryApiErrorCode.invalidOutput);
    }

    return summary;
  }

  /// Classifies a non-`200` exchange from the status, then the body, then the
  /// `Retry-After` header.
  SummaryApiFailure _failureFor(
    int statusCode,
    Map<String, String> headers,
    SummaryApiErrorCode? bodyCode,
  ) {
    // A body may only refine the status inside the codes the contract allows for
    // it; an unrecognised status keeps the fail-closed `unexpected` default.
    final SummaryApiErrorCode fallback =
        _statusFallback[statusCode] ?? SummaryApiErrorCode.unexpected;
    final Set<SummaryApiErrorCode> allowed =
        _statusBodyCodes[statusCode] ?? const <SummaryApiErrorCode>{};
    final SummaryApiErrorCode code =
        bodyCode != null && allowed.contains(bodyCode) ? bodyCode : fallback;
    return SummaryApiFailure(
      code: code,
      retryAfterSeconds: code == SummaryApiErrorCode.rateLimited
          ? _retryAfterSeconds(headers)
          : null,
    );
  }

  /// Reads the `error.code` of a failure envelope, or `null` when the body is
  /// not one. Failure bodies are best-effort: an authorizer or a gateway may
  /// answer with something that is not this envelope at all.
  static SummaryApiErrorCode? _envelopeCode(Uint8List bodyBytes) {
    final Object? decoded = _decode(bodyBytes);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final Object? error = decoded['error'];
    if (error is! Map<String, dynamic>) {
      return null;
    }
    final Object? code = error['code'];
    if (code is! String) {
      return null;
    }
    for (final SummaryApiErrorCode candidate in SummaryApiErrorCode.values) {
      if (candidate.name == code) {
        return candidate;
      }
    }
    return null;
  }

  /// Reads a valid integer `Retry-After` header, bounded to `1..3600`.
  ///
  /// The header is either absent or a plain whole number of seconds; an HTTP
  /// date, a sign, a fraction, zero, or an out-of-range value is ignored rather
  /// than guessed at.
  static int? _retryAfterSeconds(Map<String, String> headers) {
    for (final MapEntry<String, String> header in headers.entries) {
      if (header.key.toLowerCase() != 'retry-after') {
        continue;
      }
      final String raw = header.value.trim();
      if (raw.isEmpty) {
        return null;
      }
      for (final int unit in raw.codeUnits) {
        if (unit < 0x30 || unit > 0x39) {
          return null;
        }
      }
      final int? seconds = int.tryParse(raw);
      if (seconds == null || seconds < 1 || seconds > maxRetryAfterSeconds) {
        return null;
      }
      return seconds;
    }
    return null;
  }

  /// Decodes a JSON body, or `null` when it is not valid UTF-8 JSON.
  ///
  /// Malformed UTF-8 is rejected rather than replaced, so a body that cannot be
  /// decoded faithfully can never become a summary.
  static Object? _decode(Uint8List bodyBytes) {
    try {
      return jsonDecode(utf8.decode(bodyBytes));
    } on Object {
      return null;
    }
  }

  /// Whether [value] has exactly [fields], no more and no fewer.
  static bool _hasExactFields(Map<String, dynamic> value, Set<String> fields) =>
      value.length == fields.length && fields.every(value.containsKey);

  /// Reads a token count: a whole non-negative JSON number in the safe range.
  ///
  /// `0` is valid - the backend accepts it - but a fraction, a negative number,
  /// a boolean, a string, or a value past `2^53 - 1` is not.
  static int? _safeCount(Object? value) {
    if (value is! num ||
        !value.isFinite ||
        value < 0 ||
        value > _maxSafeInteger ||
        value % 1 != 0) {
      return null;
    }
    return value.toInt();
  }

  static Never _fail(SummaryApiErrorCode code) =>
      throw SummaryApiFailure(code: code);
}
