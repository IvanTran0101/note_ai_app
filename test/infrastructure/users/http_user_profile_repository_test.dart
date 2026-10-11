import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note_ai_app/domain/users/profile_failure.dart';
import 'package:note_ai_app/domain/users/user_profile.dart';
import 'package:note_ai_app/infrastructure/users/http_user_profile_repository.dart';

/// Behavior coverage for the cloud HTTP profile adapter.
///
/// Every request is served by a `MockClient`, so the assertions are about the
/// bytes on the wire and the values that cross back into Application: route,
/// headers, JSON body, actor verification around the token fetch, the one-shot
/// 401 refresh, response-owner matching, strict decoding, and the guarantee
/// that no token, response body, or raw exception text appears in a failure.

const String _baseUrl = 'https://api.example.com/prod';
const String _actor = 'user-a';
const String _profileUrl = '$_baseUrl/me/profile';

String _tokenForSubject(String subject) {
  final String payload = base64Url
      .encode(utf8.encode(jsonEncode(<String, Object?>{'sub': subject})))
      .replaceAll('=', '');
  return 'header.$payload.signature';
}

Map<String, Object?> _canonicalProfile({
  Object? userId = _actor,
  Object? displayName = 'Ada Lovelace',
  Object? avatarReference = 'avatar-1',
  Object? revision = 3,
  Object? updatedAt = '2026-10-09T10:00:00.000Z',
}) {
  return <String, Object?>{
    'userId': userId,
    'displayName': displayName,
    'avatarReference': avatarReference,
    'revision': revision,
    'updatedAt': updatedAt,
  };
}

Map<String, Object?> _canonicalBody({
  Object? userId = _actor,
  Object? displayName = 'Ada Lovelace',
  Object? avatarReference = 'avatar-1',
  Object? revision = 3,
  Object? updatedAt = '2026-10-09T10:00:00.000Z',
}) {
  return <String, Object?>{
    'profile': _canonicalProfile(
      userId: userId,
      displayName: displayName,
      avatarReference: avatarReference,
      revision: revision,
      updatedAt: updatedAt,
    ),
  };
}

http.Response _json(int status, Object? body) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: <String, String>{'content-type': 'application/json'},
  );
}

http.Response _ok(Object? body) => _json(200, body);

Matcher _failure(ProfileFailureCode code) => throwsA(
  isA<ProfileFailure>().having(
    (ProfileFailure failure) => failure.code,
    'code',
    code,
  ),
);

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
  HttpUserProfileRepository repository,
  _Server server,
  _Tokens tokens,
  _Identity identity,
});

_Harness _build(
  http.Client client, {
  List<String>? tokens,
  List<String?>? identities,
  String actor = _actor,
  Uri? baseUri,
}) {
  final _Tokens tokenSource = _Tokens(tokens ?? <String>[_tokenForSubject(actor)]);
  final _Identity identity = _Identity(identities ?? <String?>[actor]);
  return (
    repository: HttpUserProfileRepository(
      baseUri: baseUri ?? Uri.parse(_baseUrl),
      accessTokenProvider: tokenSource.call,
      authenticatedUserId: identity.call,
      client: client,
    ),
    server: _Server(<http.Response>[]),
    tokens: tokenSource,
    identity: identity,
  );
}

_Harness _harness(
  _Server server, {
  List<String>? tokens,
  List<String?>? identities,
  String actor = _actor,
}) {
  final _Tokens tokenSource = _Tokens(tokens ?? <String>[_tokenForSubject(actor)]);
  final _Identity identity = _Identity(identities ?? <String?>[actor]);
  return (
    repository: HttpUserProfileRepository(
      baseUri: Uri.parse(_baseUrl),
      accessTokenProvider: tokenSource.call,
      authenticatedUserId: identity.call,
      client: MockClient(server.handle),
    ),
    server: server,
    tokens: tokenSource,
    identity: identity,
  );
}

