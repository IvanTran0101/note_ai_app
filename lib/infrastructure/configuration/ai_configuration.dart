/// Runtime configuration for the local AI infrastructure.
///
/// This class owns application-level defaults and environment overrides. It
/// intentionally does not contain model-specific metadata such as a selected
/// model's context window or output limit; those values belong to the selected
/// model descriptor and are supplied after model selection.
library;

/// Immutable configuration shared by the local model provisioning and
/// inference composition.
///
/// The public constructor validates every value at runtime so invalid
/// configuration cannot be silently accepted in a release build.
final class AiConfiguration {
  /// Creates a validated AI configuration.
  ///
  /// The context and output defaults are fallback values for paths that do
  /// not have selected model metadata, such as the legacy macOS override path.
  /// A selected model's metadata remains the source of truth for mobile
  /// provisioning.
  factory AiConfiguration({
    String? modelPathOverride,
    Duration downloadTimeout = const Duration(minutes: 15),
    int maxRedirects = 5,
    int workerThreads = 0,
    int defaultContextSize = 2048,
    int defaultMaxOutputTokens = 128,
  }) {
    _validate(
      downloadTimeout: downloadTimeout,
      maxRedirects: maxRedirects,
      workerThreads: workerThreads,
      defaultContextSize: defaultContextSize,
      defaultMaxOutputTokens: defaultMaxOutputTokens,
    );

    return AiConfiguration._(
      modelPathOverride: _normalizeModelPath(modelPathOverride),
      downloadTimeout: downloadTimeout,
      maxRedirects: maxRedirects,
      workerThreads: workerThreads,
      defaultContextSize: defaultContextSize,
      defaultMaxOutputTokens: defaultMaxOutputTokens,
    );
  }

  /// Creates a configuration from the compile-time model-path override.
  ///
  /// A blank or whitespace-only `LOCAL_LLM_MODEL_PATH` is treated as absent,
  /// allowing the normal model-provisioning path to remain active.
  factory AiConfiguration.fromEnvironment() {
    const String rawModelPath = String.fromEnvironment('LOCAL_LLM_MODEL_PATH');
    return AiConfiguration(modelPathOverride: rawModelPath);
  }

  const AiConfiguration._({
    required this.modelPathOverride,
    required this.downloadTimeout,
    required this.maxRedirects,
    required this.workerThreads,
    required this.defaultContextSize,
    required this.defaultMaxOutputTokens,
  });

  /// Optional explicit local GGUF path, normally used by the macOS debug
  /// workflow. A null value means automatic model provisioning may be used.
  final String? modelPathOverride;

  /// Maximum time allowed for establishing and receiving a model download.
  final Duration downloadTimeout;

  /// Maximum number of HTTPS redirects accepted by the model downloader.
  final int maxRedirects;

  /// Number of native worker threads. Zero delegates thread selection to the
  /// native runtime.
  final int workerThreads;

  /// Fallback context window for an explicitly supplied model path.
  final int defaultContextSize;

  /// Fallback output-token limit for an explicitly supplied model path.
  final int defaultMaxOutputTokens;

  static String? _normalizeModelPath(String? rawModelPath) {
    final String? normalized = rawModelPath?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static void _validate({
    required Duration downloadTimeout,
    required int maxRedirects,
    required int workerThreads,
    required int defaultContextSize,
    required int defaultMaxOutputTokens,
  }) {
    if (downloadTimeout.inMicroseconds <= 0) {
      throw ArgumentError.value(
        downloadTimeout,
        'downloadTimeout',
        'must be greater than zero',
      );
    }
    if (maxRedirects < 0) {
      throw ArgumentError.value(
        maxRedirects,
        'maxRedirects',
        'must be greater than or equal to zero',
      );
    }
    if (workerThreads < 0) {
      throw ArgumentError.value(
        workerThreads,
        'workerThreads',
        'must be greater than or equal to zero',
      );
    }
    if (defaultContextSize < 2 || defaultContextSize > 4096) {
      throw ArgumentError.value(
        defaultContextSize,
        'defaultContextSize',
        'must be between 2 and 4096 inclusive',
      );
    }
    if (defaultMaxOutputTokens < 1 || defaultMaxOutputTokens > 512) {
      throw ArgumentError.value(
        defaultMaxOutputTokens,
        'defaultMaxOutputTokens',
        'must be between 1 and 512 inclusive',
      );
    }
  }
}
