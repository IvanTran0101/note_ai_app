/// HTTP transport for the frozen Phase 5 RAG API.
///
/// The adapter owns everything the Domain refuses to know about: the wire
/// envelope, the Cognito access token, JSON, response bounds, redirects, and the
/// absolute 26-second budget. It is deliberately small:
///
/// * One call is one attempt. There is no retry, no refresh-then-resend, no
///   redirect following, and no `401` special case.
/// * [RagCallContext] stays local. The `expectedUserId`, `cancelled`,
///   `beforeDispatch`, and `deadline` are never serialized, echoed, or logged,
///   and neither is the token.
/// * The context's `beforeDispatch` is awaited immediately before every
///   `client.send`, under the same budget, and is never allowed to start another
///   gateway call.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../domain/note_intelligence/i_rag_gateway.dart';
import '../../domain/note_intelligence/rag_models.dart';
import 'rag_http_call.dart';
import 'rag_http_mapper.dart';

part 'rag_http_response.dart';
part 'rag_http_token_part.dart';

/// HTTP implementation of [IRagGateway] for one API base URI.
final class RagHttpGateway implements IRagGateway {
  /// Creates a gateway over [baseUri] and the session [tokenProvider].
  ///
  /// [client] and [now] are bounded test seams: when no client is injected the
  /// gateway creates and owns one, and only then does [close] close it. The
  /// token supplier is always called with `forceRefresh: false` and at most once
  /// per gateway call.
  RagHttpGateway({
    required Uri baseUri,
    required Future<String?> Function({required bool forceRefresh})
    tokenProvider,
    http.Client? client,
    DateTime Function()? now,
  }) : _baseUri = _validateBaseUri(baseUri),
       // The public parameter name and the private field differ on purpose: the
       // frozen constructor names this seam `tokenProvider`.
       // ignore: prefer_initializing_formals
       _tokenProvider = tokenProvider,
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _now = now ?? DateTime.now;

  /// The consent route, appended to the base URI's path.
  static const String consentRoute = 'ai/rag/consent';

  /// The query route, appended to the base URI's path.
  static const String queryRoute = 'ai/rag/query';

  /// Transport cap for one response body (`responseMaxUtf8Bytes`).
  static const int maxResponseBytes = 64 * 1024;

  /// Request body cap (`bodyMaxUtf8Bytes`), mirroring the backend.
  static const int maxRequestBodyBytes = 16 * 1024;

  final Uri _baseUri;
  final Future<String?> Function({required bool forceRefresh}) _tokenProvider;
  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;
  final RagHttpMapper _mapper = const RagHttpMapper();
  final Set<RagHttpCall> _calls = <RagHttpCall>{};

  bool _closed = false;

  @override
  Future<RagConsent> readConsent({required RagCallContext context}) {
    return _perform(context, (RagHttpCall call) async {
      final String token = await _token(call, context);
      final http.StreamedResponse response = await _send(
        call,
        context,
        method: 'GET',
        route: consentRoute,
        token: token,
        body: null,
      );
      final Uint8List? body = await _readBody(call, response);
      call.throwIfStopped();
      return _mapper.mapConsent(
        statusCode: response.statusCode,
        headers: response.headers,
        bodyBytes: body,
      );
    });
  }

  @override
  Future<RagConsent> updateConsent(
    RagConsentUpdate update, {
    required RagCallContext context,
  }) {
    return _perform(context, (RagHttpCall call) async {
      final Uint8List body = _consentBody(update);
      final String token = await _token(call, context);
      final http.StreamedResponse response = await _send(
        call,
        context,
        method: 'PUT',
        route: consentRoute,
        token: token,
        body: body,
      );
      final Uint8List? responseBody = await _readBody(call, response);
      call.throwIfStopped();
      return _mapper.mapConsent(
        statusCode: response.statusCode,
        headers: response.headers,
        bodyBytes: responseBody,
      );
    });
  }

  @override
  Future<RagResult> query(
    RagRequest request, {
    required RagCallContext context,
  }) {
    return _perform(context, (RagHttpCall call) async {
      final Uint8List body = _queryBody(request);
      final String token = await _token(call, context);
      final http.StreamedResponse response = await _send(
        call,
        context,
        method: 'POST',
        route: queryRoute,
        token: token,
        body: body,
      );
      final Uint8List? responseBody = await _readBody(call, response);
      call.throwIfStopped();
      return _mapper.mapQuery(
        statusCode: response.statusCode,
        headers: response.headers,
        bodyBytes: responseBody,
      );
    });
  }

