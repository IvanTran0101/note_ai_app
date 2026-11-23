import 'dart:convert';

import '../../application/sync/revision_source.dart';

Map<String, Object?>? decodeEventFrame(Object? value) {
  if (value is! String || value.length > 65536) return null;
  try {
    final data = jsonDecode(value);
    return data is Map<String, dynamic> ? data : null;
  } on Object {
    return null;
  }
}

RevisionSignal? decodeRevisionSignal(Object? value) {
  final row = decodeEventFrame(value);
  const allowed = {
    'version',
    'eventId',
    'ownerId',
    'noteId',
    'invalidate',
    'revision',
    'protectionRevision',
    'accessRevision',
  };
  if (row == null ||
      row.keys.any((k) => !allowed.contains(k)) ||
      row['version'] != 1 ||
      row['invalidate'] != true) {
    return null;
  }
  for (final key in ['eventId', 'ownerId', 'noteId']) {
    final x = row[key];
    if (x is! String || x.isEmpty || x.length > 512) return null;
  }
  for (final key in ['revision', 'protectionRevision', 'accessRevision']) {
    final x = row[key];
    if (x != null && (x is! int || x < 0 || x > 9007199254740991)) return null;
  }
  return RevisionSignal(
    eventId: row['eventId']! as String,
    ownerId: row['ownerId']! as String,
    noteId: row['noteId']! as String,
    revision: row['revision'] as int?,
    protectionRevision: row['protectionRevision'] as int?,
    accessRevision: row['accessRevision'] as int?,
  );
}

DateTime? tokenExpiry(String token, String actor) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final claims = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (claims is! Map ||
        claims['sub'] != actor ||
        claims['token_use'] != 'id' ||
        claims['exp'] is! int) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(
      (claims['exp'] as int) * 1000,
      isUtc: true,
    );
  } on Object {
    return null;
  }
}
