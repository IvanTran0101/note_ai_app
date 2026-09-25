import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/application/sync/sync_result.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/infrastructure/sync/sync_http_mapper.dart';

/// Behavior coverage for the pure sync wire mapper.
///
/// The fixtures follow `docs/sync_api_contract.md` rather than the backend or
/// any provider SDK: request shaping, applied and conflict results, tombstones,
/// cursor paging, and the rejection of every malformed payload. Two invariants
/// get their own assertions because they are easy to regress: a request body
/// never carries an `ownerId`, and no provider text survives into a failure.

const String _mutationId = 'mutation-1';
const String _noteId = 'note-1';
const String _content = 'Private note content';
const String _createdAt = '2026-09-24T10:00:00.000Z';
const String _serverUpdatedAt = '2026-09-24T11:00:00.000Z';

SyncMutation _mutation({
  SyncMutationOperation operation = SyncMutationOperation.create,
  int baseRevision = 0,
}) {
  return SyncMutation(
    mutationId: _mutationId,
    noteId: _noteId,
    operation: operation,
    baseRevision: baseRevision,
    payload: operation == SyncMutationOperation.delete
        ? null
        : const SyncNotePayload(title: 'Title', content: _content),
  );
}

/// One note payload; [overrides] injects malformed values for rejection tests.
Map<String, Object?> _noteJson({
  Map<String, Object?> overrides = const <String, Object?>{},
}) {
  return <String, Object?>{
    'id': _noteId,
    'title': 'Title',
    'content': _content,
    'createdAt': _createdAt,
    'serverUpdatedAt': _serverUpdatedAt,
    'revision': 1,
    'deletedAt': null,
  }..addAll(overrides);
}

Map<String, Object?> _appliedJson({Map<String, Object?>? note}) {
  return <String, Object?>{
    'status': 'applied',
    'mutationId': _mutationId,
    'note': note ?? _noteJson(),
  };
}

Map<String, Object?> _conflictJson({
  Object? remoteNote,
  bool includeMutationId = true,
}) {
  return <String, Object?>{
    'code': 'REVISION_CONFLICT',
    'retryable': false,
    if (includeMutationId) 'mutationId': _mutationId,
    'remoteNote': remoteNote,
  };
}

Map<String, Object?> _changesJson({
  List<Object?>? items,
  Object? nextCursor,
  Object? hasMore,
}) {
  return <String, Object?>{
    'items': items ?? <Object?>[_noteJson()],
    'nextCursor': ?nextCursor,
    'hasMore': ?hasMore,
  };
}

Matcher _throwsFormatException() {
  return throwsA(isA<FormatException>());
}

