import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/note_sync_status.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_codec_exception.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_codec_reader.dart';

import 'local_sync_codec_fixtures.dart';

void main() {
  group('SyncCodecObject', () {
    test('rejects a non-object, a non-string key, an unknown and a missing '
        'field', () {
      expect(
        codecFailure(
          () => SyncCodecObject.from(
            42,
            path: 'note',
            allowedFields: const <String>{'id'},
          ),
        ).message,
        'must be an object.',
      );
      expect(
        codecFailure(
          () => SyncCodecObject.from(
            <Object?, Object?>{1: 'id'},
            path: 'note',
            allowedFields: const <String>{'id'},
          ),
        ).message,
        'must use string field names.',
      );
      expect(
        codecFailure(
          () => SyncCodecObject.from(
            <String, Object?>{'id': 'note-1', 'secret': 'value'},
            path: 'note',
            allowedFields: const <String>{'id'},
          ),
        ).message,
        contains('outside the M2 local sync schema'),
      );
      expect(
        codecFailure(
          () => SyncCodecObject.from(
            <String, Object?>{},
            path: 'note',
            allowedFields: const <String>{'id'},
          ),
        ).message,
        'must contain the field "id".',
      );
    });

    test('reads fields and reports failures under the object path', () {
      final SyncCodecObject record = SyncCodecObject.from(
        <String, Object?>{
          'status': 'pending',
          'deletedAt': null,
          'title': 'a title',
        },
        path: 'notes[0]',
        allowedFields: const <String>{'status', 'deletedAt', 'title'},
      );

      expect(
        record.requireEnum('status', NoteSyncStatus.values),
        NoteSyncStatus.pending,
      );
      expect(
        record.requireNullableEnum('deletedAt', NoteSyncStatus.values),
        isNull,
      );
      expect(record.requireNullableTimestamp('deletedAt'), isNull);
      expect(record.rawValue('title'), 'a title');
      expect(record.fieldPath('title'), 'notes[0].title');

      final LocalSyncCodecException error = codecFailure(
        () => record.requireInt('title'),
      );
      expect(error.message, 'must be an integer.');
      expect(error.path, 'notes[0].title');
    });
  });

  test('translates a model invariant failure without carrying its message', () {
    final LocalSyncCodecException error = codecFailure(
      () => buildCodecModel<String>(
        () => throw ArgumentError.value(
          'SECRET-MODEL-VALUE',
          'field',
          'SECRET-MODEL-DETAIL',
        ),
        path: 'note',
      ),
    );

    expect(error.message, 'does not satisfy the model invariants.');
    expect(error.path, 'note');
    final String rendered = error.toString();
    expect(rendered, isNot(contains('SECRET-MODEL-VALUE')));
    expect(rendered, isNot(contains('SECRET-MODEL-DETAIL')));
    expect(rendered, isNot(contains('ArgumentError')));
  });

  test('does not rewrite a typed codec failure raised inside the builder', () {
    final LocalSyncCodecException error = codecFailure(
      () => buildCodecModel<String>(
        () => throw const LocalSyncCodecException(
          'must be an object.',
          path: 'note',
        ),
        path: 'note',
      ),
    );

    expect(error.message, 'must be an object.');
    expect(error.path, 'note');
  });
}
