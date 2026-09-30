import 'summary_policy_test_support.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/note_intelligence/summary.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_api_failure.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_request_policy.dart';

import 'remote_summary_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SummaryRequestPolicy policy;
  late SummaryRequestPolicy smallPolicy;

  setUpAll(() async {
    policy = await loadSummaryTestPolicy();
    smallPolicy = await policyWith((Map<String, dynamic> data) {
      data['maxInputEstimate'] = 1000;
    });
  });

  group('routing and budget', () {
    test('preflights body caps before spending any section call', () async {
      final int capacity = sectionCapacity(smallPolicy, SummaryStage.section);
      final SummaryTestGenerator generator = SummaryTestGenerator(
        (SummaryTestStageCall call) async => 'text',
      );
      final String content =
          '${'a' * capacity}${' ' * smallPolicy.maxBodyBytesUtf8}b';
      await expectLater(
        remoteService(smallPolicy, generator).summarize(content),
        failsWith(SummaryApiErrorCode.inputTooLong),
      );
      expect(generator.calls, isEmpty);
    });

    test('sends exactly one direct call at the direct boundary', () async {
      final String content = directContentAt(policy, policy.maxInputEstimate);
      expect(policy.maxInputEstimate, 16000);
      expect(
        policy.estimateInputTokens(SummaryStage.direct, <String>[content]),
        16000,
      );
      final SummaryTestGenerator generator = SummaryTestGenerator(
        (SummaryTestStageCall call) async => 'direct',
      );

      final Summary summary = await remoteService(
        policy,
        generator,
      ).summarize(content);

      expect(summary.text, 'direct');
      expect(generator.stages, <SummaryStage>[SummaryStage.direct]);
      expect(generator.calls.single.inputs, <String>[content]);
      expect(generator.calls.single.consentAccepted, isTrue);
      expect(generator.calls.single.deadline, isNotNull);
    });

    test(
      'chunks one byte past the boundary into two sections and one merge',
      () async {
        final String content = directContentAt(
          policy,
          policy.maxInputEstimate + 1,
        );
        expect(
          policy.estimateInputTokens(SummaryStage.direct, <String>[content]),
          16001,
        );
        final SummaryTestGenerator generator = SummaryTestGenerator((
          SummaryTestStageCall call,
        ) async {
          switch (call.stage) {
            case SummaryStage.section:
              return 'section ${call.inputs.single.length}';
            case SummaryStage.direct:
              return 'unexpected direct';
            case SummaryStage.merge:
              return 'merged';
          }
        });

        final Summary summary = await remoteService(
          policy,
          generator,
        ).summarize(content);

        expect(summary.text, 'merged');
        expect(generator.stages, <SummaryStage>[
          SummaryStage.section,
          SummaryStage.section,
          SummaryStage.merge,
        ]);
        final List<String> chunks = <String>[
          for (final SummaryTestStageCall call in generator.calls)
            if (call.stage == SummaryStage.section) call.inputs.single,
        ];
        expect(chunks.join(), content);
        expect(generator.calls.last.inputs, <String>[
          for (final String chunk in chunks) 'section ${chunk.length}',
        ]);
      },
    );

    test('runs four sections and one merge for a four chunk note', () async {
      final int capacity = sectionCapacity(smallPolicy, SummaryStage.section);
      expect(capacity, greaterThan(8));
      final String content = 'a' * (capacity * 3 + 1);
      final SummaryTestGenerator generator = SummaryTestGenerator(
        (SummaryTestStageCall call) async => 'section text',
      );

      final Summary summary = await remoteService(
        smallPolicy,
        generator,
      ).summarize(content);

      expect(summary.text, 'section text');
      expect(generator.stages, <SummaryStage>[
        SummaryStage.section,
        SummaryStage.section,
        SummaryStage.section,
        SummaryStage.section,
        SummaryStage.merge,
      ]);
      expect(generator.calls.last.inputs, hasLength(4));
    });

    test('refuses more than four chunks before any generation', () async {
      final int capacity = sectionCapacity(smallPolicy, SummaryStage.section);
      final String content = 'a' * (capacity * smallPolicy.maxChunks + 1);
      final SummaryTestGenerator generator = SummaryTestGenerator(
        (SummaryTestStageCall call) async => 'x',
      );

      await expectLater(
        remoteService(smallPolicy, generator).summarize(content),
        failsWith(SummaryApiErrorCode.pipelineTooLarge),
      );
      expect(generator.calls, isEmpty);
    });

    test('refuses content that cannot fit a single rune', () async {
      final SummaryRequestPolicy tiny = await policyWith((
        Map<String, dynamic> data,
      ) {
        data['maxInputEstimate'] = 300;
      });
      final SummaryTestGenerator generator = SummaryTestGenerator(
        (SummaryTestStageCall call) async => 'x',
      );

      await expectLater(
        remoteService(tiny, generator).summarize('hello'),
        failsWith(SummaryApiErrorCode.pipelineTooLarge),
      );
      expect(generator.calls, isEmpty);
    });
  });

  group('input normalization', () {
    test('rejects blank input without a call', () async {
      for (final String content in <String>[
        '',
        '   ',
        '\n\t ',
        '\u00A0\uFEFF',
        '\u2028',
      ]) {
        final SummaryTestGenerator generator = SummaryTestGenerator(
          (SummaryTestStageCall call) async => 'x',
        );
        await expectLater(
          remoteService(policy, generator).summarize(content),
          failsWith(SummaryApiErrorCode.invalidInput),
        );
        expect(generator.calls, isEmpty);
      }
    });

    test('keeps U+0085 content that Dart trim would remove', () async {
      const String content = '\u0085note\u0085';
      final SummaryTestGenerator generator = SummaryTestGenerator(
        (SummaryTestStageCall call) async => 'summary',
      );

      final Summary summary = await remoteService(
        policy,
        generator,
      ).summarize(content);

      expect(summary.text, 'summary');
      expect(generator.calls.single.inputs, <String>[content]);
    });
  });

  group('stage failures', () {
    test(
      'stops on the first section failure without a partial summary',
      () async {
        final int capacity = sectionCapacity(smallPolicy, SummaryStage.direct);
        final String content = 'a' * (capacity + 1);
        final SummaryTestGenerator generator = SummaryTestGenerator((
          SummaryTestStageCall call,
        ) async {
          throw const SummaryApiFailure(
            code: SummaryApiErrorCode.providerUnavailable,
          );
        });

        await expectLater(
          remoteService(smallPolicy, generator).summarize(content),
          failsWith(SummaryApiErrorCode.providerUnavailable),
        );
        expect(generator.stages, <SummaryStage>[SummaryStage.section]);
      },
    );

    test('rejects a blank section output before the merge', () async {
      final int capacity = sectionCapacity(smallPolicy, SummaryStage.direct);
      final String content = 'a' * (capacity + 1);
      final SummaryTestGenerator generator = SummaryTestGenerator(
        (SummaryTestStageCall call) async =>
            call.stage == SummaryStage.section ? '   ' : 'merged',
      );

      await expectLater(
        remoteService(smallPolicy, generator).summarize(content),
        failsWith(SummaryApiErrorCode.invalidOutput),
      );
      expect(generator.stages, <SummaryStage>[SummaryStage.section]);
    });

    test('rejects a blank direct or merge output', () async {
      final SummaryTestGenerator direct = SummaryTestGenerator(
        (SummaryTestStageCall call) async => ' \n ',
      );
      await expectLater(
        remoteService(policy, direct).summarize('short note'),
        failsWith(SummaryApiErrorCode.invalidOutput),
      );
      expect(direct.stages, <SummaryStage>[SummaryStage.direct]);

      final int capacity = sectionCapacity(smallPolicy, SummaryStage.direct);
      final SummaryTestGenerator merge = SummaryTestGenerator(
        (SummaryTestStageCall call) async =>
            call.stage == SummaryStage.merge ? '' : 'section text',
      );
      await expectLater(
        remoteService(smallPolicy, merge).summarize('a' * (capacity + 1)),
        failsWith(SummaryApiErrorCode.invalidOutput),
      );
      expect(merge.stages, <SummaryStage>[
        SummaryStage.section,
        SummaryStage.section,
        SummaryStage.merge,
      ]);
    });

    test(
      'fails before the merge call when the sections cannot fit it',
      () async {
        final int capacity = sectionCapacity(smallPolicy, SummaryStage.direct);
        final String oversized = 'b' * smallPolicy.maxInputEstimate;
        final SummaryTestGenerator generator = SummaryTestGenerator(
          (SummaryTestStageCall call) async =>
              call.stage == SummaryStage.section ? oversized : 'merged',
        );

        await expectLater(
          remoteService(smallPolicy, generator).summarize('a' * (capacity + 1)),
          failsWith(SummaryApiErrorCode.pipelineTooLarge),
        );
        expect(generator.stages, <SummaryStage>[
          SummaryStage.section,
          SummaryStage.section,
        ]);
      },
    );
  });
}
