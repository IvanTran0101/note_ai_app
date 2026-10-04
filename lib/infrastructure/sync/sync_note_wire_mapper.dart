part of 'sync_http_mapper.dart';

/// Authorized Note snapshot projection and scalar validation.
SyncNoteSnapshot _decodeNote(
  Map<String, Object?> json, {
  bool authorizedContent = false,
}) {
  final Object? id = json['id'];
  final securityFields = [
    'protected',
    'protectionRevision',
    'contentAvailable',
  ];
  if (securityFields.any(json.containsKey) &&
      !securityFields.every(json.containsKey)) {
    throw const FormatException('Incomplete note protection metadata.');
  }
  if (id is! String || id.trim().isEmpty) {
    throw const FormatException('Note "id" must be a non-blank string.');
  }
  final enabled = json['protected'] ?? false;
  final epoch = json['protectionRevision'] ?? 0;
  final available = json['contentAvailable'] ?? (enabled == false);
  if (enabled is! bool ||
      epoch is! int ||
      epoch < 0 ||
      (enabled && epoch == 0) ||
      available is! bool) {
    throw const FormatException('Invalid note protection metadata.');
  }
  final hasContent = available && (!enabled || authorizedContent);
  final share = json['share'] == null
      ? null
      : ShareWireCodec.decode(json['share']);
  final owner = share == null && !json.containsKey('protected')
      ? null
      : json['ownerId'];
  if (share != null &&
      (owner != share.note.ownerId || id != share.note.noteId)) {
    throw const FormatException('Mismatched canonical sharing metadata.');
  }
  return SyncNoteSnapshot(
    id: id,
    ownerId: owner as String?,
    share: share,
    title: hasContent ? _readString(json, 'title') : '',
    content: hasContent ? _readString(json, 'content') : '',
    attachments:
        hasContent &&
            json['deletedAt'] == null &&
            json.containsKey('attachments')
        ? AttachmentCodec.decodeList(json['attachments'], noteId: id)
        : const [],
    includesAttachments: json.containsKey('attachments'),
    labelIds:
        hasContent && json['deletedAt'] == null && json.containsKey('labelIds')
        ? LabelCodec.ids(json['labelIds'])
        : const [],
    labelProjections:
        hasContent &&
            json['deletedAt'] == null &&
            json.containsKey('labelProjections')
        ? LabelCodec.decodeProjections(json['labelProjections'])
        : const [],
    includesLabels: json.containsKey('labelIds'),
    protection: NoteProtection(enabled: enabled, revision: epoch),
    contentAvailable: hasContent,
    createdAt: _readTimestamp(json, 'createdAt'),
    serverUpdatedAt: _readTimestamp(json, 'serverUpdatedAt'),
    revision: _readPositiveRevision(json),
    pinnedAt: _readOptionalUtcTimestamp(json, 'pinnedAt'),
    deletedAt: _readOptionalTimestamp(json, 'deletedAt'),
  );
}

/// Reads a required string field, or throws when it is missing or not a string.
String _readString(Map<String, Object?> json, String fieldName) {
  if (!json.containsKey(fieldName)) {
    throw FormatException('Missing required note field "$fieldName".');
  }
  final Object? value = json[fieldName];
  if (value is! String) {
    throw FormatException('Note field "$fieldName" must be a string.');
  }
  return value;
}

/// Reads a required ISO-8601 field, or throws when it cannot be parsed.
///
/// Anything present must parse, so a malformed timestamp can never become a
/// silently wrong `DateTime`.
DateTime _readTimestamp(Map<String, Object?> json, String fieldName) {
  final DateTime? timestamp = _tryTimestamp(json[fieldName]);
  if (timestamp == null) {
    throw FormatException(
      'Note field "$fieldName" must be a valid ISO-8601 timestamp.',
    );
  }
  return timestamp;
}

/// Reads the optional tombstone marker: an absent or `null` field means the
/// note is alive, and anything present must parse.
DateTime? _readOptionalTimestamp(Map<String, Object?> json, String fieldName) {
  final Object? value = json[fieldName];
  if (value == null) {
    return null;
  }
  final DateTime? timestamp = _tryTimestamp(value);
  if (timestamp == null) {
    throw FormatException(
      'Note field "$fieldName" must be null or a valid ISO-8601 timestamp.',
    );
  }
  return timestamp;
}

DateTime? _readOptionalUtcTimestamp(
  Map<String, Object?> json,
  String fieldName,
) {
  final Object? value = json[fieldName];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException(
      'Note field "$fieldName" must be null or a valid UTC timestamp.',
    );
  }
  final Match? parts = _utcTimestampPattern.firstMatch(value);
  final DateTime? timestamp = DateTime.tryParse(value);
  if (parts == null ||
      timestamp == null ||
      !timestamp.isUtc ||
      timestamp.year != int.parse(parts[1]!) ||
      timestamp.month != int.parse(parts[2]!) ||
      timestamp.day != int.parse(parts[3]!) ||
      timestamp.hour != int.parse(parts[4]!) ||
      timestamp.minute != int.parse(parts[5]!) ||
      timestamp.second != int.parse(parts[6]!)) {
    throw FormatException(
      'Note field "$fieldName" must be null or a valid UTC timestamp.',
    );
  }
  return timestamp;
}

/// Parses a non-empty ISO-8601 string, or returns `null` when it cannot.
DateTime? _tryTimestamp(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}

/// Reads the note revision, which the Application contract requires positive.
int _readPositiveRevision(Map<String, Object?> json) {
  final Object? value = json['revision'];
  if (value is! int) {
    throw const FormatException('Note field "revision" must be an integer.');
  }
  if (value <= 0) {
    throw const FormatException('Note field "revision" must be positive.');
  }
  return value;
}
