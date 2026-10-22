import '../../domain/note_intelligence/i_note_summarization_service.dart';
import '../../domain/note_intelligence/summary.dart';

import '../ai/llm_worker_contract.dart';
import '../../evidence/trace.dart';
import 'note_summary_resource_policy.dart';

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

String _buildSectionSummaryPrompt(String note) {
  return '${_summaryUserInstruction.trim()}\n\n'
      'This is one section of a longer note. Summarize only this section '
      'with the important factual points so another step can merge it.\n\n'
      '<note>\n$note\n</note>';
}

String _buildMergePrompt(List<String> sectionSummaries) {
  final String sections = sectionSummaries
      .asMap()
      .entries
      .map(
        (MapEntry<int, String> entry) =>
            '<section index="${entry.key + 1}">\n${entry.value}\n</section>',
      )
      .join('\n');
  return '${_summaryUserInstruction.trim()}\n\n'
      'Merge the following section summaries into one concise, coherent '
      'summary of the original note. Preserve important facts and avoid '
      'introducing information that is not present in the sections.\n\n'
      '<section_summaries>\n$sections\n</section_summaries>';
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
    int contextSize = 2048,
    NoteSummaryResourcePolicy? resourcePolicy,
  }) : resourcePolicy =
           resourcePolicy ??
           NoteSummaryResourcePolicy(
             contextSize: contextSize,
             maxOutputTokens: maxTokens,
           ) {
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

  /// Context-aware policy used to choose direct or chunked summarization.
  final NoteSummaryResourcePolicy resourcePolicy;
  int _evidenceCalls = 0;
  int _evidenceMerges = 0;

  @override
  Future<Summary> summarize(String content) async {
    final Stopwatch watch = Stopwatch()..start();
    _evidenceCalls = 0;
    _evidenceMerges = 0;
    evidencePhase = 'summarization_setup';
    evidenceTrace('summary_start', <String, Object?>{
      'input_characters': content.runes.length,
      'context': resourcePolicy.contextSize,
      'max_output_tokens': maxTokens,
    });
    String status = 'ok';
    try {
      final String note = content.trim();
      if (note.isEmpty) {
        throw ArgumentError.value(content, 'content', 'must not be blank');
      }

      final List<String> chunks = resourcePolicy.split(note);
      evidenceTrace('chunks', <String, Object?>{'count': chunks.length});
      if (chunks.length == 1) {
        return Summary(
          await _generate(
            _buildSummaryUserPrompt(chunks.single),
            maxTokens: maxTokens,
          ),
        );
      }

      final List<String> sectionSummaries = <String>[];
      for (final String chunk in chunks) {
        sectionSummaries.add(
          await _generate(
            _buildSectionSummaryPrompt(chunk),
            maxTokens: resourcePolicy.chunkOutputTokens,
          ),
        );
      }
      return Summary(await _mergeSummaries(sectionSummaries));
    } on Object catch (error) {
      status = 'error';
      evidenceTrace('summary_error', <String, Object?>{
        'error': error.toString(),
      });
      rethrow;
    } finally {
      evidenceLastSummaryUs = watch.elapsedMicroseconds;
      evidenceTrace('summary_end', <String, Object?>{
        'elapsed_us': watch.elapsedMicroseconds,
        'status': status,
        'generation_calls': _evidenceCalls,
        'merge_rounds': _evidenceMerges,
      });
      evidencePhase = 'idle';
    }
  }

  Future<String> _generate(String prompt, {required int maxTokens}) async {
    final int call = ++_evidenceCalls;
    final Stopwatch watch = Stopwatch()..start();
    evidencePhase = 'generation';
    evidenceTrace('generate_start', <String, Object?>{
      'call': call,
      'max_tokens': maxTokens,
    });
    evidenceText('prompt', prompt, call: call);
    try {
      // Gemma 3 IT expects system-level instructions in the initial user turn.
      // The native formatter omits the system role for an empty value.
      final String text = await workerClient.generateChat(
        systemPrompt: '',
        userPrompt: prompt,
        maxTokens: maxTokens,
      );
      evidenceText('native_output', text, call: call);
      final String summary = text.trim();
      if (summary.isEmpty) {
        throw StateError(
          'summarization returned an empty result: the local model produced '
          'no output',
        );
      }
      return summary;
    } on Object catch (error) {
      evidenceTrace('generate_error', <String, Object?>{
        'call': call,
        'error': error.toString(),
      });
      rethrow;
    } finally {
      evidenceTrace('generate_end', <String, Object?>{
        'call': call,
        'elapsed_us': watch.elapsedMicroseconds,
      });
      evidencePhase = 'between_calls';
    }
  }

  Future<String> _mergeSummaries(List<String> summaries) async {
    if (summaries.length == 1) {
      return summaries.single;
    }

    final List<List<String>> groups = _groupSummaries(summaries);
    evidenceTrace('merge_round', <String, Object?>{
      'round': ++_evidenceMerges,
      'input_summaries': summaries.length,
      'groups': groups.length,
    });
    if (groups.length == 1) {
      return _generate(_buildMergePrompt(groups.single), maxTokens: maxTokens);
    }

    final List<String> reduced = <String>[];
    for (final List<String> group in groups) {
      reduced.add(
        await _generate(_buildMergePrompt(group), maxTokens: maxTokens),
      );
    }
    return _mergeSummaries(reduced);
  }

  List<List<String>> _groupSummaries(List<String> summaries) {
    final List<List<String>> groups = <List<String>>[];
    List<String> current = <String>[];
    var currentCharacters = 0;
    for (final String summary in summaries) {
      final int separatorCharacters = current.isEmpty ? 0 : 1;
      final int candidateCharacters =
          currentCharacters + separatorCharacters + summary.runes.length;
      if (current.isNotEmpty &&
          candidateCharacters > resourcePolicy.maxInputCharacters) {
        groups.add(List<String>.unmodifiable(current));
        current = <String>[];
        currentCharacters = 0;
      }

      if (summary.runes.length > resourcePolicy.maxInputCharacters) {
        throw const NoteSummaryResourceException(
          'A generated section summary is too large to merge on this device.',
        );
      }
      current.add(summary);
      currentCharacters += (current.length == 1 ? 0 : 1) + summary.runes.length;
    }
    if (current.isNotEmpty) {
      groups.add(List<String>.unmodifiable(current));
    }
    return groups;
  }
}
