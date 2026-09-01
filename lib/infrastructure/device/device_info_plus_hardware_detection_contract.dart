/// Platform-neutral seams shared by the native and Web hardware adapters.
///
/// This file deliberately does not import `device_info_plus`, `dart:io`, or
/// Flutter. The native implementation hides the plugin behind
/// [IDeviceInfoReader], while the Web implementation exposes the same public
/// service shape and reports that local hardware detection is unavailable.
library;

/// Reads one typed platform-device snapshot for the native adapter.
///
/// The return type is [Object] so the conditional Web implementation does not
/// need to import native plugin model types. The IO adapter immediately
/// narrows the value to `AndroidDeviceInfo` or `IosDeviceInfo`; it never reads
/// the plugin's generic data map.
abstract interface class IDeviceInfoReader {
  /// Returns the current platform's typed device information object.
  Future<Object> read();
}

/// Reports that device capability detection could not produce a valid
/// platform-neutral snapshot.
final class HardwareDetectionException implements Exception {
  /// Creates a hardware detection failure with an optional underlying cause.
  const HardwareDetectionException(this.message, {this.cause});

  /// Human-readable failure explanation.
  final String message;

  /// Original plugin/reader failure, when one exists.
  final Object? cause;

  @override
  String toString() {
    final Object? original = cause;
    if (original == null) {
      return 'HardwareDetectionException: $message';
    }
    return 'HardwareDetectionException: $message (cause: $original)';
  }
}
