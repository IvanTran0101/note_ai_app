import 'local_sync_codec_exception.dart';
import 'local_sync_codec_reader.dart';
import 'local_sync_codec_schema.dart';

/// Migrates either published v3 shape without altering queued request payloads.
/// Encryption's packet version/AAD is independent of this inner schema.
Map<String, Object?> migrateLocalSyncV3(Map<String, Object?> data) {
  _rejectLegacyDocuments(data);
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
        'labelIds',
        'labelProjections',
        'document',
        if (!hasSecurity) ...security,
      }),
      optionalFields: {
        ...optional.difference({'document', 'includesDocument'}),
        'pinnedAt',
      },
    );
    return {
      'protected': false,
      'protectionRevision': 0,
      'contentAvailable': true,
      'pinnedAt': null,
      'attachments': <Object?>[],
      'labelIds': <Object?>[],
      'labelProjections': <Object?>[],
      if (remote) 'includesLabels': false,
      if (remote) 'includesAttachments': false,
      ...record,
    };
  }

  final account = data['accountUserId'];
  return {
    ...data,
    'schemaVersion': LocalSyncSchema.version,
    'labels': <Object?>[],
    'syncWireVersion': 1,
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
    allowedFields: LocalSyncSchema.envelopeFields.difference({
      'labels',
      'syncWireVersion',
    }),
  );
  void validate(Object? raw, bool remote) {
    SyncCodecObject.from(
      raw,
      path: 'legacy.v4.note',
      allowedFields:
          (remote ? LocalSyncSchema.snapshotFields : LocalSyncSchema.noteFields)
              .difference({
                'attachments',
                'labelIds',
                'labelProjections',
                'document',
              }),
      optionalFields: remote
          ? LocalSyncSchema.snapshotOptionalFields.difference({
              'document',
              'includesDocument',
            })
          : LocalSyncSchema.noteOptionalFields.difference({'document'}),
    );
  }

  envelope.requireObjectList(
    'notes',
    LocalSyncSchema.noteFields.difference({
      'attachments',
      'labelIds',
      'labelProjections',
      'document',
    }),
    optionalFields: LocalSyncSchema.noteOptionalFields.difference({'document'}),
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

/// Published M03 schema5: preserve cursor and all attempted wire bytes.
Map<String, Object?> migrateLocalSyncV5(Map<String, Object?> data) {
  _rejectLegacyDocuments(data);
  final envelope = SyncCodecObject.from(
    data,
    path: 'legacy.v5',
    allowedFields: LocalSyncSchema.envelopeFields.difference({
      'labels',
      'syncWireVersion',
    }),
  );
  Map<String, Object?> note(Object? raw, bool remote) {
    final record = SyncCodecObject.from(
      raw,
      path: 'legacy.v5.note',
      allowedFields:
          (remote ? LocalSyncSchema.snapshotFields : LocalSyncSchema.noteFields)
              .difference({'labelIds', 'labelProjections', 'document'}),
      optionalFields:
          (remote
                  ? LocalSyncSchema.snapshotOptionalFields
                  : LocalSyncSchema.noteOptionalFields)
              .difference({'includesLabels', 'document', 'includesDocument'}),
    );
    record.requireString('id');
    return {
      ...Map<String, Object?>.from(raw as Map),
      'labelIds': <Object?>[],
      'labelProjections': <Object?>[],
      if (remote) 'includesLabels': false,
    };
  }

  final notes = envelope.rawValue('notes'),
      conflicts = envelope.rawValue('conflicts');
  if (notes is! List || conflicts is! List) {
    throw const LocalSyncCodecException('Invalid legacy collections.');
  }
  return {
    ...data,
    'schemaVersion': LocalSyncSchema.version,
    'labels': <Object?>[],
    'syncWireVersion': 1,
    'notes': notes.map((n) => note(n, false)).toList(),
    'conflicts': conflicts.map((c) {
      if (c is! Map) {
        throw const LocalSyncCodecException('Invalid legacy conflict.');
      }
      return {
        ...Map<String, Object?>.from(c),
        'local': note(c['local'], false),
        'remote': c['remote'] == null ? null : note(c['remote'], true),
      };
    }).toList(),
  };
}

void _rejectLegacyDocuments(Map<String, Object?> data) {
  void pending(Object? raw) {
    if (raw is! Map) {
      throw const LocalSyncCodecException('Invalid legacy mutation.');
    }
    final payload = raw['payload'];
    if (payload is Map && payload.containsKey('document')) {
      throw const LocalSyncCodecException(
        'Legacy payload cannot contain document.',
      );
    }
  }

  final outbox = data['outbox'];
  final conflicts = data['conflicts'];
  if (outbox is! List || conflicts is! List) {
    throw const LocalSyncCodecException('Invalid legacy collections.');
  }
  for (final entry in outbox) {
    pending(entry);
  }
  for (final conflict in conflicts) {
    if (conflict is! Map) {
      throw const LocalSyncCodecException('Invalid legacy conflict.');
    }
    pending(conflict['pending']);
  }
}

/// Inner v6 has no document. Preserve every payload field, retry and ID exactly.
Map<String, Object?> migrateLocalSyncV6(Map<String, Object?> data) {
  final envelope = SyncCodecObject.from(
    data,
    path: 'legacy.v6',
    allowedFields: LocalSyncSchema.envelopeFields,
  );
  void note(Object? raw, bool remote) {
    SyncCodecObject.from(
      raw,
      path: 'legacy.v6.note',
      allowedFields:
          (remote ? LocalSyncSchema.snapshotFields : LocalSyncSchema.noteFields)
              .difference({'document'}),
      optionalFields:
          (remote
                  ? LocalSyncSchema.snapshotOptionalFields
                  : LocalSyncSchema.noteOptionalFields)
              .difference({'document', 'includesDocument'}),
    );
  }

  void pending(Object? raw) {
    final entry = SyncCodecObject.from(
      raw,
      path: 'legacy.v6.pending',
      allowedFields: LocalSyncSchema.mutationFields,
      optionalFields: LocalSyncSchema.mutationOptionalFields,
    );
    entry.requireNullableObject(
      'payload',
      LocalSyncSchema.payloadFields.difference({'document'}),
      optionalFields: {'pinnedAt', 'attachments', 'labelIds'},
    );
  }

  for (final record in envelope.requireObjectList(
    'notes',
    LocalSyncSchema.noteFields.difference({'document'}),
    optionalFields: LocalSyncSchema.noteOptionalFields.difference({'document'}),
  )) {
    record.requireString('id');
  }
  final outbox = envelope.rawValue('outbox');
  if (outbox is! List) {
    throw const LocalSyncCodecException('Invalid legacy outbox.');
  }
  for (final entry in outbox) {
    pending(entry);
  }
  for (final conflict in envelope.requireObjectList(
    'conflicts',
    LocalSyncSchema.conflictFields,
  )) {
    note(conflict.rawValue('local'), false);
    if (conflict.rawValue('remote') != null) {
      note(conflict.rawValue('remote'), true);
    }
    pending(conflict.rawValue('pending'));
  }
  return {...data, 'schemaVersion': LocalSyncSchema.version};
}
