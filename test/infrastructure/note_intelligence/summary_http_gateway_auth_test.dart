import 'summary_policy_test_support.dart';

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
  group('auth', () {
    test('an absent token is unauthorized without a request', () async {
      final SummaryTestClient client = fixture.successClient();
      final SummaryHttpGateway gateway = fixture.buildGateway(
        client: client,
        tokenProvider: ({required bool forceRefresh}) async => null,
      );
      await expectLater(
        fixture.generate(gateway),
        throwsCode(SummaryApiErrorCode.unauthorized),
      );
      expect(client.requests, isEmpty);
    });

    test('a blank token is unauthorized without a request', () async {
      for (final String value in <String>['', '   ', '\t\n']) {
        final SummaryTestClient client = fixture.successClient();
        final SummaryHttpGateway gateway = fixture.buildGateway(
          client: client,
          tokenProvider: staticToken(value),
        );
        await expectLater(
          fixture.generate(gateway),
          throwsCode(SummaryApiErrorCode.unauthorized),
          reason: 'token "$value"',
        );
        expect(client.requests, isEmpty, reason: 'token "$value"');
      }
    });

    test(
      'a malformed or foreign token is unauthorized without a request',
      () async {
        for (final String value in <String>[
          'not-a-jwt',
          'a.b',
          jwt(null),
          jwt('user-2'),
          jwt(''),
        ]) {
          final SummaryTestClient client = fixture.successClient();
          final SummaryHttpGateway gateway = fixture.buildGateway(
            client: client,
            tokenProvider: staticToken(value),
          );
          await expectLater(
            fixture.generate(gateway),
            throwsCode(SummaryApiErrorCode.unauthorized),
            reason: 'token "$value"',
          );
          expect(client.requests, isEmpty, reason: 'token "$value"');
        }
      },
    );

    test('a token provider failure is unexpected and leaks nothing', () async {
      const String providerText = 'Synthetic provider failure for user-1';
      final SummaryTestClient client = fixture.successClient();
      final SummaryHttpGateway gateway = fixture.buildGateway(
        client: client,
        tokenProvider: ({required bool forceRefresh}) async =>
            throw StateError(providerText),
      );

      try {
        await fixture.generate(gateway);
        fail('expected a failure');
      } on SummaryApiFailure catch (failure) {
        expect(failure.code, SummaryApiErrorCode.unexpected);
        expect(failure.toString(), isNot(contains(providerText)));
      }
      expect(client.requests, isEmpty);
    });

    test('a 401 refreshes exactly once inside the same call', () async {
      final List<bool> refreshes = <bool>[];
      int sends = 0;
      final SummaryTestClient client = SummaryTestClient((
        http.BaseRequest request,
      ) async {
        sends++;
        if (sends == 1) {
          return envelope(401, SummaryApiErrorCode.unauthorized);
        }
        return response(200, successBody());
      });
      final SummaryHttpGateway gateway = fixture.buildGateway(
        client: client,
        tokenProvider: ({required bool forceRefresh}) async {
          refreshes.add(forceRefresh);
          return forceRefresh ? fixture.refreshedToken : fixture.token;
        },
      );

      expect(await fixture.generate(gateway), isNotEmpty);
      expect(refreshes, <bool>[false, true]);
      expect(client.requests, hasLength(2));
      expect(
        client.requests.first.headers['Authorization'],
        'Bearer ${fixture.token}',
      );
      expect(
        client.requests.last.headers['Authorization'],
        'Bearer ${fixture.refreshedToken}',
      );
    });

    test('a second 401 is unauthorized, never a second refresh', () async {
      final List<bool> refreshes = <bool>[];
      final SummaryTestClient client = SummaryTestClient(
        (http.BaseRequest request) async =>
            envelope(401, SummaryApiErrorCode.unauthorized),
      );
      final SummaryHttpGateway gateway = fixture.buildGateway(
        client: client,
        tokenProvider: ({required bool forceRefresh}) async {
          refreshes.add(forceRefresh);
          return forceRefresh ? fixture.refreshedToken : fixture.token;
        },
      );

      await expectLater(
        fixture.generate(gateway),
        throwsCode(SummaryApiErrorCode.unauthorized),
      );
      expect(refreshes, <bool>[false, true]);
      expect(client.requests, hasLength(2));
    });

    test(
      'a refresh without a token fails unauthorized without a resend',
      () async {
        final SummaryTestClient client = SummaryTestClient(
          (http.BaseRequest request) async =>
              envelope(401, SummaryApiErrorCode.unauthorized),
        );
        final SummaryHttpGateway gateway = fixture.buildGateway(
          client: client,
          tokenProvider: ({required bool forceRefresh}) async =>
              forceRefresh ? null : fixture.token,
        );

        await expectLater(
          fixture.generate(gateway),
          throwsCode(SummaryApiErrorCode.unauthorized),
        );
        expect(client.requests, hasLength(1));
      },
    );

    test('an account switch during refresh stops before the resend', () async {
      final SummaryTestClient client = SummaryTestClient(
        (http.BaseRequest request) async =>
            envelope(401, SummaryApiErrorCode.unauthorized),
      );
      final SummaryHttpGateway gateway = fixture.buildGateway(
        client: client,
        tokenProvider: ({required bool forceRefresh}) async =>
            forceRefresh ? jwt('user-2', id: 'other') : fixture.token,
      );

      await expectLater(
        fixture.generate(gateway),
        throwsCode(SummaryApiErrorCode.unauthorized),
      );
      expect(client.requests, hasLength(1));
    });

    test('a non-401 failure never refreshes or retries', () async {
      for (final (int status, SummaryApiErrorCode code)
          in <(int, SummaryApiErrorCode)>[
            (429, SummaryApiErrorCode.rateLimited),
            (400, SummaryApiErrorCode.invalidInput),
            (502, SummaryApiErrorCode.providerUnavailable),
            (504, SummaryApiErrorCode.timeout),
          ]) {
        final List<bool> refreshes = <bool>[];
        final SummaryTestClient client = SummaryTestClient(
          (http.BaseRequest request) async => envelope(status, code),
        );
        final SummaryHttpGateway gateway = fixture.buildGateway(
          client: client,
          tokenProvider: ({required bool forceRefresh}) async {
            refreshes.add(forceRefresh);
            return fixture.token;
          },
        );

        await expectLater(fixture.generate(gateway), throwsCode(code));
        expect(refreshes, <bool>[false], reason: 'status $status');
        expect(client.requests, hasLength(1), reason: 'status $status');
      }
    });

    test('a served retry hint is carried, not obeyed', () async {
      final SummaryTestClient client = SummaryTestClient(
        (http.BaseRequest request) async => envelope(
          429,
          SummaryApiErrorCode.rateLimited,
          headers: const <String, String>{'retry-after': '30'},
        ),
      );
      final SummaryHttpGateway gateway = fixture.buildGateway(
        client: client,
        tokenProvider: staticToken(fixture.token),
      );

      try {
        await fixture.generate(gateway);
        fail('expected a failure');
      } on SummaryApiFailure catch (failure) {
        expect(failure.code, SummaryApiErrorCode.rateLimited);
        expect(failure.retryAfterSeconds, 30);
      }
      expect(client.requests, hasLength(1));
    });
  });
}
