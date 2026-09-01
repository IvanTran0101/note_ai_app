// Worker B: contract tests for the M3.2 plugin-first hardware detection
// adapter built on device_info_plus.
//
// The adapter under test is `DeviceInfoPlusHardwareDetectionService`
// (lib/infrastructure/device/device_info_plus_hardware_detection.dart).
// These tests never touch a platform channel: a fake `IDeviceInfoReader`
// supplies typed device_info_plus models (`AndroidDeviceInfo` /
// `IosDeviceInfo`), so the service under test must not construct
// `DeviceInfoPlugin` or invoke the plugin's method channel.
//
// Encoded adapter contract (the behavior these tests pin down):
//   * Android: platform `'android'`, osVersion = `version.release`,
//     isPhysicalDevice passthrough, supportedAbis passthrough (order kept),
//     totalMemoryBytes = `physicalRamSize` MB -> bytes (x1024*1024),
//     freeStorageBytes = `freeDiskSize` bytes (unchanged).
//   * iOS physical: platform `'ios'`, osVersion = `systemVersion`,
//     a real device identifier such as `iPhone17,1` maps to `['arm64']`,
//     RAM/storage units converted exactly as on Android.
//   * iOS simulator: `isPhysicalDevice == false`; the utsname machine is the
//     host architecture (`x86_64` or `arm64`) and becomes the ABI list.
//   * Errors surface as `HardwareDetectionException`: an object the adapter
//     cannot interpret, an unknown iOS machine, non-positive memory or
//     storage, and a failing reader (the service wraps reader failures).
//
// Keep every test deterministic; fixtures are built with the
// `setMockInitialValues` constructors device_info_plus ships for tests.

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/infrastructure/device/device_info_plus_hardware_detection.dart';
import 'package:note_ai_app/infrastructure/device/hardware_detection.dart';

