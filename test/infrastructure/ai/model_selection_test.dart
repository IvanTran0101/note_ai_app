// Pure unit tests for the M3.1 model-selection policy.
//
// These tests exercise only the ModelDescriptor value object,
// ModelSelectionResult, and the deterministic ModelSelectionPolicy against
// fake DeviceCapability snapshots and fake model catalogs. They never call
// ModelStorage, a downloader, the local LLM runtime, a plugin channel, or a
// real GGUF model.

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/infrastructure/ai/model_selection.dart';
import 'package:note_ai_app/infrastructure/device/hardware_detection.dart';

/// 64 zero hex digits — a valid-looking but clearly fake SHA-256.
const String _sha256Zeros =
    '0000000000000000000000000000000000000000000000000000000000000000';

/// Builds a valid descriptor; override only the fields a test cares about.
ModelDescriptor _descriptor({
  String id = 'model-a',
  String version = '1.0.0',
  String fileName = 'model-a.gguf',
  String downloadUrl = 'https://example.invalid/model-a.gguf',
  String sha256 = _sha256Zeros,
  int fileSizeBytes = 1 << 20, // 1 MiB
  int? estimatedPeakMemoryBytes = 4 << 30, // 4 GiB
  int? requiredFreeStorageBytes = 1 << 30, // 1 GiB
  List<String> supportedPlatforms = const ['android', 'ios'],
  List<String> supportedAbis = const ['arm64', 'arm64-v8a'],
  String minOsVersion = '14.0',
  int contextSize = 8192,
  int maxOutputTokens = 1024,
  String quantization = 'Q4_K_M',
  int selectionPriority = 0,
}) {
  return ModelDescriptor(
    id: id,
    version: version,
    fileName: fileName,
    downloadUrl: downloadUrl,
    sha256: sha256,
    fileSizeBytes: fileSizeBytes,
    estimatedPeakMemoryBytes: estimatedPeakMemoryBytes,
    requiredFreeStorageBytes: requiredFreeStorageBytes,
    supportedPlatforms: supportedPlatforms,
    supportedAbis: supportedAbis,
    minOsVersion: minOsVersion,
    contextSize: contextSize,
    maxOutputTokens: maxOutputTokens,
    quantization: quantization,
    selectionPriority: selectionPriority,
  );
}

/// Builds a fake capability snapshot; override only what a test cares about.
DeviceCapability _capability({
  String platform = 'ios',
  String osVersion = '17.6',
  bool isPhysicalDevice = true,
  List<String> supportedAbis = const ['arm64'],
  int totalMemoryBytes = 8 << 30, // 8 GiB
  int freeStorageBytes = 50 << 30, // 50 GiB
}) {
  return DeviceCapability(
    platform: platform,
    osVersion: osVersion,
    isPhysicalDevice: isPhysicalDevice,
    supportedAbis: supportedAbis,
    totalMemoryBytes: totalMemoryBytes,
    freeStorageBytes: freeStorageBytes,
  );
}

const IModelSelectionPolicy _policy = ModelSelectionPolicy();

