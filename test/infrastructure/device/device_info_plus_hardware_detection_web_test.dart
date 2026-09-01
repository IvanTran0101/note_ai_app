// Verifies the conditional Web surface without importing native plugin models.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/infrastructure/device/device_info_plus_hardware_detection.dart';
import 'package:note_ai_app/infrastructure/device/hardware_detection.dart';

void main() {
  test('Web hardware detection uses the unavailable stub', () {
    if (!kIsWeb) {
      return;
    }

    final IHardwareDetectionService service =
        createHardwareDetectionService();

    expect(
      () => service.getDeviceCapability(),
      throwsUnsupportedError,
    );
  });
}
