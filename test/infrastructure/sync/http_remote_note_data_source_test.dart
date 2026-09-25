import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/application/sync/sync_result.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/infrastructure/sync/cognito_access_token_provider.dart';
import 'package:note_ai_app/infrastructure/sync/http_remote_note_data_source.dart';

/// Behavior coverage for the cross-platform HTTP sync adapter.
///
/// Every request is served by a `MockClient`, so the assertions are about the
/// bytes on the wire and the values that cross back into Application: method,
/// URL, headers, JSON body, the one-shot 401 refresh, status classification,
/// transport classification, and the guarantee that a token, a cursor, note
/// content, or raw provider text never appears in a failure.
///
/// The response fixtures follow `docs/sync_api_contract.md` rather than any
/// mapper internals, so this suite exercises the adapter together with the wire
/// mapper without reaching into it.

const String _baseUrl = 'https://api.example.com/prod';
const String _accessToken = 'access-token-secret-1';
const String _refreshedToken = 'access-token-secret-2';
const String _noteContent = 'Private note content';
const String _mutationId = 'mutation-1';
const String _noteId = 'note-1';

/// A cursor with characters that must survive query encoding unchanged.
const String _opaqueCursor = 'eyJzZXEiOjQyfQ==+/a b';

SyncMutation _mutation({
  SyncMutationOperation operation = SyncMutationOperation.create,
}) {
  return SyncMutation(
    mutationId: _mutationId,
    noteId: _noteId,
    operation: operation,
    baseRevision: 0,
    payload: operation == SyncMutationOperation.delete
        ? null
        : const SyncNotePayload(title: 'Title', content: _noteContent),
  );
}

Map<String, Object?> _noteJson({int revision = 1, Object? deletedAt}) {
  return <String, Object?>{
    'id': _noteId,
    'title': 'Title',
    'content': _noteContent,
    'createdAt': '2026-09-24T10:00:00.000Z',
    'serverUpdatedAt': '2026-09-24T11:00:00.000Z',
    'revision': revision,
    'deletedAt': deletedAt,
  };
}

String _appliedBody() {
  return jsonEncode(<String, Object?>{
    'status': 'applied',
    'mutationId': _mutationId,
    'note': _noteJson(),
  });
}

String _conflictBody({bool withRemote = true}) {
  return jsonEncode(<String, Object?>{
    'code': 'REVISION_CONFLICT',
    'retryable': false,
    'mutationId': _mutationId,
    'remoteNote': withRemote ? _noteJson(revision: 5) : null,
  });
}

String _changesBody({String? nextCursor, bool hasMore = false}) {
  return jsonEncode(<String, Object?>{
    'items': <Object?>[_noteJson()],
    'nextCursor': nextCursor,
    'hasMore': hasMore,
  });
}

String _errorBody(String code) {
  return jsonEncode(<String, Object?>{
    'code': code,
    'message': 'A safe user-facing message',
    'retryable': true,
  });
}

/// Records every token request and replays a scripted answer per call.
final class _FakeTokenProvider {
  _FakeTokenProvider(this._answers);

  /// Answers in call order; the last answer repeats if called again.
  final List<String?> _answers;

  /// The `forceRefresh` flag of each call, in order.
  final List<bool> forceRefreshCalls = <bool>[];

  int get callCount => forceRefreshCalls.length;

  Future<String?> call({required bool forceRefresh}) async {
    forceRefreshCalls.add(forceRefresh);
    final int index = forceRefreshCalls.length - 1;
    return index < _answers.length ? _answers[index] : _answers.last;
  }
}

HttpRemoteNoteDataSource _adapter({
  required http.Client client,
  required _FakeTokenProvider tokens,
  String baseUrl = _baseUrl,
  Duration timeout = const Duration(seconds: 30),
}) {
  return HttpRemoteNoteDataSource(
    baseUri: Uri.parse(baseUrl),
    tokenProvider: tokens.call,
    client: client,
    timeout: timeout,
  );
}

