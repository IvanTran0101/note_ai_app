import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store_account_namespace.dart';

Future<File> _file(String account) async {
  final root = (await getApplicationSupportDirectory()).path;
  final hash = LocalSyncAccountNamespace(account).hash;
  return File('$root/accounts/$hash/local_sync_state.json');
}

Future<String> readPlatformRecord(String account) async =>
    (await _file(account)).readAsString();
Future<void> writeLegacyPlatformRecord(String account, String value) async {
  final file = await _file(account);
  await file.parent.create(recursive: true);
  await file.writeAsString(value, flush: true);
  await File('${file.path}.tmp-synthetic-migration')
      .writeAsString(value, flush: true);
}

Future<List<String>> readControlledRecords(String account) async {
  final file = await _file(account);
  final values = <String>[];
  await for (final entry in file.parent.list(followLinks: false)) {
    if (entry is File &&
        entry.path.startsWith(file.path) &&
        !entry.path.endsWith('.lock')) {
      values.add(await entry.readAsString());
    }
  }
  return values;
}
