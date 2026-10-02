/// Pure wire mapping for the remote note sync adapter (M1.3).
///
/// Every function here is a pure translation between the frozen HTTP shapes in
/// `docs/sync_api_contract.md` and the Application sync contract. Nothing in
/// this library performs I/O, holds state, imports `package:http`, or keeps
/// provider text: a payload that does not match the contract throws
/// [FormatException] instead of being half-trusted, and the only failure a
/// caller receives carries a provider-neutral [SyncErrorCode].
///
/// The two frozen routes answer with JSON text; a caller may hand either the
/// decoded object or the raw body string to the decoders, so JSON parsing lives
/// in one place. Owned routes derive their namespace from the verified actor.
/// Shared updates carry canonical owner/access epoch on a dedicated route;
/// these fields never replace JWT actor authority or fall back to owned writes.
library;

import 'dart:convert';

import 'protection_sync_codec.dart';
import 'share_wire_codec.dart';

import '../../application/sync/sync_failure.dart';
import '../../application/sync/sync_mutation.dart';
import '../../application/sync/sync_result.dart';
import '../../application/sync/sync_snapshot.dart';
import '../../domain/notes/note_protection.dart';

/// The `status` value of an applied mutation response.
const String _appliedStatus = 'applied';

/// Maps an HTTP status to the failure it means, per the frozen status table.
///
/// `409` is deliberately absent: a stale `baseRevision` is a result rather than
/// a failure, and [decodeSyncMutationResponse] turns it into a conflict.
const Map<int, SyncErrorCode> _statusErrorCodes = <int, SyncErrorCode>{
  401: SyncErrorCode.unauthorized,
  403: SyncErrorCode.forbidden,
  423: SyncErrorCode.forbidden,
  422: SyncErrorCode.invalidMutation,
  429: SyncErrorCode.throttled,
  500: SyncErrorCode.serverUnavailable,
  502: SyncErrorCode.serverUnavailable,
  503: SyncErrorCode.serverUnavailable,
  504: SyncErrorCode.serverUnavailable,
};

/// Envelope codes recognised as a fallback when the status is not in the table.
///
/// Only these exact tokens are read, so an unexpected provider string can never
/// become a failure code.
const Map<String, SyncErrorCode> _envelopeErrorCodes = <String, SyncErrorCode>{
  'UNAUTHORIZED': SyncErrorCode.unauthorized,
  'FORBIDDEN': SyncErrorCode.forbidden,
  'INVALID_MUTATION': SyncErrorCode.invalidMutation,
  'THROTTLED': SyncErrorCode.throttled,
  'SERVER_UNAVAILABLE': SyncErrorCode.serverUnavailable,
  'NETWORK_UNAVAILABLE': SyncErrorCode.networkUnavailable,
  'TIMEOUT': SyncErrorCode.timeout,
  'NOTE_SECURITY_STALE': SyncErrorCode.forbidden,
  'NOTE_LOCKED': SyncErrorCode.forbidden,
  'NOTE_GRANT_EXPIRED': SyncErrorCode.forbidden,
  'NOTE_ACCESS_DENIED': SyncErrorCode.forbidden,
};

/// Encodes one client mutation as a `POST /sync/mutations` request body.
///
/// `payload` is present exactly when the mutation carries one, so a delete
/// without content omits the key instead of sending `null`. The body includes
/// `ownerId` only for a canonical shared update.
Map<String, Object?> encodeSyncMutation(SyncMutation mutation) {
  final Map<String, Object?> body = <String, Object?>{
    'mutationId': mutation.mutationId,
    'noteId': mutation.noteId,
    'operation': mutation.operation.name,
    'baseRevision': mutation.baseRevision,
    if (mutation.ownerId != null) 'ownerId': mutation.ownerId,
    if (mutation.accessRevision != null)
      'accessRevision': mutation.accessRevision,
    if (mutation.protectionChange != null)
      'protectionChange': ProtectionSyncCodec.encode(
        mutation.protectionChange!,
      ),
  };
  final SyncNotePayload? payload = mutation.payload;
  if (payload != null) {
    body['payload'] = <String, Object?>{
      'title': payload.title,
      'content': payload.content,
    };
  }
  return body;
}