/// A single-token adapter whose client answers from [handler].
HttpRemoteNoteDataSource _singleTokenAdapter(
  Future<http.Response> Function(http.Request request) handler, {
  void Function(http.Request request)? onRequest,
  Duration timeout = const Duration(seconds: 30),
}) {
  return _adapter(
    client: MockClient((http.Request request) {
      onRequest?.call(request);
      return handler(request);
    }),
    tokens: _FakeTokenProvider(<String?>[_accessToken]),
    timeout: timeout,
  );
}

Matcher _failsWith(SyncErrorCode code) {
  return throwsA(
    isA<SyncFailure>().having((SyncFailure failure) => failure.code, 'code', code),
  );
}

void main() {
  group('request shaping', () {
    test('pushes one mutation to POST /sync/mutations as JSON', () async {
      late http.Request sent;
      final adapter = _singleTokenAdapter(
        (http.Request request) async {
          sent = request;
          return http.Response(_appliedBody(), 200);
        },
      );

      final SyncMutationResult result = await adapter.push(_mutation());

      expect(sent.method, 'POST');
      expect(sent.url.toString(), '$_baseUrl/sync/mutations');
      expect(sent.headers['authorization'], 'Bearer $_accessToken');
      expect(sent.headers['content-type'], 'application/json');
      expect(
        jsonDecode(sent.body),
        <String, Object?>{
          'mutationId': _mutationId,
          'noteId': _noteId,
          'operation': 'create',
          'baseRevision': 0,
          'payload': <String, Object?>{
            'title': 'Title',
            'content': _noteContent,
          },
        },
      );
      expect(result.isApplied, isTrue);
      expect(result.note?.revision, 1);
      expect(result.note?.content, _noteContent);
    });

    test('omits the payload for a delete mutation', () async {
      late http.Request sent;
      final adapter = _singleTokenAdapter((http.Request request) async {
        sent = request;
        return http.Response(_appliedBody(), 200);
      });

      await adapter.push(_mutation(operation: SyncMutationOperation.delete));

      final Map<String, Object?> body =
          jsonDecode(sent.body) as Map<String, Object?>;
      expect(body['operation'], 'delete');
      expect(body.containsKey('payload'), isFalse);
    });

    test('pulls a page from GET /sync/changes with the cursor and limit', () async {
      late http.Request sent;
      final adapter = _singleTokenAdapter((http.Request request) async {
        sent = request;
        return http.Response(_changesBody(nextCursor: _opaqueCursor), 200);
      });

      final SyncChangesPage page = await adapter.pull(cursor: _opaqueCursor);

      expect(sent.method, 'GET');
      expect(sent.url.path, '/prod/sync/changes');
      expect(sent.headers['authorization'], 'Bearer $_accessToken');
      expect(sent.headers['content-type'], 'application/json');
      // The cursor is opaque: it round-trips byte for byte.
      expect(sent.url.queryParameters['cursor'], _opaqueCursor);
      expect(sent.url.queryParameters['limit'], '50');
      // A GET carries no request body.
      expect(sent.body, isEmpty);
      expect(page.snapshots, hasLength(1));
      expect(page.snapshots.single.id, _noteId);
    });

    test('keeps nextCursor on a final page with hasMore false', () async {
      const String lastCursor = 'last-applied-cursor';
      final adapter = _singleTokenAdapter(
        (http.Request request) async =>
            http.Response(_changesBody(nextCursor: lastCursor), 200),
      );

      final SyncChangesPage page = await adapter.pull();

      expect(page.hasMore, isFalse);
      expect(page.nextCursor, lastCursor);
    });

    test('omits the cursor on the first page and honours a custom limit', () async {
      late http.Request sent;
      final adapter = _singleTokenAdapter((http.Request request) async {
        sent = request;
        return http.Response(_changesBody(), 200);
      });

      await adapter.pull(limit: 10);

      expect(sent.url.queryParameters.containsKey('cursor'), isFalse);
      expect(sent.url.queryParameters['limit'], '10');
    });

    test('keeps the base path with or without a trailing slash', () async {
      final List<String> urls = <String>[];
      for (final String base in <String>[
        'https://api.example.com/prod',
        'https://api.example.com/prod/',
      ]) {
        final adapter = _adapter(
          client: MockClient((http.Request request) async {
            urls.add(request.url.toString());
            return http.Response(_appliedBody(), 200);
          }),
          tokens: _FakeTokenProvider(<String?>[_accessToken]),
          baseUrl: base,
        );
        await adapter.push(_mutation());
      }

      expect(urls, <String>[
        'https://api.example.com/prod/sync/mutations',
        'https://api.example.com/prod/sync/mutations',
      ]);
    });

    test('decodes a UTF-8 body even without a charset parameter', () async {
      const String vietnamese = 'Ghi chú tiếng Việt: nội dung';
      final String body = jsonEncode(<String, Object?>{
        'status': 'applied',
        'mutationId': _mutationId,
        'note': <String, Object?>{..._noteJson(), 'content': vietnamese},
      });
      final adapter = _singleTokenAdapter(
        (http.Request request) async => http.Response.bytes(
          utf8.encode(body),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );

      final SyncMutationResult result = await adapter.push(_mutation());

      expect(result.note?.content, vietnamese);
    });
  });

  group('credentials', () {
    test('refreshes the token once on 401 and retries exactly once', () async {
      final List<String> authorizations = <String>[];
      int attempts = 0;
      final _FakeTokenProvider tokens = _FakeTokenProvider(<String?>[
        _accessToken,
        _refreshedToken,
      ]);
      final adapter = _adapter(
        client: MockClient((http.Request request) async {
          attempts++;
          authorizations.add(request.headers['authorization'] ?? '');
          return attempts == 1
              ? http.Response(_errorBody('UNAUTHORIZED'), 401)
              : http.Response(_appliedBody(), 200);
        }),
        tokens: tokens,
      );

      final SyncMutationResult result = await adapter.push(_mutation());

      expect(attempts, 2);
      expect(tokens.forceRefreshCalls, <bool>[false, true]);
      expect(authorizations, <String>[
        'Bearer $_accessToken',
        'Bearer $_refreshedToken',
      ]);
      expect(result.isApplied, isTrue);
    });

    test('reports unauthorized when the retry is rejected too', () async {
      int attempts = 0;
      final _FakeTokenProvider tokens = _FakeTokenProvider(<String?>[
        _accessToken,
        _refreshedToken,
      ]);
      final adapter = _adapter(
        client: MockClient((http.Request request) async {
          attempts++;
          return http.Response(_errorBody('UNAUTHORIZED'), 401);
        }),
        tokens: tokens,
      );

      await expectLater(
        adapter.push(_mutation()),
        _failsWith(SyncErrorCode.unauthorized),
      );

      // Exactly one retry, never a loop.
      expect(attempts, 2);
      expect(tokens.callCount, 2);
      expect(tokens.forceRefreshCalls, <bool>[false, true]);
    });

    test('sends no request at all when there is no token', () async {
      int attempts = 0;
      final _FakeTokenProvider tokens = _FakeTokenProvider(const <String?>[null]);
      final adapter = _adapter(
        client: MockClient((http.Request request) async {
          attempts++;
          return http.Response(_appliedBody(), 200);
        }),
        tokens: tokens,
      );

      await expectLater(
        adapter.pull(),
        _failsWith(SyncErrorCode.unauthorized),
      );

      expect(attempts, 0);
      expect(tokens.forceRefreshCalls, <bool>[false]);
    });

    test('fails as unauthorized when the forced refresh yields no token', () async {
      int attempts = 0;
      final _FakeTokenProvider tokens = _FakeTokenProvider(<String?>[
        _accessToken,
        null,
      ]);
      final adapter = _adapter(
        client: MockClient((http.Request request) async {
          attempts++;
          return http.Response(_errorBody('UNAUTHORIZED'), 401);
        }),
        tokens: tokens,
      );

      await expectLater(
        adapter.push(_mutation()),
        _failsWith(SyncErrorCode.unauthorized),
      );

      expect(attempts, 1);
      expect(tokens.forceRefreshCalls, <bool>[false, true]);
    });

    test('refreshes on a 401 from the change feed as well', () async {
      int attempts = 0;
      final _FakeTokenProvider tokens = _FakeTokenProvider(<String?>[
        _accessToken,
        _refreshedToken,
      ]);
      final adapter = _adapter(
        client: MockClient((http.Request request) async {
          attempts++;
          return attempts == 1
              ? http.Response(_errorBody('UNAUTHORIZED'), 401)
              : http.Response(_changesBody(), 200);
        }),
        tokens: tokens,
      );

      await adapter.pull();

      expect(attempts, 2);
      expect(tokens.forceRefreshCalls, <bool>[false, true]);
    });
  });

  group('mutation results', () {
    test('maps a 409 revision conflict to a conflict result', () async {
      final adapter = _singleTokenAdapter(
        (http.Request request) async => http.Response(_conflictBody(), 409),
      );

      final SyncMutationResult result = await adapter.push(_mutation());

      expect(result.isConflict, isTrue);
      expect(result.isApplied, isFalse);
      expect(result.mutationId, _mutationId);
      expect(result.conflictRemote?.revision, 5);
    });

    test('maps a conflict without a remote snapshot', () async {
      final adapter = _singleTokenAdapter(
        (http.Request request) async =>
            http.Response(_conflictBody(withRemote: false), 409),
      );

      final SyncMutationResult result = await adapter.push(_mutation());

      expect(result.isConflict, isTrue);
      expect(result.conflictRemote, isNull);
    });
  });

  group('status mapping', () {
    const Map<int, SyncErrorCode> cases = <int, SyncErrorCode>{
      403: SyncErrorCode.forbidden,
      422: SyncErrorCode.invalidMutation,
      429: SyncErrorCode.throttled,
      500: SyncErrorCode.serverUnavailable,
      503: SyncErrorCode.serverUnavailable,
    };

    cases.forEach((int status, SyncErrorCode code) {
      test('maps HTTP $status to ${code.name} on push', () async {
        final adapter = _singleTokenAdapter(
          (http.Request request) async =>
              http.Response(_errorBody('SOME_CODE'), status),
        );

        await expectLater(adapter.push(_mutation()), _failsWith(code));
      });
    });

    test('maps pull failures the same way', () async {
      final adapter = _singleTokenAdapter(
        (http.Request request) async => http.Response(_errorBody('FORBIDDEN'), 403),
      );

      await expectLater(adapter.pull(), _failsWith(SyncErrorCode.forbidden));
    });

    test('maps an unlisted 400 to unexpected', () async {
      final adapter = _singleTokenAdapter(
        (http.Request request) async => http.Response(_errorBody('BAD'), 400),
      );

      await expectLater(adapter.push(_mutation()), _failsWith(SyncErrorCode.unexpected));
    });

    test('classifies a malformed success body as unexpected', () async {
      final adapter = _singleTokenAdapter(
        (http.Request request) async => http.Response('not json', 200),
      );

      await expectLater(adapter.push(_mutation()), _failsWith(SyncErrorCode.unexpected));
    });
  });

  group('transport mapping', () {
    test('maps a timeout to timeout', () async {
      final adapter = _singleTokenAdapter(
        (http.Request request) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return http.Response(_appliedBody(), 200);
        },
        timeout: const Duration(milliseconds: 20),
      );

      await expectLater(
        adapter.pull(),
        _failsWith(SyncErrorCode.timeout),
      );
    });

    test('maps a client exception to networkUnavailable', () async {
      final adapter = _singleTokenAdapter(
        (http.Request request) async =>
            throw http.ClientException('connection closed'),
      );

      await expectLater(
        adapter.push(_mutation()),
        _failsWith(SyncErrorCode.networkUnavailable),
      );
    });

    test('maps an unknown error to unexpected without keeping its text', () async {
      final adapter = _singleTokenAdapter(
        (http.Request request) async => throw StateError(
          'boom $_accessToken $_noteContent $_opaqueCursor',
        ),
      );

      await expectLater(
        adapter.push(_mutation()),
        throwsA(
          isA<SyncFailure>()
              .having(
                (SyncFailure failure) => failure.code,
                'code',
                SyncErrorCode.unexpected,
              )
              .having(
                (SyncFailure failure) => failure.detail,
                'detail',
                isNull,
              ),
        ),
      );
    });
  });

  group('no credential leakage', () {
    test('sends the token only in the Authorization header', () async {
      final List<http.Request> sent = <http.Request>[];
      final adapter = _singleTokenAdapter((http.Request request) async {
        sent.add(request);
        return request.method == 'GET'
            ? http.Response(_changesBody(), 200)
            : http.Response(_appliedBody(), 200);
      });

      await adapter.push(_mutation());
      await adapter.pull(cursor: _opaqueCursor);

      for (final http.Request request in sent) {
        expect(request.url.toString(), isNot(contains(_accessToken)));
        expect(request.headers['authorization'], 'Bearer $_accessToken');
      }
      // A mutation URL carries no query at all; the cursor only ever rides the
      // change-feed query, and only as the caller supplied it.
      expect(sent.first.url.query, isEmpty);
      expect(sent.last.url.queryParameters['cursor'], _opaqueCursor);
    });

    test('keeps the token and port the request body out of failures', () async {
      final adapter = _singleTokenAdapter(
        (http.Request request) async =>
            throw http.ClientException('failed: Bearer $_accessToken'),
      );

      await expectLater(
        adapter.push(_mutation()),
        throwsA(
          isA<SyncFailure>()
              .having(
                (SyncFailure failure) => failure.detail,
                'detail',
                isNull,
              )
              .having(
                (SyncFailure failure) => failure.toString(),
                'toString',
                allOf(
                  isNot(contains(_accessToken)),
                  isNot(contains(_noteContent)),
                ),
              ),
        ),
      );
    });

    test('keeps the token, note content, and cursor out of error responses', () async {
      final adapter = _singleTokenAdapter(
        (http.Request request) async =>
            http.Response(_errorBody('SERVER_UNAVAILABLE'), 500),
      );

      await expectLater(
        adapter.pull(cursor: _opaqueCursor),
        throwsA(
          isA<SyncFailure>().having(
            (SyncFailure failure) => failure.toString(),
            'toString',
            allOf(
              isNot(contains(_accessToken)),
              isNot(contains(_noteContent)),
              isNot(contains(_opaqueCursor)),
            ),
          ),
        ),
      );
    });
  });

  group('client ownership', () {
    test('does not close an injected client', () async {
      final MockClient client = MockClient(
        (http.Request request) async => http.Response(_appliedBody(), 200),
      );
      final adapter = _adapter(
        client: client,
        tokens: _FakeTokenProvider(<String?>[_accessToken]),
      );

      adapter.close();
      adapter.close();

      // The injected client is still usable after the adapter released it.
      final SyncMutationResult result = await adapter.push(_mutation());
      expect(result.isApplied, isTrue);
    });

    test('closes the client it created', () async {
      final adapter = HttpRemoteNoteDataSource(
        baseUri: Uri.parse(_baseUrl),
        tokenProvider: _FakeTokenProvider(<String?>[_accessToken]).call,
      );

      adapter.close();

      await expectLater(
        adapter.push(_mutation()),
        _failsWith(SyncErrorCode.networkUnavailable),
      );
    });
  });

  group('Cognito provider seam', () {
    test('CognitoAccessTokenProvider satisfies SyncAccessTokenProvider', () {
      // Compile-time contract: the Amplify-backed provider is assignable to the
      // callback the adapter accepts, so wiring them together needs no
      // Amplify type outside Infrastructure.
      final SyncAccessTokenProvider tokens =
          const CognitoAccessTokenProvider().call;

      expect(tokens, isNotNull);
    });
  });
}
