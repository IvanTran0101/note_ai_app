/// In-process, debug-only HTTP transport for the explicit offline RAG mock.
///
/// This client owns no network client at all: it can only answer from bounded,
/// mutable in-memory state. Every request is validated (logical host, route
/// allowlist, no feature headers) *before* it is handled, and an unknown host or
/// route throws a [http.ClientException] instead of being forwarded anywhere.
///
/// The responses are the real frozen envelopes: the canonical consent DTO, the
/// empty `wireVersion` 1/2 changes page, the RAG `wireVersion` 1 answer and
/// refusal shapes, and safe `ERROR` envelopes. The production `RagHttpMapper`
/// and the real sync mapper parse them unchanged, so this exercises the real
/// adapter code rather than a parallel fake.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/note_intelligence/rag_models.dart';
import 'rag_mock_actors.dart';
import 'rag_mock_fixture.dart';

/// A synthetic, in-memory [http.Client] for the offline RAG mock root.
final class RagMockClient extends http.BaseClient {
  /// Creates the client.
  RagMockClient();

  /// The only logical host this transport answers to.
  static const String logicalHost = 'rag-mock.invalid';

  /// Request bodies larger than this are refused before any decode.
  static const int maxRequestBytes = 64 * 1024;

  final Map<String, _MockConsent> _consents = <String, _MockConsent>{};
  bool _closed = false;
  int _served = 0;
  int _requestIds = 0;