/// Method channel the real plugin would call if the service ever bypassed the
/// injected reader. Registered as a recording spy in the channel-isolation
/// test; zero invocations prove the fake reader is the only data source.
const _deviceInfoChannel = MethodChannel(
  'dev.fluttercommunity.plus/device_info',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Android mapping', () {
    test('maps a physical Android device into a DeviceCapability', () async {
      final service = DeviceInfoPlusHardwareDetectionService(
        reader: _FakeDeviceInfoReader(
          _android(
            release: '14',
            isPhysicalDevice: true,
            supportedAbis: const ['arm64-v8a', 'armeabi-v7a'],
            physicalRamSizeMb: 4096,
            freeDiskBytes: 107374182400,
          ),
        ),
      );

      final capability = await service.getDeviceCapability();

      expect(
        capability,
        const DeviceCapability(
          platform: 'android',
          osVersion: '14',
          isPhysicalDevice: true,
          supportedAbis: ['arm64-v8a', 'armeabi-v7a'],
          totalMemoryBytes: 4294967296, // 4096 MB
          freeStorageBytes: 107374182400,
        ),
      );
    });

    test('converts Android RAM from megabytes to bytes', () async {
      final service = DeviceInfoPlusHardwareDetectionService(
        reader: _FakeDeviceInfoReader(_android(physicalRamSizeMb: 8192)),
      );

      final capability = await service.getDeviceCapability();

      expect(capability.totalMemoryBytes, 8589934592); // 8192 MB
      expect(capability.totalMemoryBytes, 8192 * 1024 * 1024);
    });

    test('keeps Android free disk size in bytes unchanged', () async {
      final service = DeviceInfoPlusHardwareDetectionService(
        reader: _FakeDeviceInfoReader(_android(freeDiskBytes: 53687091200)),
      );

      final capability = await service.getDeviceCapability();

      expect(capability.freeStorageBytes, 53687091200);
    });

    test('maps an Android emulator with isPhysicalDevice false', () async {
      final service = DeviceInfoPlusHardwareDetectionService(
        reader: _FakeDeviceInfoReader(
          _android(
            release: '13',
            isPhysicalDevice: false,
            supportedAbis: const ['x86_64'],
            physicalRamSizeMb: 6144,
          ),
        ),
      );

      final capability = await service.getDeviceCapability();

      expect(capability.platform, 'android');
      expect(capability.osVersion, '13');
      expect(capability.isPhysicalDevice, isFalse);
      expect(capability.supportedAbis, ['x86_64']);
      expect(capability.totalMemoryBytes, 6442450944); // 6144 MB
    });
  });

  group('iOS physical device mapping', () {
    test('maps a physical iPhone (iPhone17,1) to arm64', () async {
      final service = DeviceInfoPlusHardwareDetectionService(
        reader: _FakeDeviceInfoReader(
          _ios(
            systemVersion: '18.1',
            isPhysicalDevice: true,
            machine: 'iPhone17,1',
            physicalRamSizeMb: 8192,
            freeDiskBytes: 107374182400,
          ),
        ),
      );

      final capability = await service.getDeviceCapability();

      expect(
        capability,
        const DeviceCapability(
          platform: 'ios',
          osVersion: '18.1',
          isPhysicalDevice: true,
          supportedAbis: ['arm64'],
          totalMemoryBytes: 8589934592, // 8192 MB
          freeStorageBytes: 107374182400,
        ),
      );
    });

    test('maps a physical iPad to arm64 too', () async {
      final service = DeviceInfoPlusHardwareDetectionService(
        reader: _FakeDeviceInfoReader(
          _ios(isPhysicalDevice: true, machine: 'iPad14,1'),
        ),
      );

      final capability = await service.getDeviceCapability();

      expect(capability.platform, 'ios');
      expect(capability.isPhysicalDevice, isTrue);
      expect(capability.supportedAbis, ['arm64']);
    });
  });

  group('iOS simulator mapping', () {
    test('maps an x86_64 Intel simulator to the x86_64 ABI', () async {
      final service = DeviceInfoPlusHardwareDetectionService(
        reader: _FakeDeviceInfoReader(
          _ios(
            systemVersion: '18.1',
            isPhysicalDevice: false,
            machine: 'x86_64',
            physicalRamSizeMb: 16384,
          ),
        ),
      );

      final capability = await service.getDeviceCapability();

      expect(
        capability,
        const DeviceCapability(
          platform: 'ios',
          osVersion: '18.1',
          isPhysicalDevice: false,
          supportedAbis: ['x86_64'],
          totalMemoryBytes: 17179869184, // 16384 MB
          freeStorageBytes: 107374182400,
        ),
      );
    });

    test('maps an arm64 Apple Silicon simulator to the arm64 ABI', () async {
      final service = DeviceInfoPlusHardwareDetectionService(
        reader: _FakeDeviceInfoReader(
          _ios(isPhysicalDevice: false, machine: 'arm64'),
        ),
      );

      final capability = await service.getDeviceCapability();

      expect(capability.isPhysicalDevice, isFalse);
      expect(capability.supportedAbis, ['arm64']);
    });
  });

  group('Invalid input handling', () {
    test(
      'throws HardwareDetectionException for an unsupported object',
      () async {
        for (final unsupported in <Object>['not device info', 42]) {
          final service = DeviceInfoPlusHardwareDetectionService(
            reader: _FakeDeviceInfoReader(unsupported),
          );

          await expectLater(
            service.getDeviceCapability(),
            throwsA(isA<HardwareDetectionException>()),
          );
        }
      },
    );

    test('throws for a physical iOS device with an unknown machine', () async {
      for (final machine in <String>['', 'nope', 'iPhoneFake']) {
        final service = DeviceInfoPlusHardwareDetectionService(
          reader: _FakeDeviceInfoReader(
            _ios(isPhysicalDevice: true, machine: machine),
          ),
        );

        await expectLater(
          service.getDeviceCapability(),
          throwsA(isA<HardwareDetectionException>()),
        );
      }
    });

    test('throws for a simulator with an unrecognized machine', () async {
      final service = DeviceInfoPlusHardwareDetectionService(
        reader: _FakeDeviceInfoReader(
          _ios(isPhysicalDevice: false, machine: 'not-an-arch'),
        ),
      );

      await expectLater(
        service.getDeviceCapability(),
        throwsA(isA<HardwareDetectionException>()),
      );
    });

    test('throws for zero or negative Android memory', () async {
      for (final ramMb in <int>[0, -1, -4096]) {
        final service = DeviceInfoPlusHardwareDetectionService(
          reader: _FakeDeviceInfoReader(_android(physicalRamSizeMb: ramMb)),
        );

        await expectLater(
          service.getDeviceCapability(),
          throwsA(isA<HardwareDetectionException>()),
        );
      }
    });

    test('throws for zero or negative Android storage', () async {
      for (final freeBytes in <int>[0, -1, -1024]) {
        final service = DeviceInfoPlusHardwareDetectionService(
          reader: _FakeDeviceInfoReader(_android(freeDiskBytes: freeBytes)),
        );

        await expectLater(
          service.getDeviceCapability(),
          throwsA(isA<HardwareDetectionException>()),
        );
      }
    });

    test('throws for zero or negative iOS memory', () async {
      for (final ramMb in <int>[0, -1]) {
        final service = DeviceInfoPlusHardwareDetectionService(
          reader: _FakeDeviceInfoReader(_ios(physicalRamSizeMb: ramMb)),
        );

        await expectLater(
          service.getDeviceCapability(),
          throwsA(isA<HardwareDetectionException>()),
        );
      }
    });

    test('throws for zero or negative iOS storage', () async {
      for (final freeBytes in <int>[0, -1]) {
        final service = DeviceInfoPlusHardwareDetectionService(
          reader: _FakeDeviceInfoReader(_ios(freeDiskBytes: freeBytes)),
        );

        await expectLater(
          service.getDeviceCapability(),
          throwsA(isA<HardwareDetectionException>()),
        );
      }
    });

    test('wraps a reader failure in HardwareDetectionException', () async {
      final service = DeviceInfoPlusHardwareDetectionService(
        reader: _FakeDeviceInfoReader.failure(StateError('channel failed')),
      );

      await expectLater(
        service.getDeviceCapability(),
        throwsA(isA<HardwareDetectionException>()),
      );
    });
  });

  group('Reader injection and platform-channel isolation', () {
    test('uses the injected fake reader exactly once', () async {
      final reader = _FakeDeviceInfoReader(_android());

      final service = DeviceInfoPlusHardwareDetectionService(reader: reader);
      final capability = await service.getDeviceCapability();

      expect(capability.platform, 'android');
      expect(reader.readCalls, 1);
    });

    test('never invokes the device_info_plus platform channel', () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var channelInvocations = 0;
      messenger.setMockMethodCallHandler(_deviceInfoChannel, (
        MethodCall call,
      ) async {
        channelInvocations++;
        return <String, dynamic>{};
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(_deviceInfoChannel, null),
      );

      final reader = _FakeDeviceInfoReader(_ios(machine: 'iPhone17,1'));
      final service = DeviceInfoPlusHardwareDetectionService(reader: reader);
      final capability = await service.getDeviceCapability();

      expect(capability.platform, 'ios');
      expect(capability.supportedAbis, ['arm64']);
      expect(channelInvocations, 0);
      expect(reader.readCalls, 1);
    });
  });
}

