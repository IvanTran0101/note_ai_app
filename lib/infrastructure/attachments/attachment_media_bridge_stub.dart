import '../../application/attachments/attachment_media.dart';
import '../../application/notes/note_access.dart';

AttachmentMediaBridge createAttachmentMediaBridge() => _Unavailable();

final class _Unavailable implements AttachmentMediaBridge {
  @override
  Future<AttachmentMediaHandle> open(AttachmentMediaRequest request) async =>
      throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
}
