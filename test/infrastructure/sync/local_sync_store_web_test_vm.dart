/// Dart VM branch of the Web local sync store test shell.
///
/// There is no IndexedDB on the VM, so the browser suite cannot compile here.
/// This branch keeps `flutter test` honest: it declares one intentionally
/// skipped test naming the exact browser command that runs the real suite.
library;

import 'package:flutter_test/flutter_test.dart';

/// Registers the Web suite placeholder on a host without IndexedDB.
void runLocalSyncStoreWebTests() {
  test(
    'IndexedDB local sync store requires a browser runner',
    () {
      fail(
        'unreachable: run the Web suite with '
        'flutter test --platform chrome',
      );
    },
    skip:
        'IndexedDB needs a browser: flutter test --platform chrome '
        'test/infrastructure/sync/local_sync_store_web_test.dart',
  );
}
