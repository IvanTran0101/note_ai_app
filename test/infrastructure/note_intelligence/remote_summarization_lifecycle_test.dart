import 'summary_policy_test_support.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/remote_summarization_service.dart';
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

  group('consent', () {
    test('sends nothing when consent is refused at the start', () async {
      final SummaryTestConsent consent = SummaryTestConsent(
        (int check) => false,
      );
      final SummaryTestGenerator generator = SummaryTestGenerator(
        (SummaryTestStageCall call) async => 'x',
      );

      await expectLater(
        remoteService(policy, generator, consent: consent).summarize('note'),
        failsWith(SummaryApiErrorCode.consentRequired),
      );
      expect(generator.calls, isEmpty);
      expect(consent.checks, 1);
    });

    test('rechecks consent before every stage', () async {
      final int capacity = sectionCapacity(smallPolicy, SummaryStage.direct);
      final SummaryTestConsent consent = SummaryTestConsent(
        (int check) => check < 2,
      );
      final SummaryTestGenerator generator = SummaryTestGenerator(
        (SummaryTestStageCall call) async => 'x',
      );

      await expectLater(
        remoteService(
          smallPolicy,
          generator,
          consent: consent,
        ).summarize('a' * (capacity + 1)),
        failsWith(SummaryApiErrorCode.consentRequired),
      );
      expect(generator.calls, isEmpty);
      expect(consent.checks, 2);
    });

    test('rechecks consent before accepting a direct result', () async {
      final SummaryTestConsent consent = SummaryTestConsent(
        (int check) => check <= 2,
      );
      final SummaryTestGenerator generator = SummaryTestGenerator(
        (SummaryTestStageCall call) async => 'direct',
      );

      await expectLater(
        remoteService(policy, generator, consent: consent).summarize('note'),
        failsWith(SummaryApiErrorCode.consentRequired),
      );
      expect(generator.stages, <SummaryStage>[SummaryStage.direct]);
      expect(consent.checks, 3);
    });

    test('rechecks consent before accepting a merged result', () async {
      final int capacity = sectionCapacity(smallPolicy, SummaryStage.direct);
      final SummaryTestConsent consent = SummaryTestConsent(
        (int check) => check <= 4,
      );
      final SummaryTestGenerator generator = SummaryTestGenerator(
        (SummaryTestStageCall call) async => 'text',
      );

      await expectLater(
        remoteService(
          smallPolicy,
          generator,
          consent: consent,
        ).summarize('a' * (capacity + 1)),
        failsWith(SummaryApiErrorCode.consentRequired),
      );
      expect(generator.stages, <SummaryStage>[
        SummaryStage.section,
        SummaryStage.section,
        SummaryStage.merge,
      ]);
      expect(consent.checks, 5);
    });
  });

  group('deadline', () {
    test('a hanging generator fails at the pipeline deadline', () async {
      final Completer<String> gate = Completer<String>();
      final SummaryTestGenerator generator = SummaryTestGenerator(
        (SummaryTestStageCall call) => gate.future,
      );
      await expectLater(
        remoteService(
          policy,
          generator,
          timeout: const Duration(milliseconds: 40),
        ).summarize('content').timeout(const Duration(seconds: 1)),
        failsWith(SummaryApiErrorCode.timeout),
      );
      gate.complete('late');
      await Future<void>.delayed(Duration.zero);
      expect(generator.calls, hasLength(1));
    });

    test('passes one complete deadline to every stage', () async {
      final int capacity = sectionCapacity(smallPolicy, SummaryStage.direct);
      final SummaryTestGenerator generator = SummaryTestGenerator(
        (SummaryTestStageCall call) async => 'text',
      );
      final DateTime before = DateTime.now();

      await remoteService(
        smallPolicy,
        generator,
        timeout: const Duration(seconds: 30),
      ).summarize('a' * (capacity + 1));
      final DateTime after = DateTime.now();

      final Set<DateTime> deadlines = <DateTime>{
        for (final SummaryTestStageCall call in generator.calls) call.deadline!,
      };
      expect(deadlines, hasLength(1));
      final DateTime deadline = deadlines.single;
      expect(
        deadline.isBefore(before.add(const Duration(seconds: 30))),
        isFalse,
      );
      expect(deadline.isAfter(after.add(const Duration(seconds: 30))), isFalse);
    });

    test('does not start another stage after the deadline', () async {
      final int capacity = sectionCapacity(smallPolicy, SummaryStage.direct);
      final SummaryTestGenerator generator = SummaryTestGenerator((
        SummaryTestStageCall call,
      ) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return 'late section';
      });

      await expectLater(
        remoteService(
          smallPolicy,
          generator,
          timeout: const Duration(milliseconds: 100),
        ).summarize('a' * (capacity + 1)),
        failsWith(SummaryApiErrorCode.timeout),
      );
      expect(generator.stages, <SummaryStage>[SummaryStage.section]);
    });

    test('bounds the pipeline timeout', () {
      final SummaryTestGenerator generator = SummaryTestGenerator(
        (SummaryTestStageCall call) async => 'x',
      );
      final RemoteSummarizationService service = remoteService(
        policy,
        generator,
      );
      expect(service.pipelineTimeout, const Duration(seconds: 150));
      expect(
        () => remoteService(policy, generator, timeout: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => remoteService(
          policy,
          generator,
          timeout: const Duration(seconds: 151),
        ),
        throwsArgumentError,
      );
    });
  });
}