void main() {
  group('ModelDescriptor value object', () {
    test('exposes every field exactly as provided', () {
      const descriptor = ModelDescriptor(
        id: 'gemma-3-1b-it',
        version: '1.0.0',
        fileName: 'gemma-3-1b-it-Q4_K_M.gguf',
        downloadUrl: 'https://example.invalid/gemma-3-1b-it.gguf',
        sha256: _sha256Zeros,
        fileSizeBytes: 1048576,
        estimatedPeakMemoryBytes: 4294967296,
        requiredFreeStorageBytes: 1073741824,
        supportedPlatforms: ['android', 'ios'],
        supportedAbis: ['arm64', 'arm64-v8a'],
        minOsVersion: '14.0',
        contextSize: 8192,
        maxOutputTokens: 1024,
        quantization: 'Q4_K_M',
        selectionPriority: 2,
      );

      expect(descriptor.id, 'gemma-3-1b-it');
      expect(descriptor.version, '1.0.0');
      expect(descriptor.fileName, 'gemma-3-1b-it-Q4_K_M.gguf');
      expect(
        descriptor.downloadUrl,
        'https://example.invalid/gemma-3-1b-it.gguf',
      );
      expect(descriptor.sha256, _sha256Zeros);
      expect(descriptor.fileSizeBytes, 1048576);
      expect(descriptor.estimatedPeakMemoryBytes, 4294967296);
      expect(descriptor.requiredFreeStorageBytes, 1073741824);
      expect(descriptor.supportedPlatforms, ['android', 'ios']);
      expect(descriptor.supportedAbis, ['arm64', 'arm64-v8a']);
      expect(descriptor.minOsVersion, '14.0');
      expect(descriptor.contextSize, 8192);
      expect(descriptor.maxOutputTokens, 1024);
      expect(descriptor.quantization, 'Q4_K_M');
      expect(descriptor.selectionPriority, 2);
    });

    test('is const-constructible, so every field is final and required', () {
      const descriptor = ModelDescriptor(
        id: 'small',
        version: '1.0.0',
        fileName: 'small.gguf',
        downloadUrl: 'https://example.invalid/small.gguf',
        sha256: _sha256Zeros,
        fileSizeBytes: 1,
        estimatedPeakMemoryBytes: 1,
        requiredFreeStorageBytes: 1,
        supportedPlatforms: ['android'],
        supportedAbis: ['arm64-v8a'],
        minOsVersion: '12',
        contextSize: 2048,
        maxOutputTokens: 256,
        quantization: 'Q4_K_M',
        selectionPriority: 0,
      );
      expect(descriptor.id, 'small');
    });

    test('is value-equal and hash-equal by content, including lists', () {
      final a = _descriptor(id: 'a');
      final b = _descriptor(id: 'a');
      final c = _descriptor(id: 'a', supportedAbis: ['x86_64']);

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a == Object(), isFalse);
    });
  });

  group('hard gates', () {
    test('platform gate rejects a model on an unsupported platform', () {
      final result = _policy.select(
        capability: _capability(platform: 'macos'),
        candidates: [_descriptor(id: 'a')],
      );

      expect(result.selectedModel, isNull);
      expect(
        result.rejectionReasonFor(_descriptor(id: 'a')),
        contains('platform gate'),
      );
    });

    test('minimum OS version gate rejects an older OS', () {
      final result = _policy.select(
        capability: _capability(osVersion: '13.5'),
        candidates: [_descriptor(id: 'a', minOsVersion: '14.0')],
      );

      expect(result.selectedModel, isNull);
      expect(
        result.rejectionReasonFor(_descriptor(id: 'a')),
        contains('OS version gate'),
      );
    });

    test('a device OS at or above the minimum passes the OS gate', () {
      final result = _policy.select(
        capability: _capability(osVersion: '14.0'),
        candidates: [_descriptor(id: 'a', minOsVersion: '14.0')],
      );

      expect(result.selectedModel, isNotNull);
      expect(result.selectedModel!.id, 'a');
    });

    test('ABI gate rejects when device and model share no ABI', () {
      final result = _policy.select(
        capability: _capability(supportedAbis: ['x86_64']),
        candidates: [
          _descriptor(id: 'a', supportedAbis: ['arm64']),
        ],
      );

      expect(result.selectedModel, isNull);
      expect(
        result.rejectionReasonFor(_descriptor(id: 'a')),
        contains('ABI gate'),
      );
    });

    test(
      'memory gate rejects when device memory is below the peak estimate',
      () {
        final result = _policy.select(
          capability: _capability(totalMemoryBytes: 4 << 30),
          candidates: [
            _descriptor(id: 'big', estimatedPeakMemoryBytes: 6 << 30),
          ],
        );

        expect(result.selectedModel, isNull);
        expect(
          result.rejectionReasonFor(_descriptor(id: 'big')),
          contains('memory gate'),
        );
      },
    );

    test('high memory selects the bigger model, low memory falls back', () {
      final candidates = [
        _descriptor(
          id: 'small',
          estimatedPeakMemoryBytes: 2 << 30,
          selectionPriority: 1,
        ),
        _descriptor(
          id: 'big',
          estimatedPeakMemoryBytes: 6 << 30,
          selectionPriority: 2,
        ),
      ];

      final highMemory = _policy.select(
        capability: _capability(totalMemoryBytes: 8 << 30),
        candidates: candidates,
      );
      expect(highMemory.selectedModel!.id, 'big');

      final lowMemory = _policy.select(
        capability: _capability(totalMemoryBytes: 4 << 30),
        candidates: candidates,
      );
      expect(lowMemory.selectedModel!.id, 'small');
      expect(
        lowMemory.rejectionReasonFor(
          _descriptor(id: 'big', estimatedPeakMemoryBytes: 6 << 30),
        ),
        contains('memory gate'),
      );
    });

    test('storage gate rejects when free storage is below the requirement', () {
      final result = _policy.select(
        capability: _capability(freeStorageBytes: 5 << 30),
        candidates: [_descriptor(id: 'a', requiredFreeStorageBytes: 10 << 30)],
      );

      expect(result.selectedModel, isNull);
      expect(
        result.rejectionReasonFor(_descriptor(id: 'a')),
        contains('storage gate'),
      );
    });

    test('skips memory and storage gates when thresholds are null', () {
      final result = _policy.select(
        capability: _capability(totalMemoryBytes: 0, freeStorageBytes: 0),
        candidates: [
          _descriptor(
            id: 'no-resource-thresholds',
            estimatedPeakMemoryBytes: null,
            requiredFreeStorageBytes: null,
          ),
        ],
      );

      expect(result.selectedModel!.id, 'no-resource-thresholds');
    });
  });

  group('priority selection', () {
    test('selects the highest selectionPriority among passing candidates', () {
      final result = _policy.select(
        capability: _capability(),
        candidates: [
          _descriptor(id: 'low', selectionPriority: 1),
          _descriptor(id: 'high', selectionPriority: 9),
          _descriptor(id: 'mid', selectionPriority: 5),
        ],
      );

      expect(result.selectedModel!.id, 'high');
      expect(result.selectionReason, contains('selected high'));
      expect(result.selectionReason, contains('priority 9'));
    });

    test('priority beats catalog order', () {
      final result = _policy.select(
        capability: _capability(),
        candidates: [
          _descriptor(id: 'first-in-catalog', selectionPriority: 1),
          _descriptor(id: 'later-higher-priority', selectionPriority: 3),
        ],
      );

      expect(result.selectedModel!.id, 'later-higher-priority');
    });

    test('ties keep catalog order, so the result is deterministic', () {
      final candidates = [
        _descriptor(id: 'first', selectionPriority: 5),
        _descriptor(id: 'second', selectionPriority: 5),
      ];

      final firstRun = _policy.select(
        capability: _capability(),
        candidates: candidates,
      );
      final secondRun = _policy.select(
        capability: _capability(),
        candidates: candidates,
      );

      expect(firstRun.selectedModel!.id, 'first');
      expect(secondRun.selectedModel!.id, 'first');
    });
  });

  group('no candidate', () {
    test('returns null with a rejection reason per rejected candidate', () {
      final result = _policy.select(
        capability: _capability(),
        candidates: [
          _descriptor(id: 'no-memory', estimatedPeakMemoryBytes: 100 << 30),
          _descriptor(id: 'wrong-abi', supportedAbis: ['x86_64']),
        ],
      );

      expect(result.selectedModel, isNull);
      expect(result.hasSelectedModel, isFalse);
      expect(
        result.rejectionReasons.keys,
        unorderedEquals(['no-memory', 'wrong-abi']),
      );
      expect(
        result.rejectionReasonFor(_descriptor(id: 'no-memory')),
        contains('memory gate'),
      );
      expect(
        result.rejectionReasonFor(_descriptor(id: 'wrong-abi')),
        contains('ABI gate'),
      );
      expect(result.selectionReason, startsWith('no candidate passed'));
    });

    test('an empty candidate list is a deterministic no-candidate result', () {
      final result = _policy.select(
        capability: _capability(),
        candidates: const <ModelDescriptor>[],
      );

      expect(result.selectedModel, isNull);
      expect(result.rejectionReasons, isEmpty);
      expect(result.selectionReason, 'no candidates were provided');
    });
  });

  group('simulator and physical device', () {
    test('a simulator is allowed when every hard gate passes', () {
      final result = _policy.select(
        capability: _capability(isPhysicalDevice: false),
        candidates: [_descriptor(id: 'a')],
      );

      expect(result.selectedModel, isNotNull);
      expect(result.selectedModel!.id, 'a');
    });

    test(
      'isPhysicalDevice is carried into the selection reason, never a gate',
      () {
        final simulator = _policy.select(
          capability: _capability(isPhysicalDevice: false),
          candidates: [_descriptor(id: 'a')],
        );
        final physical = _policy.select(
          capability: _capability(isPhysicalDevice: true),
          candidates: [_descriptor(id: 'a')],
        );

        expect(simulator.selectionReason, contains('simulator'));
        expect(physical.selectionReason, contains('physical device'));
        expect(simulator.selectedModel, isNotNull);
      },
    );
  });

  group('unknown or invalid values reject safely, not guess', () {
    test('unknown device memory (zero) rejects instead of guessing', () {
      final result = _policy.select(
        capability: _capability(totalMemoryBytes: 0),
        candidates: [_descriptor(id: 'a')],
      );

      expect(result.selectedModel, isNull);
      expect(
        result.rejectionReasonFor(_descriptor(id: 'a')),
        contains('memory is unknown'),
      );
    });

    test('unknown free storage (zero) rejects instead of guessing', () {
      final result = _policy.select(
        capability: _capability(freeStorageBytes: 0),
        candidates: [_descriptor(id: 'a')],
      );

      expect(result.selectedModel, isNull);
      expect(
        result.rejectionReasonFor(_descriptor(id: 'a')),
        contains('storage is unknown'),
      );
    });

    test('unparseable device OS version rejects instead of guessing', () {
      final result = _policy.select(
        capability: _capability(osVersion: 'unknown'),
        candidates: [_descriptor(id: 'a', minOsVersion: '14.0')],
      );

      expect(result.selectedModel, isNull);
      expect(
        result.rejectionReasonFor(_descriptor(id: 'a')),
        contains('not a numeric version'),
      );
    });

    test('an unparseable minimum OS version rejects the candidate', () {
      final result = _policy.select(
        capability: _capability(),
        candidates: [_descriptor(id: 'a', minOsVersion: 'beta')],
      );

      expect(result.selectedModel, isNull);
      expect(
        result.rejectionReasonFor(_descriptor(id: 'a')),
        contains('not a numeric version'),
      );
    });

    test('a descriptor with no supported ABIs rejects as invalid', () {
      final result = _policy.select(
        capability: _capability(),
        candidates: [_descriptor(id: 'a', supportedAbis: const <String>[])],
      );

      expect(result.selectedModel, isNull);
      expect(
        result.rejectionReasonFor(_descriptor(id: 'a')),
        contains('invalid descriptor'),
      );
    });

    test('a descriptor with a non-positive peak memory rejects as invalid', () {
      final result = _policy.select(
        capability: _capability(),
        candidates: [_descriptor(id: 'a', estimatedPeakMemoryBytes: 0)],
      );

      expect(result.selectedModel, isNull);
      expect(
        result.rejectionReasonFor(_descriptor(id: 'a')),
        contains('estimatedPeakMemoryBytes must be positive'),
      );
    });

    test('a descriptor with an empty id rejects as invalid', () {
      final result = _policy.select(
        capability: _capability(),
        candidates: [_descriptor(id: '  ')],
      );

      expect(result.selectedModel, isNull);
      expect(
        result.rejectionReasonFor(_descriptor(id: '  ')),
        contains('id is empty'),
      );
    });
  });
}
