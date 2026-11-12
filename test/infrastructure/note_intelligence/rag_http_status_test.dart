import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/rag_http_mapper.dart';

import 'rag_http_test_support.dart';

/// Status-first classification: the contract's `errorHttpStatus` table stays
/// authoritative, the body may refine it only inside the codes that status
/// allows, an unknown status or code fails closed, and `Retry-After` is read
/// only for `429` and only when it is a bounded whole number of seconds.
void main() {
  const RagHttpMapper mapper = RagHttpMapper();

  /// The exact status of every backend code, from `policy_v1.json`.
  const Map<String, int> statusOfCode = <String, int>{
    'INVALID_INPUT': 400,
    'INPUT_TOO_LONG': 413,
    'UNAUTHORIZED': 401,
    'CONSENT_REQUIRED': 403,
    'SCOPE_DENIED': 404,
    'INDEX_NOT_READY': 409,
    'SOURCE_CHANGED': 409,
    'RATE_LIMITED': 429,
    'EVIDENCE_VALIDATION_UNAVAILABLE': 503,
    'PROVIDER_UNAVAILABLE': 503,
    'INVALID_PROVIDER_OUTPUT': 502,
    'TIMEOUT': 504,
    'LIVE_POLICY_NOT_CONFIGURED': 503,
  };

  Uint8List bytes(Object? body) => Uint8List.fromList(
    utf8.encode(body is String ? body : jsonEncode(body)),
  );

  RagFailure failureOf(
    int statusCode,
    Uint8List? body, {
    Map<String, String> headers = const <String, String>{},
  }) {
    try {
      mapper.mapQuery(
        statusCode: statusCode,
        headers: headers,
        bodyBytes: body,
      );
    } on RagFailure catch (failure) {
      return failure;
    }
    fail('expected a RagFailure for status $statusCode');
  }

  group('contract codes', () {
    test('maps every backend code at its contract status', () {
      // The frozen contract has exactly these thirteen backend codes.
      expect(statusOfCode, hasLength(13));

      for (final MapEntry<String, int> entry in statusOfCode.entries) {
        final RagFailureCode? expected = RagFailureCode.fromWireCode(entry.key);
        expect(expected, isNotNull, reason: entry.key);
        final RagFailure failure = failureOf(
          entry.value,
          bytes(errorEnvelope(entry.key)),
        );
        expect(failure.code, expected, reason: entry.key);
      }
    });

    test('refuses an unknown code and keeps the status classification', () {
      expect(
        failureOf(500, bytes(errorEnvelope('TEAPOT'))).code,
        RagFailureCode.providerUnavailable,
      );
      expect(
        failureOf(400, bytes(errorEnvelope('TEAPOT'))).code,
        RagFailureCode.invalidInput,
      );
    });

    test('refuses a body code the status does not allow', () {
      // A `500` may not claim a timeout; the status stays in charge.
      expect(
        failureOf(500, bytes(errorEnvelope('TIMEOUT'))).code,
        RagFailureCode.providerUnavailable,
      );
      expect(
        failureOf(429, bytes(errorEnvelope('SOURCE_CHANGED'))).code,
        RagFailureCode.rateLimited,
      );
    });

    test('lets an ambiguous status refine from the body', () {
      expect(
        failureOf(409, bytes(errorEnvelope('INDEX_NOT_READY'))).code,
        RagFailureCode.indexNotReady,
      );
      expect(
        failureOf(409, bytes(errorEnvelope('SOURCE_CHANGED'))).code,
        RagFailureCode.sourceChanged,
      );
      expect(
        failureOf(502, bytes(errorEnvelope('INVALID_PROVIDER_OUTPUT'))).code,
        RagFailureCode.invalidProviderOutput,
      );
      expect(
        failureOf(
          503,
          bytes(errorEnvelope('EVIDENCE_VALIDATION_UNAVAILABLE')),
        ).code,
        RagFailureCode.evidenceValidationUnavailable,
      );
      expect(
        failureOf(503, bytes(errorEnvelope('LIVE_POLICY_NOT_CONFIGURED'))).code,
        RagFailureCode.livePolicyNotConfigured,
      );
      expect(
        failureOf(403, bytes(errorEnvelope('SCOPE_DENIED'))).code,
        RagFailureCode.scopeDenied,
      );
    });

    test('ignores a malformed envelope instead of refining with it', () {
      expect(
        failureOf(400, bytes('{"code":"RATE_LIMITED"')).code,
        RagFailureCode.invalidInput,
      );
      expect(
        failureOf(
          400,
          bytes(<String, Object?>{...errorEnvelope('RATE_LIMITED'), 'status': 'OK'}),
        ).code,
        RagFailureCode.invalidInput,
      );
      expect(
        failureOf(
          400,
          bytes(<String, Object?>{...errorEnvelope('RATE_LIMITED'), 'wireVersion': 2}),
        ).code,
        RagFailureCode.invalidInput,
      );
      expect(
        failureOf(
          400,
          bytes(<String, Object?>{
            ...errorEnvelope('RATE_LIMITED'),
            'requestId': 7,
          }),
        ).code,
        RagFailureCode.invalidInput,
      );
    });
  });

  group('non-JSON gateway answers', () {
    test('classifies an authorizer 401 and a throttle 429', () {
      for (final Uint8List? body in <Uint8List?>[
        null,
        Uint8List(0),
        bytes('<html>unauthorized</html>'),
        Uint8List.fromList(<int>[0xff, 0xfe]),
      ]) {
        expect(failureOf(401, body).code, RagFailureCode.unauthorized);
        expect(failureOf(429, body).code, RagFailureCode.rateLimited);
      }
    });

    test('classifies every 5xx as provider failure with 504 as timeout', () {
      for (final int status in <int>[500, 501, 502, 505, 599]) {
        expect(failureOf(status, null).code, RagFailureCode.providerUnavailable);
      }
      expect(failureOf(503, null).code, RagFailureCode.providerUnavailable);
      expect(failureOf(504, null).code, RagFailureCode.timeout);
    });

    test('classifies 403, 404, 409, 413, and 400 without a body', () {
      expect(failureOf(400, null).code, RagFailureCode.invalidInput);
      expect(failureOf(403, null).code, RagFailureCode.consentRequired);
      expect(failureOf(404, null).code, RagFailureCode.scopeDenied);
      expect(failureOf(409, null).code, RagFailureCode.sourceChanged);
      expect(failureOf(413, null).code, RagFailureCode.inputTooLong);
    });

    test('fails closed on a status the contract never defined', () {
      for (final int status in <int>[204, 301, 302, 402, 418, 600]) {
        expect(
          failureOf(status, bytes(answeredEnvelope())).code,
          RagFailureCode.invalidProviderOutput,
        );
      }
    });

    test('never accepts a redirect body as a result', () {
      expect(
        failureOf(
          302,
          bytes(answeredEnvelope()),
          headers: <String, String>{'location': 'https://evil.test'},
        ).code,
        RagFailureCode.invalidProviderOutput,
      );
    });

    test('never accepts an answer envelope served with a failure status', () {
      expect(
        failureOf(503, bytes(answeredEnvelope())).code,
        RagFailureCode.providerUnavailable,
      );
    });
  });

  group('retry hint', () {
    RagFailure retry(String? header, {int status = 429}) {
      return failureOf(
        status,
        bytes(errorEnvelope('RATE_LIMITED')),
        headers: <String, String>{
          'Retry-After': ?header,
        },
      );
    }

    test('reads a bounded whole number of seconds', () {
      expect(retry('1').retryAfterSeconds, 1);
      expect(retry('30').retryAfterSeconds, 30);
      expect(retry('3600').retryAfterSeconds, 3600);
      expect(retry(' 42 ').retryAfterSeconds, 42);
    });

    test('drops an unusable hint instead of clamping it', () {
      for (final String? header in <String?>[
        null,
        '',
        '0',
        '3601',
        '-5',
        '1.5',
        'soon',
        'Wed, 21 Oct 2026 07:28:00 GMT',
      ]) {
        expect(retry(header).retryAfterSeconds, isNull, reason: '$header');
      }
    });

    test('ignores the hint on any other status', () {
      expect(
        failureOf(
          503,
          bytes(errorEnvelope('PROVIDER_UNAVAILABLE')),
          headers: const <String, String>{'Retry-After': '30'},
        ).retryAfterSeconds,
        isNull,
      );
    });
  });

  group('consent route', () {
    RagFailureCode consentProblem(int statusCode, Uint8List? body) {
      try {
        mapper.mapConsent(
          statusCode: statusCode,
          headers: const <String, String>{},
          bodyBytes: body,
        );
      } on RagFailure catch (failure) {
        return failure.code;
      }
      fail('expected a RagFailure for status $statusCode');
    }

    test('classifies a non-JSON 409 compare-and-set loss as sourceChanged', () {
      expect(consentProblem(409, null), RagFailureCode.sourceChanged);
    });

    test('classifies a refusal by the pilot policy', () {
      expect(
        consentProblem(503, bytes(errorEnvelope('LIVE_POLICY_NOT_CONFIGURED'))),
        RagFailureCode.livePolicyNotConfigured,
      );
    });

    test('classifies an expired token as unauthorized', () {
      expect(consentProblem(401, null), RagFailureCode.unauthorized);
    });

    test('fails closed on an unknown status', () {
      expect(
        consentProblem(418, bytes(consentEnvelope())),
        RagFailureCode.invalidProviderOutput,
      );
    });
  });
}
