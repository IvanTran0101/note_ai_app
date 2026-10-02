import 'package:integration_test/integration_test.dart';

import '../test/security/local_first_scenarios.dart';
import '../test/security/security_ui_scenarios.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerLocalFirstScenarios();
  registerSecurityUiScenarios(includeLocalFirst: true);
}
