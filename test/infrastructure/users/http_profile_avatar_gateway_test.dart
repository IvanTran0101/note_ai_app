import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note_ai_app/domain/users/profile_avatar_gateway.dart';
import 'package:note_ai_app/domain/users/profile_failure.dart';
import 'package:note_ai_app/infrastructure/users/http_profile_avatar_gateway.dart';

/// Behavior coverage for the avatar binary gateway.
///
/// Every request is served by a `MockClient`, so the assertions are about the
/// three-leg capability flow on the wire: the bound intent request, the
/// token-free presigned `PUT`, the completion call, the actor checks around
/// each leg, the one-shot 401 refresh, and the strict bounds on read bytes and
/// on the returned staging capability.

const String _baseUrl = 'https://api.example.com/prod';
const String _actor = 'user-a';
const String _intentsUrl = '$_baseUrl/me/avatar-intents';
const String _avatarUrl = '$_baseUrl/me/avatar';
const String _stagingUrl =
    'https://bucket.s3.amazonaws.com/staging/profile/user-a/intent-1'
    '?X-Amz-Signature=abc';

final Uint8List _pngBytes = Uint8List.fromList(<int>[
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
]);

String _tokenForSubject(String subject) {
  final String payload = base64Url
      .encode(utf8.encode(jsonEncode(<String, Object?>{'sub': subject})))
      .replaceAll('=', '');
  return 'header.$payload.signature';
}

http.Response _json(int status, Object? body) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: <String, String>{'content-type': 'application/json'},
  );
}

http.Response _ok(Object? body) => _json(200, body);

Map<String, Object?> _intentBody({
  Object? intentId = 'intent-1',
  Object? uploadUrl = _stagingUrl,
  Object? headers = const <String, Object?>{
    'content-type': 'image/png',
    'x-amz-checksum-sha256': 'checksum',
  },
}) {
  return <String, Object?>{
    'intentId': intentId,
    'uploadUrl': uploadUrl,
    'headers': headers,
  };
}

Matcher _failure(ProfileFailureCode code) => throwsA(
  isA<ProfileFailure>().having(
    (ProfileFailure failure) => failure.code,
    'code',
    code,
  ),
);

Matcher _invalid() => _failure(ProfileFailureCode.invalid);

Matcher _conflict() => _failure(ProfileFailureCode.conflict);

Matcher _unavailable() => _failure(ProfileFailureCode.unavailable);

Matcher _unauthorized() => _failure(ProfileFailureCode.unauthorized);

final class _Server {
  _Server(this.responses);

  final List<http.Response> responses;
  final List<http.Request> requests = <http.Request>[];

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    if (responses.isEmpty) {
      throw StateError('Unexpected request: ${request.method} ${request.url}');
    }
    return responses.removeAt(0);
  }
}

final class _Identity {
  _Identity(this._values);

  final List<String?> _values;

  Future<String?> call() async {
    if (_values.length > 1) {
      return _values.removeAt(0);
    }
    return _values.isEmpty ? null : _values.first;
  }
}

final class _Tokens {
  _Tokens(this._values);

  final List<String> _values;
  final List<bool> forceRefresh = <bool>[];

  Future<String> call({required bool forceRefresh}) async {
    this.forceRefresh.add(forceRefresh);
    if (_values.length > 1) {
      return _values.removeAt(0);
    }
    return _values.first;
  }
}

typedef _Harness = ({
  HttpProfileAvatarGateway gateway,
  _Server server,
  _Tokens tokens,
});

_Harness _harness(
  _Server server, {
  List<String>? tokens,
  List<String?>? identities,
  Uri? baseUri,
}) {
  final _Tokens tokenSource = _Tokens(
    tokens ?? <String>[_tokenForSubject(_actor)],
  );
  return (
    gateway: HttpProfileAvatarGateway(
      baseUri: baseUri ?? Uri.parse(_baseUrl),
      accessTokenProvider: tokenSource.call,
      authenticatedUserId: _Identity(identities ?? <String?>[_actor]).call,
      client: MockClient(server.handle),
    ),
    server: server,
    tokens: tokenSource,
  );
}

