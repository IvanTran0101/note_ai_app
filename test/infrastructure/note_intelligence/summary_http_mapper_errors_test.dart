import 'summary_policy_test_support.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_api_failure.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_http_mapper.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_request_policy.dart';

import 'summary_mapper_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SummaryRequestPolicy policy;
  late SummaryHttpMapper mapper;

  setUpAll(() async {
    policy = await loadSummaryTestPolicy();
    mapper = SummaryHttpMapper(policy: policy);
  });

  String map(
    int statusCode,
    String body, {
    SummaryStage stage = SummaryStage.direct,
    Map<String, String> headers = const <String, String>{},
  }) => mapper.mapResponse(
    stage: stage,
    statusCode: statusCode,
    bodyBytes: bytes(body),
    headers: headers,
  );

  group('status classification stays authoritative', () {
    final List<(int, String, SummaryApiErrorCode, String)> cases =
        <(int, String, SummaryApiErrorCode, String)>[
          (
            400,
            '{"error":{"code":"invalidInput"}}',
            SummaryApiErrorCode.invalidInput,
            'contract 400',
          ),
          (
            400,
            '{"error":{"code":"unauthorized"}}',
            SummaryApiErrorCode.invalidInput,
            'body may not upgrade a 400',
          ),
          (
            401,
            '{"error":{"code":"unauthorized"}}',
            SummaryApiErrorCode.unauthorized,
            'contract 401',
          ),
          (
            401,
            '{"message":"Unauthorized"}',
            SummaryApiErrorCode.unauthorized,
            'authorizer rejection without envelope',
          ),
          (
            401,
            '{"error":{"code":"consentRequired"}}',
            SummaryApiErrorCode.unauthorized,
            'body may not upgrade a 401',
          ),
          (
            403,
            '{"error":{"code":"consentRequired"}}',
            SummaryApiErrorCode.consentRequired,
            'contract 403',
          ),
          (
            413,
            '{"error":{"code":"inputTooLong"}}',
            SummaryApiErrorCode.inputTooLong,
            'contract 413',
          ),
          (
            429,
            '{"error":{"code":"rateLimited"}}',
            SummaryApiErrorCode.rateLimited,
            'contract 429',
          ),
          (
            500,
            '{"error":{"code":"unexpected"}}',
            SummaryApiErrorCode.unexpected,
            'contract 500',
          ),
          (
            502,
            '{"error":{"code":"providerUnavailable"}}',
            SummaryApiErrorCode.providerUnavailable,
            'ambiguous 502',
          ),
          (
            502,
            '{"error":{"code":"invalidOutput"}}',
            SummaryApiErrorCode.invalidOutput,
            'ambiguous 502',
          ),
          (
            502,
            '<html>bad gateway</html>',
            SummaryApiErrorCode.providerUnavailable,
            'gateway body outside the envelope',
          ),
          (
            502,
            '{"error":{"code":"rateLimited"}}',
            SummaryApiErrorCode.providerUnavailable,
            'body may not invent a code for 502',
          ),
          (
            504,
            '{"error":{"code":"timeout"}}',
            SummaryApiErrorCode.timeout,
            'contract 504',
          ),
          (
            500,
            'not json at all',
            SummaryApiErrorCode.unexpected,
            'non-envelope 500',
          ),
          (
            404,
            '{"error":{"code":"unexpected"}}',
            SummaryApiErrorCode.unexpected,
            'undefined status',
          ),
          (
            503,
            '{"error":{"code":"providerUnavailable"}}',
            SummaryApiErrorCode.unexpected,
            'status outside the contract table',
          ),
          (
            302,
            '',
            SummaryApiErrorCode.unexpected,
            'a redirect is never followed or trusted',
          ),
          (0, '', SummaryApiErrorCode.unexpected, 'no status at all'),
        ];

    for (final (int status, String body, SummaryApiErrorCode code, String label)
        in cases) {
      test('$status -> ${code.name} ($label)', () {
        expect(() => map(status, body), throwsCode(code));
      });
    }
  });

  group('Retry-After is a bounded hint, never a retry', () {
    SummaryApiFailure rateLimited(Map<String, String> headers) {
      try {
        map(429, '{"error":{"code":"rateLimited"}}', headers: headers);
      } on SummaryApiFailure catch (failure) {
        return failure;
      }
      fail('expected a failure');
    }

    test('reads a valid integer header case-insensitively', () {
      expect(
        rateLimited(const <String, String>{'retry-after': '30'})
            .retryAfterSeconds,
        30,
      );
      expect(
        rateLimited(const <String, String>{'Retry-After': ' 45 '})
            .retryAfterSeconds,
        45,
      );
      expect(
        rateLimited(const <String, String>{'RETRY-AFTER': '3600'})
            .retryAfterSeconds,
        3600,
      );
      expect(
        rateLimited(const <String, String>{'retry-after': '1'})
            .retryAfterSeconds,
        1,
      );
    });

    test('ignores everything that is not a bounded whole number', () {
      for (final String value in <String>[
        '0',
        '3601',
        '-5',
        '+5',
        '5.5',
        'abc',
        'Wed, 21 Oct 2015 07:28:00 GMT',
        '1 2',
        '',
      ]) {
        expect(
          rateLimited(<String, String>{'retry-after': value}).retryAfterSeconds,
          isNull,
          reason: 'value: "$value"',
        );
      }
      expect(rateLimited(const <String, String>{}).retryAfterSeconds, isNull);
    });

    test('is not attached to any other failure', () {
      for (final int status in <int>[400, 401, 403, 500, 502, 504]) {
        try {
          map(
            status,
            '{}',
            headers: const <String, String>{'retry-after': '30'},
          );
          fail('expected a failure');
        } on SummaryApiFailure catch (failure) {
          expect(failure.retryAfterSeconds, isNull, reason: 'status $status');
        }
      }
    });
  });

  test('failures carry only a code, never a body or a requestId', () {
    const String secret = 'sk-live-should-never-surface';
    try {
      map(
        500,
        '{"error":{"code":"unexpected"},"requestId":"req-secret",'
        '"providerKey":"$secret"}',
      );
      fail('expected a failure');
    } on SummaryApiFailure catch (failure) {
      expect(failure.toString(), 'SummaryApiFailure(unexpected)');
      expect(failure.toString(), isNot(contains(secret)));
      expect(failure.toString(), isNot(contains('req-secret')));
    }

    try {
      map(200, successBody(summary: '', requestId: secret));
      fail('expected a failure');
    } on SummaryApiFailure catch (failure) {
      expect(failure.toString(), 'SummaryApiFailure(invalidOutput)');
      expect(failure.toString(), isNot(contains(secret)));
    }
  });
}
