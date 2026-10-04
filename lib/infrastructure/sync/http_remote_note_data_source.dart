/// Cross-platform HTTP adapter for the remote note sync port.
///
/// One implementation serves iOS, macOS, and Web: `package:http` picks the
/// platform client, so this library never imports `dart:io` and needs no
/// conditional import per platform.
///
/// The adapter owns transport only. It attaches credentials, routes requests,
/// and classifies failures; every wire shape is decoded by
/// `sync_http_mapper.dart`, and every value crossing the boundary is an
/// Application contract type. It never logs: an access token, note content, a
/// request body, a cursor in a query string, and raw exception text are all
/// kept out of thrown values because the only field a [SyncFailure] carries is
/// whatever safe message the mapper chose to expose.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../application/sync/remote_note_data_source.dart';
import '../../application/sync/shared_label_projection_source.dart';
import '../../application/sync/local_note_state.dart';
import '../../application/sync/sync_failure.dart';
import '../../application/sync/sync_mutation.dart';
import '../../application/sync/sync_result.dart';
import '../../application/sync/sync_snapshot.dart';
import 'sync_http_mapper.dart';
import '../../application/notes/note_access.dart';

/// Supplies the bearer token for one sync call.
///
/// `forceRefresh` asks the provider to ignore any cached session and re-issue
/// credentials. Returning `null` means "no usable token"; the adapter turns
/// that into [SyncErrorCode.unauthorized] without issuing a request.
///
/// `CognitoAccessTokenProvider` in `cognito_access_token_provider.dart` is the
/// production implementation.
typedef SyncAccessTokenProvider = Future<String?> Function({
  required bool forceRefresh,
});

