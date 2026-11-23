import 'package:integration_test/integration_test.dart';

import '../test/security/m09_platform_document_scenarios.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerM09PlatformDocumentScenarios();
}
