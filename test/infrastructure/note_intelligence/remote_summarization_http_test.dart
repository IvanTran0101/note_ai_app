import 'summary_policy_test_support.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note_ai_app/domain/note_intelligence/summary.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/remote_summarization_service.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_http_gateway.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_request_policy.dart';

import 'remote_summary_test_support.dart' show policyWith, sectionCapacity;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final String token =
      'e30.${base64Url.encode(utf8.encode(jsonEncode(<String, String>{'sub': 'user-1'}))).replaceAll('=', '')}.c2ln';

  for (final bool chunked in <bool>[false, true]) {
    test(
      'gateway + orchestrator: ${chunked ? 'four sections and merge' : 'direct'}',
      () async {
        final SummaryRequestPolicy policy = chunked
            ? await policyWith((data) => data['maxInputEstimate'] = 1000)
            : await loadSummaryTestPolicy();
        final List<String> stages = <String>[];
        final MockClient client = MockClient((request) async {
          expect(request.url.path, '/prod/ai/summary');
          expect(request.headers['Authorization'], 'Bearer $token');
          final Map<String, dynamic> body =
              jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['consent'], <String, Object?>{
            'accepted': true,
            'version': policy.consentVersion,
          });
          final String stage = body['stage'] as String;
          stages.add(stage);
          final String text;
          if (stage == 'section') {
            text = 'section ${stages.length}';
          } else {
            if (stage == 'merge') {
              expect(body['inputs'], <String>[
                'section 1',
                'section 2',
                'section 3',
                'section 4',
              ]);
            }
            text = 'Kết quả cuối';
          }
          return http.Response(
            jsonEncode(<String, Object?>{
              'summary': text,
              'requestId': 'synthetic-${stages.length}',
              'usage': <String, int>{'inputTokens': 1, 'outputTokens': 1},
            }),
            200,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        });
        addTearDown(client.close);
        final SummaryHttpGateway gateway = SummaryHttpGateway(
          baseUri: Uri.parse('https://mock.example/prod'),
          policy: policy,
          expectedAccountUserId: 'user-1',
          tokenProvider: ({required bool forceRefresh}) async => token,
          client: client,
        );
        final RemoteSummarizationService service = RemoteSummarizationService(
          policy: policy,
          generate: gateway.generate,
          hasConsent: () => true,
        );
        final String content = chunked
            ? 'a' * (3 * sectionCapacity(policy, SummaryStage.section) + 1)
            : 'Nội dung note giả lập';
        expect(await service.summarize(content), const Summary('Kết quả cuối'));
        expect(
          stages,
          chunked
              ? <String>['section', 'section', 'section', 'section', 'merge']
              : <String>['direct'],
        );
      },
    );
  }
}
