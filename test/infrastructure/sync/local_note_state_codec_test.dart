import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/note_sync_status.dart';
import 'package:note_ai_app/infrastructure/sync/local_note_state_codec.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_codec_exception.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_codec_schema.dart';

import 'local_sync_codec_fixtures.dart';

void main() {
  group('round trip', () {
    test('decodes an encoded live note into an equal note', () {
      final LocalNoteState note = noteFixture(
        serverRevision: 7,
        status: NoteSyncStatus.failed,
      );

      final Map<String, Object?> record = LocalNoteStateCodec.encode(note);
      final LocalNoteState decoded = LocalNoteStateCodec.decode(record);

      expect(decoded, note);
      expect(decoded.isDeleted, isFalse);
      expect(
        record.keys.toSet(),
        LocalSyncSchema.noteFields.difference({'document'}),
      );
      expect(record['createdAt'], fixtureCreatedAt.toIso8601String());
      expect(record['updatedAt'], fixtureUpdatedAt.toIso8601String());
      expect(record['deletedAt'], isNull);
      expect(record['status'], 'failed');
    });

    test('keeps a tombstone as state rather than dropping the note', () {
      final LocalNoteState note = noteFixture(
        deletedAt: fixtureUpdatedAt,
        status: NoteSyncStatus.conflict,
      );

      final LocalNoteState decoded = LocalNoteStateCodec.decode(
        LocalNoteStateCodec.encode(note),
      );

      expect(decoded, note);
      expect(decoded.isDeleted, isTrue);
      expect(decoded.deletedAt, fixtureUpdatedAt);
      expect(decoded.status, NoteSyncStatus.conflict);
    });

    test('round-trips a local (non-UTC) timestamp instant', () {
      final LocalNoteState note = noteFixture(
        createdAt: DateTime(2026, 9, 25, 9, 0, 0, 1, 2),
        updatedAt: DateTime(2026, 9, 25, 10),
      );

      final LocalNoteState decoded = LocalNoteStateCodec.decode(
        LocalNoteStateCodec.encode(note),
      );

      expect(decoded.createdAt, note.createdAt);
      expect(decoded.createdAt.isUtc, isFalse);
      expect(decoded, note);
    });

    test('round-trips every sync status name', () {
      for (final NoteSyncStatus status in NoteSyncStatus.values) {
        final LocalNoteState note = noteFixture(status: status);
        final LocalNoteState decoded = LocalNoteStateCodec.decode(
          LocalNoteStateCodec.encode(note),
        );
        expect(decoded.status, status);
      }
    });
  });

  group('strict record validation', () {
    test('rejects a missing field', () {
      final Map<String, Object?> record = LocalNoteStateCodec.encode(
        noteFixture(),
      )..remove('updatedAt');

      final LocalSyncCodecException error = codecFailure(
        () => LocalNoteStateCodec.decode(record),
      );

      expect(error.message, 'must contain the field "updatedAt".');
      expect(error.path, 'note');
    });

    test('rejects a field outside the frozen note schema', () {
      final Map<String, Object?> record = LocalNoteStateCodec.encode(
        noteFixture(),
      )..['owner'] = 'user-1';

      final LocalSyncCodecException error = codecFailure(
        () => LocalNoteStateCodec.decode(record),
      );

      expect(error.message, contains('outside the M2 local sync schema'));
      expect(error.path, 'note');
    });

    test('rejects wrong field types', () {
      for (final String field in <String>[
        'id',
        'ownerId',
        'title',
        'content',
        'createdAt',
        'updatedAt',
        'serverRevision',
        'status',
      ]) {
        final Map<String, Object?> record = LocalNoteStateCodec.encode(
          noteFixture(),
        )..[field] = <String>['not', 'a', 'scalar'];

        final LocalSyncCodecException error = codecFailure(
          () => LocalNoteStateCodec.decode(record),
        );

        expect(error.path, 'note.$field');
        expect(error, isA<LocalSyncCodecException>());
      }
    });

    test('rejects a blank id or owner', () {
      final Map<String, Object?> blankId = LocalNoteStateCodec.encode(
        noteFixture(),
      )..['id'] = ' ';
      expect(
        codecFailure(() => LocalNoteStateCodec.decode(blankId)).message,
        'must not be blank.',
      );

      final Map<String, Object?> blankOwner = LocalNoteStateCodec.encode(
        noteFixture(),
      )..['ownerId'] = '';
      expect(
        codecFailure(() => LocalNoteStateCodec.decode(blankOwner)).message,
        'must not be blank.',
      );
    });

    test('rejects an unknown status name', () {
      final Map<String, Object?> record = LocalNoteStateCodec.encode(
        noteFixture(),
      )..['status'] = 'pendingSync';

      final LocalSyncCodecException error = codecFailure(
        () => LocalNoteStateCodec.decode(record),
      );

      expect(error.message, 'must name a declared NoteSyncStatus value.');
      expect(error.path, 'note.status');
    });

    test('rejects an unparsable or empty timestamp', () {
      for (final Object? value in <Object?>['yesterday', '', 0, null]) {
        final Map<String, Object?> record = LocalNoteStateCodec.encode(
          noteFixture(),
        )..['createdAt'] = value;

        final LocalSyncCodecException error = codecFailure(
          () => LocalNoteStateCodec.decode(record),
        );

        expect(error.path, 'note.createdAt');
        expect(error, isA<LocalSyncCodecException>());
      }
    });

    test('rejects a negative server revision', () {
      final Map<String, Object?> record = LocalNoteStateCodec.encode(
        noteFixture(),
      )..['serverRevision'] = -1;

      final LocalSyncCodecException error = codecFailure(
        () => LocalNoteStateCodec.decode(record),
      );

      expect(error.message, 'must not be negative.');
      expect(error.path, 'note.serverRevision');
    });

    test('rejects a malformed tombstone marker', () {
      final Map<String, Object?> record = LocalNoteStateCodec.encode(
        noteFixture(),
      )..['deletedAt'] = 'never';

      final LocalSyncCodecException error = codecFailure(
        () => LocalNoteStateCodec.decode(record),
      );

      expect(error.message, 'must be a valid ISO-8601 timestamp.');
      expect(error.path, 'note.deletedAt');
    });
  });

  test('never echoes note title or content in a failure', () {
    final Map<String, Object?> record = LocalNoteStateCodec.encode(
      noteFixture(title: secretTitle, content: secretContent),
    )..['serverRevision'] = -5;

    final LocalSyncCodecException error = codecFailure(
      () => LocalNoteStateCodec.decode(record),
    );

    expect(error.toString(), isNot(contains(secretTitle)));
    expect(error.toString(), isNot(contains(secretContent)));
  });
}
