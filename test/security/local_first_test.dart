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
    await _removeFixture(support);
  });
  registerLocalFirstScenarios(
    supportPathResolver: () async => support.path,
    readRecord: (account) => File(
      '${support.path}/accounts/${LocalSyncAccountNamespace(account).hash}/local_sync_state.json',
    ).readAsString(),
  );
}

Future<void> _removeFixture(Directory support) async {
  final resolved = Directory(await support.resolveSymbolicLinks());
  final root = Directory(await Directory.systemTemp.resolveSymbolicLinks());
  final name = resolved.path.split(RegExp(r'[/\\]')).last;
  if (resolved.parent.path.toLowerCase() != root.path.toLowerCase() ||
      !name.startsWith('m05_local_first_vm_')) {
    throw StateError('Refusing to remove a non-fixture directory.');
  }
  for (var attempt = 0; ; attempt++) {
    try {
      await resolved.delete(recursive: true);
      return;
    } on FileSystemException catch (error) {
      if (!Platform.isWindows ||
          error.osError?.errorCode != 32 ||
          attempt >= 5) {
        rethrow;
      }
      // Allow a transient Windows file handle to close; other errors still fail.
      await Future<void>.delayed(Duration(milliseconds: 80 * (attempt + 1)));
    }
  }
}
