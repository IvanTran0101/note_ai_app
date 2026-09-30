import 'summary_policy_test_support.dart';

import 'dart:convert';

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

  group('success envelope', () {
    test('matches backend ECMAScript trim for U+0085 output', () {
      expect(map(200, successBody(summary: '\u0085')), '\u0085');
    });

    test('returns the served text unchanged, including Unicode', () {
      const String text = 'Ghi chú: họp lúc 9h — ổn định ✓ ① không đổi';
      expect(map(200, successBody(summary: text)), text);
    });

    test('accepts token counts at the policy bounds', () {
      expect(
        map(
          200,
          successBody(
            usage: <String, Object?>{
              'inputTokens': policy.maxInputEstimate,
              'outputTokens': policy.maxOutputTokens(SummaryStage.direct),
            },
          ),
        ),
        isNotEmpty,
      );
      expect(
        map(
          200,
          successBody(
            usage: <String, Object?>{
              'inputTokens': policy.maxInputEstimate,
              'outputTokens': policy.maxOutputTokens(SummaryStage.section),
            },
          ),
          stage: SummaryStage.section,
        ),
        isNotEmpty,
      );
    });

    test('accepts zero usage, because the backend contract does', () {
      expect(
        map(
          200,
          successBody(
            usage: const <String, Object?>{'inputTokens': 0, 'outputTokens': 0},
          ),
        ),
        isNotEmpty,
      );
    });

    test('rejects usage past the input budget or the stage output budget', () {
      expect(
        () => map(
          200,
          successBody(
            usage: <String, Object?>{
              'inputTokens': policy.maxInputEstimate + 1,
              'outputTokens': 1,
            },
          ),
        ),
        throwsCode(SummaryApiErrorCode.invalidOutput),
      );
      expect(
        () => map(
          200,
          successBody(
            usage: <String, Object?>{
              'inputTokens': 1,
              'outputTokens': policy.maxOutputTokens(SummaryStage.section) + 1,
            },
          ),
          stage: SummaryStage.section,
        ),
        throwsCode(SummaryApiErrorCode.invalidOutput),
      );
      expect(
        () => map(
          200,
          successBody(
            usage: <String, Object?>{
              'inputTokens': 1,
              'outputTokens': policy.maxOutputTokens(SummaryStage.direct) + 1,
            },
          ),
        ),
        throwsCode(SummaryApiErrorCode.invalidOutput),
      );
    });
  });

  group('malformed success is invalidOutput, never a partial summary', () {
    final Map<String, String> bodies = <String, String>{
      'empty body': '',
      'not json': '<html>gateway</html>',
      'json array': '[1, 2, 3]',
      'json string': '"summary"',
      'missing summary': jsonEncode(<String, Object?>{
        'requestId': 'r',
        'usage': <String, Object?>{'inputTokens': 1, 'outputTokens': 1},
      }),
      'blank summary': successBody(summary: ' \t\n '),
      'summary wrong type': successBody(summary: 7),
      'missing requestId': jsonEncode(<String, Object?>{
        'summary': 'ok',
        'usage': <String, Object?>{'inputTokens': 1, 'outputTokens': 1},
      }),
      'blank requestId': successBody(requestId: '   '),
      'requestId wrong type': successBody(requestId: 12),
      'missing usage': jsonEncode(<String, Object?>{
        'summary': 'ok',
        'requestId': 'r',
      }),
      'usage array': successBody(usage: <Object?>[]),
      'usage empty': successBody(usage: <String, Object?>{}),
      'usage extra field': successBody(
        usage: <String, Object?>{
          'inputTokens': 1,
          'outputTokens': 1,
          'totalTokens': 2,
        },
      ),
      'usage missing output': successBody(
        usage: <String, Object?>{'inputTokens': 1},
      ),
      'usage bool': successBody(
        usage: <String, Object?>{'inputTokens': true, 'outputTokens': 1},
      ),
      'usage string': successBody(
        usage: <String, Object?>{'inputTokens': '1', 'outputTokens': 1},
      ),
      'usage negative': successBody(
        usage: <String, Object?>{'inputTokens': -1, 'outputTokens': 1},
      ),
      'usage fractional': successBody(
        usage: <String, Object?>{'inputTokens': 1, 'outputTokens': 1.5},
      ),
      'usage not finite':
          '{"summary":"ok","requestId":"r",'
          '"usage":{"inputTokens":1e999,"outputTokens":1}}',
      'extra top-level field': successBody(
        extra: const <String, Object?>{'model': 'deepseek-flash'},
      ),
      'error envelope served as 200':
          '{"error":{"code":"timeout"},"requestId":"r"}',
    };

    bodies.forEach((String label, String body) {
      test(label, () {
        expect(
          () => map(200, body),
          throwsCode(SummaryApiErrorCode.invalidOutput),
        );
      });
    });

    test('invalid UTF-8 bytes', () {
      expect(
        () => mapper.mapResponse(
          stage: SummaryStage.direct,
          statusCode: 200,
          bodyBytes: rawBytes(<int>[0x7b, 0xff, 0xfe, 0x7d]),
          headers: const <String, String>{},
        ),
        throwsCode(SummaryApiErrorCode.invalidOutput),
      );
    });
  });
}
