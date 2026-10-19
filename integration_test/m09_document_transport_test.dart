import 'package:integration_test/integration_test.dart';

import '../test/security/m09_local_transport_scenarios.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerM09LocalTransportScenarios(realPlatform: true);
}
