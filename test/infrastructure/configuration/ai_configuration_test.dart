import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/infrastructure/configuration/ai_configuration.dart';

void main() {
  group('AiConfiguration defaults', () {
    test('preserves the established runtime defaults', () {
      final AiConfiguration configuration = AiConfiguration();

      expect(configuration.modelPathOverride, isNull);
      expect(configuration.downloadTimeout, const Duration(minutes: 15));
      expect(configuration.maxRedirects, 5);
      expect(configuration.workerThreads, 0);
      expect(configuration.defaultContextSize, 2048);
      expect(configuration.defaultMaxOutputTokens, 128);
    });

    test('normalizes an explicitly supplied blank model path', () {
      final AiConfiguration configuration = AiConfiguration(
        modelPathOverride: ' \t\n ',
      );

      expect(configuration.modelPathOverride, isNull);
    });

    test('normalizes the compile-time environment model path', () {
      const String rawModelPath = String.fromEnvironment(
        'LOCAL_LLM_MODEL_PATH',
      );
      final AiConfiguration configuration = AiConfiguration.fromEnvironment();
      final String normalizedPath = rawModelPath.trim();

      expect(
        configuration.modelPathOverride,
        normalizedPath.isEmpty ? isNull : normalizedPath,
      );
    });
  });

  group('AiConfiguration validation', () {
    test('rejects a non-positive download timeout', () {
      expect(
        () => AiConfiguration(downloadTimeout: Duration.zero),
        _invalidArgumentNamed('downloadTimeout'),
      );
      expect(
        () =>
            AiConfiguration(downloadTimeout: const Duration(microseconds: -1)),
        _invalidArgumentNamed('downloadTimeout'),
      );
    });

    test('rejects a negative redirect count', () {
      expect(
        () => AiConfiguration(maxRedirects: -1),
        _invalidArgumentNamed('maxRedirects'),
      );
    });

    test('rejects a negative worker-thread count', () {
      expect(
        () => AiConfiguration(workerThreads: -1),
        _invalidArgumentNamed('workerThreads'),
      );
    });

    test('enforces the native context-size range', () {
      expect(
        () => AiConfiguration(defaultContextSize: 1),
        _invalidArgumentNamed('defaultContextSize'),
      );
      expect(
        () => AiConfiguration(defaultContextSize: 4097),
        _invalidArgumentNamed('defaultContextSize'),
      );
    });

    test('enforces the native output-token range', () {
      expect(
        () => AiConfiguration(defaultMaxOutputTokens: 0),
        _invalidArgumentNamed('defaultMaxOutputTokens'),
      );
      expect(
        () => AiConfiguration(defaultMaxOutputTokens: 513),
        _invalidArgumentNamed('defaultMaxOutputTokens'),
      );
    });
  });
}

Matcher _invalidArgumentNamed(String name) {
  return throwsA(
    isA<ArgumentError>().having(
      (ArgumentError error) => error.name,
      'name',
      name,
    ),
  );
}