void main() {
  group('encodeSyncMutation', () {
    test('encodes a create mutation as the frozen request body', () {
      final Map<String, Object?> body = encodeSyncMutation(_mutation());

      expect(body, <String, Object?>{
        'mutationId': _mutationId,
        'noteId': _noteId,
        'operation': 'create',
        'baseRevision': 0,
        'payload': <String, Object?>{'title': 'Title', 'content': _content},
      });
      // JSON-compatible: every value survives a real encode round trip.
      expect(jsonDecode(jsonEncode(body)), body);
    });

    test('encodes an update mutation with its payload', () {
      final Map<String, Object?> body = encodeSyncMutation(
        _mutation(operation: SyncMutationOperation.update, baseRevision: 4),
      );

      expect(body['operation'], 'update');
      expect(body['baseRevision'], 4);
      expect(body['payload'], <String, Object?>{
        'title': 'Title',
        'content': _content,
      });
    });

    test('omits the payload key for a delete mutation', () {
      final Map<String, Object?> body = encodeSyncMutation(
        _mutation(operation: SyncMutationOperation.delete, baseRevision: 4),
      );

      expect(body['operation'], 'delete');
      expect(body.containsKey('payload'), isFalse);
      expect(body.keys, <String>[
        'mutationId',
        'noteId',
        'operation',
        'baseRevision',
      ]);
    });

    test('never adds an ownerId to the request body', () {
      for (final SyncMutationOperation operation
          in SyncMutationOperation.values) {
        final Map<String, Object?> body = encodeSyncMutation(
          _mutation(operation: operation),
        );

        // The server derives the account namespace from the Cognito sub.
        expect(body.containsKey('ownerId'), isFalse);
        expect(jsonEncode(body), isNot(contains('ownerId')));
      }
    });
  });

  group('decodeSyncMutationResponse applied', () {
    test('decodes an applied response with a decoded body', () {
      final SyncMutationResult result = decodeSyncMutationResponse(
        statusCode: 200,
        body: _appliedJson(),
      );

      expect(result.isApplied, isTrue);
      expect(result.isConflict, isFalse);
      expect(result.mutationId, _mutationId);
      expect(result.note?.id, _noteId);
      expect(result.note?.title, 'Title');
      expect(result.note?.content, _content);
      expect(result.note?.revision, 1);
      expect(result.note?.createdAt, DateTime.utc(2026, 9, 24, 10));
      expect(result.note?.serverUpdatedAt, DateTime.utc(2026, 9, 24, 11));
      expect(result.note?.deletedAt, isNull);
      expect(result.note?.isDeleted, isFalse);
      expect(result.conflictRemote, isNull);
    });

    test('decodes an applied response from raw JSON text', () {
      final SyncMutationResult result = decodeSyncMutationResponse(
        statusCode: 200,
        body: jsonEncode(_appliedJson()),
      );

      expect(result.isApplied, isTrue);
      expect(result.note?.content, _content);
    });

    test('treats any 2xx status as applied', () {
      final SyncMutationResult result = decodeSyncMutationResponse(
        statusCode: 201,
        body: _appliedJson(),
      );

      expect(result.isApplied, isTrue);
    });

    test('falls back to the request mutationId when the body omits it', () {
      final Map<String, Object?> json = _appliedJson()..remove('mutationId');

      final SyncMutationResult result = decodeSyncMutationResponse(
        statusCode: 200,
        body: json,
        mutationId: _mutationId,
      );

      expect(result.mutationId, _mutationId);
    });

    test('rejects an applied response without a mutation identity', () {
      final Map<String, Object?> json = _appliedJson()..remove('mutationId');

      expect(
        () => decodeSyncMutationResponse(statusCode: 200, body: json),
        _throwsFormatException(),
      );
    });

    test('rejects a non-2xx, non-409 status', () {
      expect(
        () => decodeSyncMutationResponse(statusCode: 500, body: _appliedJson()),
        _throwsFormatException(),
      );
    });

    test('rejects a response whose status field contradicts the code', () {
      final Map<String, Object?> json = _appliedJson()..['status'] = 'conflict';

      expect(
        () => decodeSyncMutationResponse(statusCode: 200, body: json),
        _throwsFormatException(),
      );
    });
  });

  group('decodeSyncMutationResponse conflict', () {
    test('decodes a 409 conflict with the remote snapshot', () {
      final SyncMutationResult result = decodeSyncMutationResponse(
        statusCode: 409,
        body: _conflictJson(remoteNote: _noteJson(overrides: {'revision': 5})),
      );

      expect(result.isConflict, isTrue);
      expect(result.isApplied, isFalse);
      expect(result.mutationId, _mutationId);
      expect(result.note, isNull);
      expect(result.conflictRemote?.revision, 5);
      expect(result.conflictRemote?.content, _content);
    });

    test('decodes a 409 conflict whose remoteNote is null', () {
      final SyncMutationResult result = decodeSyncMutationResponse(
        statusCode: 409,
        body: _conflictJson(),
      );

      expect(result.isConflict, isTrue);
      expect(result.conflictRemote, isNull);
    });

    test('decodes a 409 conflict from raw JSON text', () {
      final SyncMutationResult result = decodeSyncMutationResponse(
        statusCode: 409,
        body: jsonEncode(_conflictJson(remoteNote: _noteJson())),
        mutationId: _mutationId,
      );

      expect(result.isConflict, isTrue);
      expect(result.conflictRemote?.id, _noteId);
    });

    test('falls back to the request mutationId for a bare 409 envelope', () {
      final SyncMutationResult result = decodeSyncMutationResponse(
        statusCode: 409,
        body: <String, Object?>{'code': 'REVISION_CONFLICT'},
        mutationId: _mutationId,
      );

      expect(result.mutationId, _mutationId);
      expect(result.conflictRemote, isNull);
    });

    test('rejects a 409 conflict with no mutation identity at all', () {
      expect(
        () => decodeSyncMutationResponse(
          statusCode: 409,
          body: <String, Object?>{'code': 'REVISION_CONFLICT'},
        ),
        _throwsFormatException(),
      );
    });
  });

  group('decodeChangesPage', () {
    test('decodes items, the cursor, and hasMore', () {
      final SyncChangesPage page = decodeChangesPage(
        _changesJson(nextCursor: 'opaque-cursor', hasMore: true),
      );

      expect(page.snapshots, hasLength(1));
      expect(page.snapshots.single.id, _noteId);
      expect(page.snapshots.single.revision, 1);
      expect(page.nextCursor, 'opaque-cursor');
      expect(page.hasMore, isTrue);
    });

    test('keeps nextCursor on a final page with hasMore false', () {
      final SyncChangesPage page = decodeChangesPage(
        _changesJson(nextCursor: 'last-applied-cursor', hasMore: false),
      );

      // The final cursor is the last applied position, not only a paging hint.
      expect(page.hasMore, isFalse);
      expect(page.nextCursor, 'last-applied-cursor');
    });

    test('decodes a tombstone item as deleted', () {
      final SyncChangesPage page = decodeChangesPage(
        _changesJson(
          items: <Object?>[
            _noteJson(
              overrides: <String, Object?>{
                'deletedAt': '2026-09-24T12:00:00.000Z',
              },
            ),
          ],
        ),
      );

      final SyncNoteSnapshot tombstone = page.snapshots.single;
      expect(tombstone.isDeleted, isTrue);
      expect(tombstone.deletedAt, DateTime.utc(2026, 9, 24, 12));
      // A tombstone keeps the note identity and content it deleted.
      expect(tombstone.id, _noteId);
      expect(tombstone.content, _content);
    });

    test('decodes an empty first page', () {
      final SyncChangesPage page = decodeChangesPage(<String, Object?>{
        'items': <Object?>[],
      });

      expect(page.snapshots, isEmpty);
      expect(page.nextCursor, isNull);
      expect(page.hasMore, isFalse);
    });

    test('decodes a page from raw JSON text', () {
      final SyncChangesPage page = decodeChangesPage(
        jsonEncode(_changesJson(nextCursor: 'c1', hasMore: false)),
      );

      expect(page.snapshots.single.id, _noteId);
      expect(page.nextCursor, 'c1');
    });

    test('treats an empty cursor as absent', () {
      final SyncChangesPage page = decodeChangesPage(
        _changesJson(nextCursor: '', hasMore: false),
      );

      expect(page.nextCursor, isNull);
      expect(page.hasMore, isFalse);
    });
  });

  group('malformed payload rejection', () {
    test('rejects a body that is not a JSON object', () {
      expect(() => decodeChangesPage(<Object?>[]), _throwsFormatException());
      expect(
        () => decodeSyncMutationResponse(statusCode: 200, body: <Object?>[]),
        _throwsFormatException(),
      );
      expect(() => decodeChangesPage(null), _throwsFormatException());
    });

    test('rejects raw text that is not JSON', () {
      expect(() => decodeChangesPage('not json'), _throwsFormatException());
      expect(
        () => decodeSyncMutationResponse(statusCode: 200, body: 'not json'),
        _throwsFormatException(),
      );
    });

    test('rejects JSON text that is not an object', () {
      expect(() => decodeChangesPage('[]'), _throwsFormatException());
      expect(() => decodeChangesPage('42'), _throwsFormatException());
    });

    test('rejects an applied response without a note', () {
      final Map<String, Object?> json = _appliedJson()..remove('note');

      expect(
        () => decodeSyncMutationResponse(statusCode: 200, body: json),
        _throwsFormatException(),
      );
    });

    test('rejects an applied response whose note is not an object', () {
      expect(
        () => decodeSyncMutationResponse(
          statusCode: 200,
          body: <String, Object?>{
            'status': 'applied',
            'mutationId': _mutationId,
            'note': <Object?>[],
          },
        ),
        _throwsFormatException(),
      );
    });

    test('rejects a note with a missing required field', () {
      for (final String field in <String>[
        'id',
        'title',
        'content',
        'createdAt',
        'serverUpdatedAt',
        'revision',
      ]) {
        final Map<String, Object?> note = _noteJson()..remove(field);

        expect(
          () => decodeSyncMutationResponse(
            statusCode: 200,
            body: _appliedJson(note: note),
          ),
          _throwsFormatException(),
          reason: 'missing $field must be rejected',
        );
      }
    });

    test('rejects a note with a blank or non-string id', () {
      for (final Object? id in <Object?>['', '   ', 7, null]) {
        expect(
          () => decodeSyncMutationResponse(
            statusCode: 200,
            body: _appliedJson(note: _noteJson(overrides: {'id': id})),
          ),
          _throwsFormatException(),
          reason: 'id $id must be rejected',
        );
      }
    });

    test('rejects a non-string title or content', () {
      for (final String field in <String>['title', 'content']) {
        expect(
          () => decodeSyncMutationResponse(
            statusCode: 200,
            body: _appliedJson(note: _noteJson(overrides: {field: 7})),
          ),
          _throwsFormatException(),
          reason: 'non-string $field must be rejected',
        );
      }
    });

    test('rejects a malformed createdAt or serverUpdatedAt', () {
      for (final String field in <String>['createdAt', 'serverUpdatedAt']) {
        for (final Object? value in <Object?>['', 'not-a-date', 42, true]) {
          expect(
            () => decodeSyncMutationResponse(
              statusCode: 200,
              body: _appliedJson(note: _noteJson(overrides: {field: value})),
            ),
            _throwsFormatException(),
            reason: '$field $value must be rejected',
          );
        }
      }
    });

    test('rejects a malformed tombstone timestamp', () {
      for (final Object? value in <Object?>['', 'not-a-date', 42, true]) {
        expect(
          () => decodeChangesPage(
            _changesJson(
              items: <Object?>[
                _noteJson(overrides: <String, Object?>{'deletedAt': value}),
              ],
            ),
          ),
          _throwsFormatException(),
          reason: 'deletedAt $value must be rejected',
        );
      }
    });

    test('rejects a revision that is not a positive integer', () {
      for (final Object? revision in <Object?>[0, -1, 1.5, '1', null, true]) {
        expect(
          () => decodeSyncMutationResponse(
            statusCode: 200,
            body: _appliedJson(
              note: _noteJson(
                overrides: <String, Object?>{'revision': revision},
              ),
            ),
          ),
          _throwsFormatException(),
          reason: 'revision $revision must be rejected',
        );
      }
    });

    test('rejects a page without an items array', () {
      expect(
        () => decodeChangesPage(<String, Object?>{'nextCursor': 'c1'}),
        _throwsFormatException(),
      );
      expect(
        () => decodeChangesPage(<String, Object?>{'items': 'nope'}),
        _throwsFormatException(),
      );
    });

    test('rejects a page whose item is not an object', () {
      expect(
        () => decodeChangesPage(<String, Object?>{
          'items': <Object?>['not-a-note'],
        }),
        _throwsFormatException(),
      );
    });

    test('rejects a page that claims hasMore without a cursor', () {
      expect(
        () => decodeChangesPage(<String, Object?>{
          'items': <Object?>[],
          'hasMore': true,
        }),
        _throwsFormatException(),
      );
      expect(
        () => decodeChangesPage(_changesJson(nextCursor: '', hasMore: true)),
        _throwsFormatException(),
      );
    });

    test('rejects a non-boolean hasMore or non-string cursor', () {
      expect(
        () => decodeChangesPage(_changesJson(hasMore: 'true')),
        _throwsFormatException(),
      );
      expect(
        () => decodeChangesPage(_changesJson(nextCursor: 42)),
        _throwsFormatException(),
      );
    });

    test('rejects a malformed conflict remoteNote', () {
      expect(
        () => decodeSyncMutationResponse(
          statusCode: 409,
          body: _conflictJson(remoteNote: <Object?>[]),
        ),
        _throwsFormatException(),
      );
      expect(
        () => decodeSyncMutationResponse(
          statusCode: 409,
          body: _conflictJson(
            remoteNote: _noteJson(overrides: <String, Object?>{'revision': 0}),
          ),
        ),
        _throwsFormatException(),
      );
    });
  });

  group('decodeError', () {
    test('classifies the frozen status table', () {
      const Map<int, SyncErrorCode> cases = <int, SyncErrorCode>{
        401: SyncErrorCode.unauthorized,
        403: SyncErrorCode.forbidden,
        422: SyncErrorCode.invalidMutation,
        429: SyncErrorCode.throttled,
        500: SyncErrorCode.serverUnavailable,
        502: SyncErrorCode.serverUnavailable,
        503: SyncErrorCode.serverUnavailable,
        504: SyncErrorCode.serverUnavailable,
      };

      cases.forEach((int status, SyncErrorCode code) {
        final SyncFailure failure = decodeError(
          statusCode: status,
          body: <String, Object?>{'code': 'SOME_CODE', 'retryable': true},
        );

        expect(failure.code, code, reason: 'status $status');
        expect(
          failure.retryable,
          code == SyncErrorCode.throttled ||
              code == SyncErrorCode.serverUnavailable,
          reason: 'status $status retryability',
        );
      });
    });

    test('maps an unlisted status to unexpected', () {
      expect(
        decodeError(
          statusCode: 400,
          body: <String, Object?>{'code': 'BAD_REQUEST'},
        ).code,
        SyncErrorCode.unexpected,
      );
    });

    test('falls back to the envelope code when the status is absent', () {
      expect(
        decodeError(body: <String, Object?>{'code': 'THROTTLED'}).code,
        SyncErrorCode.throttled,
      );
      expect(
        decodeError(
          statusCode: 418,
          body: <String, Object?>{'code': 'SERVER_UNAVAILABLE'},
        ).code,
        SyncErrorCode.serverUnavailable,
      );
      expect(
        decodeError(body: <String, Object?>{'code': 'NONSENSE'}).code,
        SyncErrorCode.unexpected,
      );
    });

    test('does not throw on a malformed error body', () {
      expect(
        decodeError(statusCode: 500, body: 'not json').code,
        SyncErrorCode.serverUnavailable,
      );
      expect(
        decodeError(statusCode: 503, body: <Object?>[]).code,
        SyncErrorCode.serverUnavailable,
      );
      expect(decodeError().code, SyncErrorCode.unexpected);
    });

    test('retains no provider text from the error envelope', () {
      const String secret = 'access-token-secret-1';
      final SyncFailure failure = decodeError(
        statusCode: 500,
        body: <String, Object?>{
          'code': 'SERVER_UNAVAILABLE',
          'message': 'failed for $secret with $_content at $_mutationId',
          'retryable': true,
          'stackTrace': 'at handler (/var/task/index.js:1:1)',
        },
      );

      expect(failure.code, SyncErrorCode.serverUnavailable);
      expect(failure.detail, isNull);
      expect(failure.toString(), isNot(contains(secret)));
      expect(failure.toString(), isNot(contains(_content)));
      expect(failure.toString(), isNot(contains('/var/task')));
    });
  });
}
