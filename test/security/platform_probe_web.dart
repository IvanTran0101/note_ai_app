import 'dart:js_interop';

import 'package:indexed_db/indexed_db.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store_account_namespace.dart';

Future<Database> _database(String account) async {
  final name = LocalSyncAccountNamespace(account).webDatabaseName;
  final current = await IdbFactory().open(name);
  if ((current.objectStoreNames ?? []).contains('local_sync_state')) {
    return current;
  }
  final version = current.version! + 1;
  current.close();
  return IdbFactory().open(
    name,
    version: version,
    onUpgradeNeeded: (event) {
      event.target.database.createObjectStore('local_sync_state');
    },
  );
}

Future<String> readPlatformRecord(String account) async {
  final db = await _database(account);
  try {
    final tx = db.transactionList(['local_sync_state'], 'readonly');
    final value = await tx
        .objectStore('local_sync_state')
        .getObject('state'.toJS);
    await tx.completed;
    return value is String ? value : (value as JSString).toDart;
  } finally {
    db.close();
  }
}

Future<void> writeLegacyPlatformRecord(String account, String value) async {
  final db = await _database(account);
  try {
    final tx = db.transactionList(['local_sync_state'], 'readwrite');
    await tx.objectStore('local_sync_state').put(value.toJS, 'state'.toJS);
    await tx.completed;
  } finally {
    db.close();
  }
}

Future<List<String>> readControlledRecords(String account) async => [
  await readPlatformRecord(account),
];
