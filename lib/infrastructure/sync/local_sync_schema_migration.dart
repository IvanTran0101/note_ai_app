import 'local_sync_codec_exception.dart';
import 'local_sync_codec_reader.dart';
import 'local_sync_codec_schema.dart';

/// Migrates either published v3 shape without altering queued request payloads.
/// Encryption's packet version/AAD is independent of this inner schema.
Map<String, Object?> migrateLocalSyncV3(Map<String, Object?> data) {
  SyncCodecObject.from(
    data,
    path: 'localSyncState',
    allowedFields: LocalSyncSchema.envelopeFieldsV2,
    optionalFields: {LocalSyncSchema.userPreferences},
  );
  List<dynamic> records(String field) {
    final value = data[field];
    if (value is! List) {
      throw const LocalSyncCodecException('must be a list.');
    }
    return value;
  }

  Map<String, Object?> note(Object? raw, bool remote) {
    if (raw is! Map) throw const LocalSyncCodecException('must be an object.');
    final record = Map<String, Object?>.from(raw);
    final fields = remote
        ? LocalSyncSchema.snapshotFields
        : LocalSyncSchema.noteFields;
    final optional = remote
        ? LocalSyncSchema.snapshotOptionalFields
        : LocalSyncSchema.noteOptionalFields;
    final security = {'protected', 'protectionRevision', 'contentAvailable'};
    final hasSecurity = security.any(record.containsKey);
    SyncCodecObject.from(
      record,
      path: 'legacy.note',
      allowedFields: fields.difference({
        'pinnedAt',
        'attachments',
        if (!hasSecurity) ...security,
      }),
      optionalFields: {...optional, 'pinnedAt'},
    );
    return {
      'protected': false,
      'protectionRevision': 0,
      'contentAvailable': true,
      'pinnedAt': null,
      'attachments': <Object?>[],
      if (remote) 'includesAttachments': false,
      ...record,
    };
  }

  final account = data['accountUserId'];
  return {
    ...data,
    'schemaVersion': LocalSyncSchema.version,
    'notes': records('notes').map((n) => note(n, false)).toList(),
    'conflicts': records('conflicts').map((raw) {
      if (raw is! Map) {
        throw const LocalSyncCodecException('must be an object.');
      }
      final conflict = Map<String, Object?>.from(raw);
      return {
        ...conflict,
        'local': note(conflict['local'], false),
        'remote': conflict['remote'] == null
            ? null
            : note(conflict['remote'], true),
      };
    }).toList(),
    'userPreferences':
        data['userPreferences'] ??
        {
          'userId': account,
          'theme': 'system',
          'noteFontSize': 'medium',
          'noteColorKey': null,
          'noteLayout': 'grid',
        },
  };
}

/// Inner v4 predates attachments. Freeze its exact note shape before adding
/// the empty manifest; queued payloads remain byte-for-byte unchanged.
Map<String, Object?> migrateLocalSyncV4(Map<String, Object?> data) {
  final envelope = SyncCodecObject.from(
    data,
    path: 'legacy.v4',
    allowedFields: LocalSyncSchema.envelopeFields,
  );
  void validate(Object? raw, bool remote) {
    SyncCodecObject.from(
      raw,
      path: 'legacy.v4.note',
      allowedFields:
          (remote ? LocalSyncSchema.snapshotFields : LocalSyncSchema.noteFields)
              .difference({'attachments'}),
      optionalFields: remote
          ? LocalSyncSchema.snapshotOptionalFields
          : LocalSyncSchema.noteOptionalFields,
    );
  }

  envelope.requireObjectList(
    'notes',
    LocalSyncSchema.noteFields.difference({'attachments'}),
    optionalFields: LocalSyncSchema.noteOptionalFields,
  );
  for (final record in envelope.requireObjectList(
    'conflicts',
    LocalSyncSchema.conflictFields,
  )) {
    validate(record.rawValue('local'), false);
    if (record.rawValue('remote') != null) {
      validate(record.rawValue('remote'), true);
    }
  }
  return migrateLocalSyncV3(data);
}