/// Fake [IDeviceInfoReader] returning a fixed object, counting reads, and
/// (in the failing variant) throwing instead of returning.
class _FakeDeviceInfoReader implements IDeviceInfoReader {
  _FakeDeviceInfoReader(Object result) : _result = result, _failure = null;

  _FakeDeviceInfoReader.failure(Object failure)
    : _result = null,
      _failure = failure;

  final Object? _result;
  final Object? _failure;
  int readCalls = 0;

  @override
  Future<Object> read() async {
    readCalls++;
    final failure = _failure;
    if (failure != null) {
      throw failure;
    }
    return _result!;
  }
}

/// Typed Android fixture built with device_info_plus' testing constructor.
AndroidDeviceInfo _android({
  String release = '14',
  bool isPhysicalDevice = true,
  List<String> supportedAbis = const ['arm64-v8a', 'armeabi-v7a'],
  int physicalRamSizeMb = 4096,
  int freeDiskBytes = 107374182400,
}) {
  return AndroidDeviceInfo.setMockInitialValues(
    version: AndroidBuildVersion.setMockInitialValues(
      baseOS: 'REL',
      codename: 'REL',
      incremental: 'A05SXX',
      previewSdkInt: 0,
      release: release,
      sdkInt: 34,
      securityPatch: '2024-06-01',
    ),
    board: 'board',
    bootloader: 'bootloader',
    brand: 'samsung',
    device: 'a05s',
    display: 'display',
    fingerprint: 'fingerprint',
    hardware: 'hardware',
    host: 'host',
    id: 'id',
    manufacturer: 'samsung',
    model: 'SM-A057F',
    product: 'a05s',
    name: 'Galaxy A05s',
    supported32BitAbis: const ['armeabi-v7a'],
    supported64BitAbis: const ['arm64-v8a'],
    supportedAbis: supportedAbis,
    tags: 'release-keys',
    type: 'user',
    isPhysicalDevice: isPhysicalDevice,
    freeDiskSize: freeDiskBytes,
    totalDiskSize: freeDiskBytes + 1024,
    systemFeatures: const <String>[],
    isLowRamDevice: false,
    physicalRamSize: physicalRamSizeMb,
    availableRamSize: physicalRamSizeMb,
  );
}

/// Typed iOS fixture built with device_info_plus' testing constructors.
IosDeviceInfo _ios({
  String systemVersion = '18.1',
  bool isPhysicalDevice = true,
  String machine = 'iPhone17,1',
  int physicalRamSizeMb = 8192,
  int freeDiskBytes = 107374182400,
}) {
  return IosDeviceInfo.setMockInitialValues(
    name: 'Test iPhone',
    systemName: 'iOS',
    systemVersion: systemVersion,
    model: 'iPhone',
    modelName: 'iPhone 17 Pro',
    localizedModel: 'iPhone',
    identifierForVendor: '00000000-0000-0000-0000-000000000000',
    freeDiskSize: freeDiskBytes,
    totalDiskSize: freeDiskBytes + 1024,
    isPhysicalDevice: isPhysicalDevice,
    isiOSAppOnMac: false,
    isiOSAppOnVision: false,
    physicalRamSize: physicalRamSizeMb,
    availableRamSize: physicalRamSizeMb,
    utsname: IosUtsname.setMockInitialValues(
      sysname: 'Darwin',
      nodename: 'localhost',
      release: '24.1.0',
      version: 'Darwin Kernel Version 24.1.0',
      machine: machine,
    ),
  );
}
