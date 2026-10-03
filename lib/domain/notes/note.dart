import 'note_metadata.dart';
import 'note_protection.dart';
import 'note_identity.dart';
import 'note_share_grant.dart';

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
  );

  /// Creates a new note with valid text and identical creation/update times.
  factory Note.create({
    required String id,
    required String ownerId,
    required String title,
    required String content,
    required DateTime now,
  }) {
    _requireText(title, "title");
    _requireText(content, "content");
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
  }) {
    if (share != null &&
        (share.note != NoteIdentity(ownerId, id) ||
            !share.isActive && contentAvailable)) {
      throw ArgumentError('Invalid canonical sharing projection.');
    }
    if (contentRevision < 0 ||
        (!contentAvailable && (title.isNotEmpty || content.isNotEmpty))) {
      throw ArgumentError('Invalid note content availability.');
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
  DateTime _updatedAt;
  DateTime? _pinnedAt;
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

  /// When this note was created. Never changes after creation.
  DateTime get createdAt => _createdAt;
  DateTime get updatedAt => _updatedAt;
  DateTime? get pinnedAt => _pinnedAt;

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
    _requireText(content, "content");
    if (_content == content) return;
    _content = content;
    _updatedAt = now;
  }

  void replaceText(String title, String content, DateTime now) {
    _requireContent();
    _requireText(title, 'title');
    _requireText(content, 'content');
    if (_title == title && _content == content) return;
    _title = title;
    _content = content;
    _updatedAt = now.toUtc();
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
