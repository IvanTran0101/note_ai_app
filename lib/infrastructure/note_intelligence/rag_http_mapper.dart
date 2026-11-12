/// Strict reader for the frozen Phase 5 RAG wire envelopes.
library;

import 'dart:typed_data';

import '../../domain/note_intelligence/rag_models.dart';
import 'rag_json_guard.dart';

part 'rag_http_status_part.dart';

/// Turns one completed RAG HTTP exchange into Domain values, or a safe failure.
///
/// The mapper is the only place that reads a response body, so it is also the
/// only place that can turn one into a failure:
///
/// * A `200` must carry exactly the frozen envelope for its route, in strict
///   UTF-8 `application/json`, with no duplicate keys and no nesting past
///   `MAX_JSON_DEPTH`. Anything else — including a well-formed `ERROR` envelope
///   served with a `200`, an extra field, a wrong type, a citation label that
///   names no source, or a body past 64 KiB — is
///   [RagFailureCode.invalidProviderOutput]. A `200` never becomes a refusal.
/// * Every other status is classified from the contract's status table first
///   (`docs/rag/policy_v1.json technicalDefaults.errorHttpStatus`), so a
///   non-JSON `401`/`429`/`5xx` from API Gateway is still safe. The body's
///   `code` refines that classification only when the contract allows that code
///   for that status; an unknown status or code fails closed.
///
/// Nothing from a body is ever attached to a failure, and no failure path
/// retries. The `Retry-After` header is read only for `429` and only when it is
/// a bounded whole number of seconds.
final class RagHttpMapper {
  /// Creates the shared, stateless mapper.
  const RagHttpMapper();

  /// Upper bound for a served retry hint, mirroring the backend clamp.
  static const int maxRetryAfterSeconds = 3600;

  /// Maximum citations one answered result may carry (`MAX_GENERATED_SOURCES`).
  static const int maxGeneratedSources = 24;

  /// `2^53 - 1`, the largest integer JSON can carry without precision loss.
  static const int _maxSafeInteger = 9007199254740991;

  static final RegExp _citationLabel = RegExp(r'\[(S[0-9]+)\]');

  static const Set<String> _answeredFields = <String>{
    'wireVersion',
    'requestId',
    'status',
    'answer',
    'sources',
  };

  static const Set<String> _abstentionFields = <String>{
    'wireVersion',
    'requestId',
    'status',
    'reason',
    'answer',
    'sources',
  };


  static const Set<String> _consentEnvelopeFields = <String>{
    'wireVersion',
    'requestId',
    'consent',
  };

  static const Set<String> _consentFields = <String>{
    'accepted',
    'version',
    'generation',
  };

  static const Set<String> _sourceFields = <String>{
    'sourceId',
    'noteId',
    'revision',
    'title',
    'startOffset',
    'endOffset',
    'quote',
  };

  /// Maps one `GET /ai/rag/consent` exchange.
  RagConsent mapConsent({
    required int statusCode,
    required Map<String, String> headers,
    required Uint8List? bodyBytes,
  }) {
    if (statusCode != 200) {
      throw _failureFor(statusCode, headers, bodyBytes);
    }
    final Map<String, dynamic> envelope = _envelope(
      headers,
      bodyBytes,
      _consentEnvelopeFields,
    );
    final Object? consent = envelope['consent'];
    if (consent is! Map<String, dynamic> ||
        !_hasExactFields(consent, _consentFields)) {
      _fail();
    }
    final Object? accepted = consent['accepted'];
    final Object? version = consent['version'];
    final int? generation = _safeInteger(consent['generation']);
    if (accepted is! bool || version is! String || generation == null) {
      _fail();
    }
    try {
      return RagConsent(
        accepted: accepted,
        version: version,
        generation: generation,
      );
    } on ArgumentError {
      _fail();
    }
  }

  /// Maps one `POST /ai/rag/query` exchange.
  RagResult mapQuery({
    required int statusCode,
    required Map<String, String> headers,
    required Uint8List? bodyBytes,
  }) {
    if (statusCode != 200) {
      throw _failureFor(statusCode, headers, bodyBytes);
    }
    final Map<String, dynamic> envelope = _envelope(headers, bodyBytes, null);
    final Object? status = envelope['status'];
    if (status == 'ANSWERED') {
      return _answered(envelope);
    }
    if (status == 'NOT_ENOUGH_CONTEXT') {
      return _abstention(envelope);
    }
    // A `200` that carries an ERROR envelope, or any other status, is not a
    // result: it is never answered and never treated as an abstention.
    _fail();
  }

