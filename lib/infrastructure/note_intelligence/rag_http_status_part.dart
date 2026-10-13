part of 'rag_http_mapper.dart';

// Status-first classification of a failed RAG exchange.
//
// The contract's `errorHttpStatus` table stays authoritative, so a non-JSON
// `401`/`429`/`5xx` from API Gateway is classified exactly like the backend's
// own envelope. The body may refine the status only with a code the contract
// permits for it, and the `Retry-After` header is read only for `429`. It is a
// separate responsibility from reading a `200` envelope, so it lives in this
// part.

/// The status -> code table of the contract, minus the `5xx` default.
const Map<int, RagFailureCode> _statusFallback = <int, RagFailureCode>{
  400: RagFailureCode.invalidInput,
  401: RagFailureCode.unauthorized,
  403: RagFailureCode.consentRequired,
  404: RagFailureCode.scopeDenied,
  409: RagFailureCode.sourceChanged,
  413: RagFailureCode.inputTooLong,
  429: RagFailureCode.rateLimited,
  502: RagFailureCode.providerUnavailable,
  503: RagFailureCode.providerUnavailable,
  504: RagFailureCode.timeout,
};

/// The only body codes the contract permits for each status.
///
/// `409` is the one ambiguous status (the consent compare-and-set and an unready
/// index share it), so the body decides which one it is and `sourceChanged` is
/// the fail-closed default. `403` may refine to `scopeDenied` as well, because
/// both are contract denials; every other ambiguous pair is explicit here.
const Map<int, Set<RagFailureCode>> _statusBodyCodes =
    <int, Set<RagFailureCode>>{
      400: <RagFailureCode>{RagFailureCode.invalidInput},
      401: <RagFailureCode>{RagFailureCode.unauthorized},
      403: <RagFailureCode>{
        RagFailureCode.consentRequired,
        RagFailureCode.scopeDenied,
      },
      404: <RagFailureCode>{RagFailureCode.scopeDenied},
      409: <RagFailureCode>{
        RagFailureCode.sourceChanged,
        RagFailureCode.indexNotReady,
      },
      413: <RagFailureCode>{RagFailureCode.inputTooLong},
      429: <RagFailureCode>{RagFailureCode.rateLimited},
      502: <RagFailureCode>{
        RagFailureCode.providerUnavailable,
        RagFailureCode.invalidProviderOutput,
      },
      503: <RagFailureCode>{
        RagFailureCode.providerUnavailable,
        RagFailureCode.evidenceValidationUnavailable,
        RagFailureCode.livePolicyNotConfigured,
      },
      504: <RagFailureCode>{RagFailureCode.timeout},
    };

/// The exact fields of an `ERROR` envelope.
const Set<String> _errorFields = <String>{
  'wireVersion',
  'requestId',
  'status',
  'code',
};

/// Classifies a non-`200` exchange from the status, then the body, then the
/// `Retry-After` header.
RagFailure _failureFor(
  int statusCode,
  Map<String, String> headers,
  Uint8List? bodyBytes,
) {
  final RagFailureCode fallback = _fallbackFor(statusCode);
  final RagFailureCode? fromBody = _envelopeCode(bodyBytes);
  final Set<RagFailureCode> allowed =
      _statusBodyCodes[statusCode] ?? const <RagFailureCode>{};
  final RagFailureCode code = fromBody != null && allowed.contains(fromBody)
      ? fromBody
      : fallback;
  return RagFailure(
    code,
    retryAfterSeconds: code == RagFailureCode.rateLimited
        ? _retryAfterSeconds(headers)
        : null,
  );
}

/// The contract's status default; an unknown status fails closed.
RagFailureCode _fallbackFor(int statusCode) {
  final RagFailureCode? known = _statusFallback[statusCode];
  if (known != null) {
    return known;
  }
  if (statusCode >= 500 && statusCode <= 599) {
    // Every other 5xx is a provider/gateway failure; `504` stays a timeout
    // because the table names it.
    return RagFailureCode.providerUnavailable;
  }
  return RagFailureCode.invalidProviderOutput;
}

/// Reads the `code` of a well-formed `ERROR` envelope, or null.
///
/// A failure body is best-effort: an authorizer or gateway may answer with
/// something that is not this envelope at all, and an unknown code must never
/// become a classification.
RagFailureCode? _envelopeCode(Uint8List? bodyBytes) {
  if (bodyBytes == null) {
    return null;
  }
  final Object? decoded = _decodeLenient(bodyBytes);
  if (decoded is! Map<String, dynamic> ||
      !_hasExactFields(decoded, _errorFields) ||
      decoded['wireVersion'] is! int ||
      decoded['wireVersion'] != ragWireVersion ||
      decoded['requestId'] is! String ||
      decoded['status'] != 'ERROR') {
    return null;
  }
  final Object? code = decoded['code'];
  return code is String ? RagFailureCode.fromWireCode(code) : null;
}

/// Decodes a failure body best-effort; a problem only means "no refinement".
Object? _decodeLenient(Uint8List bodyBytes) {
  try {
    return decodeRagJson(bodyBytes);
  } on RagJsonProblem {
    return null;
  }
}

/// Reads a valid integer `Retry-After` header, bounded to `1..3600`.
int? _retryAfterSeconds(Map<String, String> headers) {
  final String? raw = _header(headers, 'retry-after')?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  for (final int unit in raw.codeUnits) {
    if (unit < 0x30 || unit > 0x39) {
      return null;
    }
  }
  final int? seconds = int.tryParse(raw);
  if (seconds == null ||
      seconds < 1 ||
      seconds > RagHttpMapper.maxRetryAfterSeconds) {
    return null;
  }
  return seconds;
}

/// Reads one header value case-insensitively.
String? _header(Map<String, String> headers, String name) {
  for (final MapEntry<String, String> header in headers.entries) {
    if (header.key.toLowerCase() == name) {
      return header.value;
    }
  }
  return null;
}

/// Whether a `200` response declares the JSON UTF-8 body this contract serves.
bool _isJsonUtf8(String? value) {
  if (value == null) {
    return false;
  }
  final List<String> parts = value.split(';');
  if (parts.first.trim().toLowerCase() != 'application/json') {
    return false;
  }
  for (final String parameter in parts.skip(1)) {
    final String trimmed = parameter.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final int equals = trimmed.indexOf('=');
    if (equals <= 0) {
      return false;
    }
    final String name = trimmed.substring(0, equals).trim().toLowerCase();
    final String charset = trimmed
        .substring(equals + 1)
        .trim()
        .replaceAll('"', '')
        .toLowerCase();
    if (name != 'charset' || (charset != 'utf-8' && charset != 'utf8')) {
      return false;
    }
  }
  return true;
}
