/// Checks the actual production RAM policy without loading a native model.
/// Run after flutter pub get: dart tool/verify_ram_selection.dart
library;

import 'dart:io';

import 'package:note_ai_app/infrastructure/ai/model_catalog.dart';
import 'package:note_ai_app/infrastructure/ai/model_selection.dart';
import 'package:note_ai_app/infrastructure/device/hardware_detection.dart';

void main() {
  final cases = <(String, int, List<String>, String?)>[
    ('unknown RAM', 0, ['arm64-v8a'], null),
    ('below 2 GiB', (2 << 30) - 1, ['arm64-v8a'], null),
    ('exactly 2 GiB', 2 << 30, ['arm64-v8a'], 'gemma-3-1b-it'),
    ('measured vivo RAM', 5886804 * 1024, ['arm64-v8a'], 'gemma-3-1b-it'),
    ('below 6 GiB', (6 << 30) - 1, ['arm64-v8a'], 'gemma-3-1b-it'),
    ('exactly 6 GiB', 6 << 30, ['arm64-v8a'], 'gemma-4-e2b-it'),
    ('8 GiB', 8 << 30, ['arm64-v8a'], 'gemma-4-e2b-it'),
    ('unsupported 32-bit ABI', 8 << 30, ['armeabi-v7a'], null),
  ];
  var failures = 0;
  for (final (name, ram, abis, expected) in cases) {
    final result = const ModelSelectionPolicy().select(
      capability: DeviceCapability(
        platform: 'android',
        osVersion: '12',
        isPhysicalDevice: true,
        supportedAbis: abis,
        totalMemoryBytes: ram,
        freeStorageBytes: 40 << 30,
      ),
      candidates: productionModelCatalog.models,
    );
    final actual = result.selectedModel?.id;
    final passed = actual == expected;
    if (!passed) failures++;
    stdout.writeln(
      '${passed ? "PASS" : "FAIL"}: $name; expected=$expected; actual=$actual',
    );
  }
  stdout.writeln(
    '${cases.length - failures}/${cases.length} RAM selection checks passed. No model inference was run.',
  );
  if (failures != 0) exitCode = 1;
}
