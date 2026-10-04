import '../../domain/notes/attachment.dart';

/// Official M03 policy; mirrored by the backend byte validator.
abstract final class AttachmentPolicy {
  static const mib = 1024 * 1024;
  static const maxFiles = 10;
  static const maxNoteBytes = 100 * mib;
  static const maxCacheBytes = 250 * mib;
  static const chunkBytes = 256 * 1024;
  static const types = <String, ({String mime, int limit})>{
    'jpg': (mime: 'image/jpeg', limit: 10 * mib),
    'jpeg': (mime: 'image/jpeg', limit: 10 * mib),
    'png': (mime: 'image/png', limit: 10 * mib),
    'webp': (mime: 'image/webp', limit: 10 * mib),
    'mp4': (mime: 'video/mp4', limit: 50 * mib),
    'pdf': (mime: 'application/pdf', limit: 20 * mib),
    'txt': (mime: 'text/plain', limit: 20 * mib),
    'csv': (mime: 'text/csv', limit: 20 * mib),
  };

  static String validate({
    required String fileName,
    required String mimeType,
    required int sizeBytes,
    required Iterable<Attachment> existing,
    int reservedCount = 0,
    int reservedBytes = 0,
  }) {
    if (fileName.isEmpty ||
        fileName.length > 255 ||
        RegExp(r'[/\\\x00-\x1f\x7f]').hasMatch(fileName)) {
      throw ArgumentError('Invalid filename.');
    }
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    final type = types[ext];
    if (type == null || type.mime != mimeType.toLowerCase().trim()) {
      throw ArgumentError('Unsupported file type.');
    }
    if (sizeBytes <= 0 || sizeBytes > type.limit) {
      throw ArgumentError('File exceeds its type limit or is empty.');
    }
    if (reservedCount < 0 ||
        reservedBytes < 0 ||
        existing.length + reservedCount >= maxFiles ||
        existing.fold<int>(0, (n, a) => n + a.sizeBytes) +
                reservedBytes +
                sizeBytes >
            maxNoteBytes) {
      throw ArgumentError('Note attachment quota exceeded.');
    }
    return type.mime;
  }
}
