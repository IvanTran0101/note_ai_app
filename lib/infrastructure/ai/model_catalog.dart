/// Production model catalog for the midterm on-device provisioning flow.
///
/// This catalog intentionally contains one verified artifact. A model is
/// added only after its source revision, size, and SHA-256 digest are known;
/// this prevents selection from silently pointing at an unverified download.
library;

import 'model_provisioning_contract.dart';
import 'model_selection.dart';

/// Pinned source revision for the verified Gemma 3 1B IT GGUF repository.
const String kGemma3_1bItQ4KmRevision =
    'f9c28bcd85737ffc5aef028638d3341d49869c27';

/// SHA-256 of the pinned Gemma 3 1B IT Q4_K_M artifact.
const String kGemma3_1bItQ4KmSha256 =
    '8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135';

/// Exact byte size of the pinned Gemma 3 1B IT Q4_K_M artifact.
const int kGemma3_1bItQ4KmFileSizeBytes = 806058240;

/// Pinned HTTPS source for the Gemma 3 1B IT Q4_K_M artifact.
const String kGemma3_1bItQ4KmDownloadUrl =
    'https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/'
    '$kGemma3_1bItQ4KmRevision/gemma-3-1b-it-Q4_K_M.gguf?download=true';

/// The only production model currently eligible for midterm provisioning.
///
/// The resource thresholds are intentionally null. M3.3b keeps model
/// selection focused on platform, OS, and ABI compatibility; measured RAM and
/// storage policy can be introduced after device benchmarks are available.
const ModelDescriptor gemma3_1bItQ4KmModel = ModelDescriptor(
  id: 'gemma-3-1b-it',
  version: kGemma3_1bItQ4KmRevision,
  fileName: 'gemma-3-1b-it-Q4_K_M.gguf',
  downloadUrl: kGemma3_1bItQ4KmDownloadUrl,
  sha256: kGemma3_1bItQ4KmSha256,
  fileSizeBytes: kGemma3_1bItQ4KmFileSizeBytes,
  estimatedPeakMemoryBytes: null,
  requiredFreeStorageBytes: null,
  supportedPlatforms: <String>['ios', 'android'],
  supportedAbis: <String>['arm64', 'arm64-v8a', 'x86_64'],
  // The model has no separately verified platform-specific minimum in this
  // catalog. `0` is the contract's numeric baseline and leaves that gate
  // open for the two currently supported platforms.
  minOsVersion: '0',
  contextSize: 4096,
  maxOutputTokens: 512,
  quantization: 'Q4_K_M',
  selectionPriority: 1,
);

/// Immutable production catalog in deterministic selection order.
final class ModelCatalog implements IModelCatalog {
  /// Creates the production catalog.
  const ModelCatalog();

  @override
  List<ModelDescriptor> get models => const <ModelDescriptor>[
    gemma3_1bItQ4KmModel,
  ];
}

/// Shared catalog instance for the application composition root.
const ModelCatalog productionModelCatalog = ModelCatalog();
