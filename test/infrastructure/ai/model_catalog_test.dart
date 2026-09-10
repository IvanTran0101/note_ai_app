import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/infrastructure/ai/model_catalog.dart';
import 'package:note_ai_app/infrastructure/ai/model_selection.dart';
import 'package:note_ai_app/infrastructure/device/hardware_detection.dart';

void main() {
  group('production model catalog', () {
    test('contains the verified 1B fallback and Gemma 4 E2B candidate', () {
      const ModelCatalog catalog = ModelCatalog();

      expect(catalog.models, [gemma3_1bItQ4KmModel, gemma4E2bItQ4_0Model]);
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

    test('pins the official Gemma 4 E2B Q4_0 artifact metadata', () {
      expect(gemma4E2bItQ4_0Model.id, 'gemma-4-e2b-it');
      expect(gemma4E2bItQ4_0Model.version, kGemma4E2bItQ4_0Revision);
      expect(
        gemma4E2bItQ4_0Model.fileName,
        'gemma-4-E2B_q4_0-it.gguf',
      );
      expect(
        gemma4E2bItQ4_0Model.downloadUrl,
        kGemma4E2bItQ4_0DownloadUrl,
      );
      expect(gemma4E2bItQ4_0Model.downloadUrl, startsWith('https://'));
      expect(
        gemma4E2bItQ4_0Model.fileSizeBytes,
        kGemma4E2bItQ4_0FileSizeBytes,
      );
      expect(gemma4E2bItQ4_0Model.sha256, kGemma4E2bItQ4_0Sha256);
      expect(gemma4E2bItQ4_0Model.quantization, 'Q4_0');
      expect(gemma4E2bItQ4_0Model.contextSize, 4096);
      expect(gemma4E2bItQ4_0Model.maxOutputTokens, 512);
      expect(gemma4E2bItQ4_0Model.selectionPriority, greaterThan(1));
      expect(
        gemma4E2bItQ4_0Model.supportedPlatforms,
        containsAll(<String>['ios', 'android']),
      );
      expect(
        gemma4E2bItQ4_0Model.supportedAbis,
        containsAll(<String>['arm64', 'arm64-v8a', 'x86_64']),
      );
    });

    test('keeps resource gates unset until real-device measurements', () {
      expect(gemma3_1bItQ4KmModel.estimatedPeakMemoryBytes, isNull);
      expect(gemma3_1bItQ4KmModel.requiredFreeStorageBytes, isNull);
      expect(gemma4E2bItQ4_0Model.estimatedPeakMemoryBytes, isNull);
      expect(gemma4E2bItQ4_0Model.requiredFreeStorageBytes, isNull);
      expect(
        gemma3_1bItQ4KmModel.supportedPlatforms,
        containsAll(<String>['ios', 'android']),
      );
      expect(
        gemma3_1bItQ4KmModel.supportedAbis,
        containsAll(<String>['arm64', 'arm64-v8a', 'x86_64']),
      );
    });

    test('selection priority chooses E2B for a compatible iOS simulator', () {
      const DeviceCapability simulator = DeviceCapability(
        platform: 'ios',
        osVersion: '27.0',
        isPhysicalDevice: false,
        supportedAbis: <String>['arm64'],
        totalMemoryBytes: 8 << 30,
        freeStorageBytes: 20 << 30,
      );

      final ModelSelectionResult result = const ModelSelectionPolicy().select(
        capability: simulator,
        candidates: productionModelCatalog.models,
      );

      expect(result.selectedModel, gemma4E2bItQ4_0Model);
      expect(result.rejectionReasons, isEmpty);
    });

    test('shared production instance preserves catalog order', () {
      expect(productionModelCatalog.models, [
        gemma3_1bItQ4KmModel,
        gemma4E2bItQ4_0Model,
      ]);
    });
  });
}
