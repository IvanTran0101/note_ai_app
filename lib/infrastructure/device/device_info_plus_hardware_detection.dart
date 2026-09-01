/// Public entrypoint for the plugin-first hardware detection adapter.
///
/// Native targets use the `device_info_plus` implementation. Web receives a
/// matching stub that rejects local hardware detection without importing
/// `dart:io` or the native plugin implementation.
library;

export 'device_info_plus_hardware_detection_contract.dart';

export 'device_info_plus_hardware_detection_stub.dart'
    if (dart.library.io) 'device_info_plus_hardware_detection_io.dart';
