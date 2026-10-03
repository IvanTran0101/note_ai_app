@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_cursor.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_state_codec.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store_account_namespace.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store_io.dart'
    as native;
import 'package:note_ai_app/infrastructure/sync/local_sync_store_stub.dart'
    as stub;

import 'local_sync_codec_fixtures.dart';

const String _account = 'user-1';
const String _otherAccount = 'user-2';
const String _stateFileName = 'local_sync_state.json';

/// Builds one account state with a single note and no outbox.
LocalSyncState _stateFor(String accountUserId, {String noteId = 'note-1'}) {
  return LocalSyncState(
    accountUserId: accountUserId,
    notes: <LocalNoteState>[noteFixture(id: noteId, ownerId: accountUserId)],
  );
}

typedef _Fixture = ({
  Directory supportDirectory,
  native.FileLocalSyncStore store,
});

Future<Directory> _supportDirectory() async {
  final Directory directory = await Directory.systemTemp.createTemp(
    'local_sync_store_test_',
  );
  addTearDown(() async {
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });
  return directory;
}

/// A native store over a fresh temporary support directory, deleted at the end.
Future<_Fixture> _newFixture({String accountUserId = _account}) async {
  final Directory directory = await _supportDirectory();
  return (
    supportDirectory: directory,
    store: native.FileLocalSyncStore(
      accountUserId: accountUserId,
      applicationSupportPathResolver: () async => directory.path,
    ),
  );
}

String _separator() => Platform.pathSeparator;

Directory _namespaceDirectory(Directory support, String accountUserId) {
  return Directory(
    '${support.path}${_separator()}'
    '${LocalSyncAccountNamespace.accountsDirectoryName}${_separator()}'
    '${LocalSyncAccountNamespace(accountUserId).hash}',
  );
}

File _stateFile(Directory support, String accountUserId) {
  return File(
    '${_namespaceDirectory(support, accountUserId).path}'
    '${_separator()}$_stateFileName',
  );
}

/// Every stored file under [support], relative to it, for name assertions.
List<String> _relativePaths(Directory support) {
  if (!support.existsSync()) {
    return const <String>[];
  }
  final String prefix = '${support.path}${_separator()}';
  return support
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => !file.path.endsWith('.lock'))
      .map((File file) => file.path.replaceFirst(prefix, ''))
      .toList(growable: false);
}

