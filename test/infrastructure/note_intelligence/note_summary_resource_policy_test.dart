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

  group('shared summary chunk boundaries', () {
    test('keeps the narrow whitespace and newline set', () {
      for (final int unit in <int>[9, 10, 13, 32]) {
        expect(isSummaryChunkWhitespace(unit), isTrue);
      }
      for (final int unit in <int>[0x85, 0xA0, 0x2028, 0x2029, 0xFEFF]) {
        expect(isSummaryChunkWhitespace(unit), isFalse);
      }
      expect(isSummaryChunkNewline(10), isTrue);
      expect(isSummaryChunkNewline(13), isTrue);
      expect(isSummaryChunkNewline(9), isFalse);
      expect(isSummaryChunkNewline(0x2028), isFalse);
    });

    test('prefers the highest newline over any whitespace', () {
      const String text = 'alpha beta\ngamma';

      expect(
        chooseSummaryChunkBoundary(start: 0, end: 12, unitAt: text.codeUnitAt),
        11,
      );
    });

    test('falls back to the highest whitespace without a newline', () {
      const String text = 'alpha beta gamma';

      expect(
        chooseSummaryChunkBoundary(start: 0, end: 11, unitAt: text.codeUnitAt),
        11,
      );
      expect(
        chooseSummaryChunkBoundary(start: 0, end: 10, unitAt: text.codeUnitAt),
        6,
      );
    });

    test('returns the proposed end when no boundary is in range', () {
      const String text = 'abcdefghij';

      expect(
        chooseSummaryChunkBoundary(start: 0, end: 4, unitAt: text.codeUnitAt),
        4,
      );
      expect(
        chooseSummaryChunkBoundary(start: 3, end: 6, unitAt: text.codeUnitAt),
        6,
      );
    });

    test('picks the same boundary from runes and from code units', () {
      const String text = 'a😀 b';
      final List<int> runes = text.runes.toList(growable: false);

      final int byRune = chooseSummaryChunkBoundary(
        start: 0,
        end: 3,
        unitAt: (int index) => runes[index],
      );
      final int byCodeUnit = chooseSummaryChunkBoundary(
        start: 0,
        end: 4,
        unitAt: text.codeUnitAt,
      );

      expect(byRune, 3);
      expect(byCodeUnit, 4);
      expect(
        text.substring(0, byCodeUnit),
        String.fromCharCodes(runes.sublist(0, byRune)),
      );
    });

    test('local split still normalizes boundary whitespace away', () {
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
      for (final String chunk in chunks) {
        expect(chunk, chunk.trim());
      }
    });
  });
}
