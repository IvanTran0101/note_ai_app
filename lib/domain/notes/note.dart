import 'note_metadata.dart';
import 'note_protection.dart';
import 'note_identity.dart';
import 'note_share_grant.dart';
import 'attachment.dart';
import '../labels/label.dart';
import '../labels/label_projection.dart';
import 'note_document.dart';

/// The Note aggregate root for the notes domain.
///
/// It owns note text, pin state, and their invariants. It does not save itself,
/// run AI, or map itself to UI data.
class Note {
  Note._(
    this._id,
    this._ownerId,
    this._title,
    this._content,
    this._createdAt,
    this._updatedAt,
    this._protection,
    this._contentAvailable,
    this._contentRevision,
    this.share,
    this._pinnedAt,
    this._attachments,
    this._labelIds,
    this.labelProjections,
    this._document,
  );

  /// Creates a new note with valid text and identical creation/update times.
  factory Note.create({
    required String id,
    required String ownerId,
    required String title,
    required String content,
    required DateTime now,
    NoteDocument? document,
  }) {
    _requireText(title, "title");
    _requireDocumentProjection(content, document);
    return Note._(
      id,
      ownerId,
      title,
      content,
      now,
      now,
      const NoteProtection.unprotected(),
      true,
      0,
      null,
      null,
      const [],
      const [],
      const [],
      document,
    );
  }

  /// Restores persisted values without applying current write validation.
  factory Note.reconstitute({
    required String id,
    required String ownerId,
    required String title,
    required String content,
    required DateTime createdAt,
    required DateTime updatedAt,
    NoteProtection protection = const NoteProtection.unprotected(),
    bool contentAvailable = true,
    int contentRevision = 0,
    NoteShareGrant? share,
    DateTime? pinnedAt,
    List<Attachment> attachments = const [],
    Iterable<String> labelIds = const [],
    Iterable<LabelProjection> labelProjections = const [],
    NoteDocument? document,
  }) {
    if (share != null &&
        (share.note != NoteIdentity(ownerId, id) ||
            !share.isActive && contentAvailable)) {
      throw ArgumentError('Invalid canonical sharing projection.');
    }
    if (contentRevision < 0 ||
        (!contentAvailable &&
            (title.isNotEmpty ||
                content.isNotEmpty ||
                attachments.isNotEmpty ||
                labelIds.isNotEmpty ||
                labelProjections.isNotEmpty ||
                document != null))) {
      throw ArgumentError('Invalid note content availability.');
    }
    if (document != null && document.plainText != content) {
      throw ArgumentError('Note document projection does not match content.');
    }
    return Note._(
      id,
      ownerId,
      title,
      content,
      createdAt,
      updatedAt,
      protection,
      contentAvailable,
      contentRevision,
      share,
      pinnedAt?.toUtc(),
      freezeAttachments(attachments, noteId: id),
      freezeLabelIds(labelIds),
      List.unmodifiable(labelProjections),
      document,
    );
  }

  final NoteShareGrant? share;
  NoteIdentity get identity => NoteIdentity(ownerId, id);
  String get reference => identity.referenceFor(share?.recipientId ?? ownerId);

  final String _id;
  final String _ownerId;
  final DateTime _createdAt;
  String _title;
  String _content;
  NoteDocument? _document;
  DateTime _updatedAt;
  DateTime? _pinnedAt;
  List<Attachment> _attachments;
  List<String> _labelIds;
  final List<LabelProjection> labelProjections;
  NoteProtection _protection;
  final bool _contentAvailable;
  final int _contentRevision;

  NoteProtection get protection => _protection;
  bool get contentAvailable => _contentAvailable;
  int get contentRevision => _contentRevision;

  NoteMetadata get metadata => NoteMetadata(
    id: id,
    ownerId: ownerId,
    createdAt: createdAt,
    updatedAt: updatedAt,
    contentRevision: contentRevision,
    protection: protection,
    previewTitle: protection.enabled || !contentAvailable ? null : _title,
  );

  void applyProtection(NoteProtection next) {
    _protection.requireSuccessor(next);
    _protection = next;
  }

  void _requireContent() {
    if (!contentAvailable) throw const NoteContentUnavailable();
  }

  String get id => _id;
  String get ownerId => _ownerId;

  /// The current title.
  String get title {
    _requireContent();
    return _title;
  }

  /// The current content.
  String get content {
    _requireContent();
    return _content;
  }

