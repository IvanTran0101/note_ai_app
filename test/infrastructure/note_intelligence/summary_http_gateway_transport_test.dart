import 'summary_policy_test_support.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:note_ai_app/infrastructure/note_intelligence/summary_api_failure.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_http_gateway.dart';

import 'summary_gateway_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SummaryGatewayTestFixture fixture;
  setUpAll(() async {
    fixture = SummaryGatewayTestFixture(await loadSummaryTestPolicy());
  });
  group('deadline', () {
    test('an expired deadline fails without a token read or request', () async {
      final SummaryTestClient client = fixture.successClient();
      int tokenReads = 0;
      final SummaryHttpGateway gateway = fixture.buildGateway(
        client: client,
        tokenProvider: ({required bool forceRefresh}) async {
          tokenReads++;
          return fixture.token;
        },
      );

      await expectLater(
        fixture.generate(
          gateway,
          deadline: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
        throwsCode(SummaryApiErrorCode.timeout),
      );
      expect(tokenReads, 0);
      expect(client.requests, isEmpty);
    });

    test(
      'a token that lands after the deadline never starts a request',
      () async {
        final SummaryTestClient client = fixture.successClient();
        final Completer<String?> gate = Completer<String?>();
        final SummaryHttpGateway gateway = fixture.buildGateway(
          client: client,
          tokenProvider: ({required bool forceRefresh}) => gate.future,
          timeout: const Duration(milliseconds: 40),
        );

        await expectLater(
          fixture.generate(gateway),
          throwsCode(SummaryApiErrorCode.timeout),
        );
        expect(client.requests, isEmpty);

        gate.complete(fixture.token);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          client.requests,
          isEmpty,
          reason: 'late token must not dispatch',
        );
      },
    );

    test(
      'a body that never completes times out, aborts, and cancels the stream',
      () async {
        bool cancelled = false;
        final StreamController<List<int>> controller =
            StreamController<List<int>>();
        controller.onCancel = () => cancelled = true;
        controller.add(utf8.encode('{"summary":"cut'));
        final SummaryTestClient client = SummaryTestClient(
          (http.BaseRequest request) async =>
              response(200, '', stream: controller.stream),
        );
        final SummaryHttpGateway gateway = fixture.buildGateway(
          client: client,
          tokenProvider: staticToken(fixture.token),
          timeout: const Duration(milliseconds: 60),
        );

        await expectLater(
          fixture.generate(gateway),
          throwsCode(SummaryApiErrorCode.timeout),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(cancelled, isTrue);

        final http.AbortableRequest request =
            client.requests.single as http.AbortableRequest;
        await request.abortTrigger!.timeout(const Duration(seconds: 1));
        await controller.close();
      },
    );

    test('a deadline shorter than the timeout bounds the whole call', () async {
      final StreamController<List<int>> controller =
          StreamController<List<int>>();
      final SummaryTestClient client = SummaryTestClient(
        (http.BaseRequest request) async =>
            response(200, '', stream: controller.stream),
      );
      final SummaryHttpGateway gateway = fixture.buildGateway(
        client: client,
        tokenProvider: staticToken(fixture.token),
      );

      await expectLater(
        fixture.generate(
          gateway,
          deadline: DateTime.now().add(const Duration(milliseconds: 60)),
        ),
        throwsCode(SummaryApiErrorCode.timeout),
      );
      expect(client.requests, hasLength(1));
      await controller.close();
    });

    test('a call inside its budget still succeeds', () async {
      final SummaryTestClient client = fixture.successClient();
      final SummaryHttpGateway gateway = fixture.buildGateway(
        client: client,
        tokenProvider: staticToken(fixture.token),
        timeout: const Duration(milliseconds: 500),
      );

      expect(
        await fixture.generate(
          gateway,
          deadline: DateTime.now().add(const Duration(seconds: 5)),
        ),
        isNotEmpty,
      );
      expect(client.requests, hasLength(1));
    });
  });

  group('response handling', () {
    test(
      'a malformed success is invalidOutput, never a partial summary',
      () async {
        final SummaryTestClient client = SummaryTestClient(
          (http.BaseRequest request) async => response(200, '{"summary":"ok"}'),
        );
        final SummaryHttpGateway gateway = fixture.buildGateway(
          client: client,
          tokenProvider: staticToken(fixture.token),
        );

        await expectLater(
          fixture.generate(gateway),
          throwsCode(SummaryApiErrorCode.invalidOutput),
        );
      },
    );

    test('a declared oversized body is refused without buffering it', () async {
      bool cancelled = false;
      final StreamController<List<int>> controller =
          StreamController<List<int>>();
      controller.onCancel = () => cancelled = true;
      final SummaryTestClient client = SummaryTestClient(
        (http.BaseRequest request) async => http.StreamedResponse(
          controller.stream,
          200,
          contentLength: SummaryHttpGateway.maxResponseBytes + 1,
        ),
      );
      final SummaryHttpGateway gateway = fixture.buildGateway(
        client: client,
        tokenProvider: staticToken(fixture.token),
      );

      await expectLater(
        fixture.generate(gateway),
        throwsCode(SummaryApiErrorCode.invalidOutput),
      );
      expect(cancelled, isTrue);
      await controller.close();
    });

    test('a chunked body past the cap aborts the read', () async {
      bool cancelled = false;
      final StreamController<List<int>> controller =
          StreamController<List<int>>();
      controller.onCancel = () => cancelled = true;
      for (int index = 0; index < 9; index++) {
        controller.add(List<int>.filled(8 * 1024, 0x61));
      }
      final SummaryTestClient client = SummaryTestClient(
        (http.BaseRequest request) async =>
            response(200, '', stream: controller.stream),
      );
      final SummaryHttpGateway gateway = fixture.buildGateway(
        client: client,
        tokenProvider: staticToken(fixture.token),
      );

      await expectLater(
        fixture.generate(gateway),
        throwsCode(SummaryApiErrorCode.invalidOutput),
      );
      expect(cancelled, isTrue);
      await controller.close();
    });

    test(
      'a redirect is not followed and keeps the token off the next host',
      () async {
        final SummaryTestClient client = SummaryTestClient(
          (http.BaseRequest request) async => response(
            302,
            '',
            headers: const <String, String>{
              'location': 'https://evil.example.com/',
            },
          ),
        );
        final SummaryHttpGateway gateway = fixture.buildGateway(
          client: client,
          tokenProvider: staticToken(fixture.token),
        );

        await expectLater(
          fixture.generate(gateway),
          throwsCode(SummaryApiErrorCode.unexpected),
        );
        expect(client.requests, hasLength(1));
        expect(client.requests.single.followRedirects, isFalse);
        expect(client.requests.single.maxRedirects, 0);
        expect(client.requests.single, isA<http.AbortableRequest>());
      },
    );

    test(
      'a transport failure is networkUnavailable and leaks nothing',
      () async {
        const String url =
            'https://api.example.com/prod/ai/summary?token=secret';
        final SummaryTestClient client = SummaryTestClient(
          (http.BaseRequest request) async =>
              throw http.ClientException(url, request.url),
        );
        final SummaryHttpGateway gateway = fixture.buildGateway(
          client: client,
          tokenProvider: staticToken(fixture.token),
        );

        try {
          await fixture.generate(gateway);
          fail('expected a failure');
        } on SummaryApiFailure catch (failure) {
          expect(failure.code, SummaryApiErrorCode.networkUnavailable);
          expect(failure.toString(), 'SummaryApiFailure(networkUnavailable)');
          expect(failure.toString(), isNot(contains('secret')));
          expect(failure.toString(), isNot(contains(fixture.token)));
        }
      },
    );

    test('a failure never carries the token or the note text', () async {
      const String note = 'Ghi chú riêng tư tuyệt mật';
      final SummaryTestClient client = SummaryTestClient(
        (http.BaseRequest request) async => response(
          500,
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{'code': 'unexpected'},
            'requestId': 'req-secret',
            'echo': note,
          }),
        ),
      );
      final SummaryHttpGateway gateway = fixture.buildGateway(
        client: client,
        tokenProvider: staticToken(fixture.token),
      );

      try {
        await fixture.generate(gateway, inputs: <String>[note]);
        fail('expected a failure');
      } on SummaryApiFailure catch (failure) {
        expect(failure.code, SummaryApiErrorCode.unexpected);
        expect(failure.toString(), 'SummaryApiFailure(unexpected)');
        expect(failure.toString(), isNot(contains(note)));
        expect(failure.toString(), isNot(contains(fixture.token)));
        expect(failure.toString(), isNot(contains('req-secret')));
      }
    });
  });
}
