import '../../domain/notes/attachment.dart';
import 'attachment_binding.dart';

/// A staged file is durable, but upload must wait for the canonical create ACK.
/// This is a normal local-first state, not a validation or transfer failure.
final class AttachmentAwaitingNoteSync implements Exception {
  const AttachmentAwaitingNoteSync();
}

final class AttachmentProgress {
  const AttachmentProgress(
    this.id,
    this.phase,
    this.completedBytes,
    this.totalBytes,
  );
  final String id;
  final String phase;
  final int completedBytes;
  final int totalBytes;
}

typedef ReadRemoteAttachment = Stream<List<int>> Function(
  AttachmentBinding binding,
  Attachment attachment, {
  int start,
  int? end,
});
typedef CancelRemoteAttachment = Future<void> Function(
  AttachmentBinding binding,
  String id,
);

/// Binary state stays separate from the Note outbox, and contains no capability.
abstract interface class AttachmentTransferCache {
  Stream<List<int>> readAssociated(
    AttachmentBinding binding,
    Attachment attachment,
    ReadRemoteAttachment remote, {
    int start = 0,
    int? end,
  });
  Future<void> queueCancellation(AttachmentBinding binding, String id);
  Future<List<String>> cancellationIds(AttachmentBinding binding);
  Future<void> finishCancellation(AttachmentBinding binding, String id);
  Future<bool> isLinked(AttachmentBinding binding, String id);
}

/// A binary-only removal intent precedes the canonical Note writer. It prevents
/// retry resurrection across a crash without creating another Note outbox.
abstract interface class AttachmentRemovalCache {
  Future<void> prepareRemoval(AttachmentBinding binding, Attachment attachment);
  Future<List<String>> removalIds(AttachmentBinding binding);
}
