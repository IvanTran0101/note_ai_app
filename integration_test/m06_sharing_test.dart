import 'package:integration_test/integration_test.dart';

import '../test/domain/notes/note_sharing_test.dart' as domain;
import '../test/application/sync/shared_projection_test.dart' as projection;
import '../test/security/shared_store_scenarios.dart';
import '../test/security/legacy_pair_binding_scenarios.dart';
import '../test/security/shared_editor_evidence_scenarios.dart';
import '../test/sharing/m06_application_test.dart' as sharing_application;
import '../test/sharing/editor_snapshot_test.dart' as editor_snapshot;
import '../test/application/sync/shared_coordinator_test.dart' as sharing_sync;
import '../test/application/sync/sync_coordinator_service_test.dart'
    as coordinator;
import '../test/application/sync/sync_conflict_resolver_test.dart' as conflicts;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  domain.main();
  projection.main();
  sharing_sync.main();
  coordinator.main();
  conflicts.main();
  sharing_application.main();
  editor_snapshot.main();
  // Real secure storage + platform backing, unique synthetic namespaces.
  registerSharedStoreScenarios();
  registerLegacyPairBindingScenarios();
  registerEditorEvidenceScenarios();
}
