import '../../domain/note_intelligence/i_note_summarization_service.dart';
import '../../domain/note_intelligence/summary.dart';

import '../ai/llm_worker_contract.dart';

/// Gemma-compatible instruction sent in the initial user turn.
///
/// Gemma 3 IT does not use a separate system turn reliably, so the task
/// policy and note are composed into one user prompt below.
const String _summaryUserInstruction = '''
You are a concise note summarizer.

LANGUAGE RULES:
- If the note is primarily Vietnamese, write the summary in Vietnamese.
- If the note is primarily English, write the summary in English.
- Preserve the original language of the note.
- Do not translate the note.
- Ignore the language used in these instructions.
- Ignore names, URLs, code, and isolated foreign words.
- If the note contains both Vietnamese and English, use the language of the majority of its natural-language sentences.
- Never use English only because these instructions are written in English.

OUTPUT RULES:
- Return only the summary.
- Do not mention the detected language.
- Do not add labels, prefixes, explanations, or greetings.
- Keep the summary concise.

''';

String _buildSummaryUserPrompt(String note) {
  return '${_summaryUserInstruction.trim()}\n\n<note>\n$note\n</note>';
}

/// [INoteSummarizationService] backed by the local LLM worker isolate.
///
/// The [LlmWorkerClient] is injected so unit tests can substitute a fake
/// without loading a model. On the Web the client throws [UnsupportedError]
/// (never a fabricated summary).
final class LocalSummarizationService implements INoteSummarizationService {
  LocalSummarizationService({
    required this.workerClient,
    this.maxTokens = 128,
  }) {
    if (maxTokens <= 0 || maxTokens > 512) {
      throw ArgumentError.value(
        maxTokens,
        'maxTokens',
        'must be between 1 and 512',
      );
    }
  }

  final LlmWorkerClient workerClient;

  /// Maximum number of output tokens requested from the selected model.
  final int maxTokens;

  @override
  Future<Summary> summarize(String content) async {
    final String note = content.trim();
    if (note.isEmpty) {
      throw ArgumentError.value(content, 'content', 'must not be blank');
    }

    final String text = await workerClient.generateChat(
      // Gemma 3 IT expects system-level instructions in the initial user
      // turn. The native formatter omits the system role for an empty value.
      systemPrompt: '',
      userPrompt: _buildSummaryUserPrompt(note),
      maxTokens: maxTokens,
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
