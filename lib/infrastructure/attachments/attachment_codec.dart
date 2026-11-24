import '../../domain/notes/attachment.dart';

abstract final class AttachmentCodec {
  static Map<String, Object?> encode(Attachment value) => {
    'id': value.id,
    'noteId': value.noteId,
    'fileName': value.fileName,
    'mimeType': value.mimeType,
    'sizeBytes': value.sizeBytes,
    'storageObjectId': value.storageObjectId,
    'objectVersion': value.objectVersion,
    'sha256': value.sha256,
    'addedAt': value.addedAt.toIso8601String(),
  };

  static List<Attachment> decodeList(Object? input, {String? noteId}) {
    if (input is! List || input.length > 10) {
      throw const FormatException('Invalid attachment metadata.');
    }
    try {
      return freezeAttachments(
        input.map((value) {
          if (value is! Map || value.length != 9) {
            throw const FormatException('Invalid attachment descriptor.');
          }
          final addedAt = DateTime.tryParse(value['addedAt'] as String);
          if (addedAt == null ||
              !addedAt.isUtc ||
              !(value['addedAt'] as String).endsWith('Z')) {
            throw const FormatException('Attachment time must be UTC.');
          }
          return Attachment(
            id: value['id'] as String,
            noteId: value['noteId'] as String,
            fileName: value['fileName'] as String,
            mimeType: value['mimeType'] as String,
            sizeBytes: value['sizeBytes'] as int,
            storageObjectId: value['storageObjectId'] as String,
            objectVersion: value['objectVersion'] as String,
            sha256: value['sha256'] as String,
            addedAt: addedAt,
          );
        }),
        noteId: noteId,
      );
    } on Object {
      // Never echo filenames, object keys or a malformed input into logs.
      throw const FormatException('Invalid attachment metadata.');
    }
  }
}
