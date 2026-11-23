import 'dart:js_interop';

@JS('m05TestProceed')
external JSBoolean? get _proceed;

/// Test-only gate: Chrome disables network before allowing local operations.
Future<void> waitForOfflineProbe() async {
  for (var i = 0; i < 1200; i++) {
    if (_proceed?.toDart == true) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('Offline browser probe was not started.');
}
