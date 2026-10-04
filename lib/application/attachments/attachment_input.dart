/// A selected file source, not a persisted path or credential.
final class AttachmentInput {
  const AttachmentInput({
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.openRead,
  });
  final String fileName;
  final String mimeType;
  final int sizeBytes;

  /// Fresh stream per call; callers must not load an entire video into RAM.
  final Stream<List<int>> Function([int? start, int? end]) openRead;
}

enum AttachmentSource { files, gallery, cameraPhoto, cameraVideo }
