import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/note_sync_status.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_cursor.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_codec_exception.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_codec_schema.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_state_codec.dart';

import 'local_sync_codec_fixtures.dart';

void main() {
  test(
    'inner v4 migration preserves pins, preferences and attempted payloads',
    () {
      final state = richStateFixture();
      final encoded = LocalSyncStateCodec.encode(state);
      encoded['schemaVersion'] = 4;
      for (final raw in encoded['notes']! as List<Object?>) {
        (raw! as Map<String, Object?>).remove('attachments');
      }
      for (final raw in encoded['conflicts']! as List<Object?>) {
        final conflict = raw! as Map<String, Object?>;
        (conflict['local']! as Map<String, Object?>).remove('attachments');
        final remote = conflict['remote'] as Map<String, Object?>?;
        remote?.remove('attachments');
        remote?.remove('includesAttachments');
      }
      final migrated = LocalSyncStateCodec.decode(encoded);
      expect(migrated, state);
      expect(LocalSyncStateCodec.encode(migrated)['outbox'], encoded['outbox']);
      expect(migrated.userPreferences, state.userPreferences);
    },
  );

  group('envelope round trip', () {
    test('decodes an encoded account state into an equal state', () {
      final LocalSyncState state = richStateFixture();

      final LocalSyncState decoded = LocalSyncStateCodec.decode(
        LocalSyncStateCodec.encode(state),
      );

      expect(decoded, state);
      expect(decoded.notes, hasLength(3));
      expect(decoded.outbox, hasLength(3));
      expect(decoded.conflicts, hasLength(3));
      expect(decoded.cursor, const SyncCursor('opaque-cursor-1'));
    });

    test(
      'writes exactly the frozen envelope fields at inner schema version 5',
      () {
        final Map<String, Object?> envelope = LocalSyncStateCodec.encode(
          richStateFixture(),
        );

        expect(LocalSyncStateCodec.schemaVersion, 5);
        expect(LocalSyncSchema.version, 5);
        expect(envelope.keys.toSet(), <String>{
          'schemaVersion',
          'accountUserId',
          'notes',
          'outbox',
          'cursor',
          'conflicts',
          'userPreferences',
        });
        expect(envelope['schemaVersion'], 5);
        expect(envelope['accountUserId'], 'user-1');
        expect(envelope['cursor'], 'opaque-cursor-1');
        expect(envelope['notes'], isA<List<Object?>>());
        expect(envelope['outbox'], isA<List<Object?>>());
        expect(envelope['conflicts'], isA<List<Object?>>());
        expect(envelope['userPreferences'], isA<Map<String, Object?>>());
      },
    );

    test('round-trips an empty account with an explicit null cursor', () {
      final LocalSyncState state = LocalSyncState(accountUserId: 'user-1');

      final Map<String, Object?> envelope = LocalSyncStateCodec.encode(state);

      expect(envelope.containsKey('cursor'), isTrue);
      expect(envelope['cursor'], isNull);
      expect(envelope['notes'], isEmpty);
      expect(envelope['outbox'], isEmpty);
      expect(envelope['conflicts'], isEmpty);
      final LocalSyncState decoded = LocalSyncStateCodec.decode(envelope);
      expect(decoded, state);
      expect(decoded.isEmpty, isTrue);
      expect(decoded.cursor, isNull);
    });

    test('writes every record field a caller later needs', () {
      final Map<String, Object?> envelope = LocalSyncStateCodec.encode(
        richStateFixture(),
      );

      final Map<String, Object?> tombstone = copyRecord(
        (envelope['notes']! as List<Object?>)[2],
      );
      expect(tombstone.keys.toSet(), LocalSyncSchema.noteFields);
      expect(tombstone['deletedAt'], fixtureUpdatedAt.toIso8601String());
      expect(tombstone['status'], 'conflict');
      expect(tombstone['serverRevision'], 4);

      final Map<String, Object?> retried = copyRecord(
        (envelope['outbox']! as List<Object?>)[1],
      );
      expect(retried.keys.toSet(), LocalSyncSchema.mutationFields);
      expect(retried['retryCount'], 2);
      expect(retried['lastError'], 'throttled');
      expect(retried['blocked'], true);

      final Map<String, Object?> removed = copyRecord(
        (envelope['outbox']! as List<Object?>)[2],
      );
      expect(removed['operation'], 'delete');
      expect(removed['payload'], isNull);

      final Map<String, Object?> payload = copyRecord(
        (envelope['outbox']! as List<Object?>)[0],
      );
      expect(copyRecord(payload['payload']), <String, Object?>{
        'title': fixturePayloadTitle,
        'content': fixturePayloadContent,
      });

      final List<Object?> conflicts = envelope['conflicts']! as List<Object?>;
      expect(conflicts, hasLength(3));
      final Map<String, Object?> liveRemote = copyRecord(
        copyRecord(conflicts[0])['remote'],
      );
      expect(liveRemote.keys.toSet(), {
        ...LocalSyncSchema.snapshotFields,
        'includesAttachments',
      });
      expect(liveRemote['revision'], 5);
      expect(liveRemote['serverUpdatedAt'], fixtureUpdatedAt.toIso8601String());
      expect(liveRemote['deletedAt'], isNull);
      expect(copyRecord(conflicts[1])['remote'], isNull);
      final Map<String, Object?> tombstoneRemote = copyRecord(
        copyRecord(conflicts[2])['remote'],
      );
      expect(tombstoneRemote['deletedAt'], fixtureUpdatedAt.toIso8601String());
    });

    test('migrates schema 2 without changing attempted mutations', () {
      final LocalSyncState state = richStateFixture();
      final Map<String, Object?> legacy = LocalSyncStateCodec.encode(state)
        ..['schemaVersion'] = 2
        ..remove('userPreferences');

      final List<Object?> oldConflicts = legacy['conflicts']! as List<Object?>;
      for (int i = 0; i < oldConflicts.length; i++) {
        final Map<String, Object?> conflict = copyRecord(oldConflicts[i]);
        final Map<String, Object?> local = copyRecord(conflict['local'])
          ..remove('pinnedAt')
          ..remove('attachments')
          ..remove('includesAttachments')
          ..remove('protected')
          ..remove('protectionRevision')
          ..remove('contentAvailable');
        final Object? remoteValue = conflict['remote'];
        Map<String, Object?>? remote;
        if (remoteValue != null) {
          remote = copyRecord(remoteValue)
            ..remove('pinnedAt')
            ..remove('attachments')
            ..remove('includesAttachments')
            ..remove('protected')
            ..remove('protectionRevision')
            ..remove('contentAvailable');
        }
        oldConflicts[i] = <String, Object?>{
          ...conflict,
          'local': local,
          'remote': remote,
        };
      }
      final List<Object?> notes = legacy['notes']! as List<Object?>;
      for (int i = 0; i < notes.length; i++) {
        notes[i] = copyRecord(notes[i])
          ..remove('pinnedAt')
          ..remove('attachments')
          ..remove('includesAttachments')
          ..remove('protected')
          ..remove('protectionRevision')
          ..remove('contentAvailable');
      }

      final LocalSyncState migrated = LocalSyncStateCodec.decode(legacy);

      expect(migrated.outbox, state.outbox);
      expect(migrated.conflicts, state.conflicts);
      expect(
        migrated.notes.every((LocalNoteState note) => note.pinnedAt == null),
        isTrue,
      );
      expect(migrated.userPreferences.noteLayout.name, 'grid');
      expect(migrated.userPreferences.userId, state.accountUserId);
    });

    test(
      'rejects schema 2 records that contain fields from a newer schema',
      () {
        final Map<String, Object?> legacy =
            LocalSyncStateCodec.encode(simpleStateFixture())
              ..['schemaVersion'] = 2
              ..remove('userPreferences');
        final List<Object?> notes = legacy['notes']! as List<Object?>;
        notes[0] = copyRecord(notes[0])..['unexpected'] = true;
        notes[0] = copyRecord(notes[0])
          ..remove('pinnedAt')
          ..remove('attachments')
          ..remove('includesAttachments')
          ..remove('protected')
          ..remove('protectionRevision')
          ..remove('contentAvailable');

        expect(
          () => LocalSyncStateCodec.decode(legacy),
          throwsA(isA<LocalSyncCodecException>()),
        );
      },
    );
  });

  group('cursor opacity', () {
    test('stores the raw cursor byte-for-byte', () {
      const String raw = '  {"offset":"12"}\n\t✓ end ';
      final LocalSyncState state = LocalSyncState(
        accountUserId: 'user-1',
        cursor: const SyncCursor(raw),
      );

      final Map<String, Object?> envelope = LocalSyncStateCodec.encode(state);

      expect(envelope['cursor'], same(raw));
      expect(LocalSyncStateCodec.decode(envelope).cursor?.value, raw);
    });

    test('preserves an empty cursor value instead of folding it to null', () {
      final LocalSyncState state = LocalSyncState(
        accountUserId: 'user-1',
        cursor: const SyncCursor(''),
      );

      final LocalSyncState decoded = LocalSyncStateCodec.decode(
        LocalSyncStateCodec.encode(state),
      );

      expect(decoded.cursor, isNotNull);
      expect(decoded.cursor!.value, '');
      expect(decoded.cursor!.hasValue, isTrue);
    });

    test('rejects a non-string cursor without echoing the stored value', () {
      final Map<String, Object?> envelope = LocalSyncStateCodec.encode(
        simpleStateFixture(),
      )..['cursor'] = 42;

      final LocalSyncCodecException error = codecFailure(
        () => LocalSyncStateCodec.decode(envelope),
      );

      expect(error.message, 'must be a string or null.');
      expect(error.path, 'localSyncState.cursor');
    });
  });

  group('strict envelope validation', () {
    test('rejects anything that is not a decoded map', () {
      const String rawJson = '{"schemaVersion":2,"accountUserId":"user-1"}';
      final List<Object?> inputs = <Object?>[
        rawJson,
        <Object?>[],
        42,
        true,
        null,
      ];

      for (final Object? input in inputs) {
        final LocalSyncCodecException error = codecFailure(
          () => LocalSyncStateCodec.decode(input),
        );
        expect(error.message, 'must be an object.');
        expect(error, isA<LocalSyncCodecException>());
      }
    });

    test('rejects a map that does not use string field names', () {
      final Map<Object?, Object?> envelope = <Object?, Object?>{1: 'notes'};

      final LocalSyncCodecException error = codecFailure(
        () => LocalSyncStateCodec.decode(envelope),
      );

      expect(error.message, 'must use string field names.');
    });

    test('rejects a field outside the frozen schema', () {
      final Map<String, Object?> envelope = LocalSyncStateCodec.encode(
        simpleStateFixture(),
      )..['extra'] = 'value';

      final LocalSyncCodecException error = codecFailure(
        () => LocalSyncStateCodec.decode(envelope),
      );

      expect(error.message, contains('outside the M2 local sync schema'));
      expect(error.message, isNot(contains('extra')));
    });

    test('rejects every missing envelope field', () {
      for (final String field in <String>[
        'schemaVersion',
        'accountUserId',
        'notes',
        'outbox',
        'cursor',
        'conflicts',
        'userPreferences',
      ]) {
        final Map<String, Object?> envelope = LocalSyncStateCodec.encode(
          simpleStateFixture(),
        )..remove(field);

        final LocalSyncCodecException error = codecFailure(
          () => LocalSyncStateCodec.decode(envelope),
        );

        expect(error.message, 'must contain the field "$field".');
        expect(error.path, 'localSyncState');
      }
    });

    test(
      'rejects versions outside v2/v3/v4 legacy and v5 current contract',
      () {
        // Web numbers erase the int/double distinction for integral values.
        // A fractional version is invalid on both runtimes.
        final List<Object?> versions = <Object?>[
          0,
          1,
          6,
          '3',
          3.25,
          null,
          true,
        ];

        for (final Object? version in versions) {
          final Map<String, Object?> envelope = LocalSyncStateCodec.encode(
            simpleStateFixture(),
          )..['schemaVersion'] = version;

          final LocalSyncCodecException error = codecFailure(
            () => LocalSyncStateCodec.decode(envelope),
          );

          expect(error.path, 'localSyncState.schemaVersion');
          expect(error, isA<LocalSyncCodecException>());
        }
      },
    );

    test('rejects a wrong-typed or blank account id', () {
      final Map<String, Object?> wrongType = LocalSyncStateCodec.encode(
        simpleStateFixture(),
      )..['accountUserId'] = 7;
      expect(
        codecFailure(() => LocalSyncStateCodec.decode(wrongType)).message,
        'must be a string.',
      );

      final Map<String, Object?> blank = LocalSyncStateCodec.encode(
        simpleStateFixture(),
      )..['accountUserId'] = '  ';
      final LocalSyncCodecException error = codecFailure(
        () => LocalSyncStateCodec.decode(blank),
      );
      expect(error.message, 'must not be blank.');
      expect(error.path, 'localSyncState.accountUserId');
    });

    test('rejects a collection field that is not an array', () {
      for (final String field in <String>['notes', 'outbox', 'conflicts']) {
        final Map<String, Object?> envelope = LocalSyncStateCodec.encode(
          simpleStateFixture(),
        )..[field] = 'not an array';

        final LocalSyncCodecException error = codecFailure(
          () => LocalSyncStateCodec.decode(envelope),
        );

        expect(error.message, 'must be an array.');
        expect(error.path, 'localSyncState.$field');
      }
    });

    test('rejects a collection entry that is not an object', () {
      final Map<String, Object?> envelope = LocalSyncStateCodec.encode(
        simpleStateFixture(),
      );
      (envelope['notes']! as List<Object?>)[0] = 42;

      final LocalSyncCodecException error = codecFailure(
        () => LocalSyncStateCodec.decode(envelope),
      );

      expect(error.message, 'must be an object.');
      expect(error.path, 'localSyncState.notes[0]');
    });
  });

  group('account invariants', () {
    test('rejects a duplicate note id at the second occurrence', () {
      final Map<String, Object?> envelope = LocalSyncStateCodec.encode(
        LocalSyncState(
          accountUserId: 'user-1',
          notes: <LocalNoteState>[
            noteFixture(),
            noteFixture(id: 'note-2'),
          ],
        ),
      );
      (envelope['notes']! as List<Object?>)[1] = copyRecord(
        (envelope['notes']! as List<Object?>)[0],
      );

      final LocalSyncCodecException error = codecFailure(
        () => LocalSyncStateCodec.decode(envelope),
      );

      expect(error.message, 'duplicates an earlier note id.');
      expect(error.path, 'localSyncState.notes[1].id');
    });

    test('rejects a duplicate mutation id at the second occurrence', () {
      final Map<String, Object?> envelope = LocalSyncStateCodec.encode(
        LocalSyncState(
          accountUserId: 'user-1',
          outbox: <PendingMutation>[
            mutationFixture(),
            mutationFixture(mutationId: 'mutation-2'),
          ],
        ),
      );
      (envelope['outbox']! as List<Object?>)[1] = copyRecord(
        (envelope['outbox']! as List<Object?>)[0],
      );

      final LocalSyncCodecException error = codecFailure(
        () => LocalSyncStateCodec.decode(envelope),
      );

      expect(error.message, 'duplicates an earlier mutation id.');
      expect(error.path, 'localSyncState.outbox[1].mutationId');
    });

    test('rejects a note owned by another account', () {
      final Map<String, Object?> envelope = LocalSyncStateCodec.encode(
        LocalSyncState(
          accountUserId: 'user-1',
          notes: <LocalNoteState>[
            noteFixture(),
            noteFixture(id: 'note-2'),
          ],
        ),
      );
      final Map<String, Object?> foreign = copyRecord(
        (envelope['notes']! as List<Object?>)[1],
      )..['ownerId'] = 'user-2';
      (envelope['notes']! as List<Object?>)[1] = foreign;

      final LocalSyncCodecException error = codecFailure(
        () => LocalSyncStateCodec.decode(envelope),
      );

      expect(error.message, 'must belong to the state account.');
      expect(error.path, 'localSyncState.notes[1].ownerId');
    });

    test('reports a malformed nested record with its full path', () {
      final Map<String, Object?> envelope = LocalSyncStateCodec.encode(
        richStateFixture(),
      );
      final Map<String, Object?> record = copyRecord(
        (envelope['notes']! as List<Object?>)[1],
      )..['status'] = 'archived';
      (envelope['notes']! as List<Object?>)[1] = record;

      final LocalSyncCodecException error = codecFailure(
        () => LocalSyncStateCodec.decode(envelope),
      );

      expect(error.message, 'must name a declared NoteSyncStatus value.');
      expect(error.path, 'localSyncState.notes[1].status');
    });
  });

  group('safe failure messages', () {
    test('never carries note content, titles, ids, or cursor values', () {
      final LocalNoteState secretNote = noteFixture(
        id: 'SECRET-NOTE-ID',
        title: secretTitle,
        content: secretContent,
        status: NoteSyncStatus.pending,
      );
      final Map<String, Object?> envelope = LocalSyncStateCodec.encode(
        LocalSyncState(
          accountUserId: 'user-1',
          notes: <LocalNoteState>[
            secretNote,
            noteFixture(id: 'note-2'),
          ],
          cursor: const SyncCursor(secretCursor),
        ),
      );
      final Map<String, Object?> broken = copyRecord(
        (envelope['notes']! as List<Object?>)[1],
      )..['createdAt'] = 'not a timestamp';
      (envelope['notes']! as List<Object?>)[1] = broken;
      envelope['cursor'] = 3.14;

      final LocalSyncCodecException error = codecFailure(
        () => LocalSyncStateCodec.decode(envelope),
      );

      final String rendered = error.toString();
      expect(error.message, isNot(contains(secretTitle)));
      expect(error.message, isNot(contains(secretContent)));
      expect(error.message, isNot(contains(secretCursor)));
      expect(error.message, isNot(contains('SECRET-NOTE-ID')));
      expect(rendered, isNot(contains(secretTitle)));
      expect(rendered, isNot(contains(secretContent)));
      expect(rendered, isNot(contains(secretCursor)));
      expect(rendered, isNot(contains('SECRET-NOTE-ID')));
    });

    test('never echoes a received enum name or field name', () {
      final Map<String, Object?> envelope = LocalSyncStateCodec.encode(
        simpleStateFixture(),
      );
      final Map<String, Object?> record = copyRecord(
        (envelope['notes']! as List<Object?>)[0],
      )..['status'] = 'SECRET-STATUS-NAME';
      (envelope['notes']! as List<Object?>)[0] = record;

      final LocalSyncCodecException error = codecFailure(
        () => LocalSyncStateCodec.decode(envelope),
      );

      expect(error.toString(), isNot(contains('SECRET-STATUS-NAME')));
    });

    test('carries no provider or model exception text', () {
      final Map<String, Object?> envelope = LocalSyncStateCodec.encode(
        simpleStateFixture(),
      )..['schemaVersion'] = '2';

      final LocalSyncCodecException error = codecFailure(
        () => LocalSyncStateCodec.decode(envelope),
      );

      final String rendered = error.toString();
      expect(rendered, isNot(contains('ArgumentError')));
      expect(rendered, isNot(contains('FormatException')));
      expect(rendered, isNot(contains('TypeError')));
      expect(rendered, isNot(contains('_TypeError')));
      expect(rendered, startsWith('LocalSyncCodecException: '));
    });
  });
}
