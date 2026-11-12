import 'note_protection.dart';

/// Safe identity/revision data. Protected metadata never includes a title/body.
final class NoteMetadata {
  NoteMetadata({
    required this.id,
    required this.ownerId,
    required this.createdAt,
    required this.updatedAt,
    required this.contentRevision,
    required this.protection,
    String? previewTitle,
  }) : previewTitle = protection.enabled ? null : previewTitle;

  final String id;
  final String ownerId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int contentRevision;
  final NoteProtection protection;
  final String? previewTitle;

  @override
  String toString() =>
      'NoteMetadata(id: $id, protected: ${protection.enabled})';
}
