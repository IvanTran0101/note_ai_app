@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/infrastructure/device/device_info_plus_hardware_detection.dart';

void main() {
  test('Web fails explicitly instead of inventing native model capabilities', () {
    expect(
      () => const DeviceInfoPlusHardwareDetectionService().getDeviceCapability(),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
