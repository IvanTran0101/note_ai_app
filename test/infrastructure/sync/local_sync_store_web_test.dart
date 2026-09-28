/// Web local sync store tests, routed by platform.
///
/// The Dart VM has no IndexedDB, so the default branch registers a skipped test
/// that names the browser command. Under `flutter test --platform chrome` the
/// `dart.library.js_interop` branch compiles the real IndexedDB suite:
///
/// ```bash
/// flutter test --platform chrome \
///   test/infrastructure/sync/local_sync_store_web_test.dart
/// ```
library;

import 'local_sync_store_web_test_vm.dart'
    if (dart.library.js_interop) 'local_sync_store_web_test_browser.dart';

void main() => runLocalSyncStoreWebTests();
