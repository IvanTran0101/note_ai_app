/// Production model catalog for the midterm on-device provisioning flow.
///
/// A model is added only after its source revision, size, and SHA-256 digest
/// are known; this prevents selection from silently pointing at an
/// unverified download.
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

/// Pinned source revision for the official Gemma 4 E2B IT Q4_0 GGUF file.
const String kGemma4E2bItQ4_0Revision = '347eef7';

/// SHA-256 of the verified Gemma 4 E2B IT Q4_0 GGUF artifact.
const String kGemma4E2bItQ4_0Sha256 =
    'fa401b55b07ee70a54c6dae3903c783a6e65064312529ea57175cb5f8dec6634';

/// Exact byte size of the verified Gemma 4 E2B IT Q4_0 GGUF artifact.
const int kGemma4E2bItQ4_0FileSizeBytes = 3349516256;

/// Pinned HTTPS source for the official Gemma 4 E2B IT Q4_0 GGUF artifact.
const String kGemma4E2bItQ4_0DownloadUrl =
    'https://huggingface.co/google/gemma-4-E2B-it-qat-q4_0-gguf/resolve/'
    '$kGemma4E2bItQ4_0Revision/gemma-4-E2B_q4_0-it.gguf?download=true';

/// The low-tier fallback model for midterm provisioning.
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

/// Verified Gemma 4 E2B IT Q4_0 candidate for capable mobile devices.
///
/// The native smoke test verified the `gemma4` architecture and E2B model
/// type with the current bridge. Its trained context is 131072 tokens, but
/// the application deliberately caps the runtime context at 4096 for the
/// mobile midterm. Resource thresholds remain null until real-device memory
/// and storage measurements are available; the macOS smoke test is not a
/// mobile fit guarantee.
const ModelDescriptor gemma4E2bItQ4_0Model = ModelDescriptor(
  id: 'gemma-4-e2b-it',
  version: kGemma4E2bItQ4_0Revision,
  fileName: 'gemma-4-E2B_q4_0-it.gguf',
  downloadUrl: kGemma4E2bItQ4_0DownloadUrl,
  sha256: kGemma4E2bItQ4_0Sha256,
  fileSizeBytes: kGemma4E2bItQ4_0FileSizeBytes,
  estimatedPeakMemoryBytes: null,
  requiredFreeStorageBytes: null,
  supportedPlatforms: <String>['ios', 'android'],
  supportedAbis: <String>['arm64', 'arm64-v8a', 'x86_64'],
  minOsVersion: '0',
  contextSize: 4096,
  maxOutputTokens: 512,
  quantization: 'Q4_0',
  selectionPriority: 2,
);

/// Immutable production catalog in deterministic selection order.
final class ModelCatalog implements IModelCatalog {
  /// Creates the production catalog.
  const ModelCatalog();

  @override
  List<ModelDescriptor> get models => const <ModelDescriptor>[
    gemma3_1bItQ4KmModel,
    gemma4E2bItQ4_0Model,
  ];
}

/// Shared catalog instance for the application composition root.
const ModelCatalog productionModelCatalog = ModelCatalog();
