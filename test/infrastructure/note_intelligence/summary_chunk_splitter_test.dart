import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/note_intelligence/summary.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_chunk_splitter.dart';
import 'package:note_ai_app/infrastructure/note_intelligence/summary_request_policy.dart';

import 'remote_summary_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SummaryRequestPolicy smallPolicy;

  setUpAll(() async {
    smallPolicy = await policyWith((Map<String, dynamic> data) {
      data['maxInputEstimate'] = 1000;
    });
  });

  group('text preservation', () {
    test(
      'trim-only Unicode whitespace at a chunk start stays reconstructable',
      () async {
        final int capacity = sectionCapacity(smallPolicy, SummaryStage.section);
        for (final String space in <String>['\u00A0', '\u2028', '\uFEFF']) {
          final String content =
              '${'a' * (capacity - 5)} $space${'b' * capacity}';
          final SummaryTestGenerator generator = SummaryTestGenerator(
            (SummaryTestStageCall call) async => 'text',
          );
          await remoteService(smallPolicy, generator).summarize(content);
          final List<String> chunks = generator.calls
              .where((call) => call.stage == SummaryStage.section)
              .map((call) => call.inputs.single)
              .toList();
          expect(chunks, hasLength(2));
          expect(chunks.join(), content);
        }
      },
    );

    test('pair-aligned binary search fills four exact emoji chunks', () async {
      final int budget = smallPolicy.estimateInputTokens(
        SummaryStage.section,
        <String>['😀' * 71],
      );
      final SummaryRequestPolicy emojiPolicy = await policyWith((data) {
        data['maxInputEstimate'] = budget;
      });
      final String content = '😀' * (71 * 4);
      final List<String> chunks = SummaryChunkSplitter(emojiPolicy)
          .split(content);
      expect(chunks, hasLength(4));
      expect(chunks.every((chunk) => chunk == '😀' * 71), isTrue);
      expect(chunks.join(), content);
      expectNoSplitPairs(chunks, content);
    });

    test(
      'prefers newline boundaries and keeps whitespace for reconstruction',
      () {
        final int capacity = sectionCapacity(smallPolicy, SummaryStage.section);
        final String content =
            '${'x' * capacity}\n${'y' * capacity}\n${'z' * capacity}';

        final List<String> chunks = SummaryChunkSplitter(smallPolicy)
            .split(content);

        expect(chunks, hasLength(3));
        expect(chunks[0], endsWith('\n'));
        expect(chunks[1], endsWith('\n'));
        expect(chunks[2], 'z' * capacity);
        expect(chunks.join(), content);
        expect(
          chunks.every(
            (String chunk) =>
                SummaryRequestPolicy.normalizeInput(chunk).isNotEmpty,
          ),
          isTrue,
        );
      },
    );

    test('preserves unicode, combining marks, and lone surrogates', () async {
      final int capacity = sectionCapacity(smallPolicy, SummaryStage.section);
      // Emoji pair, combining acute accent, Vietnamese, tab, U+0085, NBSP,
      // ASCII, newline, and both halves of a broken pair kept lone by the 'x'.
      const String segment = '😀e\u0301Việt\t\u0085\u00A0x\n\uD83Dx\uDE00';
      final StringBuffer buffer = StringBuffer();
      while (buffer.length < capacity) {
        buffer.write(segment);
      }
      final String content = buffer.toString();
      final String normalized = SummaryRequestPolicy.normalizeInput(content);
      final SummaryTestGenerator generator = SummaryTestGenerator(
        (SummaryTestStageCall call) async => 'text',
      );

      final Summary summary = await remoteService(
        smallPolicy,
        generator,
      ).summarize(content);

      expect(summary.text, 'text');
      final List<String> chunks = <String>[
        for (final SummaryTestStageCall call in generator.calls)
          if (call.stage == SummaryStage.section) call.inputs.single,
      ];
      expect(chunks.length, inInclusiveRange(2, smallPolicy.maxChunks));
      expect(chunks.join(), normalized);
      expect(generator.calls.last.inputs, isNotEmpty);
      for (final String chunk in chunks) {
        expect(SummaryRequestPolicy.normalizeInput(chunk), isNotEmpty);
      }
      expectNoSplitPairs(chunks, normalized);
    });
  });
}
