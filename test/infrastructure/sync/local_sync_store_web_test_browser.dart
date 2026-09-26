/// IndexedDB branch of the Web local sync store test suite.
///
/// Compiled only under `flutter test --platform chrome`; it imports the Web
/// store and `package:indexed_db` directly, so it must never be imported by a
/// VM-compiled library. Every test uses its own account id, which gives it its
/// own database and keeps tests independent inside one browser profile.
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:indexed_db/indexed_db.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/local_sync_store.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_cursor.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_codec_schema.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_state_codec.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store_account_namespace.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store_contract.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store_web.dart';

import 'local_sync_codec_fixtures.dart';

/// The one object store and record key the Web adapter owns.
const String _storeName = 'local_sync_state';
const String _recordKey = 'state';

/// The account of [richStateFixture].
const String _richAccount = 'user-1';

ILocalSyncStore _storeFor(String accountUserId) =>
    createLocalSyncStore(accountUserId: accountUserId);

/// One account state with a single note and no outbox.
LocalSyncState _stateFor(String accountUserId, {String noteId = 'note-1'}) {
  return LocalSyncState(
    accountUserId: accountUserId,
    notes: <LocalNoteState>[noteFixture(id: noteId, ownerId: accountUserId)],
  );
}

/// Opens the account's own database, mirroring the adapter's fixed schema.
Future<Database> _openAccountDatabase(String accountUserId) {
  return IdbFactory().open(
    LocalSyncAccountNamespace(accountUserId).webDatabaseName,
    version: 1,
    onUpgradeNeeded: (VersionChangeEvent event) {
      final Database database = event.target.database;
      final List<String> stores = database.objectStoreNames ?? const <String>[];
      if (!stores.contains(_storeName)) {
        database.createObjectStore(_storeName);
      }
    },
  );
}

/// Opens a transaction over the one envelope store.
///
/// Mirrors the adapter: the store name is converted through
/// `transactionList`, because the string convenience method forwards a Dart
/// string through a `dynamic` parameter that the Wasm backend cannot cast.
Transaction _transaction(Database database, String mode) {
  return database.transactionList(<String>[_storeName], mode);
}

/// The raw record an account database holds under the single envelope key.
Future<Object?> _readRawRecord(String accountUserId) async {
  final Database database = await _openAccountDatabase(accountUserId);
  try {
    final Transaction transaction = _transaction(database, 'readonly');
    final Object? value = await transaction
        .objectStore(_storeName)
        .getObject(_recordKey.toJS);
    await transaction.completed;
    return value;
  } finally {
    database.close();
  }
}

/// Writes one raw record, so a test can present a document the adapter did not
/// produce.
Future<void> _writeRawRecord(String accountUserId, Object? value) async {
  final Database database = await _openAccountDatabase(accountUserId);
  try {
    final Transaction transaction = _transaction(database, 'readwrite');
    final String encoded = value is String ? value : jsonEncode(value);
    await transaction
        .objectStore(_storeName)
        .put(encoded.toJS, _recordKey.toJS);
    await transaction.completed;
  } finally {
    database.close();
  }
}

/// The JSON text of a raw record, which is a JavaScript string on Wasm.
String _jsonText(Object record) {
  if (record is String) {
    return record;
  }
  if (record.isA<JSString>()) {
    return (record as JSString).toDart;
  }
  fail('the raw record is not JSON text');
}

Matcher _storeError(LocalSyncStoreFailure failure, String fragment) {
  return throwsA(
    isA<LocalSyncStoreException>()
        .having(
          (LocalSyncStoreException error) => error.failure,
          'failure',
          failure,
        )
        .having(
          (LocalSyncStoreException error) => error.toString(),
          'message',
          contains(fragment),
        ),
  );
}

/// Asserts that a store failure carries none of the stored document's values.
void _expectNoLeakage(Object error, String accountUserId) {
  final String text = error.toString();
  for (final String forbidden in <String>[
    accountUserId,
    LocalSyncAccountNamespace(accountUserId).webDatabaseName,
    secretTitle,
    secretContent,
    secretCursor,
    fixturePayloadTitle,
    fixturePayloadContent,
  ]) {
    expect(
      text,
      isNot(contains(forbidden)),
      reason: 'a store failure must not leak "$forbidden"',
    );
  }
}

