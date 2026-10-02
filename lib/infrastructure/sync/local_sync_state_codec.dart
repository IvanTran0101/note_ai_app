/// The M2.0 local sync state envelope codec.
///
/// [LocalSyncStateCodec] is the single entrypoint for the frozen local sync
/// document: [encode] turns a validated [LocalSyncState] into a
/// `Map<String, Object?>` and [decode] turns such a map back into a state,
/// rejecting anything that is not exactly the M2 schema. The map is the
/// boundary -- a caller serializes it later with `jsonEncode` for native JSON or
/// stores it as-is in IndexedDB -- so this library has no JSON, file, browser,
/// or provider dependency, and no I/O of any kind.
///
/// Every record codec writes each declared field, nullable ones as explicit
/// nulls, so the document shape is fixed. An unknown field, a missing field, a
/// wrong type, an unknown enum name, an unparsable timestamp, a duplicate note
/// or mutation id, and a note owned by another account are all rejected with a
/// [LocalSyncCodecException] whose message never contains a stored value.
library;

import '../../application/sync/local_note_state.dart';
import '../../application/sync/local_sync_state.dart';
import '../../application/sync/pending_mutation.dart';
import '../../application/sync/sync_conflict.dart';
import '../../application/sync/sync_cursor.dart';
import 'local_note_state_codec.dart';
import 'local_sync_codec_reader.dart';
import 'local_sync_codec_schema.dart';
import 'pending_mutation_codec.dart';
import 'sync_conflict_codec.dart';
import 'sync_cursor_codec.dart';

/// Maps the whole account-scoped local sync document.
abstract final class LocalSyncStateCodec {
  /// The schema version this codec writes and the only one it reads.
  static const int schemaVersion = LocalSyncSchema.version;

  /// Root path used in failure messages, for example
  /// `localSyncState.notes[1].status`.
  static const String _rootPath = 'localSyncState';

  /// Encodes [state] as a JSON-compatible envelope.
  ///
  /// The result carries exactly `schemaVersion`, `accountUserId`, `notes`,
  /// `outbox`, `cursor`, and `conflicts`. The cursor is the raw value or null.
  static Map<String, Object?> encode(LocalSyncState state) {
    return <String, Object?>{
      LocalSyncSchema.schemaVersion: schemaVersion,
      LocalSyncSchema.accountUserId: state.accountUserId,
      LocalSyncSchema.notes: <Object?>[
        for (final LocalNoteState note in state.notes)
          LocalNoteStateCodec.encode(note),
      ],
      LocalSyncSchema.outbox: <Object?>[
        for (final PendingMutation entry in state.outbox)
          PendingMutationCodec.encode(entry),
      ],
      LocalSyncSchema.cursor: SyncCursorCodec.encode(state.cursor),
      LocalSyncSchema.conflicts: <Object?>[
        for (final SyncConflict conflict in state.conflicts)
          SyncConflictCodec.encode(conflict),
      ],
    };
  }

  /// Decodes a stored envelope back into a validated [LocalSyncState].
  ///
  /// [data] is the already-decoded object: a `Map<String, Object?>` from
  /// `jsonDecode`, from IndexedDB, or from a test. Raw JSON text is not accepted
  /// here, because JSON parsing is the caller's boundary and not this codec's.
  static LocalSyncState decode(Object? data) {
    final SyncCodecObject envelope = SyncCodecObject.from(
      data,
      path: _rootPath,
      allowedFields: LocalSyncSchema.envelopeFields,
    );

    final int version = envelope.requireInt(LocalSyncSchema.schemaVersion);
    if (version != schemaVersion) {
      envelope.fail(
        LocalSyncSchema.schemaVersion,
        'must be schemaVersion $schemaVersion.',
      );
    }
    final String accountUserId = envelope.requireNonBlankString(
      LocalSyncSchema.accountUserId,
    );

    final List<LocalNoteState> notes = <LocalNoteState>[];
    final Set<String> noteIds = <String>{};
    for (final SyncCodecObject record in envelope.requireObjectList(
      LocalSyncSchema.notes,
      LocalSyncSchema.noteFields,
      optionalFields: LocalSyncSchema.noteOptionalFields,
    )) {
      final LocalNoteState note = LocalNoteStateCodec.decodeRecord(record);
      if (note.ownerId != accountUserId &&
          (note.share == null || note.share!.recipientId != accountUserId)) {
        record.fail(
          LocalSyncSchema.ownerId,
          'must belong to the state account.',
        );
      }
      if (!noteIds.add(note.identity.key)) {
        record.fail(LocalSyncSchema.id, 'duplicates an earlier note id.');
      }
      notes.add(note);
    }

    final List<PendingMutation> outbox = <PendingMutation>[];
    final Set<String> mutationIds = <String>{};
    for (final SyncCodecObject record in envelope.requireObjectList(
      LocalSyncSchema.outbox,
      LocalSyncSchema.mutationFields,
      optionalFields: LocalSyncSchema.mutationOptionalFields,
    )) {
      final PendingMutation entry = PendingMutationCodec.decodeRecord(record);
      if (!mutationIds.add(entry.mutationId)) {
        record.fail(
          LocalSyncSchema.mutationId,
          'duplicates an earlier mutation id.',
        );
      }
      outbox.add(entry);
    }

    final SyncCursor? cursor = SyncCursorCodec.decode(
      envelope.rawValue(LocalSyncSchema.cursor),
      path: envelope.fieldPath(LocalSyncSchema.cursor),
    );

    final List<SyncConflict> conflicts = <SyncConflict>[
      for (final SyncCodecObject record in envelope.requireObjectList(
        LocalSyncSchema.conflicts,
        LocalSyncSchema.conflictFields,
      ))
        SyncConflictCodec.decodeRecord(record),
    ];

    return buildCodecModel(
      () => LocalSyncState(
        accountUserId: accountUserId,
        notes: notes,
        outbox: outbox,
        conflicts: conflicts,
        cursor: cursor,
      ),
      path: _rootPath,
    );
  }
}
