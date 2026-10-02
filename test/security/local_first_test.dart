@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store_account_namespace.dart';

import 'local_first_scenarios.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    support = await Directory.systemTemp.createTemp('m05_local_first_vm_');
  });
  tearDown(() async {
    // Only the fixture directory returned by createTemp is removed.
    await support.delete(recursive: true);
  });
  registerLocalFirstScenarios(
    supportPathResolver: () async => support.path,
    readRecord: (account) => File(
      '${support.path}/accounts/${LocalSyncAccountNamespace(account).hash}/local_sync_state.json',
    ).readAsString(),
  );
}