  /// Reads and validates the exact `ANSWERED` envelope.
  RagResult _answered(Map<String, dynamic> envelope) {
    if (!_hasExactFields(envelope, _answeredFields)) {
      _fail();
    }
    final Object? answer = envelope['answer'];
    final Object? requestId = envelope['requestId'];
    final Object? sources = envelope['sources'];
    if (answer is! String || requestId is! String || sources is! List) {
      _fail();
    }
    if (sources.isEmpty || sources.length > maxGeneratedSources) {
      _fail();
    }
    final List<RagSource> parsed = <RagSource>[];
    final Set<String> sourceIds = <String>{};
    for (final Object? candidate in sources) {
      final RagSource source = _source(candidate);
      if (!sourceIds.add(source.sourceId)) {
        _fail();
      }
      parsed.add(source);
    }
    _requireCitationLabels(answer, sourceIds);
    try {
      return RagResult.answered(
        requestId: requestId,
        answer: answer,
        sources: parsed,
      );
    } on ArgumentError {
      _fail();
    }
  }

  /// Reads and validates the exact `NOT_ENOUGH_CONTEXT` envelope.
  RagResult _abstention(Map<String, dynamic> envelope) {
    if (!_hasExactFields(envelope, _abstentionFields)) {
      _fail();
    }
    final Object? requestId = envelope['requestId'];
    final Object? reason = envelope['reason'];
    final Object? answer = envelope['answer'];
    final Object? sources = envelope['sources'];
    if (requestId is! String ||
        reason is! String ||
        answer != null ||
        sources is! List ||
        sources.isNotEmpty) {
      _fail();
    }
    try {
      return RagResult.notEnoughContext(requestId: requestId, reason: reason);
    } on ArgumentError {
      _fail();
    }
  }

  /// Builds one citation, validating every field before the Domain does.
  RagSource _source(Object? value) {
    if (value is! Map<String, dynamic> ||
        !_hasExactFields(value, _sourceFields)) {
      _fail();
    }
    final Object? sourceId = value['sourceId'];
    final Object? noteId = value['noteId'];
    final Object? title = value['title'];
    final Object? quote = value['quote'];
    final int? revision = _safeInteger(value['revision']);
    final int? startOffset = _safeInteger(value['startOffset']);
    final int? endOffset = _safeInteger(value['endOffset']);
    if (sourceId is! String ||
        noteId is! String ||
        title is! String ||
        quote is! String ||
        revision == null ||
        startOffset == null ||
        endOffset == null) {
      _fail();
    }
    try {
      return RagSource(
        sourceId: sourceId,
        noteId: noteId,
        revision: revision,
        title: title,
        startOffset: startOffset,
        endOffset: endOffset,
        quote: quote,
      );
    } on ArgumentError {
      _fail();
    }
  }

  /// Requires one `[S<n>]` label per cited source, and no label without one.
  void _requireCitationLabels(String answer, Set<String> sourceIds) {
    final Set<String> labels = <String>{
      for (final RegExpMatch match in _citationLabel.allMatches(answer))
        match.group(1)!,
    };
    if (labels.isEmpty || labels.length != sourceIds.length) {
      _fail();
    }
    for (final String label in labels) {
      if (!sourceIds.contains(label)) {
        _fail();
      }
    }
  }

  /// Reads the strict `200` envelope shared by both routes.
  Map<String, dynamic> _envelope(
    Map<String, String> headers,
    Uint8List? bodyBytes,
    Set<String>? extraFields,
  ) {
    if (bodyBytes == null || !_isJsonUtf8(_header(headers, 'content-type'))) {
      _fail();
    }
    final Object? decoded = _decodeStrict(bodyBytes);
    if (decoded is! Map<String, dynamic>) {
      _fail();
    }
    if (decoded['wireVersion'] is! int ||
        decoded['wireVersion'] != ragWireVersion ||
        decoded['requestId'] is! String) {
      _fail();
    }
    if (extraFields != null && !_hasExactFields(decoded, extraFields)) {
      _fail();
    }
    return decoded;
  }

  /// Decodes a body that must be a valid envelope; any problem fails closed.
  static Object? _decodeStrict(Uint8List bodyBytes) {
    try {
      return decodeRagJson(bodyBytes);
    } on RagJsonProblem {
      _fail();
    }
  }

  static Never _fail() =>
      throw const RagFailure(RagFailureCode.invalidProviderOutput);
}

/// A whole non-negative JSON number inside the safe-integer range.
int? _safeInteger(Object? value) {
  if (value is! int || value < 0 || value > RagHttpMapper._maxSafeInteger) {
    return null;
  }
  return value;
}

/// Whether [value] has exactly [fields], no more and no fewer.
bool _hasExactFields(Map<String, dynamic> value, Set<String> fields) =>
    value.length == fields.length && fields.every(value.containsKey);
