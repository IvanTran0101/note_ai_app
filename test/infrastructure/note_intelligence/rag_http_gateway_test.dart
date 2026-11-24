import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/rag_http_gateway.dart';

import 'rag_http_test_support.dart';

/// Transport behaviour of the shared RAG adapter: one actor-free request per
/// call, a token that may not leave for the wrong account, one absolute budget
/// over token/guard/body, no redirect and no retry, and a client this gateway
/// only closes when it created it.
void main() {
  final RagRequest request = RagRequest(
    question: 'What did I decide?',
    scope: const RagScope.account(),
  );

  Map<String, Object?> bodyOf(ScriptedClient client) =>
      jsonDecode(utf8.decode(client.bodies.single)) as Map<String, Object?>;

  group('request wire', () {
    test('sends the exact actor-free query envelope', () async {
      final ScriptedClient client = ScriptedClient(
        (_) async => jsonResponse(200, answeredEnvelope()),
      );
      final RagHttpGateway gateway = testGateway(client: client);

      final RagResult result = await gateway.query(
        request,
        context: testContext(),
      );

      expect(result.isAnswered, isTrue);
      expect(client.requests, hasLength(1));
      final http.BaseRequest sent = client.requests.single;
      expect(sent.method, 'POST');
      expect(sent.url.toString(), 'https://api.example.test/ai/rag/query');
      expect(sent.headers['Authorization'], 'Bearer ${testToken()}');
      expect(sent.headers['Accept'], 'application/json');
      expect(sent.headers['Content-Type'], 'application/json');
      expect(sent.followRedirects, isFalse);
      expect(sent, isA<http.AbortableRequest>());
      expect(bodyOf(client), <String, Object?>{
        'wireVersion': 1,
        'question': 'What did I decide?',
        'scope': <String, Object?>{'type': 'account'},
      });
    });

    test('sends a note scope with its note id and nothing else', () async {
      final ScriptedClient client = ScriptedClient(
        (_) async => jsonResponse(200, answeredEnvelope()),
      );
      final RagHttpGateway gateway = testGateway(client: client);

      await gateway.query(
        RagRequest(question: 'This note?', scope: RagScope.note('note-1')),
        context: testContext(),
      );

      expect(bodyOf(client)['scope'], <String, Object?>{
        'type': 'note',
        'noteId': 'note-1',
      });
    });

    test('never serializes the context, actor, token, model, or endpoint',
        () async {
      final ScriptedClient client = ScriptedClient(
        (_) async => jsonResponse(200, answeredEnvelope()),
      );
      final RagHttpGateway gateway = testGateway(client: client);

      await gateway.query(
        request,
        context: testContext(
          expectedUserId: 'user-1',
          beforeDispatch: () async {},
        ),
      );

      final String body = utf8.decode(client.bodies.single);
      for (final String leak in <String>[
        'user-1',
        'actor',
        'ownerId',
        'deadline',
        'cancelled',
        'beforeDispatch',
        'model',
        'endpoint',
        'evidence',
        'Bearer',
      ]) {
        expect(body, isNot(contains(leak)), reason: leak);
      }
    });

    test('reads consent with GET and no body', () async {
      final ScriptedClient client = ScriptedClient(
        (_) async => jsonResponse(200, consentEnvelope()),
      );
      final RagHttpGateway gateway = testGateway(client: client);

      await gateway.readConsent(context: testContext());

      final http.BaseRequest sent = client.requests.single;
      expect(sent.method, 'GET');
      expect(sent.url.toString(), 'https://api.example.test/ai/rag/consent');
      expect(client.bodies.single, isEmpty);
      expect(sent.headers.containsKey('Content-Type'), isFalse);
    });

    test('writes the exact consent compare-and-set body', () async {
      final ScriptedClient client = ScriptedClient(
        (_) async => jsonResponse(200, consentEnvelope(generation: 4)),
      );
      final RagHttpGateway gateway = testGateway(client: client);

      final RagConsent written = await gateway.updateConsent(
        RagConsentUpdate(accepted: true, expectedGeneration: 3),
        context: testContext(),
      );

      expect(written.generation, 4);
      expect(client.requests.single.method, 'PUT');
      expect(bodyOf(client), <String, Object?>{
        'accepted': true,
        'version': RagConsent.currentVersion,
        'expectedGeneration': 3,
      });
    });

    test('keeps the base URI stage path for every route', () async {
      final ScriptedClient client = ScriptedClient(
        (_) async => jsonResponse(200, consentEnvelope()),
      );
      final RagHttpGateway gateway = testGateway(
        client: client,
        baseUri: Uri.parse('https://api.example.test/dev/'),
      );

      await gateway.readConsent(context: testContext());

      expect(
        client.requests.single.url.toString(),
        'https://api.example.test/dev/ai/rag/consent',
      );
    });
  });

  group('base URI', () {
    test('accepts https and loopback http for local development', () {
      for (final String uri in <String>[
        'https://api.example.test',
        'http://localhost:8787',
        'http://127.0.0.1:8787/dev',
        'http://[::1]:8787',
      ]) {
        expect(
          () => testGateway(
            client: ScriptedClient((_) async => jsonResponse(200, <String, Object?>{})),
            baseUri: Uri.parse(uri),
          ),
          returnsNormally,
          reason: uri,
        );
      }
    });

    test('refuses plain http anywhere but loopback', () {
      expect(
        () => testGateway(
          client: ScriptedClient((_) async => jsonResponse(200, <String, Object?>{})),
          baseUri: Uri.parse('http://api.example.test'),
        ),
        throwsArgumentError,
      );
    });

    test('refuses credentials, a query, a fragment, and a blank host', () {
      for (final String uri in <String>[
        'https://user:secret@api.example.test',
        'https://api.example.test?stage=dev',
        'https://api.example.test#frag',
        'https://',
      ]) {
        expect(
          () => testGateway(
            client: ScriptedClient((_) async => jsonResponse(200, <String, Object?>{})),
            baseUri: Uri.parse(uri),
          ),
          throwsArgumentError,
          reason: uri,
        );
      }
    });
  });

  group('token', () {
    Future<RagFailure> tokenProblem({
      String? token,
      bool nullToken = false,
      String contextUser = 'user-1',
      List<bool>? calls,
      ScriptedClient? client,
    }) async {
      final ScriptedClient transport =
          client ??
          ScriptedClient((_) async => jsonResponse(200, answeredEnvelope()));
      final RagHttpGateway gateway = RagHttpGateway(
        baseUri: Uri.parse('https://api.example.test'),
        tokenProvider: ({required bool forceRefresh}) async {
          calls?.add(forceRefresh);
          return nullToken ? null : (token ?? testToken());
        },
        client: transport,
        now: () => testNow,
      );
      try {
        await gateway.query(
          request,
          context: testContext(expectedUserId: contextUser),
        );
      } on RagFailure catch (failure) {
        return failure;
      }
      fail('expected a RagFailure');
    }

    test('refuses a token for another account without dispatching', () async {
      final ScriptedClient client = ScriptedClient(
        (_) async => jsonResponse(200, answeredEnvelope()),
      );
      final List<bool> calls = <bool>[];

      final RagFailure failure = await tokenProblem(
        token: testToken(subject: 'user-2'),
        calls: calls,
        client: client,
      );

      expect(failure.code, RagFailureCode.unauthorized);
      expect(calls, <bool>[false]);
      expect(client.requests, isEmpty);
    });

    test('refuses an ID token without dispatching', () async {
      final ScriptedClient client = ScriptedClient(
        (_) async => jsonResponse(200, answeredEnvelope()),
      );

      final RagFailure failure = await tokenProblem(
        token: testToken(tokenUse: 'id'),
        client: client,
      );

      expect(failure.code, RagFailureCode.unauthorized);
      expect(client.requests, isEmpty);
    });

    test('refuses an expired token without dispatching', () async {
      final ScriptedClient client = ScriptedClient(
        (_) async => jsonResponse(200, answeredEnvelope()),
      );

      final RagFailure failure = await tokenProblem(
        token: testToken(expiresAt: freshExpiry(const Duration(seconds: -1))),
        client: client,
      );

      expect(failure.code, RagFailureCode.unauthorized);
      expect(client.requests, isEmpty);
    });

    test('refuses a malformed or missing token without dispatching', () async {
      for (final String? token in <String?>[
        '',
        'not-a-jwt',
        'a.b',
        'a.!!!.c',
        '${testToken()}.extra',
        'a.${base64Url.encode(utf8.encode('not json'))}.c',
      ]) {
        final ScriptedClient client = ScriptedClient(
          (_) async => jsonResponse(200, answeredEnvelope()),
        );
        final RagFailure failure = await tokenProblem(
          token: token,
          client: client,
        );
        expect(failure.code, RagFailureCode.unauthorized, reason: '$token');
        expect(client.requests, isEmpty);
      }

      final ScriptedClient client = ScriptedClient(
        (_) async => jsonResponse(200, answeredEnvelope()),
      );
      final RagFailure failure = await tokenProblem(
        nullToken: true,
        client: client,
      );
      expect(failure.code, RagFailureCode.unauthorized);
      expect(client.requests, isEmpty);
    });

    test('asks for exactly one token with forceRefresh false', () async {
      final ScriptedClient client = ScriptedClient(
        (_) async => jsonResponse(200, answeredEnvelope()),
      );
      final List<bool> calls = <bool>[];

      await testGateway(
        client: client,
        tokenCalls: calls,
      ).query(request, context: testContext());

      expect(calls, <bool>[false]);
    });

    test('never refreshes or resends after a 401', () async {
      final ScriptedClient client = ScriptedClient(
        (_) async => jsonResponse(401, null, contentType: null),
      );
      final List<bool> calls = <bool>[];

      final RagFailure failure = await tokenProblem(calls: calls, client: client);

      expect(failure.code, RagFailureCode.unauthorized);
      expect(client.requests, hasLength(1));
      expect(calls, <bool>[false]);
    });
  });

  group('budget and cancellation', () {
    test('refuses a call whose absolute deadline already passed', () async {
      final ScriptedClient client = ScriptedClient(
        (_) async => jsonResponse(200, answeredEnvelope()),
      );
      final List<bool> calls = <bool>[];

      await expectLater(
        testGateway(client: client, tokenCalls: calls).query(
          request,
          context: testContext(deadline: testNow),
        ),
        throwsFailure(RagFailureCode.timeout),
      );

      expect(calls, isEmpty);
      expect(client.requests, isEmpty);
    });

    test('refuses an already-cancelled call before the token is read', () async {
      final ScriptedClient client = ScriptedClient(
        (_) async => jsonResponse(200, answeredEnvelope()),
      );
      final Completer<void> cancelled = Completer<void>()..complete();
      final List<bool> calls = <bool>[];

      await expectLater(
        testGateway(client: client, tokenCalls: calls).query(
          request,
          context: testContext(cancelled: cancelled.future),
        ),
        throwsFailure(RagFailureCode.cancelled),
      );

      expect(calls, isEmpty);
      expect(client.requests, isEmpty);
    });

    test('refuses a hanging guard and never dispatches', () async {
      final ScriptedClient client = ScriptedClient(
        (_) async => jsonResponse(200, answeredEnvelope()),
      );
      final Completer<void> guard = Completer<void>();
      final Completer<void> cancelled = Completer<void>();

      final Future<Object?> pending = testGateway(client: client)
          .query(
            request,
            context: testContext(
              cancelled: cancelled.future,
              beforeDispatch: () => guard.future,
            ),
          )
          .then<Object?>((Object? value) => value, onError: (Object error) => error);
      await pumpEventQueue();
      expect(client.requests, isEmpty);

      cancelled.complete();

      expect(
        await pending,
        isA<RagFailure>().having(
          (RagFailure f) => f.code,
          'code',
          RagFailureCode.cancelled,
        ),
      );
      expect(client.requests, isEmpty);
    });

    test('propagates a guard refusal and never dispatches', () async {
      final ScriptedClient client = ScriptedClient(
        (_) async => jsonResponse(200, answeredEnvelope()),
      );

      await expectLater(
        testGateway(client: client).query(
          request,
          context: testContext(
            beforeDispatch: () async =>
                throw const RagFailure(RagFailureCode.consentRequired),
          ),
        ),
        throwsFailure(RagFailureCode.consentRequired),
      );

      expect(client.requests, isEmpty);
    });

    test('ends a hanging body read at the absolute deadline', () async {
      final StreamController<List<int>> stream =
          StreamController<List<int>>();
      final ScriptedClient client = ScriptedClient(
        (_) async => http.StreamedResponse(stream.stream, 200, headers: <String, String>{
          'content-type': 'application/json',
        }),
      );

      await expectLater(
        testGateway(client: client).query(
          request,
          context: testContext(budget: const Duration(milliseconds: 120)),
        ),
        throwsFailure(RagFailureCode.timeout),
      );

      expect(client.requests, hasLength(1));
      await stream.close();
    });

    test('aborts a hanging transport at the absolute deadline', () async {
      final Completer<http.StreamedResponse> transport =
          Completer<http.StreamedResponse>();
      final ScriptedClient client = ScriptedClient((_) => transport.future);
      final RagHttpGateway gateway = testGateway(client: client);

      final Future<RagResult> pending = gateway.query(
        request,
        context: testContext(budget: const Duration(milliseconds: 120)),
      );

      await expectLater(pending, throwsFailure(RagFailureCode.timeout));
      expect(client.requests, hasLength(1));
      final http.AbortableRequest sent =
          client.requests.single as http.AbortableRequest;
      await sent.abortTrigger; // The transport is told to stop.
    });

    test('observes a transport error that arrives after cancellation', () async {
      final List<Object> unhandled = <Object>[];

      // Everything lives inside the guarded zone: a completer created outside
      // it would report its error to the outer zone even while a listener is
      // attached (a Dart zone artifact), which is not what this test measures.
      await runZonedGuarded(() async {
        final Completer<http.StreamedResponse> transport =
            Completer<http.StreamedResponse>();
        final ScriptedClient client = ScriptedClient((_) => transport.future);
        final Completer<void> cancelled = Completer<void>();
        // The outcome is observed from the moment the call starts, so a late
        // transport error is the only thing this test can surface.
        final Future<Object?> pending = testGateway(client: client)
            .query(request, context: testContext(cancelled: cancelled.future))
            .then<Object?>((Object? value) => value, onError: (Object error) => error);
        await pumpEventQueue();
        expect(client.requests, hasLength(1));

        cancelled.complete();
        expect(
          await pending,
          isA<RagFailure>().having(
            (RagFailure f) => f.code,
            'code',
            RagFailureCode.cancelled,
          ),
        );

        transport.completeError(http.ClientException('late failure'));
        await pumpEventQueue();
      }, (Object error, StackTrace _) => unhandled.add(error));

      expect(unhandled, isEmpty);
    });
  });

  group('response bounds and redirects', () {
    test('refuses an advertised body past 64 KiB', () async {
      final ScriptedClient client = ScriptedClient(
        (_) async => streamedResponse(
          200,
          utf8.encode('{}'),
          contentLength: RagHttpGateway.maxResponseBytes + 1,
        ),
      );

      await expectLater(
        testGateway(client: client).query(request, context: testContext()),
        throwsFailure(RagFailureCode.invalidProviderOutput),
      );
    });

    test('refuses a streamed body past 64 KiB', () async {
      final List<List<int>> chunks = List<List<int>>.generate(
        65,
        (_) => List<int>.filled(1024, 0x20),
      );
      final ScriptedClient client = ScriptedClient(
        (_) async => http.StreamedResponse(
          Stream<List<int>>.fromIterable(chunks),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );

      await expectLater(
        testGateway(client: client).query(request, context: testContext()),
        throwsFailure(RagFailureCode.invalidProviderOutput),
      );
    });

    test('accepts a body of exactly 64 KiB', () async {
      final int overhead = utf8
          .encode(jsonEncode(answeredEnvelope(answer: '')))
          .length;
      final int padding = RagHttpGateway.maxResponseBytes - overhead;
      final String answer = '${'a' * (padding - 4)}[S1]';
      final Uint8List body = Uint8List.fromList(
        utf8.encode(jsonEncode(answeredEnvelope(answer: answer))),
      );
      expect(body.length, RagHttpGateway.maxResponseBytes);
      final ScriptedClient client = ScriptedClient(
        (_) async => streamedResponse(200, body),
      );

      final RagResult result = await testGateway(
        client: client,
      ).query(request, context: testContext());

      expect(result.answer, answer);
    });

    /// A response whose body breaks the cap, advertised or streamed.
    http.StreamedResponse overflowBody(
      int status, {
      required bool advertised,
      Map<String, String> headers = const <String, String>{},
    }) {
      final int size = RagHttpGateway.maxResponseBytes + 1;
      if (advertised) {
        return streamedResponse(
          status,
          const <int>[],
          contentLength: size,
          headers: headers,
        );
      }
      return http.StreamedResponse(
        Stream<List<int>>.fromIterable(<List<int>>[
          List<int>.filled(size, 0x20),
        ]),
        status,
        headers: <String, String>{
          'content-type': 'application/json',
          ...headers,
        },
      );
    }

    Future<RagFailure> overflowFailure(
      int status, {
      required bool advertised,
      Map<String, String> headers = const <String, String>{},
    }) async {
      final ScriptedClient client = ScriptedClient(
        (_) async => overflowBody(status, advertised: advertised, headers: headers),
      );
      try {
        await testGateway(client: client).query(request, context: testContext());
      } on RagFailure catch (failure) {
        return failure;
      }
      fail('expected a RagFailure for status $status');
    }

    test('classifies a status whose body broke the transport cap', () async {
      const Map<int, RagFailureCode> expected = <int, RagFailureCode>{
        401: RagFailureCode.unauthorized,
        429: RagFailureCode.rateLimited,
        503: RagFailureCode.providerUnavailable,
      };
      for (final bool advertised in <bool>[true, false]) {
        for (final MapEntry<int, RagFailureCode> entry in expected.entries) {
          final RagFailure failure = await overflowFailure(
            entry.key,
            advertised: advertised,
          );
          expect(
            failure.code,
            entry.value,
            reason: 'status ${entry.key} advertised=$advertised',
          );
        }
      }
    });

    test('keeps a 429 Retry-After hint after an overflow', () async {
      for (final bool advertised in <bool>[true, false]) {
        final RagFailure failure = await overflowFailure(
          429,
          advertised: advertised,
          headers: <String, String>{'retry-after': '30'},
        );
        expect(failure.code, RagFailureCode.rateLimited);
        expect(
          failure.retryAfterSeconds,
          30,
          reason: 'advertised=$advertised',
        );
      }
    });

    test('refuses one giant oversize 200 chunk before buffering it', () async {
      final ScriptedClient client = ScriptedClient(
        (_) async => http.StreamedResponse(
          Stream<List<int>>.fromIterable(<List<int>>[
            List<int>.filled(RagHttpGateway.maxResponseBytes * 2, 0x20),
          ]),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );

      await expectLater(
        testGateway(client: client).query(request, context: testContext()),
        throwsFailure(RagFailureCode.invalidProviderOutput),
      );
    });

    test('a transport abort after an overflow keeps the status, not network',
        () async {
      final StreamController<List<int>> stream =
          StreamController<List<int>>(sync: true);
      final ScriptedClient client = ScriptedClient(
        (_) async => http.StreamedResponse(
          stream.stream,
          429,
          headers: <String, String>{
            'content-type': 'application/json',
            'retry-after': '12',
          },
        ),
      );
      final Future<RagResult> pending = testGateway(client: client).query(
        request,
        context: testContext(),
      );
      await pumpEventQueue();
      expect(stream.hasListener, isTrue);

      // The body breaks the cap, then the released request pushes the
      // `RequestAbortedException` `package:http` injects into its stream.
      stream.add(List<int>.filled(RagHttpGateway.maxResponseBytes + 1, 0x20));
      stream.addError(http.RequestAbortedException(Uri.parse(
        'https://api.example.test/ai/rag/query',
      )));

      final Object outcome = await pending.then<Object>(
        (RagResult _) => 'resolved',
        onError: (Object error) => error,
      );
      expect(outcome, isA<RagFailure>());
      final RagFailure failure = outcome as RagFailure;
      expect(failure.code, RagFailureCode.rateLimited);
      expect(failure.retryAfterSeconds, 12);
      await stream.close();
    });

    test('never follows or accepts a redirect', () async {
      final ScriptedClient client = ScriptedClient(
        (_) async => jsonResponse(
          302,
          answeredEnvelope(),
          headers: <String, String>{'location': 'https://evil.test/next'},
        ),
      );

      await expectLater(
        testGateway(client: client).query(request, context: testContext()),
        throwsFailure(RagFailureCode.invalidProviderOutput),
      );
      expect(client.requests, hasLength(1));
      expect(
        (client.requests.single as http.AbortableRequest).followRedirects,
        isFalse,
      );
    });
  });

  group('ownership and close', () {
    test('never closes an injected client', () async {
      final ScriptedClient client = ScriptedClient(
        (_) async => jsonResponse(200, consentEnvelope()),
      );
      final RagHttpGateway gateway = testGateway(client: client);

      await gateway.readConsent(context: testContext());
      await gateway.close();

      expect(client.closed, isFalse);
    });

    test('closes once, aborts in-flight calls, and refuses new ones', () async {
      final Completer<http.StreamedResponse> transport =
          Completer<http.StreamedResponse>();
      final ScriptedClient client = ScriptedClient((_) => transport.future);
      final RagHttpGateway gateway = testGateway(client: client);

      final Future<Object?> pending = gateway
          .readConsent(context: testContext())
          .then<Object?>((Object? value) => value, onError: (Object error) => error);
      await pumpEventQueue();
      expect(client.requests, hasLength(1));

      await gateway.close();
      await gateway.close();

      expect(
        await pending,
        isA<RagFailure>().having(
          (RagFailure f) => f.code,
          'code',
          RagFailureCode.cancelled,
        ),
      );
      final http.AbortableRequest sent =
          client.requests.single as http.AbortableRequest;
      await sent.abortTrigger;

      await expectLater(
        gateway.readConsent(context: testContext()),
        throwsFailure(RagFailureCode.cancelled),
      );
      expect(client.requests, hasLength(1));
    });

    test('closes a client it created', () async {
      final RagHttpGateway gateway = RagHttpGateway(
        baseUri: Uri.parse('https://api.example.test'),
        tokenProvider: ({required bool forceRefresh}) async => testToken(),
        now: () => testNow,
      );

      await gateway.close();
      await gateway.close();
      await expectLater(
        gateway.query(request, context: testContext()),
        throwsFailure(RagFailureCode.cancelled),
      );
    });
  });

  group('transport failures', () {
    test('maps a client failure to the safe network code', () async {
      final ScriptedClient client = ScriptedClient(
        (_) async => throw http.ClientException('socket closed'),
      );

      await expectLater(
        testGateway(client: client).query(request, context: testContext()),
        throwsFailure(RagFailureCode.network),
      );
    });

    test('maps an unexpected transport error to the fail-closed code', () async {
      final ScriptedClient client = ScriptedClient(
        (_) async => throw StateError('unexpected'),
      );

      await expectLater(
        testGateway(client: client).query(request, context: testContext()),
        throwsFailure(RagFailureCode.unexpected),
      );
    });

    test('reports only the safe code from a failure', () async {
      final ScriptedClient client = ScriptedClient(
        (_) async => throw http.ClientException('token=secret-note-text'),
      );

      try {
        await testGateway(client: client).query(
          request,
          context: testContext(),
        );
        fail('expected a RagFailure');
      } on RagFailure catch (failure) {
        expect(failure.toString(), 'RagFailure(network)');
        expect(failure.toString(), isNot(contains('secret-note-text')));
      }
    });
  });
}
