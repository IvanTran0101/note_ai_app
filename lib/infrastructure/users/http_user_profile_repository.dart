/// Cross-platform HTTP adapter for the cloud profile repository.
///
/// One implementation serves iOS, macOS, and Web: `package:http` picks the
/// platform client, so this library never imports `dart:io` and needs no
/// conditional import per platform. It also does not depend on the running
/// application session: identity comes from the two injected closures, which is
/// what lets registration persist the profile of the identity it just signed in
/// before that session is published.
///
/// The adapter owns transport only. It attaches credentials, routes requests,
/// and classifies failures. Every failure crossing this boundary is a
/// [ProfileFailure] carrying a code and nothing else: a token, a response body,
/// and raw exception text are all kept out of thrown values so no credential or
/// server text can leak through logs or diagnostics.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import '../../domain/users/profile_failure.dart';
import '../../domain/users/user_profile.dart';
import '../../domain/users/user_profile_repository.dart';
import '../security/note_jwt_subject.dart';

/// Supplies one access token for a profile call.
///
/// `forceRefresh` asks the provider to ignore any cached session and re-issue
/// credentials. The adapter uses it exactly once, after a `401`.
typedef ProfileAccessTokenProvider = Future<String> Function({
  required bool forceRefresh,
});

/// [IUserProfileRepository] over the frozen M01.2 profile contract.
///
/// Routes: `GET /me/profile` (canonical or a canonical `PROFILE_MISSING` 404)
/// and `POST /me/profile` (conditional create/update by `expectedRevision`,
/// idempotent by `requestId`).
final class HttpUserProfileRepository implements IUserProfileRepository {
  /// Creates the adapter over [baseUri], for example
  /// `https://abc123.execute-api.ap-southeast-1.amazonaws.com/prod`.
  ///
  /// [baseUri] must be HTTPS: profile data and bearer tokens never travel over
  /// plaintext. [client] is optional; when it is omitted the adapter creates and
  /// owns one, and [close] releases it. An injected client is borrowed for its
  /// lifetime and is never closed here.
  factory HttpUserProfileRepository({
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
    return HttpUserProfileRepository._(
      baseUri: baseUri,
      accessTokenProvider: accessTokenProvider,
      authenticatedUserId: authenticatedUserId,
      client: client ?? http.Client(),
      ownsClient: client == null,
    );
  }

  /// Assigns the collaborators and the client-ownership decision resolved by
  /// the public factory.
  HttpUserProfileRepository._({
    required this._baseUri,
    required this._accessTokenProvider,
    required this._authenticatedUserId,
    required this._client,
    required this._ownsClient,
  });

  /// Read route for the signed-in account's profile.
  static const String _profilePath = 'me/profile';

  /// The only media type this adapter sends and accepts.
  static const String _jsonContentType = 'application/json';

  /// Upper bound on one metadata response body.
  static const int _maxResponseBytes = 8 * 1024;

  /// Upper bound on an opaque avatar reference accepted from the server.
  static const int _maxAvatarReferenceLength = 1024;

  /// Wire code of the canonical "this account has no profile" envelope.
  static const String _missingCode = 'PROFILE_MISSING';

  /// The exact canonical profile fields; anything else is off-contract.
  static const Set<String> _canonicalKeys = <String>{
    'userId',
    'displayName',
    'avatarReference',
    'revision',
    'updatedAt',
  };

  static const Duration _timeout = Duration(seconds: 30);

  final Uri _baseUri;
  final ProfileAccessTokenProvider _accessTokenProvider;
  final Future<String?> Function() _authenticatedUserId;
  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<UserProfile?> findByUserId(String userId) async {
    final String actor = _requireUserId(userId);
    final http.StreamedResponse response = await _authorizedSend(
      method: 'GET',
      uri: _endpoint(_profilePath),
      expectedUserId: actor,
    );
    if (response.statusCode == 200) {
      final _CanonicalProfile canonical = await _readCanonical(response, actor);
      // The value is about to cross the boundary: re-check the actor so a
      // session switched during the body read cannot receive the old account's
      // profile.
      await _requireActor(actor);
      return canonical.toProfile();
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
  Future<void> save(UserProfile profile) async {
    final String actor = _requireUserId(profile.userId);
    final Map<String, Object?> body = <String, Object?>{
      'requestId': _requestId(actor, profile),
      'expectedRevision': profile.revision,
      'displayName': profile.displayName,
      'avatarReference': profile.avatarReference,
    };
    final http.StreamedResponse response = await _authorizedSend(
      method: 'POST',
      uri: _endpoint(_profilePath),
      expectedUserId: actor,
      body: body,
    );
    if (response.statusCode == 200) {
      // Parsed only to enforce the response contract and the response-owner
      // match; the signature stays void and the caller refetches canonical
      // state.
      await _readCanonical(response, actor);
      await _requireActor(actor);
      return;
    }
    await _discard(response);
    throw _failureFor(response.statusCode);
  }

  /// Releases the HTTP client, but only when this adapter created it.
  void close() {
    if (_ownsClient) {
      _client.close();
    }
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
    Map<String, Object?>? body,
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
        body: body,
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
  ///
  /// Both the SDK identity and the JWT subject must name the expected actor
  /// before the token is fetched and again after it, so a token minted for an
  /// account that signed in meanwhile can never carry this request.
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

  /// Performs one HTTP round trip under [_timeout].
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
      // `bodyBytes` keeps the content type exactly `application/json`; the
      // string setter appends a charset parameter.
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

  /// Strictly decodes `{"profile": {userId, displayName, avatarReference,
  /// revision, updatedAt}}` and requires the response owner to be
  /// [expectedUserId].
  Future<_CanonicalProfile> _readCanonical(
    http.StreamedResponse response,
    String expectedUserId,
  ) async {
    final Map<String, Object?> envelope = await _readJsonObject(response);
    final Object? raw = envelope['profile'];
    if (envelope.length != 1 || raw is! Map<String, dynamic>) {
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    }
    if (raw.length != _canonicalKeys.length ||
        !raw.keys.every(_canonicalKeys.contains)) {
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    }
    final Object? userId = raw['userId'];
    final Object? displayName = raw['displayName'];
    final Object? avatarReference = raw['avatarReference'];
    final Object? revision = raw['revision'];
    final Object? updatedAt = raw['updatedAt'];
    if (userId is! String) {
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    }
    if (userId != expectedUserId) {
      // The response belongs to another account: never hand it back, whatever
      // the reason the server produced it.
      throw const ProfileFailure(ProfileFailureCode.unauthorized);
    }
    final String? normalizedName = displayName is String
        ? displayName.trim()
        : null;
    if (normalizedName == null ||
        normalizedName.isEmpty ||
        normalizedName.runes.length > UserProfile.maxDisplayNameRunes ||
        revision is! int ||
        revision < 0 ||
        updatedAt is! String ||
        updatedAt.isEmpty) {
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    }
    String? normalizedReference;
    if (avatarReference != null) {
      if (avatarReference is! String ||
          avatarReference.isEmpty ||
          avatarReference.length > _maxAvatarReferenceLength) {
        throw const ProfileFailure(ProfileFailureCode.unavailable);
      }
      normalizedReference = avatarReference;
    }
    return _CanonicalProfile(
      userId: userId,
      displayName: normalizedName,
      avatarReference: normalizedReference,
      revision: revision,
    );
  }

  /// Whether a `404` body is the canonical missing-profile envelope.
  ///
  /// Anything else — including an unknown legacy `404` — stays an unavailable
  /// failure, because only the canonical envelope means "not created yet".
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
    final Uint8List bytes = await _readBounded(response);
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

  /// Reads at most [_maxResponseBytes] of the response body.
  Future<Uint8List> _readBounded(http.StreamedResponse response) async {
    final int? declared = response.contentLength;
    if (declared != null && declared > _maxResponseBytes) {
      await _discard(response);
      throw const ProfileFailure(ProfileFailureCode.unavailable);
    }
    final BytesBuilder builder = BytesBuilder(copy: false);
    try {
      await for (final List<int> chunk in response.stream.timeout(_timeout)) {
        if (builder.length + chunk.length > _maxResponseBytes) {
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

  /// Stable idempotency key for one profile payload.
  ///
  /// Derived from the exact payload, so a retry after a lost acknowledgement
  /// reuses the same `requestId` and the server cannot create a second write
  /// from it, while a different payload gets a different id.
  static String _requestId(String actor, UserProfile profile) {
    final String digest = crypto.sha256
        .convert(
          utf8.encode(
            jsonEncode(<Object?>[
              actor,
              profile.revision,
              profile.displayName,
              profile.avatarReference,
            ]),
          ),
        )
        .toString();
    return 'profile-$digest';
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

/// The validated canonical profile fields of one response.
final class _CanonicalProfile {
  const _CanonicalProfile({
    required this.userId,
    required this.displayName,
    required this.avatarReference,
    required this.revision,
  });

  final String userId;
  final String displayName;
  final String? avatarReference;
  final int revision;

  UserProfile toProfile() {
    return UserProfile.reconstitute(
      userId: userId,
      displayName: displayName,
      avatarReference: avatarReference,
      revision: revision,
    );
  }
}
