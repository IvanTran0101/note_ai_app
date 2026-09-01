/// Model catalog descriptor and capability-based model selection (M3.1).
///
/// This library is deliberately platform-neutral and dependency-light: it must
/// stay free of `dart:io`, Flutter platform APIs, plugin types,
/// `package:local_llm_bridge`, the model-storage contract, and any downloader.
/// It imports only `hardware_detection.dart` for the [DeviceCapability] value
/// object that feeds the selection policy. Selection is a pure, deterministic
/// function of the capability snapshot and the candidate catalog: it never
/// touches storage, the network, or the local LLM runtime.
library;

import 'package:note_ai_app/infrastructure/device/hardware_detection.dart';

/// Fixed-field metadata for one downloadable model candidate.
///
/// All fields are required and fixed at construction, except resource
/// thresholds which may be null while the midterm policy intentionally skips
/// memory/storage gating. [supportedPlatforms] and [supportedAbis] are ordered
/// lists of exact identifiers (e.g. `android`,
/// `ios`, `macos` and `arm64-v8a`, `arm64`, `x86_64`). Values are plain data —
/// there is no runtime loading and no downloader here; [downloadUrl] and
/// [sha256] are metadata consumed by a separate (future) download lane.
///
/// Callers should pass const or otherwise unmodifiable lists; the value object
/// itself never mutates them.
final class ModelDescriptor {
  /// Creates a model descriptor. Every field is required; there are no
  /// defaults.
  const ModelDescriptor({
    required this.id,
    required this.version,
    required this.fileName,
    required this.downloadUrl,
    required this.sha256,
    required this.fileSizeBytes,
    required this.estimatedPeakMemoryBytes,
    required this.requiredFreeStorageBytes,
    required this.supportedPlatforms,
    required this.supportedAbis,
    required this.minOsVersion,
    required this.contextSize,
    required this.maxOutputTokens,
    required this.quantization,
    required this.selectionPriority,
  });

  /// Stable catalog identifier, e.g. `gemma-3-1b-it`.
  final String id;

  /// Model version string, e.g. `1.0.0`.
  final String version;

  /// Bare file name of the GGUF artifact, e.g. `gemma-3-1b-it-Q4_K_M.gguf`.
  /// Must not contain path separators (validated by storage).
  final String fileName;

  /// Download URL for the artifact.
  final String downloadUrl;

  /// SHA-256 hex digest of the artifact, used to verify downloads.
  final String sha256;

  /// Size of the artifact file in bytes.
  final int fileSizeBytes;

  /// Estimated peak RAM (in bytes) the runtime needs to load and run this
  /// model. When null, the current midterm policy skips the memory gate.
  final int? estimatedPeakMemoryBytes;

  /// Free storage (in bytes) required on the app-data partition, beyond what
  /// [fileSizeBytes] implies, to safely download and unpack the artifact.
  /// When null, the current midterm policy skips the storage gate.
  final int? requiredFreeStorageBytes;

  /// Exact platform identifiers this model runs on.
  final List<String> supportedPlatforms;

  /// Native ABIs this model's runtime supports, in preference order.
  final List<String> supportedAbis;

  /// Minimum operating system version, dot-separated numeric components, e.g.
  /// `14.0` or `17.6`. Compared numerically against
  /// [DeviceCapability.osVersion].
  final String minOsVersion;

  /// Model context window size in tokens.
  final int contextSize;

  /// Maximum number of output tokens per generation.
  final int maxOutputTokens;

  /// Quantization scheme, e.g. `Q4_K_M`.
  final String quantization;