void runLocalSyncStoreWebTests() {
  group('Web IndexedDbLocalSyncStore', () {
    test('reads an empty bound state when the account has no record', () async {
      const String account = 'web-empty-account';
      final ILocalSyncStore store = _storeFor(account);

      final LocalSyncState state = await store.read();

      expect(state.accountUserId, account);
      expect(state.isEmpty, isTrue);
      expect(state.notes, isEmpty);
      expect(state.outbox, isEmpty);
      expect(state.conflicts, isEmpty);
      expect(state.cursor, isNull);
    });

    test(
      'serializes concurrent read-modify-write IndexedDB transactions',
      () async {
        const String account = 'web-atomic-update-account';
        final ILocalSyncStore store = _storeFor(account);
        await Future.wait(<Future<LocalSyncState>>[
          for (final String id in <String>['note-a', 'note-b'])
            store.update((LocalSyncState current) {
              return LocalSyncState(
                accountUserId: account,
                notes: <LocalNoteState>[
                  ...current.notes,
                  noteFixture(id: id, ownerId: account),
                ],
                outbox: current.outbox,
                conflicts: current.conflicts,
                cursor: current.cursor,
              );
            }),
        ]);

        expect(
          (await store.read()).notes.map((LocalNoteState note) => note.id),
          containsAll(<String>['note-a', 'note-b']),
        );
      },
    );

    test('round-trips the whole envelope as one committed record', () async {
      final ILocalSyncStore store = _storeFor(_richAccount);
      final LocalSyncState state = richStateFixture();

      await store.replace(state);

      expect(await store.read(), state);

      final Object? record = await _readRawRecord(_richAccount);
      expect(record, isNotNull);
      final Map<Object?, Object?> decoded =
          (jsonDecode(_jsonText(record!)) as Map).cast<Object?, Object?>();
      expect(decoded.keys.toSet(), LocalSyncSchema.envelopeFields);
      expect(decoded[LocalSyncSchema.accountUserId], _richAccount);
      expect(decoded[LocalSyncSchema.notes], hasLength(state.notes.length));
      expect(decoded[LocalSyncSchema.outbox], hasLength(state.outbox.length));
      expect(
        decoded[LocalSyncSchema.conflicts],
        hasLength(state.conflicts.length),
      );
      expect(decoded[LocalSyncSchema.cursor], isNotNull);
    });

    test(
      'isolates accounts and rejects foreign replacements and updates',
      () async {
        const String account = 'web-account-a';
        const String otherAccount = 'web-account-b';
        final ILocalSyncStore store = _storeFor(account);
        final ILocalSyncStore otherStore = _storeFor(otherAccount);
        final LocalSyncState state = _stateFor(account, noteId: 'note-a');
        final LocalSyncState otherState = _stateFor(
          otherAccount,
          noteId: 'note-b',
        );

        await store.replace(state);
        expect(
          await otherStore.read(),
          LocalSyncState(accountUserId: otherAccount),
        );
        await otherStore.replace(otherState);

        expect(await store.read(), state);
        expect(await otherStore.read(), otherState);

        await expectLater(
          store.replace(otherState),
          _storeError(
            LocalSyncStoreFailure.foreignAccount,
            'belongs to a different account',
          ),
        );
        await expectLater(
          store.update((LocalSyncState _) => otherState),
          _storeError(
            LocalSyncStoreFailure.foreignAccount,
            'belongs to a different account',
          ),
        );
        expect(await store.read(), state);

        for (final String name in <String>[
          LocalSyncAccountNamespace(account).webDatabaseName,
          LocalSyncAccountNamespace(otherAccount).webDatabaseName,
        ]) {
          expect(name, isNot(contains(account)));
          expect(name, isNot(contains(otherAccount)));
        }
      },
    );

    test('strictly decodes an existing record and never repairs it', () async {
      const String account = 'web-malformed-account';
      final ILocalSyncStore store = _storeFor(account);

      await _writeRawRecord(account, <String, Object?>{
        'schemaVersion': 2,
        'accountUserId': account,
        'notes': 'not-a-list',
        'outbox': <Object?>[],
        'cursor': null,
        'conflicts': <Object?>[],
      });
      await expectLater(
        store.read(),
        _storeError(LocalSyncStoreFailure.malformed, 'M2 schema'),
      );
      expect(await _readRawRecord(account), isNotNull);

      await _writeRawRecord(account, 'not-an-envelope');
      await expectLater(
        store.read(),
        _storeError(LocalSyncStoreFailure.malformed, 'M2 schema'),
      );

      // A secret-carrying envelope that is corrupt in an unrelated field.
      final Map<String, Object?> secretEnvelope = LocalSyncStateCodec.encode(
        LocalSyncState(
          accountUserId: account,
          notes: <LocalNoteState>[
            noteFixture(
              ownerId: account,
              title: secretTitle,
              content: secretContent,
            ),
          ],
          outbox: <PendingMutation>[mutationFixture()],
          cursor: const SyncCursor(secretCursor),
        ),
      )..remove('conflicts');
      await _writeRawRecord(account, secretEnvelope);
      try {
        await store.read();
        fail('expected a LocalSyncStoreException');
      } on LocalSyncStoreException catch (error) {
        expect(error.failure, LocalSyncStoreFailure.malformed);
        _expectNoLeakage(error, account);
      }
      expect(await _readRawRecord(account), isNotNull);

      await _writeRawRecord(
        account,
        LocalSyncStateCodec.encode(_stateFor('web-other-account')),
      );
      await expectLater(
        store.read(),
        _storeError(LocalSyncStoreFailure.foreignAccount, 'different account'),
      );
    });

    test('serializes concurrent replacements and reads', () async {
      const String account = 'web-concurrent-account';
      final ILocalSyncStore store = _storeFor(account);
      final List<Future<void>> writes = <Future<void>>[];
      final List<Future<LocalSyncState>> reads = <Future<LocalSyncState>>[];

      for (int index = 0; index < 5; index++) {
        reads.add(store.read());
        writes.add(store.replace(_stateFor(account, noteId: 'note-$index')));
      }

      await Future.wait(writes);
      final List<LocalSyncState> observed = await Future.wait(reads);

      for (final LocalSyncState state in observed) {
        // Every read observed one complete document, never a partial state.
        expect(state.accountUserId, account);
        expect(state.notes.length, lessThanOrEqualTo(1));
        expect(state.outbox, isEmpty);
        expect(state.conflicts, isEmpty);
        expect(state.cursor, isNull);
      }
      expect((await store.read()).notes.single.id, 'note-4');
    });
  });
}
