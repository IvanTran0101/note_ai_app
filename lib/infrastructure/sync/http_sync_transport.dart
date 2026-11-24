part of 'http_remote_note_data_source.dart';

/// Authenticated send/read, session fences and provider-neutral failures.
extension _HttpSyncTransport on HttpRemoteNoteDataSource {
  /// Sends one request with a bearer token, refreshing the session at most once.
  ///
  /// A `401` triggers exactly one forced refresh and exactly one retry. A
  /// second `401` is returned to the caller as-is instead of looping, and a
  /// refresh that yields no token fails as unauthorized without a second
  /// request.
  Future<http.Response> _send({
    required String method,
    required Uri uri,
    Map<String, Object?>? body,
    SyncMutation? mutation,
  }) async {
    requireSession?.call();
    final String? token = await _tokenProvider(forceRefresh: false)
        .timeout(_timeout);
    requireSession?.call();
    if (token == null) {
      throw const SyncFailure(code: SyncErrorCode.unauthorized);
    }
    _requireExpectedAccount(token);

    http.Response response = await _dispatch(
      method: method,
      uri: uri,
      body: body,
      accessToken: token,
      mutation: mutation,
    );
    if (response.statusCode != 401) {
      return response;
    }

    final String? refreshed = await _tokenProvider(forceRefresh: true)
        .timeout(_timeout);
    requireSession?.call();
    if (refreshed == null) {
      throw const SyncFailure(code: SyncErrorCode.unauthorized);
    }
    _requireExpectedAccount(refreshed);
    response = await _dispatch(
      method: method,
      uri: uri,
      body: body,
      accessToken: refreshed,
      mutation: mutation,
    );
    return response;
  }

  /// Stops a token for another signed-in account before it can carry this
  /// account's local notes to the API. This is a client-side consistency guard,
  /// not JWT verification; API Gateway still verifies the token signature.
  void _requireExpectedAccount(String token) {
    final String? expected = _expectedAccountUserId;
    if (expected != null && _jwtSubject(token) != expected) {
      throw const SyncFailure(code: SyncErrorCode.forbidden);
    }
  }

  /// Performs one HTTP round trip under [_timeout].
  Future<http.Response> _dispatch({
    required String method,
    required Uri uri,
    required String accessToken,
    Map<String, Object?>? body,
    SyncMutation? mutation,
  }) async {
    requireSession?.call();
    String? grant;
    try {
      grant = mutation == null ? null : await mutationGrant?.call(mutation);
    } on NoteSecurityFailure catch (failure) {
      if (failure.code != NoteSecurityFailureCode.pendingSync) rethrow;
      return _dispatch(
        method: 'POST',
        uri: _endpoint(
          mutation != null && requiresSyncWireV3(mutation)
              ? 'sync/v3/protection-predecessor'
              : mutation != null && requiresSyncWireV2(mutation)
              ? 'sync/v2/protection-predecessor'
              : 'sync/protection-predecessor',
        ),
        accessToken: accessToken,
        body: body,
      );
    }
    requireSession?.call();
    final http.Request request = http.Request(method, uri);
    request.followRedirects = false;
    request.maxRedirects = 0;
    request.headers['Authorization'] = 'Bearer $accessToken';
    request.headers['Content-Type'] = HttpRemoteNoteDataSource._jsonContentType;
    request.headers['Accept'] = HttpRemoteNoteDataSource._jsonContentType;
    if (grant != null) request.headers['X-Note-Unlock-Grant'] = grant;
    if (body != null) {
      // `bodyBytes` instead of `body` keeps the content type exactly
      // `application/json`; the string setter appends a charset parameter.
      request.bodyBytes = utf8.encode(jsonEncode(body));
    }
    // The timeout covers reading the response body as well as the headers.
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(_timeout);
    requireSession?.call();
    if (mutation != null) await mutationGrant?.call(mutation);
    requireSession?.call();
    return response;
  }

  /// Runs one sync call and classifies every failure it can produce.
  ///
  /// A [SyncFailure] raised by the mapper is preserved; transport failures map
  /// to [SyncErrorCode.timeout] and [SyncErrorCode.networkUnavailable]. The
  /// remaining errors collapse to [SyncErrorCode.unexpected] and the original
  /// error is dropped rather than attached, because its text can carry a
  /// token, a URL, note content, or provider internals.
  Future<T> _classify<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on SyncFailure {
      rethrow;
    } on NoteSecurityFailure {
      throw const SyncFailure(code: SyncErrorCode.forbidden);
    } on TimeoutException {
      throw const SyncFailure(code: SyncErrorCode.timeout);
    } on http.ClientException {
      // `package:http` wraps socket-level failures in this type on IO
      // platforms and raises it directly on Web, which is what keeps this
      // adapter platform-neutral. TLS handshake failures are not wrapped; they
      // fall through to the generic case below.
      throw const SyncFailure(code: SyncErrorCode.networkUnavailable);
    } catch (_) {
      throw const SyncFailure(code: SyncErrorCode.unexpected);
    }
  }

  /// Builds an absolute URL from the base URI and a route [path].
  ///
  /// The base path is preserved whether or not it ends in a slash, so
  /// `https://host/api` and `https://host/api/` both reach
  /// `/api/sync/mutations`. Any query on the base URI is ignored: only the
  /// per-request [query] is sent.
  Uri _endpoint(String path, {Map<String, String>? query}) {
    final String basePath = _baseUri.path.endsWith('/')
        ? _baseUri.path
        : '${_baseUri.path}/';
    return Uri(
      scheme: _baseUri.scheme,
      userInfo: _baseUri.userInfo.isEmpty ? null : _baseUri.userInfo,
      host: _baseUri.host,
      port: _baseUri.hasPort ? _baseUri.port : null,
      path: '$basePath$path',
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  /// Reads the response body as UTF-8.
  ///
  /// JSON is UTF-8 by definition, but `http.Response.body` falls back to
  /// latin1 when the server omits a charset, which would corrupt non-ASCII
  /// note content.
  String _readBody(http.Response response) => utf8.decode(response.bodyBytes);

  /// Classifies a non-success response through the wire mapper.
  SyncFailure _decodeError(http.Response response) =>
      decodeError(statusCode: response.statusCode, body: _readBody(response));

  /// Whether [statusCode] is a 2xx success.
  bool _isSuccess(int statusCode) => statusCode >= 200 && statusCode < 300;
}

String? _jwtSubject(String token) {
  final List<String> parts = token.split('.');
  if (parts.length != 3) {
    return null;
  }
  try {
    final Object? payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is Map<String, dynamic>) {
      final Object? subject = payload['sub'];
      return subject is String && subject.isNotEmpty ? subject : null;
    }
  } on Object {
    return null;
  }
  return null;
}
