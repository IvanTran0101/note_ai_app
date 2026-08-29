import '../../domain/note_intelligence/i_note_summarization_service.dart';
import '../../domain/note_intelligence/summary.dart';

import 'llm_worker_contract.dart';

/// Concise-summary system instruction sent to the local worker. The native
/// chat template wraps it as the model's system turn.
const String _summarySystemInstruction =
    'Summarize the following note concisely. Return only the summary text.';

/// [INoteSummarizationService] backed by the local LLM worker isolate.
///
/// The [LlmWorkerClient] is injected so unit tests can substitute a fake
/// without loading a model. On the Web the client throws [UnsupportedError]
/// (never a fabricated summary).
final class LocalSummarizationService implements INoteSummarizationService {
  LocalSummarizationService({required this.workerClient});

  final LlmWorkerClient workerClient;

  @override
  Future<Summary> summarize(String content) async {
    final String note = content.trim();
    if (note.isEmpty) {
      throw ArgumentError.value(content, 'content', 'must not be blank');
    }

    final String text = await workerClient.generateChat(
      systemPrompt: _summarySystemInstruction,
      userPrompt: note,
      maxTokens: 128,
    );

    final String summary = text.trim();
    if (summary.isEmpty) {
      throw StateError(
        'summarization returned an empty result: the local model produced '
        'no output',
      );
    }
    return Summary(summary);
  }
}
