/// Conservative resource policy for local note summarization (M4.6).
///
/// The native tokenizer is intentionally hidden behind local_llm_bridge, so
/// this policy uses a configurable character-per-token estimate and reserves
/// room for instructions plus generated output. It never silently truncates a
/// note: long content is split into ordered, non-empty chunks.
library;

/// A bounded failure raised when a note cannot be processed within policy.
final class NoteSummaryResourceException implements Exception {
  /// Creates a safe resource-policy failure.
  const NoteSummaryResourceException(this.message);

  /// Safe, user-presentable explanation without prompt/path details.
  final String message;

  @override
  String toString() => 'NoteSummaryResourceException: $message';
}

/// Computes safe input budgets and deterministic note chunks for local AI.
final class NoteSummaryResourcePolicy {
  /// Creates a validated resource policy.
  factory NoteSummaryResourcePolicy({
    int contextSize = 4096,
    int maxOutputTokens = 128,
    int promptReserveTokens = 256,
    int estimatedCharactersPerToken = 2,
    int maxChunkCount = 32,
    int? chunkOutputTokens,
  }) {
    if (contextSize <= 0) {
      throw ArgumentError.value(
        contextSize,
        'contextSize',
        'must be greater than zero',
      );
    }
    if (maxOutputTokens <= 0) {
      throw ArgumentError.value(
        maxOutputTokens,
        'maxOutputTokens',
        'must be greater than zero',
      );
    }
    if (promptReserveTokens < 0) {
      throw ArgumentError.value(
        promptReserveTokens,
        'promptReserveTokens',
        'must not be negative',
      );
    }
    if (estimatedCharactersPerToken <= 0) {
      throw ArgumentError.value(
        estimatedCharactersPerToken,
        'estimatedCharactersPerToken',
        'must be greater than zero',
      );
    }
    if (maxChunkCount <= 0) {
      throw ArgumentError.value(
        maxChunkCount,
        'maxChunkCount',
        'must be greater than zero',
      );
    }

    final int availableInputTokens =
        contextSize - maxOutputTokens - promptReserveTokens;
    if (availableInputTokens <= 0) {
      throw ArgumentError.value(
        contextSize,
        'contextSize',
        'must leave room for output and prompt reserve',
      );
    }

    final int resolvedChunkOutputTokens =
        chunkOutputTokens ?? (maxOutputTokens < 128 ? maxOutputTokens : 128);
    if (resolvedChunkOutputTokens <= 0 ||
        resolvedChunkOutputTokens > maxOutputTokens) {
      throw ArgumentError.value(
        chunkOutputTokens,
        'chunkOutputTokens',
        'must be between 1 and maxOutputTokens',
      );
    }

    return NoteSummaryResourcePolicy._(
      contextSize: contextSize,
      maxOutputTokens: maxOutputTokens,
      promptReserveTokens: promptReserveTokens,
      estimatedCharactersPerToken: estimatedCharactersPerToken,
      maxChunkCount: maxChunkCount,
      chunkOutputTokens: resolvedChunkOutputTokens,
      maxInputTokens: availableInputTokens,
    );
  }

  const NoteSummaryResourcePolicy._({
    required this.contextSize,
    required this.maxOutputTokens,
    required this.promptReserveTokens,
    required this.estimatedCharactersPerToken,
    required this.maxChunkCount,
    required this.chunkOutputTokens,
    required this.maxInputTokens,
  });

  /// Native context window in tokens.
  final int contextSize;

  /// Maximum output tokens for the final summary.
  final int maxOutputTokens;

  /// Tokens reserved for the summary instruction and structural wrappers.
  final int promptReserveTokens;

  /// Conservative character-per-token estimate.
  final int estimatedCharactersPerToken;

  /// Maximum number of chunks in one note.
  final int maxChunkCount;

  /// Smaller output budget used for section summaries.
  final int chunkOutputTokens;

  /// Input token budget after reserving prompt and output space.
  final int maxInputTokens;

  /// Safe content character budget for one model request.
  int get maxInputCharacters => maxInputTokens * estimatedCharactersPerToken;

  /// Whether [content] can be sent as one direct request.
  bool isDirect(String content) {
    return content.trim().runes.length <= maxInputCharacters;
  }

  /// Splits [content] into ordered chunks without silently dropping content.
  ///
  /// Whitespace at chunk boundaries is normalized away; all non-whitespace
  /// runes remain in order. A long token with no boundary is hard-split.
  List<String> split(String content) {
    final String note = content.trim();
    if (note.isEmpty) {
      return const <String>[];
    }
    final List<int> runes = note.runes.toList(growable: false);
    if (runes.length <= maxInputCharacters) {
      return <String>[note];
    }

    final List<String> chunks = <String>[];
    var start = 0;
    while (start < runes.length) {
      final int proposedEnd = _min(start + maxInputCharacters, runes.length);
      int end = proposedEnd;
      if (proposedEnd < runes.length) {
        int? lastWhitespace;
        for (var index = proposedEnd; index > start; index--) {
          final int rune = runes[index - 1];
          if (rune == 10 || rune == 13) {
            end = index;
            break;
          }
          if (lastWhitespace == null && _isWhitespace(rune)) {
            lastWhitespace = index;
          }
        }
        if (end == proposedEnd && lastWhitespace != null) {
          end = lastWhitespace;
        }
      }

      final String chunk = String.fromCharCodes(runes.sublist(start, end))
          .trim();
      if (chunk.isNotEmpty) {
        chunks.add(chunk);
        if (chunks.length > maxChunkCount) {
          throw NoteSummaryResourceException(
            'This note is too long to summarize on this device.',
          );
        }
      }
      start = end;
      while (start < runes.length && _isWhitespace(runes[start])) {
        start++;
      }
    }
    return List<String>.unmodifiable(chunks);
  }

  static int _min(int a, int b) => a < b ? a : b;

  static bool _isWhitespace(int rune) {
    return rune == 9 || rune == 10 || rune == 13 || rune == 32;
  }
}
