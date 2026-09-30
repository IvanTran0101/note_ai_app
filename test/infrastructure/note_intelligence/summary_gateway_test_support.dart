import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:note_ai_app/infrastructure/note_intelligence/summary_api_failure.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_http_gateway.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_request_policy.dart';

/// Matches a [SummaryApiFailure] carrying [code].
Matcher throwsCode(SummaryApiErrorCode code) => throwsA(
  isA<SummaryApiFailure>().having(
    (SummaryApiFailure failure) => failure.code,
    'code',
    code,
  ),
);

/// A synthetic Cognito-shaped access token; never a real credential.
///
/// Only the payload segment matters here, and [id] keeps two tokens for the
/// same account distinguishable in the `Authorization` header.
String jwt(String? subject, {String id = 'a'}) {
  final Map<String, Object?> payload = <String, Object?>{
    'token_use': 'access',
    'jti': id,
  };
  if (subject != null) {
    payload['sub'] = subject;
  }
  return '${_jwtSegment(<String, Object?>{'alg': 'RS256', 'typ': 'JWT'})}'
      '.${_jwtSegment(payload)}.c2lnbmF0dXJl';
}

String _jwtSegment(Map<String, Object?> payload) =>
    base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');

String successBody({String summary = 'Tóm tắt ổn định ✓'}) =>
    jsonEncode(<String, Object?>{
      'summary': summary,
      'requestId': 'req-1',
      'usage': <String, Object?>{'inputTokens': 120, 'outputTokens': 20},
    });

/// A response with no declared content length, like a chunked API response.
http.StreamedResponse response(
  int statusCode,
  String body, {
  Map<String, String> headers = const <String, String>{},
  int? contentLength,
  Stream<List<int>>? stream,
}) => http.StreamedResponse(
  stream ?? Stream<List<int>>.value(utf8.encode(body)),
  statusCode,
  headers: headers,
  contentLength: contentLength,
);

http.StreamedResponse envelope(
  int statusCode,
  SummaryApiErrorCode code, {
  Map<String, String> headers = const <String, String>{},
}) => response(
  statusCode,
  '{"error":{"code":"${code.name}"},"requestId":"req-1"}',
  headers: headers,
);

/// A client that records what the gateway sends and answers with [onSend].
final class SummaryTestClient extends http.BaseClient {
  SummaryTestClient(this._onSend);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  _onSend;

  final List<http.BaseRequest> requests = <http.BaseRequest>[];
  final List<Uint8List> bodies = <Uint8List>[];
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final Uint8List body = await request.finalize().toBytes();
    requests.add(request);
    bodies.add(body);
    return _onSend(request);
  }

  @override
  void close() => closed = true;
}

Future<String?> Function({required bool forceRefresh}) staticToken(
  String value,
) =>
    ({required bool forceRefresh}) async => value;

final class SummaryGatewayTestFixture {
  SummaryGatewayTestFixture(this.policy);
  final SummaryRequestPolicy policy;
  final String token = jwt('user-1', id: 'first');
  final String refreshedToken = jwt('user-1', id: 'second');

  SummaryHttpGateway buildGateway({
    required SummaryTestClient client,
    required Future<String?> Function({required bool forceRefresh})
    tokenProvider,
    Duration timeout = const Duration(seconds: 35),
    String expectedAccountUserId = 'user-1',
    Uri? baseUri,
  }) => SummaryHttpGateway(
    baseUri: baseUri ?? Uri.parse('https://api.example.com/prod'),
    policy: policy,
    tokenProvider: tokenProvider,
    expectedAccountUserId: expectedAccountUserId,
    client: client,
    timeout: timeout,
  );

  /// A client whose every response is the given success envelope.
  SummaryTestClient successClient({String? summary}) => SummaryTestClient(
    (http.BaseRequest request) async =>
        response(200, successBody(summary: summary ?? 'Tóm tắt ổn định ✓')),
  );

  Future<String> generate(
    SummaryHttpGateway gateway, {
    SummaryStage stage = SummaryStage.direct,
    List<String> inputs = const <String>['Nội dung ghi chú'],
    bool consentAccepted = true,
    DateTime? deadline,
  }) => gateway.generate(
    stage: stage,
    inputs: inputs,
    consentAccepted: consentAccepted,
    deadline: deadline,
  );
}
