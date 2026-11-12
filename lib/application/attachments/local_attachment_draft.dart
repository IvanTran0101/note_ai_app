final class LocalAttachmentDraft {
  const LocalAttachmentDraft({
    required this.cacheId,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.sha256,
    required this.chunkCount,
  });
  final String cacheId;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final String sha256;
  final int chunkCount;
}
