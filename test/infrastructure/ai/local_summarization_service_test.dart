// Unit tests for LocalSummarizationService using a fake worker client — no
// model, worker isolate, or FFI involved.

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/domain/note_intelligence/summary.dart';
import 'package:note_ai_app/infrastructure/ai/llm_worker_contract.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/local_summarization_service.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/note_summary_resource_policy.dart';

final class _FakeLlmWorkerClient implements LlmWorkerClient {
  _FakeLlmWorkerClient({this.result, this.error, this.emptyResult = false});

  String? result;
  Object? error;
  bool emptyResult;

  final List<String> systemPrompts = <String>[];
  final List<String> userPrompts = <String>[];
  final List<int> maxTokens = <int>[];
  int disposeCalls = 0;

  @override
  Future<String> generateChat({
    required String systemPrompt,
    required String userPrompt,
    int maxTokens = 128,
  }) async {
    systemPrompts.add(systemPrompt);
    userPrompts.add(userPrompt);
    this.maxTokens.add(maxTokens);
    if (error != null) {
      throw error!;
    }
    if (emptyResult) {
      return '';
    }
    return result ?? 'default fake summary';
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

void main() {
  group('LocalSummarizationService', () {
    test('returns Summary(text) with the worker output', () async {
      final _FakeLlmWorkerClient fake = _FakeLlmWorkerClient(
        result: '  The note summary.  ',
      );
      final LocalSummarizationService service = LocalSummarizationService(
        workerClient: fake,
      );

      final Summary summary = await service.summarize('Note body');

      expect(summary, const Summary('The note summary.'));
      expect(fake.systemPrompts.single, isEmpty);
      expect(
        fake.userPrompts.single,
        allOf(
          contains('primarily Vietnamese'),
          contains('primarily English'),
          contains('Do not translate'),
          contains('<note>\nNote body\n</note>'),
        ),
      );
      expect(fake.maxTokens.single, 128);
    });

    test('uses the injected output token budget', () async {
      final _FakeLlmWorkerClient fake = _FakeLlmWorkerClient(
        result: 'The note summary.',
      );
      final LocalSummarizationService service = LocalSummarizationService(
        workerClient: fake,
        maxTokens: 64,
      );

      await service.summarize('Note body');

      expect(fake.maxTokens.single, 64);
    });

    test('uses one direct request for a short note', () async {
      final _FakeLlmWorkerClient fake = _FakeLlmWorkerClient(
        result: 'Short summary.',
      );
      final LocalSummarizationService service = LocalSummarizationService(
        workerClient: fake,
        maxTokens: 32,
        resourcePolicy: NoteSummaryResourcePolicy(
          contextSize: 1000,
          maxOutputTokens: 32,
          promptReserveTokens: 128,
          estimatedCharactersPerToken: 2,
        ),
      );

      await service.summarize('Short note.');

      expect(fake.userPrompts, hasLength(1));
      expect(fake.userPrompts.single, contains('<note>'));
    });

    test('uses chunk-summary-merge for a long note', () async {
      final _FakeLlmWorkerClient fake = _FakeLlmWorkerClient(
        result: 'Section summary.',
      );
      final LocalSummarizationService service = LocalSummarizationService(
        workerClient: fake,
        maxTokens: 32,
        resourcePolicy: NoteSummaryResourcePolicy(
          contextSize: 1200,
          maxOutputTokens: 32,
          promptReserveTokens: 256,
          estimatedCharactersPerToken: 1,
          maxChunkCount: 8,
          chunkOutputTokens: 16,
        ),
      );
      final String longNote = List<String>.filled(500, 'important').join(' ');

      await service.summarize(longNote);

      expect(fake.userPrompts.length, greaterThan(2));
      expect(fake.userPrompts.first, contains('one section of a longer note'));
      expect(fake.userPrompts.last, contains('<section_summaries>'));
      for (final String prompt in fake.userPrompts) {
        expect(prompt, contains('Do not translate'));
        expect(prompt, contains('primarily Vietnamese'));
      }
    });

    test(
      'recursively merges section summaries when one merge is too large',
      () async {
        final _FakeLlmWorkerClient fake = _FakeLlmWorkerClient(
          result: List<String>.filled(400, 'x').join(),
        );
        final LocalSummarizationService service = LocalSummarizationService(
          workerClient: fake,
          maxTokens: 32,
          resourcePolicy: NoteSummaryResourcePolicy(
            contextSize: 1200,
            maxOutputTokens: 32,
            promptReserveTokens: 256,
            estimatedCharactersPerToken: 1,
            maxChunkCount: 8,
            chunkOutputTokens: 16,
          ),
        );
        final String longNote = List<String>.filled(500, 'important').join(' ');

        await service.summarize(longNote);

        // More calls than chunk summaries + one final merge prove that an
        // intermediate reduction happened before the final merge.
        expect(fake.userPrompts.length, greaterThan(5));
        expect(
          fake.userPrompts
              .where((String prompt) => prompt.contains('<section_summaries>'))
              .length,
          greaterThan(1),
        );
      },
    );

    test('fails with a typed resource error instead of truncating', () async {
      final _FakeLlmWorkerClient fake = _FakeLlmWorkerClient();
      final LocalSummarizationService service = LocalSummarizationService(
        workerClient: fake,
        maxTokens: 32,
        resourcePolicy: NoteSummaryResourcePolicy(
          contextSize: 200,
          maxOutputTokens: 32,
          promptReserveTokens: 64,
          estimatedCharactersPerToken: 1,
          maxChunkCount: 2,
          chunkOutputTokens: 16,
        ),
      );

      await expectLater(
        service.summarize(List<String>.filled(1000, 'word').join(' ')),
        throwsA(isA<NoteSummaryResourceException>()),
      );
      expect(fake.userPrompts, isEmpty);
    });

    test(
      'propagates the configured model context into the resource policy',
      () {
        final _FakeLlmWorkerClient fake = _FakeLlmWorkerClient();
        final LocalSummarizationService service = LocalSummarizationService(
          workerClient: fake,
          maxTokens: 64,
          contextSize: 2048,
        );

        expect(service.resourcePolicy.contextSize, 2048);
        expect(service.resourcePolicy.maxOutputTokens, 64);
      },
    );

    test('rejects an output token budget outside native limits', () {
      final _FakeLlmWorkerClient fake = _FakeLlmWorkerClient();

      expect(
        () => LocalSummarizationService(workerClient: fake, maxTokens: 0),
        throwsArgumentError,
      );
      expect(
        () => LocalSummarizationService(workerClient: fake, maxTokens: 513),
        throwsArgumentError,
      );
    });

    test('rejects blank content without calling the worker', () async {
      final _FakeLlmWorkerClient fake = _FakeLlmWorkerClient();
      final LocalSummarizationService service = LocalSummarizationService(
        workerClient: fake,
      );

      await expectLater(service.summarize('   '), throwsArgumentError);
      expect(fake.userPrompts, isEmpty);
    });

    test('rejects empty native output with a clear error', () async {
      final _FakeLlmWorkerClient fake = _FakeLlmWorkerClient(emptyResult: true);
      final LocalSummarizationService service = LocalSummarizationService(
        workerClient: fake,
      );

      await expectLater(
        service.summarize('Note body'),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('empty'),
          ),
        ),
      );
    });

    test('propagates worker errors to the caller', () async {
      final _FakeLlmWorkerClient fake = _FakeLlmWorkerClient(
        error: LlmWorkerException('native boom'),
      );
      final LocalSummarizationService service = LocalSummarizationService(
        workerClient: fake,
      );

      await expectLater(
        service.summarize('Note body'),
        throwsA(
          isA<LlmWorkerException>().having(
            (LlmWorkerException error) => error.message,
            'message',
            contains('native boom'),
          ),
        ),
      );
    });

    test(
      'propagates platform-unavailable errors without faking output',
      () async {
        final _FakeLlmWorkerClient fake = _FakeLlmWorkerClient(
          error: UnsupportedError('local inference is not available on Web'),
        );
        final LocalSummarizationService service = LocalSummarizationService(
          workerClient: fake,
        );

        await expectLater(
          service.summarize('Note body'),
          throwsA(isA<UnsupportedError>()),
        );
      },
    );
  });
}
