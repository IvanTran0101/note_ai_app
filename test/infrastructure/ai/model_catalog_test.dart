import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/infrastructure/ai/model_catalog.dart';

void main() {
  group('production model catalog', () {
    test('contains only the verified Gemma 3 1B artifact', () {
      const ModelCatalog catalog = ModelCatalog();

      expect(catalog.models, hasLength(1));
      expect(catalog.models.single, gemma3_1bItQ4KmModel);
      expect(gemma3_1bItQ4KmModel.id, 'gemma-3-1b-it');
      expect(gemma3_1bItQ4KmModel.fileName, 'gemma-3-1b-it-Q4_K_M.gguf');
      expect(
        gemma3_1bItQ4KmModel.downloadUrl,
        contains(kGemma3_1bItQ4KmRevision),
      );
      expect(gemma3_1bItQ4KmModel.downloadUrl, startsWith('https://'));
      expect(gemma3_1bItQ4KmModel.fileSizeBytes, kGemma3_1bItQ4KmFileSizeBytes);
      expect(gemma3_1bItQ4KmModel.sha256, kGemma3_1bItQ4KmSha256);
    });

    test('skips resource gates for the midterm', () {
      expect(gemma3_1bItQ4KmModel.estimatedPeakMemoryBytes, isNull);
      expect(gemma3_1bItQ4KmModel.requiredFreeStorageBytes, isNull);
      expect(
        gemma3_1bItQ4KmModel.supportedPlatforms,
        containsAll(<String>['ios', 'android']),
      );
      expect(
        gemma3_1bItQ4KmModel.supportedAbis,
        containsAll(<String>['arm64', 'arm64-v8a', 'x86_64']),
      );
    });

    test('shared production instance preserves catalog order', () {
      expect(productionModelCatalog.models, [gemma3_1bItQ4KmModel]);
    });
  });
}