void main() {
  group('HttpUserProfileRepository.findByUserId', () {
    test('sends an authorized GET and maps the canonical profile', () async {
      final _Server server = _Server(<http.Response>[_ok(_canonicalBody())]);
      final _Harness harness = _harness(server);

      final UserProfile? profile = await harness.repository.findByUserId(
        _actor,
      );

      expect(server.requests, hasLength(1));
      final http.Request request = server.requests.single;
      expect(request.method, 'GET');
      expect(request.url.toString(), _profileUrl);
      expect(request.headers['authorization'], 'Bearer ${_tokenForSubject(_actor)}');
      expect(request.headers['accept'], 'application/json');
      expect(request.bodyBytes, isEmpty);
      expect(profile, isNotNull);
      expect(profile!.userId, _actor);
      expect(profile.displayName, 'Ada Lovelace');
      expect(profile.avatarReference, 'avatar-1');
      expect(profile.revision, 3);
    });

    test('accepts a null avatar reference and a zero revision', () async {
      final _Server server = _Server(<http.Response>[
        _ok(_canonicalBody(avatarReference: null, revision: 0)),
      ]);

      final UserProfile? profile = await _harness(
        server,
      ).repository.findByUserId(_actor);

      expect(profile!.avatarReference, isNull);
      expect(profile.revision, 0);
    });

    test('returns null for the canonical missing-profile envelope', () async {
      final _Server server = _Server(<http.Response>[
        _json(404, <String, Object?>{'code': 'PROFILE_MISSING'}),
      ]);

      expect(await _harness(server).repository.findByUserId(_actor), isNull);
    });

    test('treats any other 404 as unavailable', () async {
      for (final http.Response response in <http.Response>[
        _json(404, <String, Object?>{'code': 'NOT_FOUND'}),
        _json(404, <String, Object?>{'code': 42}),
        http.Response('', 404),
        http.Response('<html>not found</html>', 404),
      ]) {
        final _Server server = _Server(<http.Response>[response]);

        await expectLater(
          _harness(server).repository.findByUserId(_actor),
          _unavailable(),
        );
      }
    });

    test('refuses a foreign actor without issuing a request', () async {
      final _Server server = _Server(<http.Response>[_ok(_canonicalBody())]);

      await expectLater(
        _harness(
          server,
          identities: <String?>['user-b'],
        ).repository.findByUserId(_actor),
        _unauthorized(),
      );
      expect(server.requests, isEmpty);
    });

    test('refuses a token minted for another subject', () async {
      final _Server server = _Server(<http.Response>[_ok(_canonicalBody())]);

      await expectLater(
        _harness(
          server,
          tokens: <String>[_tokenForSubject('user-b')],
        ).repository.findByUserId(_actor),
        _unauthorized(),
      );
      expect(server.requests, isEmpty);
    });

    test('refuses a token that is not a JWT', () async {
      final _Server server = _Server(<http.Response>[_ok(_canonicalBody())]);

      await expectLater(
        _harness(
          server,
          tokens: <String>['opaque-token'],
        ).repository.findByUserId(_actor),
        _unauthorized(),
      );
      expect(server.requests, isEmpty);
    });

    test('discards the call when the actor switches during the token fetch', () async {
      final _Server server = _Server(<http.Response>[_ok(_canonicalBody())]);

      await expectLater(
        _harness(
          server,
          identities: <String?>[_actor, 'user-b'],
        ).repository.findByUserId(_actor),
        _unauthorized(),
      );
      expect(server.requests, isEmpty);
    });

    test('refuses a response that names another owner', () async {
      final _Server server = _Server(<http.Response>[
        _ok(_canonicalBody(userId: 'user-b')),
      ]);

      await expectLater(
        _harness(server).repository.findByUserId(_actor),
        _unauthorized(),
      );
      expect(server.requests, hasLength(1));
    });

    test('refreshes once after a 401 and retries the same request', () async {
      final _Server server = _Server(<http.Response>[
        http.Response('', 401),
        _ok(_canonicalBody()),
      ]);
      final _Harness harness = _harness(
        server,
        tokens: <String>[_tokenForSubject(_actor), _tokenForSubject(_actor)],
      );

      final UserProfile? profile = await harness.repository.findByUserId(
        _actor,
      );

      expect(profile, isNotNull);
      expect(harness.tokens.forceRefresh, <bool>[false, true]);
      expect(server.requests, hasLength(2));
      expect(
        server.requests.map((http.Request request) => request.url.toString()),
        everyElement(_profileUrl),
      );
    });

    test('gives up as unauthorized after a second 401', () async {
      final _Server server = _Server(<http.Response>[
        http.Response('', 401),
        http.Response('', 401),
      ]);
      final _Harness harness = _harness(
        server,
        tokens: <String>[_tokenForSubject(_actor), _tokenForSubject(_actor)],
      );

      await expectLater(
        harness.repository.findByUserId(_actor),
        _unauthorized(),
      );
      expect(server.requests, hasLength(2));
      expect(harness.tokens.forceRefresh, <bool>[false, true]);
    });

    test('maps other statuses onto the failure vocabulary', () async {
      for (final (int status, ProfileFailureCode code) in <(
        int,
        ProfileFailureCode,
      )>[
        (403, ProfileFailureCode.unauthorized),
        (409, ProfileFailureCode.conflict),
        (400, ProfileFailureCode.invalid),
        (500, ProfileFailureCode.unavailable),
      ]) {
        final _Server server = _Server(<http.Response>[http.Response('', status)]);

        await expectLater(
          _harness(server).repository.findByUserId(_actor),
          _failure(code),
        );
      }
    });

    test('rejects off-contract canonical envelopes', () async {
      final List<Object?> bodies = <Object?>[
        <String, Object?>{},
        <String, Object?>{'profile': _canonicalProfile(), 'extra': 1},
        <String, Object?>{
          'profile': <String, Object?>{..._canonicalProfile(), 'extra': true},
        },
        <String, Object?>{
          'profile': <String, Object?>{
            ..._canonicalProfile(),
          }..remove('updatedAt'),
        },
        _canonicalBody(displayName: 7),
        _canonicalBody(displayName: '   '),
        _canonicalBody(displayName: 'a' * 101),
        _canonicalBody(revision: '3'),
        _canonicalBody(revision: -1),
        _canonicalBody(avatarReference: 9),
        _canonicalBody(avatarReference: ''),
        _canonicalBody(avatarReference: 'a' * 2048),
        _canonicalBody(updatedAt: ''),
        _canonicalBody(updatedAt: 5),
        <Object?>[],
        'not-json',
      ];

      for (final Object? body in bodies) {
        final _Server server = _Server(<http.Response>[_ok(body)]);

        await expectLater(
          _harness(server).repository.findByUserId(_actor),
          _unavailable(),
          reason: 'body: $body',
        );
      }
    });

    test('rejects a response body above the metadata bound', () async {
      for (final int? declared in <int?>[9000, null]) {
        final MockClient client = MockClient.streaming((
          http.BaseRequest request,
          http.ByteStream bodyStream,
        ) async {
          return http.StreamedResponse(
            Stream<List<int>>.value(Uint8List(9000)),
            200,
            contentLength: declared,
            headers: <String, String>{'content-type': 'application/json'},
          );
        });

        await expectLater(
          _build(client).repository.findByUserId(_actor),
          _unavailable(),
          reason: 'declared: $declared',
        );
      }
    });

    test('classifies a transport failure without leaking its text', () async {
      final MockClient client = MockClient((http.Request request) async {
        throw http.ClientException('socket down for $_actor with token');
      });

      try {
        await _build(client).repository.findByUserId(_actor);
        fail('expected a ProfileFailure');
      } on ProfileFailure catch (failure) {
        expect(failure.code, ProfileFailureCode.unavailable);
        expect(failure.toString(), 'ProfileFailure(unavailable)');
        expect(failure.toString(), isNot(contains('token')));
        expect(failure.toString(), isNot(contains('socket')));
      }
    });

    test('rejects a blank user id before any request', () async {
      final _Server server = _Server(<http.Response>[_ok(_canonicalBody())]);

      await expectLater(
        _harness(server).repository.findByUserId('   '),
        throwsArgumentError,
      );
      expect(server.requests, isEmpty);
    });
  });

  group('HttpUserProfileRepository.save', () {
    UserProfile profile({
      String displayName = 'Ada Byron',
      String? avatarReference = 'avatar-2',
      int revision = 7,
    }) {
      return UserProfile.reconstitute(
        userId: _actor,
        displayName: displayName,
        avatarReference: avatarReference,
        revision: revision,
      );
    }

    Map<String, Object?> bodyOf(http.Request request) {
      return jsonDecode(utf8.decode(request.bodyBytes)) as Map<String, Object?>;
    }

    test('posts the conditional payload derived from the profile revision', () async {
      final _Server server = _Server(<http.Response>[_ok(_canonicalBody())]);
      final _Harness harness = _harness(server);

      await harness.repository.save(profile());

      expect(server.requests, hasLength(1));
      final http.Request request = server.requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), _profileUrl);
      expect(request.headers['authorization'], 'Bearer ${_tokenForSubject(_actor)}');
      expect(request.headers['content-type'], 'application/json');
      final Map<String, Object?> body = bodyOf(request);
      expect(body.keys.toSet(), <String>{
        'requestId',
        'expectedRevision',
        'displayName',
        'avatarReference',
      });
      expect(body['expectedRevision'], 7);
      expect(body['displayName'], 'Ada Byron');
      expect(body['avatarReference'], 'avatar-2');
      expect(body['requestId'], startsWith('profile-'));
    });

    test('sends the create revision 0 when no profile is stored yet', () async {
      final _Server server = _Server(<http.Response>[
        _ok(_canonicalBody(revision: 1)),
      ]);

      await _harness(server).repository.save(
        UserProfile.create(userId: _actor, displayName: 'Ada'),
      );

      expect(bodyOf(server.requests.single)['expectedRevision'], 0);
    });

    test('reuses the requestId for a lost-ACK retry of the same payload', () async {
      final _Server server = _Server(<http.Response>[
        _ok(_canonicalBody()),
        _ok(_canonicalBody()),
      ]);
      final _Harness harness = _harness(server);
      final UserProfile candidate = profile();

      await harness.repository.save(candidate);
      await harness.repository.save(candidate);

      final List<Object?> ids = server.requests
          .map((http.Request request) => bodyOf(request)['requestId'])
          .toList();
      expect(ids, hasLength(2));
      expect(ids.first, ids.last);
    });

    test('uses a different requestId for a different payload', () async {
      final _Server server = _Server(<http.Response>[
        _ok(_canonicalBody()),
        _ok(_canonicalBody()),
      ]);
      final _Harness harness = _harness(server);

      await harness.repository.save(profile(displayName: 'Ada Byron'));
      await harness.repository.save(profile(displayName: 'Grace Hopper'));

      final List<Object?> ids = server.requests
          .map((http.Request request) => bodyOf(request)['requestId'])
          .toList();
      expect(ids.first, isNot(ids.last));
    });

    test('refreshes once after a 401 with the same payload and requestId', () async {
      final _Server server = _Server(<http.Response>[
        http.Response('', 401),
        _ok(_canonicalBody()),
      ]);
      final _Harness harness = _harness(
        server,
        tokens: <String>[_tokenForSubject(_actor), _tokenForSubject(_actor)],
      );

      await harness.repository.save(profile());

      expect(server.requests, hasLength(2));
      expect(harness.tokens.forceRefresh, <bool>[false, true]);
      expect(
        bodyOf(server.requests[0])['requestId'],
        bodyOf(server.requests[1])['requestId'],
      );
    });

    test('maps conflict, invalid, unauthorized, and unavailable', () async {
      for (final (int status, ProfileFailureCode code) in <(
        int,
        ProfileFailureCode,
      )>[
        (409, ProfileFailureCode.conflict),
        (400, ProfileFailureCode.invalid),
        (422, ProfileFailureCode.invalid),
        (403, ProfileFailureCode.unauthorized),
        (404, ProfileFailureCode.unavailable),
        (500, ProfileFailureCode.unavailable),
      ]) {
        final _Server server = _Server(<http.Response>[http.Response('', status)]);

        await expectLater(
          _harness(server).repository.save(profile()),
          _failure(code),
          reason: 'status: $status',
        );
      }
    });

    test('validates the canonical response it parses', () async {
      final List<(Object?, ProfileFailureCode)> cases =
          <(Object?, ProfileFailureCode)>[
            (_canonicalBody(userId: 'user-b'), ProfileFailureCode.unauthorized),
            (_canonicalBody(revision: '8'), ProfileFailureCode.unavailable),
            (<String, Object?>{'status': 'ok'}, ProfileFailureCode.unavailable),
          ];

      for (final (Object? body, ProfileFailureCode code) in cases) {
        final _Server server = _Server(<http.Response>[_ok(body)]);

        await expectLater(
          _harness(server).repository.save(profile()),
          _failure(code),
          reason: 'body: $body',
        );
      }
    });

    test('refuses the write when the actor is not the profile owner', () async {
      final _Server server = _Server(<http.Response>[_ok(_canonicalBody())]);

      await expectLater(
        _harness(
          server,
          identities: <String?>['user-b'],
        ).repository.save(profile()),
        _unauthorized(),
      );
      expect(server.requests, isEmpty);
    });
  });

  group('HttpUserProfileRepository construction', () {
    test('requires an HTTPS base URI', () {
      for (final String base in <String>[
        'http://api.example.com/prod',
        'https://user:pass@api.example.com/prod',
        'https://api.example.com/prod?tenant=1',
        'https://api.example.com/prod#fragment',
      ]) {
        expect(
          () => HttpUserProfileRepository(
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

    test('borrows an injected client instead of owning it', () async {
      final _Server server = _Server(<http.Response>[_ok(_canonicalBody())]);
      final HttpUserProfileRepository repository = HttpUserProfileRepository(
        baseUri: Uri.parse(_baseUrl),
        accessTokenProvider: _Tokens(<String>[_tokenForSubject(_actor)]).call,
        authenticatedUserId: _Identity(<String?>[_actor]).call,
        client: MockClient(server.handle),
      );

      repository.close();

      // A borrowed client stays usable: closing the adapter must not close a
      // connection pool its owner still uses.
      expect(await repository.findByUserId(_actor), isNotNull);
    });
  });
}
