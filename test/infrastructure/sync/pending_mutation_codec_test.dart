import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_codec_exception.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_codec_schema.dart';
import 'package:note_ai_app/infrastructure/sync/pending_mutation_codec.dart';

import 'local_sync_codec_fixtures.dart';

void main() {
  group('round trip', () {
    test('decodes an encoded create with its payload', () {
      final PendingMutation entry = mutationFixture(baseRevision: 4);

      final Map<String, Object?> record = PendingMutationCodec.encode(entry);
      final PendingMutation decoded = PendingMutationCodec.decode(record);

      expect(decoded, entry);
      expect(record.keys.toSet(), LocalSyncSchema.mutationFields);
      expect(record['operation'], 'create');
      expect(record['baseRevision'], 4);
      expect(record['createdAt'], fixtureUpdatedAt.toIso8601String());
      expect(copyRecord(record['payload']), <String, Object?>{
        'title': fixturePayloadTitle,
        'content': fixturePayloadContent,
      });
      expect(decoded.payload, entry.payload);
      expect(decoded.toMutation(), entry.toMutation());
    });

    test('round-trips retry bookkeeping and a blocked entry', () {
      final PendingMutation entry = mutationFixture(
        operation: SyncMutationOperation.update,
        baseRevision: 9,
        retryCount: 3,
        lastError: SyncErrorCode.serverUnavailable,
        blocked: true,
      );

      final PendingMutation decoded = PendingMutationCodec.decode(
        PendingMutationCodec.encode(entry),
      );

      expect(decoded, entry);
      expect(decoded.retryCount, 3);
      expect(decoded.lastError, SyncErrorCode.serverUnavailable);
      expect(decoded.blocked, isTrue);
    });

    test('writes an explicit null payload for a delete', () {
      final PendingMutation entry = mutationFixture(
        operation: SyncMutationOperation.delete,
        payload: null,
      );

      final Map<String, Object?> record = PendingMutationCodec.encode(entry);

      expect(record.containsKey('payload'), isTrue);
      expect(record['payload'], isNull);
      expect(record['lastError'], isNull);
      final PendingMutation decoded = PendingMutationCodec.decode(record);
      expect(decoded, entry);
      expect(decoded.payload, isNull);
    });

    test('round-trips every operation and error code name', () {
      for (final SyncMutationOperation operation
          in SyncMutationOperation.values) {
        for (final SyncErrorCode code in SyncErrorCode.values) {
          final PendingMutation entry = mutationFixture(
            operation: operation,
            payload: operation == SyncMutationOperation.delete
                ? null
                : const SyncNotePayload(title: 't', content: 'c'),
            lastError: code,
          );
          expect(
            PendingMutationCodec.decode(PendingMutationCodec.encode(entry)),
            entry,
          );
        }
      }
    });
  });

  group('strict record validation', () {
    test('rejects a missing metadata field', () {
      final Map<String, Object?> record = PendingMutationCodec.encode(
        mutationFixture(),
      )..remove('retryCount');

      final LocalSyncCodecException error = codecFailure(
        () => PendingMutationCodec.decode(record),
      );

      expect(error.message, 'must contain the field "retryCount".');
    });

    test('rejects a field outside the frozen mutation schema', () {
      final Map<String, Object?> record = PendingMutationCodec.encode(
        mutationFixture(),
      )..['error'] = 'none';

      final LocalSyncCodecException error = codecFailure(
        () => PendingMutationCodec.decode(record),
      );

      expect(error.message, contains('outside the M2 local sync schema'));
    });

    test('requires a payload for create and update', () {
      for (final SyncMutationOperation operation in <SyncMutationOperation>[
        SyncMutationOperation.create,
        SyncMutationOperation.update,
      ]) {
        final Map<String, Object?> record = PendingMutationCodec.encode(
          mutationFixture(operation: operation),
        )..['payload'] = null;

        final LocalSyncCodecException error = codecFailure(
          () => PendingMutationCodec.decode(record),
        );

        expect(error.message, 'is required for create and update.');
        expect(error.path, 'outbox entry.payload');
      }
    });

    test('rejects an unknown operation or error code name', () {
      final Map<String, Object?> badOperation = PendingMutationCodec.encode(
        mutationFixture(),
      )..['operation'] = 'upsert';
      expect(
        codecFailure(() => PendingMutationCodec.decode(badOperation)).message,
        'must name a declared SyncMutationOperation value.',
      );

      final Map<String, Object?> badError = PendingMutationCodec.encode(
        mutationFixture(),
      )..['lastError'] = 'rateLimited';
      expect(
        codecFailure(() => PendingMutationCodec.decode(badError)).message,
        'must name a declared SyncErrorCode value.',
      );
    });

    test('rejects negative revisions and retry counts', () {
      final Map<String, Object?> badRevision = PendingMutationCodec.encode(
        mutationFixture(),
      )..['baseRevision'] = -1;
      expect(
        codecFailure(() => PendingMutationCodec.decode(badRevision)).message,
        'must not be negative.',
      );

      final Map<String, Object?> badRetry = PendingMutationCodec.encode(
        mutationFixture(),
      )..['retryCount'] = -2;
      final LocalSyncCodecException error = codecFailure(
        () => PendingMutationCodec.decode(badRetry),
      );
      expect(error.message, 'must not be negative.');
      expect(error.path, 'outbox entry.retryCount');
    });

    test('rejects a non-boolean blocked flag', () {
      final Map<String, Object?> record = PendingMutationCodec.encode(
        mutationFixture(),
      )..['blocked'] = 'yes';

      final LocalSyncCodecException error = codecFailure(
        () => PendingMutationCodec.decode(record),
      );

      expect(error.message, 'must be a boolean.');
      expect(error.path, 'outbox entry.blocked');
    });

    test('rejects a malformed payload', () {
      final Map<String, Object?> missingContent = PendingMutationCodec.encode(
        mutationFixture(),
      );
      missingContent['payload'] = copyRecord(missingContent['payload'])
        ..remove('content');
      final LocalSyncCodecException missing = codecFailure(
        () => PendingMutationCodec.decode(missingContent),
      );
      expect(missing.message, 'must contain the field "content".');
      expect(missing.path, 'outbox entry.payload');

      final Map<String, Object?> extraField = PendingMutationCodec.encode(
        mutationFixture(),
      );
      extraField['payload'] = <String, Object?>{
        'title': fixturePayloadTitle,
        'content': fixturePayloadContent,
        'ownerId': 'user-1',
      };
      expect(
        codecFailure(() => PendingMutationCodec.decode(extraField)).message,
        contains('outside the M2 local sync schema'),
      );

      final Map<String, Object?> wrongType = PendingMutationCodec.encode(
        mutationFixture(),
      );
      wrongType['payload'] = 'title and content';
      expect(
        codecFailure(() => PendingMutationCodec.decode(wrongType)).message,
        'must be an object.',
      );
    });

    test('rejects an empty or unparsable queued timestamp', () {
      final Map<String, Object?> record = PendingMutationCodec.encode(
        mutationFixture(),
      )..['createdAt'] = '';

      final LocalSyncCodecException error = codecFailure(
        () => PendingMutationCodec.decode(record),
      );

      expect(error.path, 'outbox entry.createdAt');
    });
  });

  test('never echoes payload text in a failure', () {
    final Map<String, Object?> record = PendingMutationCodec.encode(
      mutationFixture(
        payload: const SyncNotePayload(
          title: secretTitle,
          content: secretContent,
        ),
      ),
    )..['retryCount'] = -1;

    final LocalSyncCodecException error = codecFailure(
      () => PendingMutationCodec.decode(record),
    );

    expect(error.toString(), isNot(contains(secretTitle)));
    expect(error.toString(), isNot(contains(secretContent)));
  });
}
