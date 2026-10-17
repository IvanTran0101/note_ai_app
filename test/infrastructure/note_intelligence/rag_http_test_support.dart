/// Controlled transport, wire fixtures, and call contexts for the RAG gateway
/// tests.
///
/// Everything here is synthetic: no network, no provider, no real account. The
/// client records exactly what the gateway put on the wire so a test can assert
/// the actor-free body, the exact headers, and the request count.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/rag_http_gateway.dart';

/// The instant every gateway test pins its clock to.
final DateTime testNow = DateTime.utc(2026, 1, 1, 12);

/// A whole second far enough ahead that a fixture token is live at [testNow].
int freshExpiry([Duration ahead = const Duration(hours: 1)]) =>
    testNow.add(ahead).millisecondsSinceEpoch ~/ 1000;

/// Builds one unsigned Cognito-shaped access token.
String testToken({
  String subject = 'user-1',
  String tokenUse = 'access',
  int? expiresAt,
  Map<String, Object?> extra = const <String, Object?>{},
}) {
  String part(Map<String, Object?> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part(<String, Object?>{'alg': 'none', 'typ': 'JWT'})}.'
      '${part(<String, Object?>{
        'sub': subject,
        'token_use': tokenUse,
        'exp': expiresAt ?? freshExpiry(),
        ...extra,
      })}.'
      'signature';
}

/// A [http.Client] whose every exchange is scripted by [respond].
///
/// The client records each request and its bytes, so a test can assert the
/// exact wire shape, the request count (no retries), and whether `close` was
/// called on a client the gateway does not own.
final class ScriptedClient extends http.BaseClient {
  /// Creates a client that answers every request with [respond].
  ScriptedClient(this.respond);

  /// Answers one request; return a completer's future to hold it open.
  final Future<http.StreamedResponse> Function(http.BaseRequest request) respond;

  /// Every request the gateway sent, in order.
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  /// The exact body bytes of every request, in order.
  final List<Uint8List> bodies = <Uint8List>[];

  /// Whether the gateway closed this client.
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    bodies.add(
      request is http.Request
          ? Uint8List.fromList(request.bodyBytes)
          : Uint8List(0),
    );
    return respond(request);
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

/// Builds one streamed response around [bytes].
http.StreamedResponse streamedResponse(
  int statusCode,
  List<int> bytes, {
  String? contentType = 'application/json; charset=utf-8',
  Map<String, String> headers = const <String, String>{},
  int? contentLength,
}) {
  return http.StreamedResponse(
    Stream<List<int>>.value(bytes),
    statusCode,
    contentLength: contentLength ?? bytes.length,
    headers: <String, String>{
      'content-type': ?contentType,
      ...headers,
    },
  );
}

/// Builds one JSON response from [body].
http.StreamedResponse jsonResponse(
  int statusCode,
  Object? body, {
  String? contentType = 'application/json; charset=utf-8',
  Map<String, String> headers = const <String, String>{},
  int? contentLength,
}) {
  return streamedResponse(
    statusCode,
    utf8.encode(jsonEncode(body)),
    contentType: contentType,
    headers: headers,
    contentLength: contentLength,
  );
}

/// Builds one error envelope body.
Map<String, Object?> errorEnvelope(String code, {String requestId = 'req-1'}) =>
    <String, Object?>{
      'wireVersion': 1,
      'requestId': requestId,
      'status': 'ERROR',
      'code': code,
    };

/// Builds one consent envelope body.
Map<String, Object?> consentEnvelope({
  bool accepted = true,
  String version = RagConsent.currentVersion,
  int generation = 1,
  String requestId = 'req-1',
}) => <String, Object?>{
  'wireVersion': 1,
  'requestId': requestId,
  'consent': <String, Object?>{
    'accepted': accepted,
    'version': version,
    'generation': generation,
  },
};

/// Builds one answered query envelope body.
Map<String, Object?> answeredEnvelope({
  String answer = 'Answer [S1]',
  List<Map<String, Object?>>? sources,
  String requestId = 'req-1',
}) => <String, Object?>{
  'wireVersion': 1,
  'requestId': requestId,
  'status': 'ANSWERED',
  'answer': answer,
  'sources':
      sources ??
      <Map<String, Object?>>[
        sourceJson(quote: 'Body', start: 0, end: 4),
      ],
};

/// Builds one citation JSON object; defaults match `ownedNote()` content.
Map<String, Object?> sourceJson({
  String sourceId = 'S1',
  String noteId = 'note-1',
  int revision = 3,
  String title = 'Title',
  int start = 0,
  int end = 4,
  String quote = 'Body',
}) => <String, Object?>{
  'sourceId': sourceId,
  'noteId': noteId,
  'revision': revision,
  'title': title,
  'startOffset': start,
  'endOffset': end,
  'quote': quote,
};

/// Builds one local call context with a never-completing cancellation default.
RagCallContext testContext({
  String expectedUserId = 'user-1',
  Future<void>? cancelled,
  Future<void> Function()? beforeDispatch,
  DateTime? deadline,
  Duration budget = RagCallContext.requestBudget,
}) {
  return RagCallContext(
    expectedUserId: expectedUserId,
    cancelled: cancelled ?? Completer<void>().future,
    beforeDispatch: beforeDispatch ?? () async {},
    deadline: deadline ?? testNow.add(budget),
  );
}

/// Builds the gateway every transport test drives.
///
/// [tokenCalls] records the `forceRefresh` value of every supplier call, so a
/// test can assert that a `401` never triggers a refresh or a second call.
RagHttpGateway testGateway({
  required http.Client client,
  Uri? baseUri,
  List<bool>? tokenCalls,
  String? token,
  DateTime Function()? now,
}) {
  return RagHttpGateway(
    baseUri: baseUri ?? Uri.parse('https://api.example.test'),
    tokenProvider: ({required bool forceRefresh}) async {
      tokenCalls?.add(forceRefresh);
      return token ?? testToken();
    },
    client: client,
    now: now ?? () => testNow,
  );
}

/// Matches a thrown [RagFailure] whose code is [code].
Matcher throwsFailure(RagFailureCode code) {
  return throwsA(
    isA<RagFailure>().having((RagFailure f) => f.code, 'code', code),
  );
}