  /// Relative selection preference: higher wins among candidates that pass all
  /// hard gates. Ties keep catalog order, so the result is deterministic.
  final int selectionPriority;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ModelDescriptor &&
        other.id == id &&
        other.version == version &&
        other.fileName == fileName &&
        other.downloadUrl == downloadUrl &&
        other.sha256 == sha256 &&
        other.fileSizeBytes == fileSizeBytes &&
        other.estimatedPeakMemoryBytes == estimatedPeakMemoryBytes &&
        other.requiredFreeStorageBytes == requiredFreeStorageBytes &&
        _sameStrings(other.supportedPlatforms, supportedPlatforms) &&
        _sameStrings(other.supportedAbis, supportedAbis) &&
        other.minOsVersion == minOsVersion &&
        other.contextSize == contextSize &&
        other.maxOutputTokens == maxOutputTokens &&
        other.quantization == quantization &&
        other.selectionPriority == selectionPriority;
  }

  @override
  int get hashCode => Object.hash(
    id,
    version,
    fileName,
    downloadUrl,
    sha256,
    fileSizeBytes,
    estimatedPeakMemoryBytes,
    requiredFreeStorageBytes,
    Object.hashAll(supportedPlatforms),
    Object.hashAll(supportedAbis),
    minOsVersion,
    contextSize,
    maxOutputTokens,
    quantization,
    selectionPriority,
  );

  @override
  String toString() {
    return 'ModelDescriptor(id: $id, version: $version, fileName: $fileName, '
        'quantization: $quantization, selectionPriority: $selectionPriority)';
  }

  static bool _sameStrings(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

/// The outcome of a model selection run.
///
/// [selectedModel] is null when no candidate passes every hard gate (or the
/// candidate list is empty); [rejectionReasons] then explains each rejection,
/// and [selectionReason] always explains the outcome in prose.
class ModelSelectionResult {
  /// Creates an immutable selection result.
  const ModelSelectionResult({
    required this.selectedModel,
    required this.rejectionReasons,
    required this.selectionReason,
  });

  /// The winning candidate, or null when nothing passed.
  final ModelDescriptor? selectedModel;

  /// Rejection reason per rejected candidate, keyed by [ModelDescriptor.id].
  /// Passing candidates have no entry.
  final Map<String, String> rejectionReasons;

  /// Deterministic prose explanation of the outcome, including the device
  /// summary (platform, OS version, physical/simulator, ABIs, memory, storage).
  final String selectionReason;

  /// True when a candidate passed every hard gate.
  bool get hasSelectedModel => selectedModel != null;

  /// The rejection reason recorded for [model], or null if it was not rejected
  /// (it either passed or was not part of the candidate list).
  String? rejectionReasonFor(ModelDescriptor model) =>
      rejectionReasons[model.id];
}

/// Contract for selecting a model given the device's hardware capabilities.
///
/// Implementations must be pure and deterministic: they may only inspect the
/// [DeviceCapability] and the candidate [ModelDescriptor]s, and must never call
/// [IModelStorage], a downloader, or the local LLM runtime.
abstract interface class IModelSelectionPolicy {
  /// Selects the best candidate among [candidates] for [capability], or returns
  /// a result with a null [ModelSelectionResult.selectedModel] when none pass.
  ModelSelectionResult select({
    required DeviceCapability capability,
    required List<ModelDescriptor> candidates,
  });
}

/// Default deterministic selection policy (M3.1).
///
/// Hard gates (all configured gates must pass):
///  1. platform — [DeviceCapability.platform] is in the descriptor's
///     [ModelDescriptor.supportedPlatforms];
///  2. minimum OS version — [DeviceCapability.osVersion] is at least the
///     descriptor's [ModelDescriptor.minOsVersion] (numeric comparison);
///  3. ABI — the device's [DeviceCapability.supportedAbis] intersect the
///     descriptor's [ModelDescriptor.supportedAbis];
///  4. memory — when [ModelDescriptor.estimatedPeakMemoryBytes] is present,
///     [DeviceCapability.totalMemoryBytes] must meet it;
///  5. storage — when [ModelDescriptor.requiredFreeStorageBytes] is present,
///     [DeviceCapability.freeStorageBytes] must meet it.
///
/// [DeviceCapability.isPhysicalDevice] is carried into the result's
/// [ModelSelectionResult.selectionReason] but is never a gate: a simulator is
/// allowed to select a model if every hard gate passes.
///
/// Unknown or invalid configured values are rejected safely, never guessed:
/// unparseable OS versions, non-positive device memory/storage when their
/// corresponding model threshold is configured, and malformed descriptors
/// (empty identity fields, empty platform/ABI lists, empty or unparseable
/// `minOsVersion`, non-positive sizes) produce a rejection reason instead of a
/// speculative pass. Null resource thresholds intentionally disable those two
/// gates for the midterm policy.
///
/// The winner is the passing candidate with the highest
/// [ModelDescriptor.selectionPriority]; ties keep catalog order, so the result
/// is fully deterministic.
final class ModelSelectionPolicy implements IModelSelectionPolicy {
  const ModelSelectionPolicy();

  @override
  ModelSelectionResult select({
    required DeviceCapability capability,
    required List<ModelDescriptor> candidates,
  }) {
    final String deviceSummary = _deviceSummary(capability);
    if (candidates.isEmpty) {
      return const ModelSelectionResult(
        selectedModel: null,
        rejectionReasons: <String, String>{},
        selectionReason: 'no candidates were provided',
      );
    }

    final Map<String, String> rejectionReasons = <String, String>{};
    ModelDescriptor? best;
    for (final ModelDescriptor model in candidates) {
      final List<String> failures = _gateFailures(capability, model);
      if (failures.isEmpty) {
        if (best == null || model.selectionPriority > best.selectionPriority) {
          best = model;
        }
        continue;
      }
      rejectionReasons[model.id] = failures.join(', ');
    }

    final ModelDescriptor? selected = best;
    if (selected == null) {
      return ModelSelectionResult(
        selectedModel: null,
        rejectionReasons: rejectionReasons,
        selectionReason: 'no candidate passed all hard gates on $deviceSummary',
      );
    }
    return ModelSelectionResult(
      selectedModel: selected,
      rejectionReasons: rejectionReasons,
      selectionReason:
          'selected ${selected.id} v${selected.version} (priority '
          '${selected.selectionPriority}): passed all hard gates on '
          '$deviceSummary',
    );
  }

  /// Returns the list of failing hard-gate descriptions for [model] on
  /// [capability]; empty means every gate passed. Each element is a stable,
  /// human-readable clause.
  List<String> _gateFailures(
    DeviceCapability capability,
    ModelDescriptor model,
  ) {
    final List<String> failures = <String>[];

    // 0. Descriptor validity — reject malformed metadata instead of guessing.
    failures.addAll(_descriptorFailures(model));
    if (failures.isNotEmpty) {
      return failures;
    }

    // 1. Platform.
    if (!model.supportedPlatforms.contains(capability.platform)) {
      failures.add(
        'platform gate: ${capability.platform} not in supported platforms '
        '${_list(model.supportedPlatforms)}',
      );
    }

    // 2. Minimum OS version (numeric; unparseable values reject safely).
    final int? osComparison = _compareVersions(
      capability.osVersion,
      model.minOsVersion,
    );
    if (osComparison == null) {
      failures.add(
        'OS version gate: device OS "${capability.osVersion}" or minimum '
        '"${model.minOsVersion}" is not a numeric version',
      );
    } else if (osComparison < 0) {
      failures.add(
        'OS version gate: device OS ${capability.osVersion} is below '
        'minimum ${model.minOsVersion}',
      );
    }

    // 3. ABI intersection.
    if (!_abisIntersect(capability.supportedAbis, model.supportedAbis)) {
      failures.add(
        'ABI gate: no intersection between device ABIs '
        '${_list(capability.supportedAbis)} and model ABIs '
        '${_list(model.supportedAbis)}',
      );
    }

    // 4. Memory. A null model threshold intentionally skips this gate.
    final int? estimatedPeakMemoryBytes = model.estimatedPeakMemoryBytes;
    if (estimatedPeakMemoryBytes != null) {
      final int totalMemoryBytes = capability.totalMemoryBytes;
      if (totalMemoryBytes <= 0) {
        failures.add(
          'memory gate: device memory is unknown (totalMemoryBytes '
          '$totalMemoryBytes)',
        );
      } else if (totalMemoryBytes < estimatedPeakMemoryBytes) {
        failures.add(
          'memory gate: device memory $totalMemoryBytes bytes is below '
          'required $estimatedPeakMemoryBytes bytes',
        );
      }
    }

    // 5. Storage. A null model threshold intentionally skips this gate.
    final int? requiredFreeStorageBytes = model.requiredFreeStorageBytes;
    if (requiredFreeStorageBytes != null) {
      final int freeStorageBytes = capability.freeStorageBytes;
      if (freeStorageBytes <= 0) {
        failures.add(
          'storage gate: free storage is unknown (freeStorageBytes '
          '$freeStorageBytes)',
        );
      } else if (freeStorageBytes < requiredFreeStorageBytes) {
        failures.add(
          'storage gate: free storage $freeStorageBytes bytes is below '
          'required $requiredFreeStorageBytes bytes',
        );
      }
    }

    return failures;
  }

  /// Rejects a descriptor whose required metadata is missing or nonsensical.
  List<String> _descriptorFailures(ModelDescriptor model) {
    final List<String> failures = <String>[];
    if (model.id.trim().isEmpty) {
      failures.add('invalid descriptor: id is empty');
    }
    if (model.version.trim().isEmpty) {
      failures.add('invalid descriptor: version is empty');
    }
    if (model.fileName.trim().isEmpty) {
      failures.add('invalid descriptor: fileName is empty');
    }
    if (model.downloadUrl.trim().isEmpty) {
      failures.add('invalid descriptor: downloadUrl is empty');
    }
    if (model.sha256.trim().isEmpty) {
      failures.add('invalid descriptor: sha256 is empty');
    }
    if (model.supportedPlatforms.isEmpty) {
      failures.add('invalid descriptor: supportedPlatforms is empty');
    }
    if (model.supportedAbis.isEmpty) {
      failures.add('invalid descriptor: supportedAbis is empty');
    }
    if (model.minOsVersion.trim().isEmpty) {
      failures.add('invalid descriptor: minOsVersion is empty');
    }
    if (model.fileSizeBytes <= 0) {
      failures.add('invalid descriptor: fileSizeBytes must be positive');
    }
    if (model.estimatedPeakMemoryBytes != null &&
        model.estimatedPeakMemoryBytes! <= 0) {
      failures.add(
        'invalid descriptor: estimatedPeakMemoryBytes must be positive',
      );
    }
    if (model.requiredFreeStorageBytes != null &&
        model.requiredFreeStorageBytes! <= 0) {
      failures.add(
        'invalid descriptor: requiredFreeStorageBytes must be positive',
      );
    }
    if (model.contextSize <= 0) {
      failures.add('invalid descriptor: contextSize must be positive');
    }
    if (model.maxOutputTokens <= 0) {
      failures.add('invalid descriptor: maxOutputTokens must be positive');
    }
    if (model.quantization.trim().isEmpty) {
      failures.add('invalid descriptor: quantization is empty');
    }
    return failures;
  }

  /// True when the device and model share at least one ABI.
  static bool _abisIntersect(List<String> deviceAbis, List<String> modelAbis) {
    for (final String deviceAbi in deviceAbis) {
      if (modelAbis.contains(deviceAbi)) {
        return true;
      }
    }
    return false;
  }

  /// Compares two dot-separated numeric versions; returns negative/zero/positive
  /// when [a] is below/equal/above [b], or null when either string is not a
  /// valid numeric version (missing components count as zero).
  static int? _compareVersions(String a, String b) {
    final List<int>? aParts = _parseVersion(a);
    final List<int>? bParts = _parseVersion(b);
    if (aParts == null || bParts == null) {
      return null;
    }
    final int length = aParts.length > bParts.length
        ? aParts.length
        : bParts.length;
    for (var i = 0; i < length; i++) {
      final int aPart = i < aParts.length ? aParts[i] : 0;
      final int bPart = i < bParts.length ? bParts[i] : 0;
      if (aPart != bPart) {
        return aPart - bPart;
      }
    }
    return 0;
  }

  /// Parses `17.6.1` into `[17, 6, 1]`, or null when any component is not an
  /// integer. Empty strings are unparseable.
  static List<int>? _parseVersion(String version) {
    final String trimmed = version.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final List<int> parts = <int>[];
    for (final String component in trimmed.split('.')) {
      final int? value = int.tryParse(component.trim());
      if (value == null) {
        return null;
      }
      parts.add(value);
    }
    return parts;
  }

  /// Deterministic prose summary of the device, including whether it is a
  /// physical device or a simulator.
  static String _deviceSummary(DeviceCapability capability) {
    final String kind = capability.isPhysicalDevice
        ? 'physical device'
        : 'simulator';
    return '${capability.platform} ${capability.osVersion} ($kind, ABIs '
        '${_list(capability.supportedAbis)}, '
        '${capability.totalMemoryBytes} bytes memory, '
        '${capability.freeStorageBytes} bytes free storage)';
  }

  static String _list(List<String> values) => '[${values.join(', ')}]';
}
