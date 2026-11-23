import 'package:integration_test/integration_test.dart';

import '../test/security/encrypted_store_scenarios.dart';
import '../test/security/security_ui_scenarios.dart';
import '../test/security/platform_store_scenarios.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Real device key custody; unique synthetic namespaces, no user data reset.
  registerEncryptedStoreScenarios();
  registerPlatformStoreScenarios();
  registerSecurityUiScenarios();
}
