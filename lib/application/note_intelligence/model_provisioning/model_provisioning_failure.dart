/// Application-facing model-provisioning failure contract (M4.5.a).
///
/// This library owns the stable failure vocabulary of one model-provisioning
/// attempt as observed from the Application boundary. Infrastructure maps its
/// exceptions onto [ModelProvisioningFailureCode]; Presentation consumes the
/// code and the safe prose in [ModelProvisioningFailure.detail] and never
/// imports Infrastructure exception types directly.
///
/// The library is deliberately free of Flutter, `dart:io`, and Infrastructure
/// types. Only safe, user-presentable prose may travel in
/// [ModelProvisioningFailure.detail]: never a stack trace, URL, or raw file
/// path. Raw exception text stays in Infrastructure/Diagnostics.
library;

/// Stable codes for the failure classes of a model-provisioning attempt.
///
/// Each code carries a fixed [retryable] flag deciding whether re-running the
/// same user-initiated provisioning attempt can plausibly succeed without a
/// catalog or storage change. The flag lives on the code, not on each failure
/// instance, so every producer maps one failure class consistently.
enum ModelProvisioningFailureCode {
  /// Device capability detection failed. The failure is usually transient, so
  /// retrying the same attempt can succeed.
  hardwareDetectionFailed(retryable: true),

  /// No catalog model is compatible with the detected device. Capability does
  /// not change between retries, so the attempt is not retryable.
  noCompatibleModel(retryable: false),

  /// The artifact could not be staged or committed, e.g. insufficient free
  /// storage. Retrying after freeing storage can succeed.
  storageFailed(retryable: true),

  /// Downloading the artifact failed, e.g. a network interruption. Retrying
  /// the same attempt can succeed.
  downloadFailed(retryable: true),

  /// The downloaded artifact failed size or SHA-256 verification. A fresh
  /// download may verify, so the attempt is retryable.
  integrityMismatch(retryable: true),

  /// The committed artifact could not be loaded by the native runtime. A
  /// healthy device that failed once is likely to fail again; repair or
  /// re-provisioning is a distinct action owned by a later recovery slice.
  runtimeLoadFailed(retryable: false),

  /// The current platform does not support local model provisioning. The
  /// platform does not change between retries, so the attempt is not
  /// retryable.
  unsupportedPlatform(retryable: false),

  /// Any failure that did not map to a more specific class. Retrying blindly
  /// risks a tight failure loop, so this is not retryable by default.
  unexpected(retryable: false);

  const ModelProvisioningFailureCode({required this.retryable});

  /// Whether re-running the same provisioning attempt can plausibly succeed.
  final bool retryable;
}

/// Immutable, typed failure that ends one model-provisioning attempt.
///
/// [code] is the stable failure class and [retryable] derives from it, so the
/// flag can never disagree with the code. [detail] is optional, safe,
/// user-facing prose prepared by the reporting adapter; it must never contain
/// a stack trace, URL, or raw file path.
final class ModelProvisioningFailure {
  /// Creates a provisioning failure. Pass null [detail] when no safe
  /// explanation exists; an empty detail should also be omitted.
  const ModelProvisioningFailure({required this.code, this.detail});

  /// The stable failure class of this attempt.
  final ModelProvisioningFailureCode code;

  /// Optional safe, user-presentable explanation, or null when none exists.
  final String? detail;

  /// Whether the same provisioning attempt can be retried, derived from
  /// [code] so it stays consistent across producers.
  bool get retryable => code.retryable;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ModelProvisioningFailure &&
        other.code == code &&
        other.detail == detail;
  }

  @override
  int get hashCode => Object.hash(code, detail);

  @override
  String toString() {
    return 'ModelProvisioningFailure(code: ${code.name}, '
        'retryable: $retryable, detail: $detail)';
  }
}
