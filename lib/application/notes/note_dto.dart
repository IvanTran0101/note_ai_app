import '../sync/local_note_state.dart';
import '../../domain/notes/note.dart';
import '../../domain/notes/note_identity.dart';
import '../../domain/notes/note_share_grant.dart';
import '../../domain/notes/attachment.dart';

/// A read-only application projection of the Note aggregate.
///
/// The DTO keeps presentation code independent from the domain aggregate's
/// mutation methods while preserving the fields needed by the Notes UI.
final class NoteDto {
  const NoteDto({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.isProtected = false,
    this.protectionRevision = 0,
    this.contentAvailable = true,
    this.contentRevision = 0,
    this.share,
    this.pinnedAt,
    this.attachmentManifest = const AttachmentManifest.empty(),
  });

  /// Creates a presentation-safe projection from a domain Note.
  factory NoteDto.fromDomain(Note note) {
    return NoteDto(
      id: note.id,
      ownerId: note.ownerId,
      title: note.contentAvailable ? note.title : '',
      content: note.contentAvailable ? note.content : '',
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      isProtected: note.protection.enabled,
      protectionRevision: note.protection.revision,
      contentAvailable: note.contentAvailable,
      contentRevision: note.contentRevision,
      share: note.share,
      pinnedAt: note.pinnedAt,
      attachmentManifest: AttachmentManifest(
        note.contentAvailable ? note.attachments : const [],
      ),
    );
  }

  factory NoteDto.fromLocalState(LocalNoteState note) => NoteDto(
    id: note.id,
    ownerId: note.ownerId,
    title: note.contentAvailable ? note.title : '',
    content: note.contentAvailable ? note.content : '',
    createdAt: note.createdAt,
    updatedAt: note.updatedAt,
    pinnedAt: note.pinnedAt,
    isProtected: note.protection.enabled,
    protectionRevision: note.protection.revision,
    contentAvailable: note.contentAvailable,
    contentRevision: note.serverRevision,
    share: note.share,
    attachmentManifest: AttachmentManifest(
      note.contentAvailable ? note.attachments : const [],
    ),
  );

  final DateTime? pinnedAt;
  final AttachmentManifest attachmentManifest;
  List<Attachment> get attachments => attachmentManifest.values;
  bool get isPinned => pinnedAt != null;
  final NoteShareGrant? share;
  NoteIdentity get identity => NoteIdentity(ownerId, id);
  String get reference => identity.referenceFor(share?.recipientId ?? ownerId);

  final String id;
  final String ownerId;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isProtected;
  final int protectionRevision;
  final bool contentAvailable;
  final int contentRevision;
  bool get isLocked => isProtected && !contentAvailable;

  NoteDto metadataOnly() => NoteDto(
    id: id,
    ownerId: ownerId,
    title: '',
    content: '',
    createdAt: createdAt,
    updatedAt: updatedAt,
    isProtected: isProtected,
    protectionRevision: protectionRevision,
    contentRevision: contentRevision,
    contentAvailable: false,
    share: share,
    pinnedAt: pinnedAt,
  );

  @override
  bool operator ==(Object other) {
    return other is NoteDto &&
        other.id == id &&
        other.ownerId == ownerId &&
        other.title == title &&
        other.content == content &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.isProtected == isProtected &&
        other.protectionRevision == protectionRevision &&
        other.contentAvailable == contentAvailable &&
        other.contentRevision == contentRevision &&
        other.share == share &&
        other.pinnedAt == pinnedAt &&
        other.attachmentManifest == attachmentManifest;
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    title,
    content,
    createdAt,
    updatedAt,
    isProtected,
    protectionRevision,
    contentAvailable,
    contentRevision,
    share,
    pinnedAt,
    attachmentManifest,
  );

  @override
  String toString() {
    return 'NoteDto(id: $id, ownerId: $ownerId, title: <redacted>, '
        'content: <redacted>, createdAt: $createdAt, updatedAt: $updatedAt)';
  }
}

/// Raised when an application operation targets a note that does not exist.
final class NoteNotFoundException implements Exception {
  const NoteNotFoundException(this.noteId);

  final String noteId;

  @override
  String toString() => 'NoteNotFoundException: note "$noteId" was not found';
}

/// Raised when the current user attempts to access another owner's note.
final class NoteOwnershipException implements Exception {
  const NoteOwnershipException({
    required this.noteId,
    required this.expectedOwnerId,
    required this.actualOwnerId,
  });

  final String noteId;
  final String expectedOwnerId;
  final String actualOwnerId;

  @override
  String toString() {
    return 'NoteOwnershipException: note "$noteId" belongs to '
        '"$actualOwnerId", not "$expectedOwnerId"';
  }
}
