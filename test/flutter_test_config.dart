import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (kIsWeb) {
    final previous = reportTestException;
    reportTestException = (details, description) {
      // The Chrome framework console is separate from this SDK's host reporter.
      // All test credentials/data are synthetic; retain normal failure handling.
      // ignore: avoid_print
      print(details.toString());
      previous(details, description);
    };
  }
  await testMain();
}