  NoteDocument? get document {
    _requireContent();
    return _document;
  }

  /// When this note was created. Never changes after creation.
  DateTime get createdAt => _createdAt;
  DateTime get updatedAt => _updatedAt;
  DateTime? get pinnedAt => _pinnedAt;
  List<Attachment> get attachments {
    _requireContent();
    return _attachments;
  }

  void addAttachment(Attachment attachment, DateTime now) {
    _requireContent();
    final existing = _attachments.where((item) => item.id == attachment.id);
    if (existing.isNotEmpty) {
      if (existing.single != attachment) {
        throw ArgumentError('Attachment identity cannot be rebound.');
      }
      return;
    }
    _attachments = freezeAttachments([..._attachments, attachment], noteId: id);
    _updatedAt = now.toUtc();
  }

  void removeAttachment(String attachmentId, DateTime now) {
    _requireContent();
    final next = _attachments.where((item) => item.id != attachmentId).toList();
    final nextDocument =
        _document?.removeAttachmentReferences([attachmentId]);
    final manifestChanged = next.length != _attachments.length;
    final documentChanged = !identical(nextDocument, _document);
    if (!manifestChanged && !documentChanged) return;
    if (manifestChanged) _attachments = List.unmodifiable(next);
    if (documentChanged) {
      _document = nextDocument;
      _content = nextDocument!.plainText;
    }
    _updatedAt = now.toUtc();
  }

  List<String> get labelIds {
    _requireContent();
    return _labelIds;
  }

  void attachLabel(Label label, DateTime now) {
    _requireContent();
    if (label.ownerId != ownerId || label.isDeleted) {
      throw ArgumentError('Label must be active in the note owner catalog.');
    }
    if (_labelIds.contains(label.id)) return;
    _labelIds = freezeLabelIds([..._labelIds, label.id]);
    _updatedAt = now.toUtc();
  }

  void detachLabel(String labelId, DateTime now) {
    _requireContent();
    if (!_labelIds.contains(labelId)) return;
    _labelIds = freezeLabelIds(_labelIds.where((id) => id != labelId));
    _updatedAt = now.toUtc();
  }

  /// Renames the note while preserving the entered text exactly.
  void rename(String title, DateTime now) {
    _requireContent();
    _requireText(title, "title");
    if (_title == title) return;
    _title = title;
    _updatedAt = now;
  }

  /// Replaces note content while preserving its formatting.
  void replaceContent(String content, DateTime now) {
    _requireContent();
    _requirePlainWrite(content);
    if (_content == content) return;
    _content = content;
    _updatedAt = now;
  }

  void replaceText(String title, String content, DateTime now) {
    _requireContent();
    _requireText(title, 'title');
    _requirePlainWrite(content);
    if (_title == title && _content == content) return;
    _title = title;
    _content = content;
    _updatedAt = now.toUtc();
  }

  /// A document mutation owns its plain projection; format-only changes count.
  void replaceDocument(String title, NoteDocument document, DateTime now) {
    _requireContent();
    _requireText(title, 'title');
    if (_title == title && _document == document) return;
    _title = title;
    _document = document;
    _content = document.plainText;
    _updatedAt = now.toUtc();
  }

  void _requirePlainWrite(String content) {
    if (_document == null) {
      _requireText(content, 'content');
    } else if (_content != content) {
      throw ArgumentError('A rich note requires a document snapshot.');
    }
  }

  /// Pins once; repeated requests do not move a note to the top again.
  void pin(DateTime now) {
    if (_pinnedAt != null) return;
    _pinnedAt = now.toUtc();
    _updatedAt = now;
  }

  /// Unpins the note. Repeated requests are a no-op.
  void unpin(DateTime now) {
    if (_pinnedAt == null) return;
    _pinnedAt = null;
    _updatedAt = now;
  }

  @override
  String toString() {
    return 'Note(id: $_id, ownerId: $_ownerId, title: <redacted>, '
        'createdAt: $_createdAt, updatedAt: $_updatedAt)';
  }
}

void _requireText(String value, String field) {
  if (value.trim().isEmpty) {
    throw ArgumentError('Note $field must not be blank.');
  }
}

void _requireDocumentProjection(String content, NoteDocument? document) {
  if (document == null) {
    _requireText(content, 'content');
  } else if (document.plainText != content) {
    throw ArgumentError('Note document projection does not match content.');
  }
}
