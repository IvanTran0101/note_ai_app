import 'package:integration_test/integration_test.dart';

import '../test/sharing/realtime_protocol_test.dart' as protocol;
import '../test/sharing/realtime_cursor_test.dart' as cursor;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  protocol.main();
  cursor.main();
}
