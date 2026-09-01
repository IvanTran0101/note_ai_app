// End-to-end smoke of the real worker isolate + local_llm_bridge + a real
// GGUF model. Skipped unless the model path is provided at test time:
//
//   flutter test --dart-define=LOCAL_LLM_MODEL_PATH=/abs/path/model.gguf \
//     test/infrastructure/ai/local_model_smoke_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/domain/note_intelligence/summary.dart';
import 'package:note_ai_app/infrastructure/ai/llm_worker_client.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/local_summarization_service.dart';

const String _modelPathEnv = String.fromEnvironment('LOCAL_LLM_MODEL_PATH');

void main() {
  test(
    'worker isolate loads the GGUF model and summarizes real content',
    () async {
      final LlmWorkerClient client = await startLlmWorkerClient(
        modelPath: _modelPathEnv,
      );
      addTearDown(client.dispose);
      final LocalSummarizationService service = LocalSummarizationService(
        workerClient: client,
      );

      final Summary vietnameseSummary = await service.summarize(
        'Hôm nay tôi đã hoàn thành phần thiết kế giao diện và sẽ kiểm thử '
        'ứng dụng vào ngày mai.',
      );
      final Summary englishSummary = await service.summarize(
        'The team completed the interface design and will test the application '
        'tomorrow.',
      );

      expect(vietnameseSummary.text, isNotEmpty);
      expect(englishSummary.text, isNotEmpty);
    },
    skip: _modelPathEnv.trim().isEmpty
        ? 'Set --dart-define=LOCAL_LLM_MODEL_PATH to run the real-model smoke.'
        : false,
  );
}
