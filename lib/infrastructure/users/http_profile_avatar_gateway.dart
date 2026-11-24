/// Cross-platform HTTP adapter for private profile-avatar binary I/O.
///
/// One implementation serves iOS, macOS, and Web: `package:http` picks the
/// platform client, so this library never imports `dart:io` and needs no
/// conditional import per platform.
///
/// Upload is a three-leg capability flow: a bound intent is created for the
/// signed-in identity, the bytes are staged with the returned short-lived
/// presigned `PUT` (which deliberately carries no NoteFlow bearer token), and
/// the intent is completed so the server can pin and verify the object before
/// associating it with the profile revision. Reads go through the authenticated
/// route only; no presigned or public GET URL is ever used.
///
/// Every failure crossing this boundary is a [ProfileFailure] carrying a code
/// and nothing else: a token, a signed URL, a header value, and raw exception
/// text are all kept out of thrown values.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import '../../domain/users/profile_avatar_gateway.dart';
import '../../domain/users/profile_failure.dart';
import '../security/note_jwt_subject.dart';
import 'http_user_profile_repository.dart' show ProfileAccessTokenProvider;

/// [IProfileAvatarGateway] over the frozen M01.3 avatar contract.
///
/// Routes: `GET /me/avatar`, `POST /me/avatar-intents`, and
/// `POST /me/avatar-intents/{id}/complete`.
final class HttpProfileAvatarGateway implements IProfileAvatarGateway {
  /// Creates the gateway over [baseUri], for example
  /// `https://abc123.execute-api.ap-southeast-1.amazonaws.com/prod`.
  ///
  /// [baseUri] must be HTTPS: avatar bytes, bearer tokens, and staging
  /// capabilities never travel over plaintext. [client] is optional; when it is
  /// omitted the adapter creates and owns one, and [close] releases it. An
  /// injected client is borrowed for its lifetime and is never closed here.
  factory HttpProfileAvatarGateway({
    required Uri baseUri,
    required ProfileAccessTokenProvider accessTokenProvider,
    required Future<String?> Function() authenticatedUserId,
    http.Client? client,
  }) {
    if (baseUri.scheme != 'https' ||
        baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment) {
      throw ArgumentError('An HTTPS profile API base URI is required.');
    }
    return HttpProfileAvatarGateway._(
      baseUri: baseUri,
      accessTokenProvider: accessTokenProvider,
      authenticatedUserId: authenticatedUserId,
      client: client ?? http.Client(),
      ownsClient: client == null,
    );
  }

  /// Assigns the collaborators and the client-ownership decision resolved by
  /// the public factory.
  HttpProfileAvatarGateway._({
    required this._baseUri,
    required this._accessTokenProvider,
    required this._authenticatedUserId,
    required this._client,
    required this._ownsClient,
  });

  /// Authenticated avatar read route.
  static const String _avatarPath = 'me/avatar';

  /// Bound-intent create route.
  static const String _intentsPath = 'me/avatar-intents';

  /// The only media type this adapter sends and accepts as JSON.
  static const String _jsonContentType = 'application/json';

  /// Upper bound on one intent/error response body.
  static const int _maxResponseBytes = 8 * 1024;

  /// Wire code of the canonical "this account has no avatar" envelope.
  static const String _missingCode = 'PROFILE_AVATAR_MISSING';

  /// Headers a staging `PUT` may carry. `authorization` is deliberately absent:
  /// the app bearer token must never reach the storage host.
  static const Set<String> _allowedUploadHeaders = <String>{
    'content-type',
    'x-amz-checksum-sha256',
    'x-amz-server-side-encryption',
  };

  /// Exact fields of the intent response; anything else is off-contract.
  static const Set<String> _intentKeys = <String>{
    'intentId',
    'uploadUrl',
    'headers',
  };

  /// Opaque, URL-safe intent id shape accepted from the server.
  static final RegExp _intentIdPattern = RegExp(r'^[A-Za-z0-9._~-]{1,128}$');

  static const Duration _timeout = Duration(seconds: 30);

