import 'summary_policy_test_support.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:note_ai_app/infrastructure/note_intelligence/summary_api_failure.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_http_gateway.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_request_policy.dart';

import 'summary_gateway_test_support.dart';

import 'package:note_ai_app/infrastructure/sync/cognito_access_token_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SummaryGatewayTestFixture fixture;
  setUpAll(() async {
    fixture = SummaryGatewayTestFixture(await loadSummaryTestPolicy());
  });
  group('request shape', () {
    test('sends one contract body and returns the served text', () async {
      final SummaryTestClient client = fixture.successClient(
        summary: 'Tóm tắt: họp 9h ✓ ①',
      );
      final SummaryHttpGateway gateway = fixture.buildGateway(
        client: client,
        tokenProvider: staticToken(fixture.token),
      );

      expect(
        await fixture.generate(gateway, inputs: <String>['Nội dung ghi chú']),
        'Tóm tắt: họp 9h ✓ ①',
      );

      expect(client.requests, hasLength(1));
      final http.BaseRequest request = client.requests.single;
      expect(request.method, 'POST');
      expect(request.url, Uri.parse('https://api.example.com/prod/ai/summary'));
      expect(request.headers['Authorization'], 'Bearer ${fixture.token}');
      expect(request.headers['Content-Type'], 'application/json');
      expect(request.headers['Accept'], 'application/json');
      expect(jsonDecode(utf8.decode(client.bodies.single)), <String, Object?>{
        'stage': 'direct',
        'inputs': <String>['Nội dung ghi chú'],
        'consent': <String, Object?>{
          'accepted': true,
          'version': 'summary-cloud-v1',
        },
      });
    });

    test('preserves the base path with and without a trailing slash', () async {
      const Map<String, String> cases = <String, String>{
        'https://api.example.com/prod':
            'https://api.example.com/prod/ai/summary',
        'https://api.example.com/prod/':
            'https://api.example.com/prod/ai/summary',
        'https://api.example.com': 'https://api.example.com/ai/summary',
        'http://localhost:8080/prod': 'http://localhost:8080/prod/ai/summary',
      };
      for (final MapEntry<String, String> entry in cases.entries) {
        final SummaryTestClient client = fixture.successClient();
        final SummaryHttpGateway gateway = fixture.buildGateway(
          client: client,
          tokenProvider: staticToken(fixture.token),
          baseUri: Uri.parse(entry.key),
        );
        await fixture.generate(gateway);
        expect(
          client.requests.single.url,
          Uri.parse(entry.value),
          reason: 'base ${entry.key}',
        );
      }
    });

    test('keeps merge input order and Unicode byte-for-byte', () async {
      const List<String> inputs = <String>[
        'Đoạn một 😀',
        'Đoạn hai',
        'Đoạn ba',
      ];
      final SummaryTestClient client = fixture.successClient();
      final SummaryHttpGateway gateway = fixture.buildGateway(
        client: client,
        tokenProvider: staticToken(fixture.token),
      );

      await fixture.generate(
        gateway,
        stage: SummaryStage.merge,
        inputs: inputs,
      );

      final Map<String, dynamic> body =
          jsonDecode(utf8.decode(client.bodies.single)) as Map<String, dynamic>;
      expect(body['stage'], 'merge');
      expect(body['inputs'], inputs);
    });

    test('generate matches the shared stage-generator typedef', () {
      final SummaryStageGenerator generator = fixture
          .buildGateway(
            client: fixture.successClient(),
            tokenProvider: staticToken(fixture.token),
          )
          .generate;
      expect(generator, isNotNull);
    });

    test('the existing Cognito token provider satisfies the callback shape', () {
      // A tear-off is a compile-time check only: no Amplify call is made here.
      const CognitoAccessTokenProvider provider = CognitoAccessTokenProvider();
      final Future<String?> Function({required bool forceRefresh}) callback =
          provider.call;
      expect(callback, isNotNull);
    });
  });

  group('pre-send guards', () {
    test('refuses without consent before any token read or request', () async {
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
        fixture.generate(gateway, consentAccepted: false),
        throwsCode(SummaryApiErrorCode.consentRequired),
      );
      expect(tokenReads, 0);
      expect(client.requests, isEmpty);
    });

    test(
      'refuses an over-budget input before any token read or request',
      () async {
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
          fixture.generate(gateway, inputs: <String>['a' * 20000]),
          throwsCode(SummaryApiErrorCode.inputTooLong),
        );
        expect(tokenReads, 0);
        expect(client.requests, isEmpty);
      },
    );

    test('refuses a body past the 256 KiB transport cap before auth', () async {
      // The policy estimate trims the edges, so this input fits the 16000-fixture.token
      // estimate while the bytes actually sent do not.
      final SummaryTestClient client = fixture.successClient();
      final SummaryHttpGateway gateway = fixture.buildGateway(
        client: client,
        tokenProvider: staticToken(fixture.token),
      );

      await expectLater(
        fixture.generate(gateway, inputs: <String>['${' ' * 300000}x']),
        throwsCode(SummaryApiErrorCode.inputTooLong),
      );
      expect(client.requests, isEmpty);
    });

    test(
      'refuses bad cardinality, blank inputs, and over-long merges',
      () async {
        final SummaryTestClient client = fixture.successClient();
        final SummaryHttpGateway gateway = fixture.buildGateway(
          client: client,
          tokenProvider: staticToken(fixture.token),
        );

        await expectLater(
          fixture.generate(gateway, inputs: <String>['a', 'b']),
          throwsCode(SummaryApiErrorCode.invalidInput),
        );
        await expectLater(
          fixture.generate(
            gateway,
            stage: SummaryStage.merge,
            inputs: <String>['a'],
          ),
          throwsCode(SummaryApiErrorCode.invalidInput),
        );
        await expectLater(
          fixture.generate(gateway, inputs: <String>[' \t\n']),
          throwsCode(SummaryApiErrorCode.invalidInput),
        );
        await expectLater(
          fixture.generate(
            gateway,
            stage: SummaryStage.merge,
            inputs: List<String>.filled(fixture.policy.maxChunks + 1, 'đoạn'),
          ),
          throwsCode(SummaryApiErrorCode.pipelineTooLarge),
        );
        expect(client.requests, isEmpty);
      },
    );
  });

  group('configuration', () {
    test('rejects a base URI that would make the endpoint ambiguous', () {
      for (final String base in <String>[
        'ftp://api.example.com/prod',
        'https:///prod',
        'https://user:pass@api.example.com/prod',
        'https://api.example.com/prod?stage=direct',
        'https://api.example.com/prod#fragment',
      ]) {
        expect(
          () => fixture.buildGateway(
            client: fixture.successClient(),
            tokenProvider: staticToken(fixture.token),
            baseUri: Uri.parse(base),
          ),
          throwsArgumentError,
          reason: 'base $base',
        );
      }
    });

    test('rejects a blank expected account id', () {
      for (final String account in <String>['', '   ', '\t']) {
        expect(
          () => fixture.buildGateway(
            client: fixture.successClient(),
            tokenProvider: staticToken(fixture.token),
            expectedAccountUserId: account,
          ),
          throwsArgumentError,
          reason: 'account "$account"',
        );
      }
    });

    test('accepts the 35 s ceiling and rejects anything longer', () {
      expect(
        () => fixture.buildGateway(
          client: fixture.successClient(),
          tokenProvider: staticToken(fixture.token),
          timeout: SummaryHttpGateway.maxTimeout,
        ),
        returnsNormally,
      );
      for (final Duration timeout in <Duration>[
        SummaryHttpGateway.maxTimeout + const Duration(milliseconds: 1),
        const Duration(minutes: 5),
        Duration.zero,
        const Duration(seconds: -1),
      ]) {
        expect(
          () => fixture.buildGateway(
            client: fixture.successClient(),
            tokenProvider: staticToken(fixture.token),
            timeout: timeout,
          ),
          throwsArgumentError,
          reason: 'timeout $timeout',
        );
      }
    });
  });

  group('client ownership', () {
    test('a borrowed client stays open on close', () {
      final SummaryTestClient client = fixture.successClient();
      final SummaryHttpGateway gateway = fixture.buildGateway(
        client: client,
        tokenProvider: staticToken(fixture.token),
      );

      gateway.close();
      expect(client.closed, isFalse);
    });

    test('an owned client can be closed twice without error', () {
      final SummaryHttpGateway gateway = SummaryHttpGateway(
        baseUri: Uri.parse('https://api.example.com/prod'),
        policy: fixture.policy,
        tokenProvider: staticToken(fixture.token),
        expectedAccountUserId: 'user-1',
      );

      expect(gateway.close, returnsNormally);
      expect(gateway.close, returnsNormally);
    });
  });
}
