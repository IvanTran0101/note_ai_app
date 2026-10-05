/// A selected file source, not a persisted path or credential.
final class AttachmentInput {
  const AttachmentInput({
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.openRead,
    this.release,
  });
  final String fileName;
  final String mimeType;
  final int sizeBytes;

  /// Fresh stream per call; callers must not load an entire video into RAM.
  final Stream<List<int>> Function([int? start, int? end]) openRead;

  /// Release a provider-owned temporary selection after staging or rejection.
  /// Original user files must never be deleted by this callback.
  final Future<void> Function()? release;
}

enum AttachmentSource { files, gallery, cameraPhoto, cameraVideo }

enum AttachmentSelectionFailureCode { denied, unavailable }

final class AttachmentSelectionFailure implements Exception {
  const AttachmentSelectionFailure(this.code);
  final AttachmentSelectionFailureCode code;
}
