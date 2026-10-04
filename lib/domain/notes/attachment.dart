/// Immutable server-verified file metadata. No bytes, URLs or credentials.
final class Attachment {
  Attachment({
    required this.id,
    required this.noteId,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.storageObjectId,
    required this.objectVersion,
    required this.sha256,
    required this.addedAt,
  }) {
    for (final value in [id, noteId, storageObjectId, objectVersion]) {
      if (value.trim().isEmpty ||
          value.length > 128 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(value) ||
          value.contains('://')) {
        throw ArgumentError('Invalid attachment identity.');
      }
    }
    if (fileName.isEmpty ||
        fileName.length > 255 ||
        RegExp(r'[/\\\x00-\x1f\x7f]').hasMatch(fileName) ||
        fileName == '.' ||
        fileName == '..') {
      throw ArgumentError('Attachment filename must not be a path.');
    }
    if (sizeBytes <= 0 ||
        sizeBytes > 100 * 1024 * 1024 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256) ||
        mimeType.trim().isEmpty ||
        !addedAt.isUtc) {
      throw ArgumentError('Invalid attachment descriptor.');
    }
  }

  final String id;
  final String noteId;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final String storageObjectId;
  final String objectVersion;
  final String sha256;
  final DateTime addedAt;

  @override
  bool operator ==(Object other) =>
      other is Attachment &&
      id == other.id &&
      noteId == other.noteId &&
      fileName == other.fileName &&
      mimeType == other.mimeType &&
      sizeBytes == other.sizeBytes &&
      storageObjectId == other.storageObjectId &&
      objectVersion == other.objectVersion &&
      sha256 == other.sha256 &&
      addedAt == other.addedAt;

  @override
  int get hashCode => Object.hash(
    id,
    noteId,
    fileName,
    mimeType,
    sizeBytes,
    storageObjectId,
    objectVersion,
    sha256,
    addedAt,
  );
}

List<Attachment> freezeAttachments(
  Iterable<Attachment> values, {
  String? noteId,
}) {
  final result = List<Attachment>.unmodifiable(values);
  final ids = <String>{};
  var bytes = 0;
  for (final attachment in result) {
    if (!ids.add(attachment.id) ||
        (noteId != null && attachment.noteId != noteId)) {
      throw ArgumentError('Invalid attachment association.');
    }
    bytes += attachment.sizeBytes;
  }
  if (result.length > 10 || bytes > 100 * 1024 * 1024) {
    throw ArgumentError('Note attachment quota exceeded.');
  }
  return result;
}

bool sameAttachments(List<Attachment> left, List<Attachment> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

/// A frozen collection usable in constant legacy payloads and DTOs.
final class AttachmentManifest {
  const AttachmentManifest.empty() : values = const [];
  factory AttachmentManifest(Iterable<Attachment> values, {String? noteId}) =>
      AttachmentManifest._(freezeAttachments(values, noteId: noteId));
  const AttachmentManifest._(this.values);
  final List<Attachment> values;
  @override
  bool operator ==(Object other) =>
      other is AttachmentManifest && sameAttachments(values, other.values);
  @override
  int get hashCode => Object.hashAll(values);
}
