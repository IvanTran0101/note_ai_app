/// Platform rendering/export bridges consume only authorized bounded streams.
/// This transient handle is never Note metadata, cache metadata or sync payload.
abstract interface class AttachmentMediaHandle {
  Uri? get uri;
  bool get exported;
  Future<void> close();
}

final class AttachmentMediaRequest {
  const AttachmentMediaRequest({
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.read,
    required this.authorize,
    this.exportFile = false,
  });
  final String fileName, mimeType;
  final int sizeBytes;
  final bool exportFile;
  final Stream<List<int>> Function(int start, int end) read;
  final Future<void> Function() authorize;
}

abstract interface class AttachmentMediaBridge {
  Future<AttachmentMediaHandle> open(AttachmentMediaRequest request);
}