void main() {
  group('HttpProfileAvatarGateway.getAvatar', () {
    test('reads the avatar bytes over the authenticated route', () async {
      final _Server server = _Server(<http.Response>[
        http.Response.bytes(
          _pngBytes,
          200,
          headers: <String, String>{'content-type': 'image/png'},
        ),
      ]);
      final _Harness harness = _harness(server);

      final Uint8List? bytes = await harness.gateway.getAvatar(_actor);

      expect(bytes, _pngBytes);
      final http.Request request = server.requests.single;
      expect(request.method, 'GET');
      expect(request.url.toString(), _avatarUrl);
      expect(request.headers['authorization'], 'Bearer ${_tokenForSubject(_actor)}');
    });

    test('accepts a media type with parameters', () async {
      final _Server server = _Server(<http.Response>[
        http.Response.bytes(
          _pngBytes,
          200,
          headers: <String, String>{'content-type': 'image/jpeg; charset=binary'},
        ),
      ]);

      expect(await _harness(server).gateway.getAvatar(_actor), _pngBytes);
    });

    test('returns null for the canonical missing-avatar envelope', () async {
      final _Server server = _Server(<http.Response>[
        _json(404, <String, Object?>{'code': 'PROFILE_AVATAR_MISSING'}),
      ]);

      expect(await _harness(server).gateway.getAvatar(_actor), isNull);
    });

    test('treats any other 404 as unavailable', () async {
      for (final http.Response response in <http.Response>[
        _json(404, <String, Object?>{'code': 'NOT_FOUND'}),
        _json(404, <String, Object?>{'code': 42}),
        http.Response('', 404),
      ]) {
        final _Server server = _Server(<http.Response>[response]);

        await expectLater(
          _harness(server).gateway.getAvatar(_actor),
          _unavailable(),
        );
      }
    });

    test('refuses an off-contract media type', () async {
      final _Server server = _Server(<http.Response>[
        http.Response.bytes(
          _pngBytes,
          200,
          headers: <String, String>{'content-type': 'text/html'},
        ),
      ]);

      await expectLater(
        _harness(server).gateway.getAvatar(_actor),
        _unavailable(),
      );
    });

    test('refuses an empty avatar body', () async {
      final _Server server = _Server(<http.Response>[
        http.Response.bytes(
          Uint8List(0),
          200,
          headers: <String, String>{'content-type': 'image/png'},
        ),
      ]);

      await expectLater(
        _harness(server).gateway.getAvatar(_actor),
        _unavailable(),
      );
    });

    test('refuses avatar bytes above the bound', () async {
      for (final int? declared in <int?>[
        ProfileAvatarRules.maxBytes + 1,
        null,
      ]) {
        final MockClient client = MockClient.streaming((
          http.BaseRequest request,
          http.ByteStream bodyStream,
        ) async {
          return http.StreamedResponse(
            Stream<List<int>>.value(
              Uint8List(ProfileAvatarRules.maxBytes + 1),
            ),
            200,
            contentLength: declared,
            headers: <String, String>{'content-type': 'image/png'},
          );
        });
        final HttpProfileAvatarGateway gateway = HttpProfileAvatarGateway(
          baseUri: Uri.parse(_baseUrl),
          accessTokenProvider: _Tokens(
            <String>[_tokenForSubject(_actor)],
          ).call,
          authenticatedUserId: _Identity(<String?>[_actor]).call,
          client: client,
        );

        await expectLater(
          gateway.getAvatar(_actor),
          _unavailable(),
          reason: 'declared: $declared',
        );
      }
    });

    test('refuses a foreign actor without issuing a request', () async {
      final _Server server = _Server(<http.Response>[
        http.Response.bytes(
          _pngBytes,
          200,
          headers: <String, String>{'content-type': 'image/png'},
        ),
      ]);

      await expectLater(
        _harness(
          server,
          identities: <String?>['user-b'],
        ).gateway.getAvatar(_actor),
        _unauthorized(),
      );
      expect(server.requests, isEmpty);
    });

    test('refreshes once after a 401', () async {
      final _Server server = _Server(<http.Response>[
        http.Response('', 401),
        http.Response.bytes(
          _pngBytes,
          200,
          headers: <String, String>{'content-type': 'image/png'},
        ),
      ]);
      final _Harness harness = _harness(
        server,
        tokens: <String>[_tokenForSubject(_actor), _tokenForSubject(_actor)],
      );

      expect(await harness.gateway.getAvatar(_actor), _pngBytes);
      expect(server.requests, hasLength(2));
      expect(harness.tokens.forceRefresh, <bool>[false, true]);
    });

    test('rejects a blank user id before any request', () async {
      final _Server server = _Server(<http.Response>[]);

      await expectLater(
        _harness(server).gateway.getAvatar('  '),
        throwsArgumentError,
      );
      expect(server.requests, isEmpty);
    });
  });

  group('HttpProfileAvatarGateway.uploadAvatar', () {
    test('creates an intent, stages the bytes, and completes it', () async {
      final _Server server = _Server(<http.Response>[
        _ok(_intentBody()),
        http.Response('', 200),
        _ok(<String, Object?>{}),
      ]);
      final _Harness harness = _harness(server);

      await harness.gateway.uploadAvatar(
        userId: _actor,
        expectedRevision: 4,
        bytes: _pngBytes,
        mime: ProfileAvatarRules.pngMime,
      );

      expect(server.requests, hasLength(3));
      final http.Request intent = server.requests[0];
      expect(intent.method, 'POST');
      expect(intent.url.toString(), _intentsUrl);
      expect(intent.headers['authorization'], 'Bearer ${_tokenForSubject(_actor)}');
      final Map<String, Object?> intentBody =
          jsonDecode(utf8.decode(intent.bodyBytes)) as Map<String, Object?>;
      expect(intentBody.keys.toSet(), <String>{
        'requestId',
        'expectedProfileRevision',
        'mime',
        'sizeBytes',
        'sha256',
      });
      expect(intentBody['expectedProfileRevision'], 4);
      expect(intentBody['mime'], ProfileAvatarRules.pngMime);
      expect(intentBody['sizeBytes'], _pngBytes.length);
      expect(intentBody['sha256'], crypto.sha256.convert(_pngBytes).toString());
      expect(intentBody['requestId'], startsWith('avatar-'));

      final http.Request put = server.requests[1];
      expect(put.method, 'PUT');
      expect(put.url.toString(), _stagingUrl);
      expect(put.headers['content-type'], 'image/png');
      expect(put.headers['x-amz-checksum-sha256'], 'checksum');
      expect(put.headers.containsKey('authorization'), isFalse);
      expect(put.bodyBytes, _pngBytes);

      final http.Request complete = server.requests[2];
      expect(complete.method, 'POST');
      expect(complete.url.toString(), '$_intentsUrl/intent-1/complete');
      expect(complete.headers['authorization'], 'Bearer ${_tokenForSubject(_actor)}');
      expect(jsonDecode(utf8.decode(complete.bodyBytes)), <String, Object?>{});
    });

    test('reuses the intent for a lost-ACK retry of the same payload', () async {
      final _Server server = _Server(<http.Response>[
        _ok(_intentBody()),
        http.Response('', 200),
        _ok(<String, Object?>{}),
        _ok(_intentBody()),
        http.Response('', 200),
        _ok(<String, Object?>{}),
      ]);
      final _Harness harness = _harness(server);

      for (var attempt = 0; attempt < 2; attempt++) {
        await harness.gateway.uploadAvatar(
          userId: _actor,
          expectedRevision: 4,
          bytes: _pngBytes,
          mime: ProfileAvatarRules.pngMime,
        );
      }

      String requestIdOf(int index) {
        return (jsonDecode(utf8.decode(server.requests[index].bodyBytes))
                as Map<String, Object?>)['requestId']!
            as String;
      }

      expect(requestIdOf(0), requestIdOf(3));
    });

    test('uses a different intent for a different payload', () async {
      final _Server server = _Server(<http.Response>[
        _ok(_intentBody()),
        http.Response('', 200),
        _ok(<String, Object?>{}),
        _ok(_intentBody()),
        http.Response('', 200),
        _ok(<String, Object?>{}),
      ]);
      final _Harness harness = _harness(server);

      await harness.gateway.uploadAvatar(
        userId: _actor,
        expectedRevision: 4,
        bytes: _pngBytes,
        mime: ProfileAvatarRules.pngMime,
      );
      await harness.gateway.uploadAvatar(
        userId: _actor,
        expectedRevision: 5,
        bytes: _pngBytes,
        mime: ProfileAvatarRules.pngMime,
      );

      String requestIdOf(int index) {
        return (jsonDecode(utf8.decode(server.requests[index].bodyBytes))
                as Map<String, Object?>)['requestId']!
            as String;
      }

      expect(requestIdOf(0), isNot(requestIdOf(3)));
    });

    test('validates the avatar input before any request', () async {
      final _Server server = _Server(<http.Response>[]);
      final _Harness harness = _harness(server);

      await expectLater(
        harness.gateway.uploadAvatar(
          userId: _actor,
          expectedRevision: 0,
          bytes: Uint8List(0),
          mime: ProfileAvatarRules.pngMime,
        ),
        _invalid(),
      );
      await expectLater(
        harness.gateway.uploadAvatar(
          userId: _actor,
          expectedRevision: 0,
          bytes: Uint8List(ProfileAvatarRules.maxBytes + 1),
          mime: ProfileAvatarRules.pngMime,
        ),
        _invalid(),
      );
      await expectLater(
        harness.gateway.uploadAvatar(
          userId: _actor,
          expectedRevision: 0,
          bytes: _pngBytes,
          mime: 'image/gif',
        ),
        _invalid(),
      );
      await expectLater(
        harness.gateway.uploadAvatar(
          userId: _actor,
          expectedRevision: -1,
          bytes: _pngBytes,
          mime: ProfileAvatarRules.pngMime,
        ),
        throwsArgumentError,
      );

      expect(server.requests, isEmpty);
    });

    test('refuses a foreign actor without issuing a request', () async {
      final _Server server = _Server(<http.Response>[]);

      await expectLater(
        _harness(
          server,
          identities: <String?>['user-b'],
        ).gateway.uploadAvatar(
          userId: _actor,
          expectedRevision: 0,
          bytes: _pngBytes,
          mime: ProfileAvatarRules.pngMime,
        ),
        _unauthorized(),
      );
      expect(server.requests, isEmpty);
    });

    test('rejects an off-contract staging capability', () async {
      final List<Map<String, Object?>> bodies = <Map<String, Object?>>[
        _intentBody(uploadUrl: 'http://bucket.s3.amazonaws.com/staging/x'),
        _intentBody(uploadUrl: 'https://user:pass@bucket.s3.amazonaws.com/x'),
        _intentBody(uploadUrl: '$_stagingUrl#fragment'),
        _intentBody(uploadUrl: 7),
        _intentBody(intentId: 'in tent/1'),
        _intentBody(
          headers: const <String, Object?>{'authorization': 'Bearer token'},
        ),
        _intentBody(
          headers: const <String, Object?>{'x-custom': 'value'},
        ),
        _intentBody(
          headers: const <String, Object?>{'content-type': 'image/png\nx: 1'},
        ),
        _intentBody(headers: const <String, Object?>{'content-type': ''}),
        _intentBody(headers: const <String, Object?>{'content-type': 7}),
        _intentBody(headers: const <String, Object?>{'headers': null}),
        <String, Object?>{..._intentBody(), 'extra': true},
        <String, Object?>{
          'intentId': 'intent-1',
          'uploadUrl': _stagingUrl,
        },
      ];

      for (final Map<String, Object?> body in bodies) {
        final _Server server = _Server(<http.Response>[_ok(body)]);

        await expectLater(
          _harness(server).gateway.uploadAvatar(
            userId: _actor,
            expectedRevision: 0,
            bytes: _pngBytes,
            mime: ProfileAvatarRules.pngMime,
          ),
          _unavailable(),
          reason: 'body: $body',
        );
        expect(server.requests, hasLength(1), reason: 'body: $body');
      }
    });

    test('does not complete when the staged PUT fails', () async {
      final _Server server = _Server(<http.Response>[
        _ok(_intentBody()),
        http.Response('', 403),
      ]);

      await expectLater(
        _harness(server).gateway.uploadAvatar(
          userId: _actor,
          expectedRevision: 0,
          bytes: _pngBytes,
          mime: ProfileAvatarRules.pngMime,
        ),
        _unavailable(),
      );
      expect(server.requests, hasLength(2));
    });

    test('aborts before completion when the session switches during staging', () async {
      final _Server server = _Server(<http.Response>[
        _ok(_intentBody()),
        http.Response('', 200),
        _ok(<String, Object?>{}),
      ]);

      await expectLater(
        _harness(
          server,
          identities: <String?>[_actor, _actor, _actor, _actor, 'user-b'],
        ).gateway.uploadAvatar(
          userId: _actor,
          expectedRevision: 0,
          bytes: _pngBytes,
          mime: ProfileAvatarRules.pngMime,
        ),
        _unauthorized(),
      );
      expect(server.requests, hasLength(2));
    });

    test('maps a conflict on the intent', () async {
      final _Server server = _Server(<http.Response>[_json(409, <String, Object?>{})]);

      await expectLater(
        _harness(server).gateway.uploadAvatar(
          userId: _actor,
          expectedRevision: 2,
          bytes: _pngBytes,
          mime: ProfileAvatarRules.pngMime,
        ),
        _conflict(),
      );
    });

    test('refreshes once after a 401 on the completion leg', () async {
      final _Server server = _Server(<http.Response>[
        _ok(_intentBody()),
        http.Response('', 200),
        http.Response('', 401),
        _ok(<String, Object?>{}),
      ]);
      final _Harness harness = _harness(
        server,
        tokens: <String>[_tokenForSubject(_actor), _tokenForSubject(_actor)],
      );

      await harness.gateway.uploadAvatar(
        userId: _actor,
        expectedRevision: 0,
        bytes: _pngBytes,
        mime: ProfileAvatarRules.pngMime,
      );

      expect(server.requests, hasLength(4));
      expect(harness.tokens.forceRefresh, <bool>[false, false, true]);
      expect(
        server.requests[2].url.toString(),
        server.requests[3].url.toString(),
      );
    });

    test('refreshes once after a 401 on the intent leg', () async {
      final _Server server = _Server(<http.Response>[
        http.Response('', 401),
        _ok(_intentBody()),
        http.Response('', 200),
        _ok(<String, Object?>{}),
      ]);
      final _Harness harness = _harness(
        server,
        tokens: <String>[_tokenForSubject(_actor), _tokenForSubject(_actor)],
      );

      await harness.gateway.uploadAvatar(
        userId: _actor,
        expectedRevision: 0,
        bytes: _pngBytes,
        mime: ProfileAvatarRules.pngMime,
      );

      expect(server.requests, hasLength(4));
      expect(harness.tokens.forceRefresh, <bool>[false, true, false]);
      expect(
        server.requests[0].url.toString(),
        server.requests[1].url.toString(),
      );
    });
  });

  group('HttpProfileAvatarGateway construction', () {
    test('requires an HTTPS base URI', () {
      for (final String base in <String>[
        'http://api.example.com/prod',
        'https://user:pass@api.example.com/prod',
        'https://api.example.com/prod?tenant=1',
        'https://api.example.com/prod#fragment',
      ]) {
        expect(
          () => HttpProfileAvatarGateway(
            baseUri: Uri.parse(base),
            accessTokenProvider: _Tokens(
              <String>[_tokenForSubject(_actor)],
            ).call,
            authenticatedUserId: _Identity(<String?>[_actor]).call,
            client: MockClient((http.Request request) async {
              return http.Response('', 500);
            }),
          ),
          throwsArgumentError,
          reason: base,
        );
      }
    });
  });
}
