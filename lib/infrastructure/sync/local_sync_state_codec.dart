/// Codec and schema-2 migration for one account's local sync document.
library;

import '../../application/sync/local_note_state.dart';
import '../../application/sync/local_sync_state.dart';
import '../../application/sync/pending_mutation.dart';
import '../../application/sync/sync_conflict.dart';
import '../../application/sync/sync_cursor.dart';
import '../../domain/users/user_preferences.dart';
import 'local_note_state_codec.dart';
import 'local_sync_codec_exception.dart';
import 'local_sync_codec_reader.dart';
import 'local_sync_codec_schema.dart';
import 'local_sync_schema_migration.dart';
import 'pending_mutation_codec.dart';
import 'sync_conflict_codec.dart';
import 'sync_cursor_codec.dart';

abstract final class LocalSyncStateCodec {
  static const int schemaVersion = LocalSyncSchema.version;
  static const String _rootPath = 'localSyncState';

  /// Encodes the complete account state using the current strict schema.
  static Map<String, Object?> encode(LocalSyncState state) => <String, Object?>{
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
    LocalSyncSchema.userPreferences: _encodePreferences(state.userPreferences),
  };

  /// Decodes schema 5, migrating supported schema 2/3/4 envelopes in memory.
  /// Existing attempted mutations retain their old payload shape and ID.
  static LocalSyncState decode(Object? data) {
    final Map<String, Object?> raw = _asObject(data, _rootPath);
    if (!raw.containsKey(LocalSyncSchema.schemaVersion)) {
      throw const LocalSyncCodecException(
        'must contain the field "schemaVersion".',
        path: 'localSyncState',
      );
    }
    final Object? version = raw[LocalSyncSchema.schemaVersion];
    if (version == 2) {
      final SyncCodecObject legacy = SyncCodecObject.from(
        raw,
        path: _rootPath,
        allowedFields: LocalSyncSchema.envelopeFieldsV2,
      );
      _validateV2(legacy);
      return _decodeCurrent(
        migrateLocalSyncV3(
          _migrateV2(
            raw,
            legacy.requireNonBlankString(LocalSyncSchema.accountUserId),
          ),
        ),
      );
    }
    if (version == 3) return _decodeCurrent(migrateLocalSyncV3(raw));
    if (version == 4) return _decodeCurrent(migrateLocalSyncV4(raw));
    if (version != schemaVersion) {
      throw LocalSyncCodecException(
        'must be schemaVersion $schemaVersion or a supported older version.',
        path: '$_rootPath.${LocalSyncSchema.schemaVersion}',
      );
    }
    return _decodeCurrent(raw);
  }

  static LocalSyncState _decodeCurrent(Map<String, Object?> data) {
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
    final UserPreferences preferences = _decodePreferences(
      envelope.requireObject(
        LocalSyncSchema.userPreferences,
        LocalSyncSchema.userPreferencesFields,
      ),
    );

    return buildCodecModel(
      () => LocalSyncState(
        accountUserId: accountUserId,
        notes: notes,
        outbox: outbox,
        conflicts: conflicts,
        cursor: cursor,
        userPreferences: preferences,
      ),
      path: _rootPath,
    );
  }

  static Map<String, Object?> _migrateV2(
    Map<String, Object?> old,
    String accountUserId,
  ) {
    final List<Object?> notes = _objectList(
      old,
      LocalSyncSchema.notes,
    ).map(_addNullPin).toList(growable: false);
    final List<Object?> conflicts = _objectList(old, LocalSyncSchema.conflicts)
        .map((Object? value) {
          final Map<String, Object?> conflict = _asObject(value, 'conflict');
          final Object? remote = conflict[LocalSyncSchema.remote];
          return <String, Object?>{
            ...conflict,
            LocalSyncSchema.local: _addNullPin(conflict[LocalSyncSchema.local]),
            if (remote != null) LocalSyncSchema.remote: _addNullPin(remote),
          };
        })
        .toList(growable: false);
    return <String, Object?>{
      ...old,
      LocalSyncSchema.schemaVersion: 3,
      LocalSyncSchema.notes: notes,
      LocalSyncSchema.conflicts: conflicts,
      LocalSyncSchema.userPreferences: <String, Object?>{
        LocalSyncSchema.userId: accountUserId,
        LocalSyncSchema.theme: AppThemePreference.system.name,
        LocalSyncSchema.noteFontSize: NoteFontSizePreference.medium.name,
        LocalSyncSchema.noteColorKey: null,
        LocalSyncSchema.noteLayout: NoteLayoutPreference.grid.name,
      },
    };
  }

