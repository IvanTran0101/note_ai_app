import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_request_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled concise prompts and estimates match all backend goldens',
    () async {
      final policy = await SummaryRequestPolicy.load();
      final golden = jsonDecode(
        await File('test/fixtures/summary_policy_golden.json').readAsString(),
      ) as Map<String, dynamic>;
      for (final raw in golden['cases'] as List<dynamic>) {
        final sample = raw as Map<String, dynamic>;
        final stage = SummaryStage.values.byName(sample['stage'] as String);
        final repeat = sample['repeatInput'] as Map<String, dynamic>?;
        final inputs = repeat == null
            ? (sample['inputs'] as List<dynamic>).cast<String>()
            : <String>[
                List<String>.filled(
                  repeat['count'] as int,
                  repeat['unit'] as String,
                ).join(),
              ];
        final id = sample['id'] as String;
        if (sample['expectedMessagesJson'] != null) {
          expect(
            policy.messagesJson(stage, inputs),
            sample['expectedMessagesJson'],
            reason: id,
          );
        }
        expect(
          policy.estimateInputTokens(stage, inputs),
          sample['expectedEstimate'],
          reason: id,
        );
        expect(
          policy.fitsInput(stage, inputs),
          sample['expectedFits'],
          reason: id,
        );
      }
      expect(policy.maxInputEstimate, 16000);
      expect(policy.maxChunks, 4);
      expect(policy.maxGenerationCalls, 5);
      for (final stage in SummaryStage.values) {
        final section = stage == SummaryStage.section;
        final prompt = policy
            .buildMessages(
              stage,
              stage == SummaryStage.merge ? ['a', 'b'] : ['a'],
            )
            .first['content']!;
        expect(
          prompt,
          contains(
            section
                ? '1 short sentence and 25 words'
                : '2 short sentences and 45 words',
          ),
        );
        expect(
          prompt,
          contains('omit minor details rather than listing everything'),
        );
        expect(prompt, contains('Finish complete sentences'));
        expect(policy.maxOutputTokens(stage), section ? 128 : 256);
      }
    },
  );
}