/// Decodes one `POST /sync/mutations` response.
///
/// A 2xx response must carry the applied note. A `409` becomes a conflict whose
/// remote snapshot may be `null` when the server withheld it. Any other status,
/// and any body that does not match the frozen shape, throws [FormatException]
/// so the adapter classifies it as unexpected rather than trusting half a
/// response.
///
/// [body] is the response payload, already decoded or as raw JSON text.
/// [mutationId] is the identifier of the request that produced it; the
/// response's own echo wins when present, because a replayed idempotent
/// mutation reports the identifier the server recorded, and the argument is the
/// fallback for a `409` envelope that omits it.
SyncMutationResult decodeSyncMutationResponse({
  required int statusCode,
  required Object? body,
  String? mutationId,
}) {
  final Map<String, Object?> json = _asJsonObject(body, 'mutation response');

  if (statusCode == 409) {
    return SyncMutationResult.conflict(
      mutationId: _readMutationId(json, mutationId),
      remote: _readOptionalNote(json, 'remoteNote'),
    );
  }
  if (statusCode < 200 || statusCode >= 300) {
    throw FormatException('Unsupported mutation response status $statusCode.');
  }

  final Object? status = json['status'];
  if (status != null && status != _appliedStatus) {
    throw FormatException('Unsupported mutation response status "$status".');
  }
  final Object? note = json['note'];
  if (note == null) {
    throw const FormatException('Mutation response "note" is required.');
  }
  return SyncMutationResult.applied(
    mutationId: _readMutationId(json, mutationId),
    note: _decodeNote(_asJsonObject(note, 'mutation response "note"')),
  );
}

/// Decodes one `GET /sync/changes` page.
///
/// `items` is required and may be empty. A tombstone is an item whose
/// `deletedAt` is set and is kept in the page. `nextCursor` is preserved even
/// when `hasMore` is false, because it is the last successfully applied
/// position rather than only a request for another page. A page that claims
/// `hasMore` without a cursor is malformed: the caller would have no way to ask
/// for the next page.
SyncChangesPage decodeChangesPage(Object? body) {
  final Map<String, Object?> json = _asJsonObject(body, 'changes page');

  final Object? items = json['items'];
  if (items is! List<Object?>) {
    throw const FormatException('Changes page "items" must be an array.');
  }
  final List<SyncNoteSnapshot> snapshots = <SyncNoteSnapshot>[
    for (final Object? item in items)
      _decodeNote(_asJsonObject(item, 'changes page item')),
  ];

  final String? nextCursor = _readOptionalCursor(json);
  final Object? hasMore = json['hasMore'];
  if (hasMore != null && hasMore is! bool) {
    throw const FormatException('Changes page "hasMore" must be a boolean.');
  }
  final bool hasMorePages = hasMore == true;
  if (hasMorePages && nextCursor == null) {
    throw const FormatException(
      'Changes page with "hasMore" true must carry a "nextCursor".',
    );
  }
  return SyncChangesPage(
    snapshots: snapshots,
    nextCursor: nextCursor,
    hasMore: hasMorePages,
  );
}

/// Decodes one error envelope into a provider-neutral failure.
///
/// The status decides the code; [body] is consulted only as a fallback when the
/// status is absent or outside the frozen table, and only through the exact
/// [_envelopeErrorCodes] tokens. A malformed error body therefore never throws:
/// the status still classifies the failure.
///
/// No text is taken from [body]. `SyncFailure.detail` stays `null` because a
/// provider message, a stack trace, an echoed token, or note content must not
/// cross into Application, and user-facing copy is Presentation's concern
/// rather than Infrastructure's.
SyncFailure decodeError({int? statusCode, Object? body}) {
  final SyncErrorCode? fromStatus = statusCode == null
      ? null
      : _statusErrorCodes[statusCode];
  return SyncFailure(code: fromStatus ?? _errorCodeFromEnvelope(body));
}