/// [IRemoteNoteDataSource] over the frozen M1.0 HTTP contract.
///
/// Routes: `POST /sync/mutations` (one mutation per request, idempotent by
/// `mutationId`) and `GET /sync/changes` (opaque cursor paging).
final class HttpRemoteNoteDataSource
    implements IRemoteNoteDataSource, ISharedLabelProjectionSource {
  /// Creates the adapter over [baseUri], for example
  /// `https://abc123.execute-api.ap-southeast-1.amazonaws.com/prod`.
  ///
  /// [client] is optional: when it is omitted the adapter creates and owns one,
  /// and [close] releases it. An injected client is borrowed for its lifetime
  /// and is never closed here. [timeout] bounds one whole send-and-read; it
  /// defaults to 30 seconds.
  factory HttpRemoteNoteDataSource({
    required Uri baseUri,
    required SyncAccessTokenProvider tokenProvider,
    http.Client? client,
    Duration timeout = const Duration(seconds: 30),
    String? expectedAccountUserId,
    Future<String?> Function(SyncMutation)? mutationGrant,
    void Function()? requireSession,
    bool labelsEnabled = false,
    String? Function(LocalNoteState)? projectionGrant,
  }) {
    return HttpRemoteNoteDataSource._(
      baseUri: baseUri,
      tokenProvider: tokenProvider,
      client: client ?? http.Client(),
      ownsClient: client == null,
      timeout: timeout,
      expectedAccountUserId: expectedAccountUserId,
      mutationGrant: mutationGrant,
      requireSession: requireSession,
      labelsEnabled: labelsEnabled,
      projectionGrant: projectionGrant,
    );
  }

  /// Assigns the collaborators and the client-ownership decision resolved by
  /// the public factory.
  HttpRemoteNoteDataSource._({
    required this._baseUri,
    required this._tokenProvider,
    required this._client,
    required this._ownsClient,
    required this._timeout,
    required this._expectedAccountUserId,
    required this.mutationGrant,
    required this.requireSession,
    required this.labelsEnabled,
    required this.projectionGrant,
  });

  /// Async mutation route.
  static const String _mutationsPath = 'sync/mutations';

  /// Change-feed route.
  static const String _changesPath = 'sync/changes';

  /// The only media type this adapter sends and accepts.
  static const String _jsonContentType = 'application/json';

  final Uri _baseUri;
  final SyncAccessTokenProvider _tokenProvider;
  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;
  final String? _expectedAccountUserId;
  final Future<String?> Function(SyncMutation)? mutationGrant;
  final void Function()? requireSession;
  final bool labelsEnabled;
  final String? Function(LocalNoteState)? projectionGrant;

  @override
  Future<List<SyncNoteSnapshot>> refreshLabels(
    Iterable<LocalNoteState> notes,
  ) => _classify(() async {
    final refs = notes
        .where(
          (n) =>
              !n.isDeleted &&
              n.contentAvailable &&
              (n.share?.isActive == true || n.protection.enabled),
        )
        .toList();
    final snapshots = <SyncNoteSnapshot>[];
    for (var offset = 0; offset < refs.length; offset += 50) {
      requireSession?.call();
      final batch = refs.skip(offset).take(50).toList();
      final request = <Map<String, Object?>>[];
      for (final note in batch) {
        String? grant;
        try {
          grant = projectionGrant?.call(note);
        } on NoteSecurityFailure {
          continue;
        }
        request.add({
          'ownerId': note.ownerId,
          'noteId': note.id,
          'grant': ?grant,
        });
      }
      if (request.isEmpty) continue;
      final response = await _send(
        method: 'POST',
        uri: _endpoint('sync/v2/label-projections'),
        body: {'wireVersion': 2, 'notes': request},
      );
      if (!_isSuccess(response.statusCode)) throw _decodeError(response);
      final page = decodeChangesPage(
        _readBody(response),
        authorizedContent: true,
      );
      if (page.wireVersion != 2 || page.labels.isNotEmpty) {
        throw const FormatException('Scoped Note response required.');
      }
      for (final snapshot in page.snapshots) {
        // Owned wire snapshots use the authenticated actor as implicit owner.
        // Never infer a missing owner from the requested resource itself.
        final owner = snapshot.ownerId ?? _expectedAccountUserId;
        final ref = request
            .where((r) => r['ownerId'] == owner && r['noteId'] == snapshot.id)
            .firstOrNull;
        final note = batch
            .where((n) => n.ownerId == owner && n.id == snapshot.id)
            .firstOrNull;
        if (ref == null || note == null || !snapshot.includesLabels) {
          throw const SyncFailure(code: SyncErrorCode.forbidden);
        }
        // A local lock during HTTP must invalidate even an authorized response.
        if (projectionGrant?.call(note) != ref['grant']) {
          throw const SyncFailure(code: SyncErrorCode.forbidden);
        }
      }
      snapshots.addAll(page.snapshots);
    }
    return snapshots;
  });

  @override
  Future<SyncMutationResult> push(SyncMutation mutation) {
    return _classify(() async {
      final http.Response response = await _send(
        method: 'POST',
        uri: _endpoint(
          mutation.isLabel || mutation.payload?.includesLabels == true
              ? mutation.ownerId != null
                    ? 'sync/v2/shared-mutations'
                    : mutation.protectionChange != null
                    ? 'sync/v2/protected-mutations'
                    : 'sync/v2/mutations'
              : mutation.ownerId != null
              ? 'sync/shared-mutations'
              : mutation.protectionChange == null
              ? _mutationsPath
              : 'sync/protected-mutations',
        ),
        body: encodeSyncMutation(mutation),
        mutation: mutation,
      );
      // A stale `baseRevision` is a result, not a failure: the mapper turns the
      // 409 envelope into `SyncMutationResult.conflict`, which the caller
      // reconciles against the remote snapshot it carries.
      final securityConflict =
          response.statusCode == 409 &&
          _decodeError(response).code == SyncErrorCode.forbidden;
      if (_isSuccess(response.statusCode) ||
          (response.statusCode == 409 && !securityConflict)) {
        final result = decodeSyncMutationResponse(
          statusCode: response.statusCode,
          body: _readBody(response),
          mutationId: mutation.mutationId,
        );
        if (mutation.isLabel && result.label == null && result.isApplied ||
            !mutation.isLabel && result.label != null) {
          throw const FormatException('Entity outcome mismatch.');
        }
        if (mutation.payload?.includesLabels == true &&
            result.note?.includesLabels != true &&
            result.isApplied) {
          throw const SyncFailure(code: SyncErrorCode.invalidMutation);
        }
        if (mutation.ownerId != null) {
          final snapshot = result.note ?? result.conflictRemote;
          if (result.mutationId != mutation.mutationId ||
              (snapshot != null &&
                  (snapshot.ownerId != mutation.ownerId ||
                      snapshot.id != mutation.noteId ||
                      snapshot.share == null ||
                      (_expectedAccountUserId != null &&
                          snapshot.share!.recipientId !=
                              _expectedAccountUserId)))) {
            throw const SyncFailure(code: SyncErrorCode.forbidden);
          }
        }
        return result;
      }
      throw _decodeError(response);
    });
  }

  @override
  Future<SyncChangesPage> pull({String? cursor, int limit = 50}) {
    return _classify(() async {
      final http.Response response = await _send(
        method: 'GET',
        uri: _endpoint(
          labelsEnabled ? 'sync/v2/changes' : _changesPath,
          query: <String, String>{
            // The cursor is opaque: it is forwarded exactly as the caller
            // stored it, never parsed, rebuilt, or truncated here.
            'cursor': ?cursor,
            'limit': '$limit',
          },
        ),
      );
      if (!_isSuccess(response.statusCode)) {
        throw _decodeError(response);
      }
      // The page is returned untouched, so a final page keeps the server's
      // `nextCursor` together with `hasMore == false`.
      final page = decodeChangesPage(_readBody(response));
      if (labelsEnabled && page.wireVersion != 2) {
        throw const FormatException('V2 negotiation failed.');
      }
      return page;
    });
  }

  /// Releases the HTTP client, but only when this adapter created it.
  ///
  /// An injected client belongs to whoever injected it and stays open, so a
  /// caller that shares one client across adapters is not left with a closed
  /// connection pool.
  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

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
          mutation?.payload?.includesLabels == true
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
    request.headers['Content-Type'] = _jsonContentType;
    request.headers['Accept'] = _jsonContentType;
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
  static String _readBody(http.Response response) =>
      utf8.decode(response.bodyBytes);

  /// Classifies a non-success response through the wire mapper.
  static SyncFailure _decodeError(http.Response response) =>
      decodeError(statusCode: response.statusCode, body: _readBody(response));

  /// Whether [statusCode] is a 2xx success.
  static bool _isSuccess(int statusCode) =>
      statusCode >= 200 && statusCode < 300;
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
