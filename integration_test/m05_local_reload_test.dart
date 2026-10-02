import 'package:flutter/foundation.dart';
import 'package:note_ai_app/application/notes/note_security_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store.dart';

import '../test/security/local_first_scenarios.dart';
import '../test/security/reload_probe.dart';
import '../test/security/security_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final phase = Uri.base.queryParameters['phase'];
  final account = Uri.base.queryParameters['account'] ?? '';
  test('real Chrome offline $phase phase across full page reload', () async {
    expect(kIsWeb, true);
    expect(RegExp(r'^m05-reload-[0-9]+$').hasMatch(account), true);
    await waitForOfflineProbe();
    final store =
        createLocalSyncStore(accountUserId: account) as EncryptedSyncStore;
    final service = localService(account, store);
    addTearDown(() {
      service.dispose();
      store.dispose();
    });
    if (phase == 'seed') {
      expect((await store.read()).notes, isEmpty);
      await store.replace(unsynced(account));
      await service.enable('alpha', securityPassword, securityPassword);
      expect(
        (await store.read()).outbox.single.protectionChange!.after.revision,
        1,
      );
    } else {
      expect(phase, 'reload');
      final initial = await store.read();
      expect(initial.notes.first.contentAvailable, false);
      expect(initial.outbox.single.mutationId, 'local-create');
      await expectLater(
        service.unlock('alpha', 'incorrect-password', offline: true),
        throwsException,
      );
      await service.unlock('alpha', securityPassword, offline: true);
      await service.changePassword(
        'alpha',
        securityPassword,
        'after-reload-password',
        'after-reload-password',
      );
      service.lock('alpha');
      await service.unlock('alpha', 'after-reload-password', offline: true);
      await service.disable('alpha', 'after-reload-password');
      final end = await store.read();
      expect(end.notes.first.content, privateBody);
      expect(end.notes.first.protection.enabled, false);
      expect(end.outbox.single.mutationId, 'local-create');
      expect(end.outbox.single.protectionChange!.after.revision, 3);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