/// Temporary files this store could have issued under the account namespace.
Future<List<FileSystemEntity>> _temporaryResidue(Directory support) async {
  final Directory namespaceDirectory = _namespaceDirectory(support, _account);
  if (!namespaceDirectory.existsSync()) {
    return const <FileSystemEntity>[];
  }
  return namespaceDirectory
      .list()
      .where(
        (FileSystemEntity entity) =>
            entity.path.contains('${_separator()}$_stateFileName.tmp-'),
      )
      .toList();
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
void _expectNoLeakage(Object error, Directory support) {
  final String text = error.toString();
  for (final String forbidden in <String>[
    _account,
    _otherAccount,
    support.path,
    'local_sync_store_test_',
    _stateFileName,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  group('LocalSyncAccountNamespace', () {
    test('derives one stable hash per account and no raw id in a name', () {
      final LocalSyncAccountNamespace namespace = LocalSyncAccountNamespace(
        _account,
      );
      final LocalSyncAccountNamespace repeated = LocalSyncAccountNamespace(
        'user-1',
      );
      final LocalSyncAccountNamespace other = LocalSyncAccountNamespace(
        _otherAccount,
      );

      // The namespace is the plain SHA-256 of the account id, so anyone can
      // recompute an account's backing-store name without this library.
      expect(namespace.hash, sha256.convert(utf8.encode(_account)).toString());
      // Golden digest: changing the digest would orphan stored account state.
      expect(
        namespace.hash,
        'c6c289e49e9c05b2145860387b73bcb18df43fb09a1e4a4a9713c76c88bb541b',
      );
      expect(repeated.hash, namespace.hash);
      expect(other.hash, isNot(namespace.hash));
      expect(LocalSyncAccountNamespace.accountsDirectoryName, 'accounts');
      expect(
        namespace.webDatabaseName,
        'note_ai_app_local_sync_${namespace.hash}',
      );
      for (final String name in <String>[
        LocalSyncAccountNamespace.accountsDirectoryName,
        namespace.hash,
        namespace.webDatabaseName,
      ]) {
        expect(name, isNot(contains(_account)));
      }
    });

    test('rejects a blank account id', () {
      expect(
        () => LocalSyncAccountNamespace('   '),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => native.FileLocalSyncStore(accountUserId: ''),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => createLocalSyncStore(
          accountUserId: ' ',
          applicationSupportPathResolver: () async => 'unused',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a state of another account', () {
      expect(
        () =>
            LocalSyncAccountNamespace(_account)
                .requireOwned(_stateFor(_otherAccount)),
        _storeError(
          LocalSyncStoreFailure.foreignAccount,
          'belongs to a different account',
        ),
      );
    });
  });

  group('native FileLocalSyncStore', () {
    test('reads an empty bound state when nothing is stored', () async {
      final _Fixture fixture = await _newFixture();

      final LocalSyncState state = await fixture.store.read();

      expect(state.accountUserId, _account);
      expect(state.isEmpty, isTrue);
      expect(state.notes, isEmpty);
      expect(state.outbox, isEmpty);
      expect(state.conflicts, isEmpty);
      expect(state.cursor, isNull);
      expect(_relativePaths(fixture.supportDirectory), isEmpty);
    });

    test('serializes concurrent read-modify-write updates', () async {
      final _Fixture fixture = await _newFixture();
      await Future.wait(<Future<LocalSyncState>>[
        for (final String id in <String>['note-a', 'note-b'])
          fixture.store.update((LocalSyncState current) {
            return LocalSyncState(
              accountUserId: _account,
              notes: <LocalNoteState>[
                ...current.notes,
                noteFixture(id: id, ownerId: _account),
              ],
              outbox: current.outbox,
              conflicts: current.conflicts,
              cursor: current.cursor,
            );
          }),
      ]);

      expect(
        (await fixture.store.read()).notes.map(
          (LocalNoteState note) => note.id,
        ),
        containsAll(<String>['note-a', 'note-b']),
      );
    });

    test(
      'a failed update transform leaves the stored document unchanged',
      () async {
        final _Fixture fixture = await _newFixture();
        final LocalSyncState original = _stateFor(_account);
        await fixture.store.replace(original);

        await expectLater(
          fixture.store.update((LocalSyncState _) => throw StateError('stop')),
          throwsStateError,
        );
        expect(await fixture.store.read(), original);
      },
    );

    test(
      'round-trips a rich state through the encrypted schemaVersion 3 envelope',
      () async {
        final _Fixture fixture = await _newFixture();
        final LocalSyncState state = richStateFixture();

        await fixture.store.replace(state);

        expect(await fixture.store.read(), state);
        expect(LocalSyncStateCodec.schemaVersion, 4);
        expect(_relativePaths(fixture.supportDirectory), <String>[
          '${LocalSyncAccountNamespace.accountsDirectoryName}'
              '${_separator()}${LocalSyncAccountNamespace(_account).hash}'
              '${_separator()}$_stateFileName',
        ]);

        final File file = _stateFile(fixture.supportDirectory, _account);
        final raw = await file.readAsString();
        expect((jsonDecode(raw) as Map)['schemaVersion'], 3);
        expect((jsonDecode(raw) as Map)['packet'], isA<Map>());
        for (final secret in [
          secretTitle,
          secretContent,
          secretCursor,
          fixturePayloadTitle,
          fixturePayloadContent,
        ]) {
          expect(raw, isNot(contains(secret)));
        }
        expect(await _temporaryResidue(fixture.supportDirectory), isEmpty);
      },
    );

    test('keeps one namespace per account and no raw id in any path', () async {
      final _Fixture fixture = await _newFixture();
      final native.FileLocalSyncStore otherStore = native.FileLocalSyncStore(
        accountUserId: _otherAccount,
        applicationSupportPathResolver: () async =>
            fixture.supportDirectory.path,
      );

      await fixture.store.replace(_stateFor(_account, noteId: 'note-a'));
      expect(
        await otherStore.read(),
        LocalSyncState(accountUserId: _otherAccount),
      );
      await otherStore.replace(_stateFor(_otherAccount, noteId: 'note-b'));

      expect(await fixture.store.read(), _stateFor(_account, noteId: 'note-a'));
      expect(
        await otherStore.read(),
        _stateFor(_otherAccount, noteId: 'note-b'),
      );

      final List<String> paths = _relativePaths(fixture.supportDirectory);
      expect(paths, hasLength(2));
      for (final String path in paths) {
        // Every account file sits under the one grouping directory, and its
        // only account-derived segment is the SHA-256 digest.
        expect(
          path,
          startsWith(
            '${LocalSyncAccountNamespace.accountsDirectoryName}${_separator()}',
          ),
        );
        expect(path, endsWith('${_separator()}$_stateFileName'));
        expect(path, isNot(contains(_account)));
        expect(path, isNot(contains(_otherAccount)));
      }
      expect(
        paths.where(
          (String path) =>
              path.contains(LocalSyncAccountNamespace(_account).hash),
        ),
        hasLength(1),
      );
      expect(
        paths.where(
          (String path) =>
              path.contains(LocalSyncAccountNamespace(_otherAccount).hash),
        ),
        hasLength(1),
      );
    });

    test(
      'replace and update reject another account state and keep the old one',
      () async {
        final _Fixture fixture = await _newFixture();
        final LocalSyncState stored = richStateFixture();
        await fixture.store.replace(stored);

        await expectLater(
          fixture.store.replace(_stateFor(_otherAccount)),
          _storeError(
            LocalSyncStoreFailure.foreignAccount,
            'belongs to a different account',
          ),
        );
        await expectLater(
          fixture.store.update((LocalSyncState _) => _stateFor(_otherAccount)),
          _storeError(
            LocalSyncStoreFailure.foreignAccount,
            'belongs to a different account',
          ),
        );

        expect(await fixture.store.read(), stored);
      },
    );

    test('reads malformed state as a typed failure without repair', () async {
      final _Fixture fixture = await _newFixture();
      final File file = _stateFile(fixture.supportDirectory, _account);
      await file.parent.create(recursive: true);

      const String notJson = '{"schemaVersion": 2, "notes": [';
      await file.writeAsString(notJson);
      await expectLater(
        fixture.store.read(),
        throwsA(
          isA<NoteSecurityFailure>().having(
            (e) => e.code,
            'code',
            NoteSecurityFailureCode.storage,
          ),
        ),
      );
      expect(await file.readAsString(), notJson);

      final String wrongShape = jsonEncode(<String, Object?>{
        'schemaVersion': 2,
        'accountUserId': _account,
        'notes': 'not-a-list',
        'outbox': <Object?>[],
        'cursor': null,
        'conflicts': <Object?>[],
      });
      await file.writeAsString(wrongShape);
      await expectLater(
        fixture.store.read(),
        throwsA(
          isA<NoteSecurityFailure>().having(
            (e) => e.code,
            'code',
            NoteSecurityFailureCode.storage,
          ),
        ),
      );
      expect(await file.readAsString(), wrongShape);

      final String wrongVersion = jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'accountUserId': _account,
        'notes': <Object?>[],
        'outbox': <Object?>[],
        'cursor': null,
        'conflicts': <Object?>[],
      });
      await file.writeAsString(wrongVersion);
      await expectLater(
        fixture.store.read(),
        throwsA(
          isA<NoteSecurityFailure>().having(
            (e) => e.code,
            'code',
            NoteSecurityFailureCode.storage,
          ),
        ),
      );
      expect(await file.readAsString(), wrongVersion);

      final String otherAccount = jsonEncode(
        LocalSyncStateCodec.encode(_stateFor(_otherAccount)),
      );
      await file.writeAsString(otherAccount);
      await expectLater(
        fixture.store.read(),
        throwsA(
          isA<NoteSecurityFailure>().having(
            (e) => e.code,
            'code',
            NoteSecurityFailureCode.storage,
          ),
        ),
      );
      expect(await file.readAsString(), otherAccount);
    });

    test(
      'never leaks note content, cursor, account, or path on failure',
      () async {
        final _Fixture fixture = await _newFixture();
        final File file = _stateFile(fixture.supportDirectory, _account);
        await file.parent.create(recursive: true);

        // A secret-carrying envelope that is corrupt in an unrelated field.
        final Map<String, Object?> envelope = LocalSyncStateCodec.encode(
          LocalSyncState(
            accountUserId: _account,
            notes: <LocalNoteState>[
              noteFixture(
                ownerId: _account,
                title: secretTitle,
                content: secretContent,
              ),
            ],
            outbox: <PendingMutation>[mutationFixture()],
            cursor: const SyncCursor(secretCursor),
          ),
        )..remove('conflicts');
        await file.writeAsString(jsonEncode(envelope));
        final String stored = await file.readAsString();

        try {
          await fixture.store.read();
          fail('expected a LocalSyncStoreException');
        } on NoteSecurityFailure catch (error) {
          expect(error.code, NoteSecurityFailureCode.storage);
          _expectNoLeakage(error, fixture.supportDirectory);
        }
        expect(await file.readAsString(), stored);
      },
    );

    test(
      'reports an undecodable file as unreadable without touching it',
      () async {
        final _Fixture fixture = await _newFixture();
        final File file = _stateFile(fixture.supportDirectory, _account);
        await file.parent.create(recursive: true);
        const List<int> invalidUtf8 = <int>[0xFF, 0xFE, 0xFD, 0x80];
        await file.writeAsBytes(invalidUtf8);

        await expectLater(
          fixture.store.read(),
          _storeError(LocalSyncStoreFailure.unreadable, 'cannot be read'),
        );
        expect(await file.readAsBytes(), invalidUtf8);
      },
    );

    test('cleans only its temporary file when the atomic rename fails', () async {
      final _Fixture fixture = await _newFixture();
      // A directory at the final path makes the rename fail after the temporary
      // file has been created and flushed, exercising the cleanup branch.
      await Directory(_stateFile(fixture.supportDirectory, _account).path)
          .create(recursive: true);

      await expectLater(
        fixture.store.replace(richStateFixture()),
        _storeError(LocalSyncStoreFailure.unwritable, 'cannot be committed'),
      );

      expect(await _temporaryResidue(fixture.supportDirectory), isEmpty);
      expect(
        _stateFile(fixture.supportDirectory, _account).statSync().type,
        FileSystemEntityType.directory,
      );
    });

    test(
      'keeps the stored state when a replacement cannot be written',
      () async {
        final _Fixture fixture = await _newFixture();
        final LocalSyncState stored = richStateFixture();
        await fixture.store.replace(stored);

        // Replace the account namespace directory with a file: the next
        // replacement cannot create the directory or its temporary file.
        final Directory namespaceDirectory = _namespaceDirectory(
          fixture.supportDirectory,
          _account,
        );
        final String parked = '${namespaceDirectory.path}.parked';
        await namespaceDirectory.rename(parked);
        await File(namespaceDirectory.path).writeAsString('not a directory');
        addTearDown(() async {
          if (File(namespaceDirectory.path).existsSync()) {
            await File(namespaceDirectory.path).delete();
          }
          if (Directory(parked).existsSync()) {
            await Directory(parked).rename(namespaceDirectory.path);
          }
        });

        await expectLater(
          fixture.store.replace(_stateFor(_account, noteId: 'note-9')),
          _storeError(LocalSyncStoreFailure.unwritable, 'cannot be committed'),
        );

        await File(namespaceDirectory.path).delete();
        await Directory(parked).rename(namespaceDirectory.path);
        expect(await fixture.store.read(), stored);
      },
    );

    test('serializes concurrent replacements and reads', () async {
      final _Fixture fixture = await _newFixture();
      final List<Future<void>> writes = <Future<void>>[];
      final List<Future<LocalSyncState>> reads = <Future<LocalSyncState>>[];

      for (int index = 0; index < 6; index++) {
        reads.add(fixture.store.read());
        writes.add(
          fixture.store.replace(_stateFor(_account, noteId: 'note-$index')),
        );
      }

      await Future.wait(writes);
      final List<LocalSyncState> observed = await Future.wait(reads);

      for (final LocalSyncState state in observed) {
        // Every read observed one complete document, never a partial state.
        expect(state.accountUserId, _account);
        expect(state.notes.length, lessThanOrEqualTo(1));
        expect(state.outbox, isEmpty);
        expect(state.conflicts, isEmpty);
        expect(state.cursor, isNull);
        if (state.notes.isNotEmpty) {
          expect(state.notes.single.id, startsWith('note-'));
        }
      }
      expect((await fixture.store.read()).notes.single.id, 'note-5');
      expect(await _temporaryResidue(fixture.supportDirectory), isEmpty);
    });
  });

  group('platform facade', () {
    test('exposes the native store on an IO test host', () async {
      final Directory directory = await _supportDirectory();
      final ILocalSyncStore store = createLocalSyncStore(
        accountUserId: _account,
        applicationSupportPathResolver: () async => directory.path,
      );

      expect(store, isA<native.FileLocalSyncStore>());
      expect(store, isNot(isA<stub.UnsupportedLocalSyncStore>()));

      await store.replace(simpleStateFixture());
      expect(await store.read(), simpleStateFixture());
    });

    test('unsupported stub keeps factory parity and never fakes state', () {
      final ILocalSyncStore store = stub.createLocalSyncStore(
        accountUserId: _account,
        applicationSupportPathResolver: () async => 'unused',
      );

      expect(store, isA<stub.UnsupportedLocalSyncStore>());
      expect(() => store.read(), throwsUnsupportedError);
      expect(() => store.replace(simpleStateFixture()), throwsUnsupportedError);
    });
  });
}