  /// Marks the gateway closed, aborts every in-flight call, and releases the
  /// client this gateway created.
  ///
  /// An injected client belongs to the composition root and is never closed
  /// here. In-flight calls settle with [RagFailureCode.cancelled]; their losing
  /// transport futures stay observed.
  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    final List<RagHttpCall> calls = List<RagHttpCall>.of(_calls);
    _calls.clear();
    for (final RagHttpCall call in calls) {
      call.close();
    }
    if (_ownsClient) {
      _client.close();
    }
  }

  /// Runs one operation under a fresh call budget, always releasing the call.
  ///
  /// The whole operation is raced against the call's cancellation, deadline, and
  /// close, so a transport that never answers settles exactly like a hanging
  /// token, guard, or body stream; the losing future stays observed.
  Future<T> _perform<T>(
    RagCallContext context,
    Future<T> Function(RagHttpCall call) operation,
  ) async {
    final RagHttpCall call = _beginCall(context);
    _calls.add(call);
    try {
      return await _classify(call, () => call.race(operation(call)));
    } finally {
      _calls.remove(call);
      call.dispose();
    }
  }

  /// Opens one call, refusing one whose absolute deadline already passed.
  RagHttpCall _beginCall(RagCallContext context) {
    if (_closed) {
      throw const RagFailure(RagFailureCode.cancelled);
    }
    final RagHttpCall call = RagHttpCall(context: context, now: _now());
    if (call.isStopped) {
      call.dispose();
      throw call.failure;
    }
    return call;
  }

  /// Acquires one token and refuses an egress the claims do not authorize.
  ///
  /// The token is not verified here — the backend owns the signature — but its
  /// subject, `token_use`, and expiry are decoded so a wrong account, an ID
  /// token, or an already expired token can never leave the process.
  Future<String> _token(RagHttpCall call, RagCallContext context) async {
    // Let an already-completed cancellation win before the supplier is called.
    await call.race(Future<void>.delayed(Duration.zero));
    call.throwIfStopped();
    final String? token = await call.race(_tokenProvider(forceRefresh: false));
    call.throwIfStopped();
    if (token == null || token.isEmpty) {
      throw const RagFailure(RagFailureCode.unauthorized);
    }
    final _TokenClaims? claims = _TokenClaims.read(token, _now());
    if (claims == null ||
        claims.subject != context.expectedUserId ||
        !claims.isAccessToken ||
        !claims.isLive) {
      throw const RagFailure(RagFailureCode.unauthorized);
    }
    return token;
  }

  /// Sends one request: guard first, then the frozen envelope, then the abort
  /// trigger that ends it on cancellation, deadline, or `close`.
  Future<http.StreamedResponse> _send(
    RagHttpCall call,
    RagCallContext context, {
    required String method,
    required String route,
    required String token,
    required Uint8List? body,
  }) async {
    call.throwIfStopped();
    final http.AbortableRequest request = http.AbortableRequest(
      method,
      _endpoint(route),
      abortTrigger: call.abortTrigger,
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept'] = 'application/json';
    request.followRedirects = false;
    request.maxRedirects = 0;
    if (body != null) {
      // `bodyBytes` keeps the content type exactly `application/json`; the string
      // setter appends a charset parameter the backend does not accept.
      request.headers['Content-Type'] = 'application/json';
      request.bodyBytes = body;
    }
    // The context's guard runs immediately before the request leaves, inside
    // the same budget, and may not start another gateway call.
    await call.race(context.beforeDispatch());
    call.throwIfStopped();
    return _client.send(request);
  }

  /// The exact query body: wire version, question, and scope, nothing else.
  Uint8List _queryBody(RagRequest request) {
    final Map<String, Object?> scope = request.scope.isAccount
        ? <String, Object?>{'type': 'account'}
        : <String, Object?>{
            'type': 'note',
            'noteId': request.scope.noteId,
          };
    return _encodeBody(<String, Object?>{
      'wireVersion': RagRequest.wireVersion,
      'question': request.question,
      'scope': scope,
    });
  }

  /// The exact consent write body: decision, version, and expected generation.
  Uint8List _consentBody(RagConsentUpdate update) {
    return _encodeBody(<String, Object?>{
      'accepted': update.accepted,
      'version': update.version,
      'expectedGeneration': update.expectedGeneration,
    });
  }

  Uint8List _encodeBody(Map<String, Object?> body) {
    final Uint8List encoded = utf8.encode(jsonEncode(body));
    if (encoded.length > maxRequestBodyBytes) {
      throw const RagFailure(RagFailureCode.inputTooLong);
    }
    return encoded;
  }

  /// Builds an absolute endpoint that keeps the base URI's stage path.
  Uri _endpoint(String route) {
    final String basePath = _baseUri.path.endsWith('/')
        ? _baseUri.path
        : '${_baseUri.path}/';
    return Uri(
      scheme: _baseUri.scheme,
      host: _baseUri.host,
      port: _baseUri.hasPort ? _baseUri.port : null,
      path: '$basePath$route',
    );
  }

  Future<T> _classify<T>(
    RagHttpCall call,
    Future<T> Function() operation,
  ) async {
    try {
      return await operation();
    } on RagFailure {
      rethrow;
    } on TimeoutException {
      throw const RagFailure(RagFailureCode.timeout);
    } on http.ClientException {
      throw _transportFailure(call);
    } on FormatException {
      // A raw format error is never attached to the failure a caller sees.
      throw const RagFailure(RagFailureCode.invalidProviderOutput);
    } catch (_) {
      throw const RagFailure(RagFailureCode.unexpected);
    }
  }

  /// Classifies one transport-level failure without ever echoing it.
  RagFailure _transportFailure(RagHttpCall call) {
    if (call.isStopped || call.isOversize) {
      return call.failure;
    }
    return const RagFailure(RagFailureCode.network);
  }

  /// Validates the base URI: HTTPS, or loopback HTTP for local development.
  static Uri _validateBaseUri(Uri baseUri) {
    final String scheme = baseUri.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') {
      throw ArgumentError('RAG base URI must be https');
    }
    if (baseUri.host.isEmpty) {
      throw ArgumentError('RAG base URI must have a host');
    }
    if (scheme == 'http' && !_isLoopback(baseUri.host)) {
      throw ArgumentError('RAG base URI may use http only for loopback');
    }
    if (baseUri.userInfo.isNotEmpty) {
      throw ArgumentError('RAG base URI must not carry credentials');
    }
    if (baseUri.hasQuery || baseUri.hasFragment) {
      throw ArgumentError('RAG base URI must not carry a query or fragment');
    }
    return baseUri;
  }

  static bool _isLoopback(String host) =>
      host == 'localhost' || host == '127.0.0.1' || host == '::1';
}