  final Uri _baseUri;
  final ProfileAccessTokenProvider _accessTokenProvider;
  final Future<String?> Function() _authenticatedUserId;
  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<Uint8List?> getAvatar(String userId) async {
    final String actor = _requireUserId(userId);
    final http.StreamedResponse response = await _authorizedSend(
      method: 'GET',
      uri: _endpoint(_avatarPath),
      expectedUserId: actor,
    );
    if (response.statusCode == 200) {
      final Uint8List bytes = await _readAvatar(response);
      // The bytes are about to cross the boundary: re-check the actor so a
      // session switched during the body read cannot receive them.
      await _requireActor(actor);
      return bytes;
    }
    if (response.statusCode == 404) {
      if (await _isCanonicalMissing(response)) {
        await _requireActor(actor);
        return null;
      }
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    }
    await _discard(response);
    throw _failureFor(response.statusCode);
  }

  @override
  Future<void> uploadAvatar({
    required String userId,
    required int expectedRevision,
    required Uint8List bytes,
    required String mime,
  }) async {
    final String actor = _requireUserId(userId);
    if (expectedRevision < 0) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'must not be negative',
      );
    }
    ProfileAvatarRules.validateInput(bytes: bytes, mime: mime);
    final _AvatarIntent intent = await _createIntent(
      actor: actor,
      expectedRevision: expectedRevision,
      mime: mime,
      bytes: bytes,
    );
    await _stage(actor, intent, bytes);
    await _complete(actor, intent.intentId);
  }

  /// Releases the HTTP client, but only when this adapter created it.
  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  /// Creates the bound staging intent, refreshing the session at most once.
  Future<_AvatarIntent> _createIntent({
    required String actor,
    required int expectedRevision,
    required String mime,
    required Uint8List bytes,
  }) async {
    final String sha256 = crypto.sha256.convert(bytes).toString();
    final Map<String, Object?> body = <String, Object?>{
      'requestId': _requestId(
        actor: actor,
        expectedRevision: expectedRevision,
        mime: mime,
        sizeBytes: bytes.length,
        sha256: sha256,
      ),
      'expectedProfileRevision': expectedRevision,
      'mime': mime,
      'sizeBytes': bytes.length,
      'sha256': sha256,
    };
    for (var attempt = 0; attempt < 2; attempt++) {
      final String token = await _verifiedToken(
        actor,
        forceRefresh: attempt == 1,
      );
      final http.StreamedResponse response = await _dispatch(
        method: 'POST',
        uri: _endpoint(_intentsPath),
        token: token,
        body: body,
      );
      await _requireActor(actor);
      if (response.statusCode == 401 && attempt == 0) {
        await _discard(response);
        continue;
      }
      if (response.statusCode == 200) {
        return _readIntent(response);
      }
      await _discard(response);
      throw _failureFor(response.statusCode);
    }
    throw const ProfileFailure(ProfileFailureCode.unauthorized);
  }

  /// Stages [bytes] at the signed capability, without any bearer token.
  Future<void> _stage(
    String actor,
    _AvatarIntent intent,
    Uint8List bytes,
  ) async {
    await _requireActor(actor);
    final http.Request request = http.Request('PUT', intent.uploadUrl)
      ..followRedirects = false
      ..maxRedirects = 0;
    request.bodyBytes = bytes;
    // The server-provided allowlist already excludes `authorization`, so the
    // app token is never forwarded to the storage host.
    request.headers.addAll(intent.headers);
    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(_timeout);
    } on TimeoutException {
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    } on http.ClientException {
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    } on Object {
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    }
    await _requireActor(actor);
    await _discard(response);
    if (response.statusCode != 200) {
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    }
  }

  /// Completes the intent, pinning and verifying the staged object server-side.
  Future<void> _complete(String actor, String intentId) async {
    final Uri uri = _endpoint(
      '$_intentsPath/${Uri.encodeComponent(intentId)}/complete',
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      final String token = await _verifiedToken(
        actor,
        forceRefresh: attempt == 1,
      );
      final http.StreamedResponse response = await _dispatch(
        method: 'POST',
        uri: uri,
        token: token,
        body: const <String, Object?>{},
      );
      await _requireActor(actor);
      if (response.statusCode == 401 && attempt == 0) {
        await _discard(response);
        continue;
      }
      if (response.statusCode == 200) {
        await _discard(response);
        return;
      }
      await _discard(response);
      throw _failureFor(response.statusCode);
    }
    throw const ProfileFailure(ProfileFailureCode.unauthorized);
  }

  /// Sends one authorized request, refreshing the session at most once.
  ///
  /// The signed-in actor is re-verified before the token fetch, after it, and
  /// after the response arrives. A `401` triggers exactly one forced refresh and
  /// exactly one retry with the same payload; a second `401` is unauthorized.
  Future<http.StreamedResponse> _authorizedSend({
    required String method,
    required Uri uri,
    required String expectedUserId,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final String token = await _verifiedToken(
        expectedUserId,
        forceRefresh: attempt == 1,
      );
      final http.StreamedResponse response = await _dispatch(
        method: method,
        uri: uri,
        token: token,
      );
      await _requireActor(expectedUserId);
      if (response.statusCode == 401 && attempt == 0) {
        await _discard(response);
        continue;
      }
      return response;
    }
    throw const ProfileFailure(ProfileFailureCode.unauthorized);
  }

  /// Returns a token that provably belongs to [expectedUserId].
  Future<String> _verifiedToken(
    String expectedUserId, {
    required bool forceRefresh,
  }) async {
    await _requireActor(expectedUserId);
    final String token;
    try {
      token = await _accessTokenProvider(forceRefresh: forceRefresh);
    } on ProfileFailure {
      rethrow;
    } on Object {
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    }
    if (token.isEmpty || noteJwtSubject(token) != expectedUserId) {
      throw const ProfileFailure(ProfileFailureCode.unauthorized);
    }
    await _requireActor(expectedUserId);
    return token;
  }

  /// Throws unless the SDK currently reports exactly [expectedUserId].
  Future<void> _requireActor(String expectedUserId) async {
    final String? actor;
    try {
      actor = await _authenticatedUserId();
    } on ProfileFailure {
      rethrow;
    } on Object {
      throw const ProfileFailure(ProfileFailureCode.unauthorized);
    }
    if (actor == null || actor != expectedUserId) {
      throw const ProfileFailure(ProfileFailureCode.unauthorized);
    }
  }

  /// Performs one authenticated HTTP round trip under [_timeout].
  Future<http.StreamedResponse> _dispatch({
    required String method,
    required Uri uri,
    required String token,
    Map<String, Object?>? body,
  }) async {
    final http.Request request = http.Request(method, uri)
      ..followRedirects = false
      ..maxRedirects = 0;
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept'] = _jsonContentType;
    if (body != null) {
      request.headers['Content-Type'] = _jsonContentType;
      request.bodyBytes = utf8.encode(jsonEncode(body));
    }
    try {
      return await _client.send(request).timeout(_timeout);
    } on ProfileFailure {
      rethrow;
    } on TimeoutException {
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    } on http.ClientException {
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    } on Object {
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    }
  }

  /// Strictly decodes `{intentId, uploadUrl, headers}` into a safe capability.
  ///
  /// The URL must be HTTPS with no user info or fragment, and every header must
  /// be on [_allowedUploadHeaders] with a value that cannot inject a header
  /// break; anything else fails closed instead of being sent.
  Future<_AvatarIntent> _readIntent(http.StreamedResponse response) async {
    final Map<String, Object?> body = await _readJsonObject(response);
    if (body.length != _intentKeys.length ||
        !body.keys.every(_intentKeys.contains)) {
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    }
    final Object? intentId = body['intentId'];
    final Object? uploadUrl = body['uploadUrl'];
    final Object? headers = body['headers'];
    if (intentId is! String ||
        !_intentIdPattern.hasMatch(intentId) ||
        uploadUrl is! String ||
        headers is! Map) {
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    }
    final Uri? url = Uri.tryParse(uploadUrl);
    if (url == null ||
        url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasFragment) {
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    }
    final Map<String, String> signed = <String, String>{};
    for (final MapEntry<Object?, Object?> header in headers.entries) {
      final Object? name = header.key;
      final Object? value = header.value;
      if (name is! String ||
          value is! String ||
          value.isEmpty ||
          value.contains('\n') ||
          value.contains('\r') ||
          !_allowedUploadHeaders.contains(name.toLowerCase())) {
        throw const ProfileFailure(ProfileFailureCode.unavailable);
      }
      signed[name] = value;
    }
    return _AvatarIntent(intentId: intentId, uploadUrl: url, headers: signed);
  }

  /// Reads the avatar bytes under the media-type and size contract.
  Future<Uint8List> _readAvatar(http.StreamedResponse response) async {
    final String media =
        response.headers['content-type']
            ?.split(';')
            .first
            .trim()
            .toLowerCase() ??
        '';
    final int? declared = response.contentLength;
    if (!ProfileAvatarRules.isSupportedMime(media) ||
        (declared != null &&
            (declared <= 0 || declared > ProfileAvatarRules.maxBytes))) {
      await _discard(response);
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    }
    final BytesBuilder builder = BytesBuilder(copy: false);
    try {
      await for (final List<int> chunk in response.stream.timeout(_timeout)) {
        if (builder.length + chunk.length > ProfileAvatarRules.maxBytes) {
          throw const ProfileFailure(ProfileFailureCode.unavailable);
        }
        builder.add(chunk);
      }
    } on ProfileFailure {
      rethrow;
    } on TimeoutException {
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    } on Object {
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    }
    final Uint8List bytes = builder.takeBytes();
    if (bytes.isEmpty) {
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    }
    return bytes;
  }

  /// Whether a `404` body is the canonical missing-avatar envelope.
  ///
  /// Anything else — including an unknown legacy `404` — stays an unavailable
  /// failure, because only the canonical envelope means "no avatar set".
  Future<bool> _isCanonicalMissing(http.StreamedResponse response) async {
    try {
      final Map<String, Object?> body = await _readJsonObject(response);
      return body['code'] == _missingCode;
    } on ProfileFailure {
      return false;
    }
  }

  /// Reads a bounded JSON object body, or fails as unavailable.
  Future<Map<String, Object?>> _readJsonObject(
    http.StreamedResponse response,
  ) async {
    final Uint8List bytes = await _readBounded(response, _maxResponseBytes);
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on Object {
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    }
    return decoded;
  }

  /// Reads at most [limit] bytes of the response body.
  Future<Uint8List> _readBounded(
    http.StreamedResponse response,
    int limit,
  ) async {
    final int? declared = response.contentLength;
    if (declared != null && declared > limit) {
      await _discard(response);
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    }
    final BytesBuilder builder = BytesBuilder(copy: false);
    try {
      await for (final List<int> chunk in response.stream.timeout(_timeout)) {
        if (builder.length + chunk.length > limit) {
          throw const ProfileFailure(ProfileFailureCode.unavailable);
        }
        builder.add(chunk);
      }
    } on ProfileFailure {
      rethrow;
    } on TimeoutException {
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    } on Object {
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    }
    return builder.takeBytes();
  }

  /// Releases a response whose body this adapter will not read.
  Future<void> _discard(http.StreamedResponse response) async {
    try {
      await response.stream.listen((_) {}).cancel();
    } on Object {
      // The connection is already gone; there is nothing left to release.
    }
  }

  /// Builds an absolute URL from the base URI and a route [path].
  Uri _endpoint(String path) {
    final String basePath = _baseUri.path.endsWith('/')
        ? _baseUri.path
        : '${_baseUri.path}/';
    return Uri(
      scheme: _baseUri.scheme,
      userInfo: _baseUri.userInfo.isEmpty ? null : _baseUri.userInfo,
      host: _baseUri.host,
      port: _baseUri.hasPort ? _baseUri.port : null,
      path: '$basePath$path',
    );
  }

  /// Stable idempotency key for one avatar payload.
  ///
  /// Derived from the exact content and target revision, so a retry after a lost
  /// acknowledgement reuses the same intent instead of creating a second
  /// association, while a different image gets a different id.
  static String _requestId({
    required String actor,
    required int expectedRevision,
    required String mime,
    required int sizeBytes,
    required String sha256,
  }) {
    final String digest = crypto.sha256
        .convert(
          utf8.encode(
            jsonEncode(<Object?>[
              actor,
              expectedRevision,
              mime,
              sizeBytes,
              sha256,
            ]),
          ),
        )
        .toString();
    return 'avatar-$digest';
  }

  static String _requireUserId(String userId) {
    final String normalized = userId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be blank');
    }
    return normalized;
  }

  /// Maps a non-success status onto the stable failure vocabulary.
  static ProfileFailure _failureFor(int statusCode) {
    if (statusCode == 401 || statusCode == 403) {
      return const ProfileFailure(ProfileFailureCode.unauthorized);
    }
    if (statusCode == 409) {
      return const ProfileFailure(ProfileFailureCode.conflict);
    }
    if (statusCode == 400 || statusCode == 422) {
      return const ProfileFailure(ProfileFailureCode.invalid);
    }
    return const ProfileFailure(ProfileFailureCode.unavailable);
  }
}

/// One validated staging capability.
final class _AvatarIntent {
  const _AvatarIntent({
    required this.intentId,
    required this.uploadUrl,
    required this.headers,
  });

  final String intentId;
  final Uri uploadUrl;
  final Map<String, String> headers;
}
