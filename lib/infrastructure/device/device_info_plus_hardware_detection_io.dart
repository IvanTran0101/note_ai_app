/// Native iOS/Android implementation of the plugin-first hardware adapter.
///
/// `device_info_plus` supplies typed Android/iOS models through its own native
/// plugin boundary. This adapter translates those models into the
/// platform-neutral [DeviceCapability] contract and owns unit/ABI
/// normalization. It does not perform model selection, storage, downloading,
/// or runtime loading.
library;

import 'package:device_info_plus/device_info_plus.dart';

import 'device_info_plus_hardware_detection_contract.dart';
import 'hardware_detection.dart';

/// Reads typed device information through `device_info_plus`.
final class DeviceInfoPlusReader implements IDeviceInfoReader {
  /// Uses [plugin] when supplied; otherwise creates the standard plugin.
  DeviceInfoPlusReader({DeviceInfoPlugin? plugin})
    : _plugin = plugin ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _plugin;

  @override
  Future<Object> read() async => _plugin.deviceInfo;
}

/// Maps typed `device_info_plus` data into [DeviceCapability].
final class DeviceInfoPlusHardwareDetectionService
    implements IHardwareDetectionService {
  /// Creates the adapter. [reader] is injectable for tests so no platform
  /// channel is needed to verify mapping and validation behavior.
  DeviceInfoPlusHardwareDetectionService({IDeviceInfoReader? reader})
    : _reader = reader ?? DeviceInfoPlusReader();

  final IDeviceInfoReader _reader;

  @override
  Future<DeviceCapability> getDeviceCapability() async {
    final Object snapshot;
    try {
      snapshot = await _reader.read();
    } on Object catch (error) {
      throw HardwareDetectionException(
        'failed to read device information',
        cause: error,
      );
    }

    if (snapshot is AndroidDeviceInfo) {
      return _fromAndroid(snapshot);
    }
    if (snapshot is IosDeviceInfo) {
      return _fromIos(snapshot);
    }

    throw HardwareDetectionException(
      'unsupported device information type: ${snapshot.runtimeType}',
    );
  }

  DeviceCapability _fromAndroid(AndroidDeviceInfo info) {
    final String osVersion = _requiredText(
      info.version.release,
      field: 'Android OS version',
    );
    final List<String> abis = _requiredAbis(
      info.supportedAbis,
      field: 'Android supported ABIs',
    );
    final int totalMemoryBytes = _megabytesToBytes(
      info.physicalRamSize,
      field: 'Android physical RAM',
    );
    _requirePositive(info.freeDiskSize, field: 'Android free storage');

    return DeviceCapability(
      platform: 'android',
      osVersion: osVersion,
      isPhysicalDevice: info.isPhysicalDevice,
      supportedAbis: abis,
      totalMemoryBytes: totalMemoryBytes,
      freeStorageBytes: info.freeDiskSize,
    );
  }

  DeviceCapability _fromIos(IosDeviceInfo info) {
    final String osVersion = _requiredText(
      info.systemVersion,
      field: 'iOS version',
    );
    final List<String> abis = _normalizeIosAbis(info.utsname.machine);
    final int totalMemoryBytes = _megabytesToBytes(
      info.physicalRamSize,
      field: 'iOS physical RAM',
    );
    _requirePositive(info.freeDiskSize, field: 'iOS free storage');

    return DeviceCapability(
      platform: 'ios',
      osVersion: osVersion,
      isPhysicalDevice: info.isPhysicalDevice,
      supportedAbis: abis,
      totalMemoryBytes: totalMemoryBytes,
      freeStorageBytes: info.freeDiskSize,
    );
  }

  static String _requiredText(String value, {required String field}) {
    final String normalized = value.trim();
    if (normalized.isEmpty) {
      throw HardwareDetectionException('$field is empty');
    }
    return normalized;
  }

  static List<String> _requiredAbis(
    List<String> values, {
    required String field,
  }) {
    final List<String> normalized = values
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
    if (normalized.isEmpty) {
      throw HardwareDetectionException('$field is empty');
    }
    return List<String>.unmodifiable(normalized);
  }

  /// Converts the plugin's documented RAM value (MiB) to bytes.
  static int _megabytesToBytes(int megabytes, {required String field}) {
    _requirePositive(megabytes, field: field);
    return megabytes * 1024 * 1024;
  }

  static void _requirePositive(int value, {required String field}) {
    if (value <= 0) {
      throw HardwareDetectionException('$field is unknown or non-positive');
    }
  }

  /// Converts iOS `utsname.machine` values into runtime ABI identifiers.
  ///
  /// Physical iOS devices expose identifiers such as `iPhone17,1`, while
  /// simulators normally expose `arm64` or `x86_64`. Device model identifiers
  /// are therefore mapped to arm64 only for known Apple mobile prefixes;
  /// unknown values are rejected instead of guessed.
  static List<String> _normalizeIosAbis(String machine) {
    final String normalized = machine.trim().toLowerCase();
    if (normalized == 'arm64' || normalized == 'arm64e') {
      return const <String>['arm64'];
    }
    if (normalized == 'x86_64' || normalized == 'x86-64') {
      return const <String>['x86_64'];
    }
    if (RegExp(r'^(iphone|ipad|ipod)\d+,\d+$').hasMatch(normalized)) {
      return const <String>['arm64'];
    }
    throw HardwareDetectionException(
      'unrecognized iOS machine identifier: $machine',
    );
  }
}

/// Creates the native plugin-first hardware detection implementation.
IHardwareDetectionService createHardwareDetectionService({
  IDeviceInfoReader? reader,
}) {
  return DeviceInfoPlusHardwareDetectionService(reader: reader);
}
