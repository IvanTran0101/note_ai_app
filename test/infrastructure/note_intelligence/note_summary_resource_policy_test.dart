import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/infrastructure/note_intelligence/note_summary_resource_policy.dart';

void main() {
  group('NoteSummaryResourcePolicy', () {
    test('derives a conservative input and section-output budget', () {
      final NoteSummaryResourcePolicy policy = NoteSummaryResourcePolicy();

      expect(policy.maxInputTokens, 3712);
      expect(policy.maxInputCharacters, 7424);
      expect(policy.chunkOutputTokens, 128);
    });

    test('validates resource settings', () {
      expect(
        () => NoteSummaryResourcePolicy(contextSize: 0),
        throwsArgumentError,
      );
      expect(
        () => NoteSummaryResourcePolicy(maxOutputTokens: 0),
        throwsArgumentError,
      );
      expect(
        () => NoteSummaryResourcePolicy(promptReserveTokens: -1),
        throwsArgumentError,
      );
      expect(
        () => NoteSummaryResourcePolicy(estimatedCharactersPerToken: 0),
        throwsArgumentError,
      );
      expect(
        () => NoteSummaryResourcePolicy(maxChunkCount: 0),
        throwsArgumentError,
      );
      expect(
        () => NoteSummaryResourcePolicy(
          contextSize: 100,
          maxOutputTokens: 60,
          promptReserveTokens: 50,
        ),
        throwsArgumentError,
      );
      expect(
        () => NoteSummaryResourcePolicy(
          maxOutputTokens: 64,
          chunkOutputTokens: 65,
        ),
        throwsArgumentError,
      );
    });

    test('keeps a short note as one trimmed direct chunk', () {
      final NoteSummaryResourcePolicy policy = NoteSummaryResourcePolicy(
        contextSize: 100,
        maxOutputTokens: 20,
        promptReserveTokens: 10,
        estimatedCharactersPerToken: 2,
      );

      expect(policy.isDirect('  short note  '), isTrue);
      expect(policy.split('  short note  '), <String>['short note']);
    });

    test('prefers newline and whitespace boundaries for long notes', () {
      final NoteSummaryResourcePolicy policy = NoteSummaryResourcePolicy(
        contextSize: 30,
        maxOutputTokens: 10,
        promptReserveTokens: 5,
        estimatedCharactersPerToken: 1,
      );

      final List<String> chunks = policy.split(
        'alpha one\nbeta two\ngamma three\ndelta four',
      );

      expect(chunks, isNotEmpty);
      expect(chunks.every((String chunk) => chunk.length <= 15), isTrue);
      expect(chunks.first, contains('alpha'));
      expect(chunks.join(' '), contains('delta'));
    });

    test('hard-splits an oversized token without losing characters', () {
      final NoteSummaryResourcePolicy policy = NoteSummaryResourcePolicy(
        contextSize: 24,
        maxOutputTokens: 8,
        promptReserveTokens: 4,
        estimatedCharactersPerToken: 1,
      );
      const String token = 'abcdefghijklmnopqrstuvwxyz';

      final List<String> chunks = policy.split(token);

      expect(chunks, <String>['abcdefghijkl', 'mnopqrstuvwx', 'yz']);
      expect(chunks.join(), token);
    });

    test('preserves normalized non-whitespace content', () {
      final NoteSummaryResourcePolicy policy = NoteSummaryResourcePolicy(
        contextSize: 32,
        maxOutputTokens: 8,
        promptReserveTokens: 4,
        estimatedCharactersPerToken: 1,
      );
      const String note =
          'Alpha paragraph.\n\nBeta paragraph with more words.\nGamma.';

      final String normalizedChunks = policy
          .split(note)
          .join(' ')
          .replaceAll(RegExp(r'\s+'), ' ');
      final String normalizedNote = note.replaceAll(RegExp(r'\s+'), ' ').trim();

      expect(normalizedChunks, normalizedNote);
    });

    test('rejects a note that exceeds the configured chunk count', () {
      final NoteSummaryResourcePolicy policy = NoteSummaryResourcePolicy(
        contextSize: 20,
        maxOutputTokens: 5,
        promptReserveTokens: 5,
        estimatedCharactersPerToken: 1,
        maxChunkCount: 2,
      );

      expect(
        () => policy.split('1234567890abcdefghijXYZ'),
        throwsA(isA<NoteSummaryResourceException>()),
      );
    });
  });
}
