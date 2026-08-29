// This is a command-line smoke check; stdout is its intentional output.
// ignore_for_file: avoid_print

// Web compile smoke check.
//
// Compiling this file to JavaScript proves that the public entrypoint
// (`local_llm_bridge.dart`) resolves to the Web-safe stub on platforms
// without `dart:ffi` — no `dart:ffi` import leaks into the Web
// implementation, and the package still compiles for the Web.
//
// Run: dart compile js tool/web_smoke_check.dart -o /tmp/web_smoke_check.js
// Expected output: `web stub OK: ...` and exit code 0.
import 'package:local_llm_bridge/local_llm_bridge.dart';

void main() {
  try {
    localLlmBridgeSmokeVersion();
  } on UnsupportedError catch (e) {
    print('web stub OK: ${e.message}');
    return;
  }
  print('ERROR: expected UnsupportedError on the Web');
}