/// Decodes a note snapshot, rejecting every malformed or missing field.
///
/// Unknown fields are ignored on purpose: the response is a wire payload and
/// may grow additive fields, and an `ownerId` the server chose to include is
/// dropped here rather than becoming client state.
SyncNoteSnapshot decodeSyncNoteSnapshot(
  Object? data, {
  bool authorizedContent = false,
}) => _decodeNote(
  _asJsonObject(data, 'note snapshot'),
  authorizedContent: authorizedContent,
);

SyncNoteSnapshot _decodeNote(
  Map<String, Object?> json, {
  bool authorizedContent = false,
}) {
  final Object? id = json['id'];
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
  final owner = share == null ? null : json['ownerId'];
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
    protection: NoteProtection(enabled: enabled, revision: epoch),
    contentAvailable: hasContent,
    createdAt: _readTimestamp(json, 'createdAt'),
    serverUpdatedAt: _readTimestamp(json, 'serverUpdatedAt'),
    revision: _readPositiveRevision(json),
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

/// Reads the opaque paging cursor, treating an empty string as absent.
String? _readOptionalCursor(Map<String, Object?> json) {
  final Object? value = json['nextCursor'];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw const FormatException('Changes page "nextCursor" must be a string.');
  }
  return value.isEmpty ? null : value;
}

/// Reads the mutation identifier echoed by the response, falling back to the
/// identifier of the request that was sent.
String _readMutationId(Map<String, Object?> json, String? requestMutationId) {
  final Object? echoed = json['mutationId'];
  if (echoed is String && echoed.trim().isNotEmpty) {
    return echoed;
  }
  if (requestMutationId != null && requestMutationId.trim().isNotEmpty) {
    return requestMutationId;
  }
  throw const FormatException(
    'Mutation response must identify the mutation it answers.',
  );
}

/// Reads an optional nested note, or throws when the key holds a non-object.
SyncNoteSnapshot? _readOptionalNote(
  Map<String, Object?> json,
  String fieldName,
) {
  final Object? value = json[fieldName];
  if (value == null) {
    return null;
  }
  return _decodeNote(_asJsonObject(value, 'mutation response "$fieldName"'));
}

/// Classifies an error envelope by its `code` token alone.
SyncErrorCode _errorCodeFromEnvelope(Object? body) {
  final Object? code = _tryAsJsonObject(body)?['code'];
  if (code is! String) {
    return SyncErrorCode.unexpected;
  }
  return _envelopeErrorCodes[code] ?? SyncErrorCode.unexpected;
}

/// Normalises a JSON body to a string-keyed map.
///
/// Accepts an already decoded object or the raw JSON text the adapter read off
/// the socket. Anything else, including a JSON array or scalar, is a malformed
/// payload and throws [FormatException].
Map<String, Object?> _asJsonObject(Object? body, String description) {
  final Object? value = body is String ? _decodeJson(body, description) : body;
  if (value is! Map) {
    throw FormatException('$description must be a JSON object.');
  }
  final Map<String, Object?> json = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in value.entries) {
    final Object? key = entry.key;
    if (key is! String) {
      throw FormatException('$description must use string keys.');
    }
    json[key] = entry.value;
  }
  return json;
}

/// Same as [_asJsonObject] but never throws, for the error path.
Map<String, Object?>? _tryAsJsonObject(Object? body) {
  try {
    return _asJsonObject(body, 'error response');
  } on FormatException {
    return null;
  }
}

/// Parses raw JSON text, keeping the offset and dropping the source snippet.
///
/// `jsonDecode`'s own message quotes the offending source, which can be note
/// content or a credential, so it is replaced by one that only reports where
/// parsing stopped.
Object? _decodeJson(String body, String description) {
  try {
    return jsonDecode(body);
  } on FormatException catch (error) {
    throw FormatException(
      'Malformed JSON in $description at offset ${error.offset}.',
    );
  }
}
