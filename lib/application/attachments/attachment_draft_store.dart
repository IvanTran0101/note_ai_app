import '../../domain/notes/attachment.dart';
import 'attachment_binding.dart';
import 'attachment_input.dart';
import 'local_attachment_draft.dart';

/// Encrypted, account-scoped local staging. Keys and binary storage are owned
/// by Infrastructure, not this application contract.
abstract interface class AttachmentDraftStore {
  Future<LocalAttachmentDraft> stage(
    AttachmentBinding binding,
    AttachmentInput input, {
    required Iterable<Attachment> existing,
  });
  Future<List<String>> pendingIds(AttachmentBinding binding);
  Future<void> recoverIncomplete(AttachmentBinding binding);
  Future<LocalAttachmentDraft> load(AttachmentBinding binding, String id);
  Stream<List<int>> read(
    AttachmentBinding binding,
    LocalAttachmentDraft draft, {
    int start = 0,
    int? end,
  });
  Future<void> markLinked(AttachmentBinding binding, String id);
  Future<void> cancelLocal(AttachmentBinding binding, String id);
}
