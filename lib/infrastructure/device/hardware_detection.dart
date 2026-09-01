/// Hardware capability detection contract (M3.1).
///
/// This library is deliberately platform-neutral: it must stay free of
/// `dart:io`, Flutter platform APIs, plugin types (including
/// `device_info_plus`), and the `local_llm_bridge` package. Platform
/// adapters implement [IHardwareDetectionService] and translate native
/// device facts into the [DeviceCapability] value object.
library;

/// Fixed-field snapshot of the device's hardware capabilities that matter to
/// capability-based model selection.
///
/// All six fields are required and fixed at construction; the value object
/// exposes no setters and no behavior beyond field access, value equality,
/// and a readable [toString]. Callers should pass an unmodifiable list for
/// [supportedAbis] when they need deep immutability.
final class DeviceCapability {
  /// Creates a capability snapshot. Every field is required; there are no
  /// defaults.
  const DeviceCapability({
    required this.platform,
    required this.osVersion,
    required this.isPhysicalDevice,
    required this.supportedAbis,
    required this.totalMemoryBytes,
    required this.freeStorageBytes,
  });

  /// Runtime platform identifier, e.g. `android`, `ios`, `macos`.
  final String platform;

  /// Operating system version reported by the platform, e.g. `17.6`.
  final String osVersion;

  /// True when the snapshot came from physical hardware rather than a
  /// simulator or emulator.
  final bool isPhysicalDevice;

  /// Native ABIs the device supports, in preference order (e.g.
  /// `['arm64-v8a', 'armeabi-v7a']` on Android, `['arm64']` on iOS).
  final List<String> supportedAbis;

  /// Total physical memory in bytes.
  final int totalMemoryBytes;

  /// Free storage space in bytes on the app-data filesystem partition.
  final int freeStorageBytes;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is DeviceCapability &&
        other.platform == platform &&
        other.osVersion == osVersion &&
        other.isPhysicalDevice == isPhysicalDevice &&
        _sameAbis(other.supportedAbis, supportedAbis) &&
        other.totalMemoryBytes == totalMemoryBytes &&
        other.freeStorageBytes == freeStorageBytes;
  }

  @override
  int get hashCode => Object.hash(
    platform,
    osVersion,
    isPhysicalDevice,
    Object.hashAll(supportedAbis),
    totalMemoryBytes,
    freeStorageBytes,
  );

  @override
  String toString() {
    return 'DeviceCapability(platform: $platform, osVersion: $osVersion, '
        'isPhysicalDevice: $isPhysicalDevice, supportedAbis: $supportedAbis, '
        'totalMemoryBytes: $totalMemoryBytes, '
        'freeStorageBytes: $freeStorageBytes)';
  }

  static bool _sameAbis(List<String> a, List<String> b) {
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

/// Contract for services that detect the device's hardware capabilities.
///
/// Implementations wrap platform APIs (e.g. `device_info_plus`) behind this
/// contract and return a platform-neutral [DeviceCapability] snapshot.
/// Failures are surfaced as thrown exceptions so callers decide policy.
abstract interface class IHardwareDetectionService {
  /// Returns a fixed-field snapshot of the current device's hardware
  /// capabilities.
  Future<DeviceCapability> getDeviceCapability();
}
