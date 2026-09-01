// Unit tests for LocalSummarizationService using a fake worker client — no
// model, worker isolate, or FFI involved.

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/domain/note_intelligence/summary.dart';
import 'package:note_ai_app/infrastructure/ai/llm_worker_contract.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/local_summarization_service.dart';

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
