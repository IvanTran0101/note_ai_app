// Pure contract tests for the M3.1 hardware-detection contract.
//
// These tests exercise only the platform-neutral DeviceCapability value
// object and the IHardwareDetectionService contract. They never call
// device_info_plus, a platform channel, or any Flutter binding, so they
// run in a plain Dart test environment.

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/infrastructure/device/hardware_detection.dart';

const _sample = DeviceCapability(
  platform: 'ios',
  osVersion: '17.6',
  isPhysicalDevice: true,
  supportedAbis: ['arm64'],
  totalMemoryBytes: 8589934592,
  freeStorageBytes: 107374182400,
);

void main() {
  group('DeviceCapability construction', () {
    test('exposes all six required fields exactly as provided', () {
      expect(_sample.platform, 'ios');
      expect(_sample.osVersion, '17.6');
      expect(_sample.isPhysicalDevice, isTrue);
      expect(_sample.supportedAbis, ['arm64']);
      expect(_sample.totalMemoryBytes, 8589934592);
      expect(_sample.freeStorageBytes, 107374182400);
    });

    test('is const-constructible, so every field is final and required', () {
      const capability = DeviceCapability(
        platform: 'android',
        osVersion: '14',
        isPhysicalDevice: false,
        supportedAbis: ['arm64-v8a', 'armeabi-v7a'],
        totalMemoryBytes: 6442450944,
        freeStorageBytes: 53687091200,
      );
      expect(capability.platform, 'android');
      expect(capability.osVersion, '14');
      expect(capability.isPhysicalDevice, isFalse);
      expect(capability.supportedAbis, ['arm64-v8a', 'armeabi-v7a']);
      expect(capability.totalMemoryBytes, 6442450944);
      expect(capability.freeStorageBytes, 53687091200);
    });

    test('supports an emulator snapshot with an empty ABI list', () {
      const emulator = DeviceCapability(
        platform: 'ios',
        osVersion: '17.6',
        isPhysicalDevice: false,
        supportedAbis: <String>[],
        totalMemoryBytes: 8589934592,
        freeStorageBytes: 107374182400,
      );
      expect(emulator.isPhysicalDevice, isFalse);
      expect(emulator.supportedAbis, isEmpty);
    });
  });

  group('DeviceCapability equality and props', () {
    test('is equal and hash-equal to a value with identical fields', () {
      const same = DeviceCapability(
        platform: 'ios',
        osVersion: '17.6',
        isPhysicalDevice: true,
        supportedAbis: ['arm64'],
        totalMemoryBytes: 8589934592,
        freeStorageBytes: 107374182400,
      );
      expect(same, equals(_sample));
      expect(same.hashCode, _sample.hashCode);
    });

    test('is not equal to a non-DeviceCapability value', () {
      // Object is a supertype, so this comparison is well-typed yet still
      // exercises our operator== (which requires `other is DeviceCapability`).
      expect(_sample == Object(), isFalse);
      expect(_sample, isNotNull);
    });

    test('differs when any single field differs', () {
      DeviceCapability vary({
        String platform = 'ios',
        String osVersion = '17.6',
        bool isPhysicalDevice = true,
        List<String> supportedAbis = const ['arm64'],
        int totalMemoryBytes = 8589934592,
        int freeStorageBytes = 107374182400,
      }) {
        return DeviceCapability(
          platform: platform,
          osVersion: osVersion,
          isPhysicalDevice: isPhysicalDevice,
          supportedAbis: supportedAbis,
          totalMemoryBytes: totalMemoryBytes,
          freeStorageBytes: freeStorageBytes,
        );
      }

      expect(vary(platform: 'android'), isNot(equals(_sample)));
      expect(vary(osVersion: '16.0'), isNot(equals(_sample)));
      expect(vary(isPhysicalDevice: false), isNot(equals(_sample)));
      expect(vary(supportedAbis: ['arm64', 'x86_64']), isNot(equals(_sample)));
      expect(vary(totalMemoryBytes: 1), isNot(equals(_sample)));
      expect(vary(freeStorageBytes: 1), isNot(equals(_sample)));
    });

    test('compares supportedAbis by content and order, not identity', () {
      final equalContent = <String>['arm64'];
      expect(
        _sample ==
            DeviceCapability(
              platform: 'ios',
              osVersion: '17.6',
              isPhysicalDevice: true,
              supportedAbis: equalContent,
              totalMemoryBytes: 8589934592,
              freeStorageBytes: 107374182400,
            ),
        isTrue,
      );

      expect(
        _sample ==
            DeviceCapability(
              platform: 'ios',
              osVersion: '17.6',
              isPhysicalDevice: true,
              supportedAbis: const <String>[],
              totalMemoryBytes: 8589934592,
              freeStorageBytes: 107374182400,
            ),
        isFalse,
      );

      expect(
        _sample ==
            DeviceCapability(
              platform: 'ios',
              osVersion: '17.6',
              isPhysicalDevice: true,
              supportedAbis: const ['x86_64', 'arm64'],
              totalMemoryBytes: 8589934592,
              freeStorageBytes: 107374182400,
            ),
        isFalse,
      );
    });
  });

  group('IHardwareDetectionService contract', () {
    test(
      'is implementable with a plugin-free fake returning a capability',
      () async {
        final service = _FakeDetectionService(_sample);

        final capability = await service.getDeviceCapability();

        expect(capability, equals(_sample));
        expect(capability.platform, 'ios');
      },
    );

    test(
      'surfaces a capability with different values through the contract',
      () async {
        const other = DeviceCapability(
          platform: 'android',
          osVersion: '14',
          isPhysicalDevice: true,
          supportedAbis: ['arm64-v8a'],
          totalMemoryBytes: 6442450944,
          freeStorageBytes: 53687091200,
        );
        final service = _FakeDetectionService(other);

        final capability = await service.getDeviceCapability();

        expect(capability, equals(other));
        expect(capability, isNot(equals(_sample)));
      },
    );
  });
}

/// Minimal contract-only fake: no plugin, no platform channel.
class _FakeDetectionService implements IHardwareDetectionService {
  _FakeDetectionService(this.capability);

  final DeviceCapability capability;

  @override
  Future<DeviceCapability> getDeviceCapability() async => capability;
}
