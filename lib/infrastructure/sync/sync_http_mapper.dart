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
import '../attachments/attachment_codec.dart';
import '../labels/label_codec.dart';
import '../../application/labels/local_label_state.dart';

import '../../application/sync/sync_failure.dart';
import '../../application/sync/sync_mutation.dart';
import '../../application/sync/sync_result.dart';
import '../../application/sync/sync_snapshot.dart';
import '../../domain/notes/note_protection.dart';

part 'sync_note_wire_mapper.dart';

/// The `status` value of an applied mutation response.
const String _appliedStatus = 'applied';
final RegExp _utcTimestampPattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?Z$',
);

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
  if (mutation.isLabel) {
    return {
      'wireVersion': 2,
      'entityType': 'label',
      'mutationId': mutation.mutationId,
      'labelId': mutation.noteId,
      'operation': mutation.operation.name,
      'baseRevision': mutation.baseRevision,
      if (mutation.labelName != null) 'payload': {'name': mutation.labelName},
    };
  }
  final Map<String, Object?> body = <String, Object?>{
    if (mutation.payload?.includesLabels == true) ...{
      'wireVersion': 2,
      'entityType': 'note',
    },
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
      if (payload.includesLabels) 'labelIds': payload.labelIds,
      if (payload.includesAttachments)
        'attachments': payload.attachments.map(AttachmentCodec.encode).toList(),
      if (payload.includesPinnedAt)
        'pinnedAt': payload.pinnedAt?.toIso8601String(),
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
  if (json['entityType'] == 'label') {
    if (json['wireVersion'] != 2) {
      throw const FormatException('Label wire version required.');
    }
    if (statusCode == 409) {
      return SyncMutationResult.labelConflict(
        mutationId: _readMutationId(json, mutationId),
        remote: json['remoteLabel'] == null
            ? null
            : LabelCodec.decodeWire(json['remoteLabel']),
      );
    }
    if (statusCode < 200 || statusCode >= 300 || json['status'] != 'applied') {
      throw const FormatException('Invalid Label outcome.');
    }
    return SyncMutationResult.labelApplied(
      mutationId: _readMutationId(json, mutationId),
      label: LabelCodec.decodeWire(json['label']),
    );
  }

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
SyncChangesPage decodeChangesPage(
  Object? body, {
  bool authorizedContent = false,
}) {
  final Map<String, Object?> json = _asJsonObject(body, 'changes page');

  final Object? items = json['items'];
  if (items is! List<Object?>) {
    throw const FormatException('Changes page "items" must be an array.');
  }
  final version = json['wireVersion'] ?? 1;
  if (version != 1 && version != 2) {
    throw const FormatException('Unsupported sync version.');
  }
  final snapshots = <SyncNoteSnapshot>[];
  final labels = <LocalLabelState>[];
  for (final item in items) {
    final row = _asJsonObject(item, 'changes page item');
    if (version == 1) {
      snapshots.add(_decodeNote(row));
      continue;
    }
    if (row['entityType'] == 'note') {
      snapshots.add(
        _decodeNote(
          _asJsonObject(row['note'], 'note'),
          authorizedContent: authorizedContent,
        ),
      );
    } else if (row['entityType'] == 'label') {
      labels.add(LabelCodec.decodeWire(row['label']));
    } else {
      throw const FormatException('Typed entity required.');
    }
  }

  final String? nextCursor = _readOptionalCursor(json);
  final Object? hasMore = json['hasMore'];
  if (hasMore != null && hasMore is! bool) {
    throw const FormatException('Changes page "hasMore" must be a boolean.');
  }
  final bool hasMorePages = hasMore == true;
  final catchUpPending = json['catchUpPending'];
  if (catchUpPending != null && catchUpPending is! bool) {
    throw const FormatException('Changes catch-up flag must be a boolean.');
  }
  if (hasMorePages && nextCursor == null) {
    throw const FormatException(
      'Changes page with "hasMore" true must carry a "nextCursor".',
    );
  }
  return SyncChangesPage(
    snapshots: snapshots,
    labels: labels,
    wireVersion: version as int,
    nextCursor: nextCursor,
    hasMore: hasMorePages,
    catchUpPending: catchUpPending == true,
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
