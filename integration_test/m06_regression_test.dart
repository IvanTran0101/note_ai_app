import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'm05_local_first_test.dart' as local_first;
import 'm05_security_test.dart' as security;
import 'm06_realtime_test.dart' as realtime;
import 'm06_sharing_test.dart' as sharing;

/// Run the original scenario registrations with real platform storage plugins.
/// Group boundaries keep each suite's setup/teardown scoped to its scenarios.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('M05 security regression', security.main);
  group('M05 local-first regression', local_first.main);
  group('M06 sharing regression', sharing.main);
  group('M06 realtime regression', realtime.main);
}
