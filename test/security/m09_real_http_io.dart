import 'dart:io';

import 'package:note_ai_app/dev/m06_local_connection.dart';

final class _RealLoopbackHttp extends HttpOverrides {}

/// Explicit real local network; never inherited Flutter test HTTP mocks.
M06LoopbackClient realLoopbackClient() => HttpOverrides.runWithHttpOverrides(
  () => M06LoopbackClient(),
  _RealLoopbackHttp(),
);
