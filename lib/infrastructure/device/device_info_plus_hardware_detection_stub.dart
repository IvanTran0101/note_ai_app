/// Web-safe stub for the plugin-first hardware detection adapter.
///
/// Web does not expose the native iOS/Android capability snapshot required for
/// local model selection. This file intentionally imports neither `dart:io`
/// nor `device_info_plus` and keeps the same service/factory surface as the
/// native implementation.
library;

import 'device_info_plus_hardware_detection_contract.dart';
import 'hardware_detection.dart';

/// Unavailable reader for Web.
final class DeviceInfoPlusReader implements IDeviceInfoReader {
  const DeviceInfoPlusReader();

  @override
  Future<Object> read() {
    return Future<Object>.error(
      UnsupportedError(
        'Native device information is not available on the Web.',
      ),
    );
  }
}

/// Web implementation with the same public type as the native adapter.
final class DeviceInfoPlusHardwareDetectionService
    implements IHardwareDetectionService {
  const DeviceInfoPlusHardwareDetectionService({IDeviceInfoReader? reader});

  @override
  Future<DeviceCapability> getDeviceCapability() {
    throw UnsupportedError(
      'Local hardware detection is not available on the Web.',
    );
  }
}

/// Creates the unavailable Web implementation.
IHardwareDetectionService createHardwareDetectionService({
  IDeviceInfoReader? reader,
}) {
  return const DeviceInfoPlusHardwareDetectionService();
}