  static void _validateV2(SyncCodecObject envelope) {
    envelope.requireObjectList(
      LocalSyncSchema.notes,
      LocalSyncSchema.noteFieldsV2,
    );
    for (final SyncCodecObject mutation in envelope.requireObjectList(
      LocalSyncSchema.outbox,
      LocalSyncSchema.mutationFieldsV2,
    )) {
      if (mutation.rawValue(LocalSyncSchema.payload) != null) {
        mutation.requireObject(
          LocalSyncSchema.payload,
          LocalSyncSchema.payloadFieldsV2,
        );
      }
    }
    for (final SyncCodecObject conflict in envelope.requireObjectList(
      LocalSyncSchema.conflicts,
      LocalSyncSchema.conflictFieldsV2,
    )) {
      conflict.requireObject(
        LocalSyncSchema.local,
        LocalSyncSchema.noteFieldsV2,
      );
      conflict.requireNullableObject(
        LocalSyncSchema.remote,
        LocalSyncSchema.snapshotFieldsV2,
      );
      final SyncCodecObject pending = conflict.requireObject(
        LocalSyncSchema.pending,
        LocalSyncSchema.mutationFieldsV2,
      );
      if (pending.rawValue(LocalSyncSchema.payload) != null) {
        pending.requireObject(
          LocalSyncSchema.payload,
          LocalSyncSchema.payloadFieldsV2,
        );
      }
    }
  }

  static Map<String, Object?> _addNullPin(Object? value) => <String, Object?>{
    ..._asObject(value, 'note'),
    LocalSyncSchema.pinnedAt: null,
  };

  static List<Object?> _objectList(Map<String, Object?> data, String field) {
    final Object? value = data[field];
    if (value is! List) {
      throw LocalSyncCodecException(
        'must be an array.',
        path: '$_rootPath.$field',
      );
    }
    return List<Object?>.of(value);
  }

  static Map<String, Object?> _asObject(Object? value, String path) {
    if (value is! Map) {
      throw LocalSyncCodecException('must be an object.', path: path);
    }
    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      if (entry.key is! String) {
        throw LocalSyncCodecException(
          'must use string field names.',
          path: path,
        );
      }
      result[entry.key! as String] = entry.value;
    }
    return result;
  }

  static Map<String, Object?> _encodePreferences(UserPreferences preferences) =>
      <String, Object?>{
        LocalSyncSchema.userId: preferences.userId,
        LocalSyncSchema.theme: preferences.theme.name,
        LocalSyncSchema.noteFontSize: preferences.noteFontSize.name,
        LocalSyncSchema.noteColorKey: preferences.noteColorKey,
        LocalSyncSchema.noteLayout: preferences.noteLayout.name,
      };

  static UserPreferences _decodePreferences(SyncCodecObject record) =>
      buildCodecModel(
        () => UserPreferences.reconstitute(
          userId: record.requireNonBlankString(LocalSyncSchema.userId),
          theme: record.requireEnum(
            LocalSyncSchema.theme,
            AppThemePreference.values,
          ),
          noteFontSize: record.requireEnum(
            LocalSyncSchema.noteFontSize,
            NoteFontSizePreference.values,
          ),
          noteColorKey: record.requireNullableString(
            LocalSyncSchema.noteColorKey,
          ),
          noteLayout: record.requireEnum(
            LocalSyncSchema.noteLayout,
            NoteLayoutPreference.values,
          ),
        ),
        path: record.path,
      );
}