  /// Requests that passed host/route/header validation, for test assertions.
  ///
  /// A refused request never increments this, which is how a test proves the
  /// refusal happened before any handling (and therefore before any network
  /// could have happened).
  int get servedRequests => _served;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) {
      throw http.ClientException('The offline RAG mock is closed.');
    }
    final Uri uri = request.url;
    _requireLogicalRoute(uri);
    _requireAllowedHeaders(request);
    final Uint8List body = await _readRequest(request);
    final _MockReply reply = _reply(request.method, uri, body, request);
    _served++;
    final List<int> bytes = utf8.encode(jsonEncode(reply.body));
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      reply.statusCode,
      contentLength: bytes.length,
      headers: const <String, String>{'content-type': 'application/json'},
      request: request,
    );
  }

  @override
  void close() {
    _closed = true;
  }

  /// The current canonical consent for [actor]; absent rows are
  /// [RagConsent.none] and are never auto-granted.
  RagConsent consentFor(RagMockActor actor) =>
      (_consents[actor.userId] ?? _MockConsent.none).toDomain();

  void _requireLogicalRoute(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https' ||
        uri.host != logicalHost ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw http.ClientException(
        'The offline RAG mock refuses every route outside https://$logicalHost.',
      );
    }
    final String path = uri.path;
    final bool known = switch (path) {
      '/ai/rag/consent' => true,
      '/ai/rag/query' => true,
      '/sync/changes' => true,
      '/sync/v2/changes' => true,
      '/health' => true,
      _ => false,
    };
    // Sync mutation routes are known but deliberately read-only; every other
    // path (profile, attachments, summaries, labels projections) is refused.
    if (!known && !path.startsWith('/sync/')) {
      throw http.ClientException(
        'The offline RAG mock refuses the unknown route ${uri.path}.',
      );
    }
  }

  void _requireAllowedHeaders(http.BaseRequest request) {
    for (final String name in request.headers.keys) {
      final String lower = name.toLowerCase();
      if (lower.startsWith('x-note-') ||
          lower.startsWith('x-amz-') ||
          lower == 'x-api-key') {
        throw http.ClientException(
          'The offline RAG mock refuses provider feature headers.',
        );
      }
    }
  }

  Future<Uint8List> _readRequest(http.BaseRequest request) async {
    final Uint8List bytes = await request.finalize().toBytes();
    if (bytes.length > maxRequestBytes) {
      throw http.ClientException(
        'The offline RAG mock refuses an oversized request.',
      );
    }
    return bytes;
  }

  _MockReply _reply(
    String method,
    Uri uri,
    Uint8List body,
    http.BaseRequest request,
  ) {
    final String path = uri.path;
    if (path == '/health' && method == 'GET') {
      return _MockReply(200, <String, Object?>{
        'wireVersion': 1,
        'status': 'ok',
        'mock': logicalHost,
      });
    }
    final RagMockActor actor = _requireActor(request);
    if (path == '/ai/rag/consent') {
      if (method == 'GET') return _readConsent(actor);
      if (method == 'PUT') return _writeConsent(actor, body);
      return _refuseMethod();
    }
    if (path == '/ai/rag/query' && method == 'POST') {
      return _query(actor, body);
    }
    if ((path == '/sync/changes' || path == '/sync/v2/changes') &&
        method == 'GET') {
      return _emptyChanges(path == '/sync/v2/changes' ? 2 : 1);
    }
    if (path.startsWith('/sync/') && method == 'POST') {
      return _MockReply(403, <String, Object?>{
        'status': 'ERROR',
        'code': 'FORBIDDEN',
      });
    }
    return _refuseMethod();
  }

  RagMockActor _requireActor(http.BaseRequest request) {
    final String? header =
        request.headers['Authorization'] ?? request.headers['authorization'];
    if (header == null || !header.startsWith('Bearer ')) {
      throw http.ClientException('The offline RAG mock requires a mock token.');
    }
    final RagMockActor? actor = ragMockActorFromUserId(
      ragMockJwtSubject(header.substring('Bearer '.length)),
    );
    if (actor == null) {
      throw http.ClientException('The offline RAG mock requires a mock actor.');
    }
    return actor;
  }

  _MockReply _readConsent(RagMockActor actor) => _MockReply(
    200,
    _consentEnvelope(_consents[actor.userId] ?? _MockConsent.none),
  );

  _MockReply _writeConsent(RagMockActor actor, Uint8List body) {
    final Map<String, dynamic>? decoded = _decodeObject(body);
    if (decoded == null) return _invalidInput();
    final Object? accepted = decoded['accepted'];
    final Object? version = decoded['version'];
    final Object? expected = decoded['expectedGeneration'];
    if (accepted is! bool ||
        version is! String ||
        version != RagConsent.currentVersion ||
        expected is! int ||
        expected < 0) {
      return _invalidInput();
    }
    final _MockConsent current = _consents[actor.userId] ?? _MockConsent.none;
    if (expected != current.generation) {
      return _errorEnvelope(409, 'SOURCE_CHANGED');
    }
    final _MockConsent next = _MockConsent(
      accepted: accepted,
      generation: current.generation + 1,
    );
    _consents[actor.userId] = next;
    return _MockReply(200, _consentEnvelope(next));
  }

  _MockReply _query(RagMockActor actor, Uint8List body) {
    final Map<String, dynamic>? decoded = _decodeObject(body);
    if (decoded == null || decoded['wireVersion'] != 1) {
      return _invalidInput();
    }
    final Object? question = decoded['question'];
    final Object? scope = decoded['scope'];
    if (question is! String || scope is! Map<String, dynamic>) {
      return _invalidInput();
    }
    final _MockConsent consent = _consents[actor.userId] ?? _MockConsent.none;
    if (!consent.accepted) {
      return _errorEnvelope(403, 'CONSENT_REQUIRED');
    }
    final RagMockFixture fixture = ragMockFixtureFor(actor);
    final bool scopeAllowed =
        scope['type'] == 'account' ||
        (scope['type'] == 'note' && scope['noteId'] == fixture.noteId);
    if (!scopeAllowed) {
      return _errorEnvelope(403, 'SCOPE_DENIED');
    }
    final String requestId = _nextRequestId();
    if (question.trim() == ragMockAnswerableQuestion) {
      return _MockReply(200, <String, Object?>{
        'wireVersion': 1,
        'requestId': requestId,
        'status': 'ANSWERED',
        'answer': fixture.answer,
        'sources': <Object?>[fixture.sourceWire],
      });
    }
    // Every other question — including the documented unrelated one — is a
    // normal refusal. The mock never copies the fixture answer onto an
    // arbitrary question and makes no model-quality claim.
    return _MockReply(200, <String, Object?>{
      'wireVersion': 1,
      'requestId': requestId,
      'status': 'NOT_ENOUGH_CONTEXT',
      'reason': 'INSUFFICIENT_EVIDENCE',
      'answer': null,
      'sources': const <Object?>[],
    });
  }

  _MockReply _emptyChanges(int wireVersion) =>
      _MockReply(200, <String, Object?>{
        'wireVersion': wireVersion,
        'items': const <Object?>[],
        'nextCursor': null,
        'hasMore': false,
      });

  Map<String, Object?> _consentEnvelope(_MockConsent consent) =>
      <String, Object?>{
        'wireVersion': 1,
        'requestId': _nextRequestId(),
        'consent': consent.toWire(),
      };

  _MockReply _errorEnvelope(int status, String code) => _MockReply(status, {
    'wireVersion': 1,
    'requestId': _nextRequestId(),
    'status': 'ERROR',
    'code': code,
  });

  _MockReply _invalidInput() => _errorEnvelope(400, 'INVALID_INPUT');

  _MockReply _refuseMethod() => _errorEnvelope(405, 'INVALID_INPUT');

  String _nextRequestId() => 'rag-mock-${++_requestIds}';

  static Map<String, dynamic>? _decodeObject(Uint8List body) {
    if (body.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(utf8.decode(body));
      return decoded is Map<String, dynamic> ? decoded : null;
    } on Object {
      return null;
    }
  }
}

/// One bounded, in-memory consent row; the default is the canonical none.
final class _MockConsent {
  const _MockConsent({required this.accepted, required this.generation});

  static const _MockConsent none = _MockConsent(accepted: false, generation: 0);

  final bool accepted;
  final int generation;

  RagConsent toDomain() =>
      RagConsent(accepted: accepted, generation: generation);

  Map<String, Object?> toWire() => <String, Object?>{
    'accepted': accepted,
    'version': RagConsent.currentVersion,
    'generation': generation,
  };
}

/// One synthetic response: a status and an already-JSON-safe body.
final class _MockReply {
  const _MockReply(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;
}
