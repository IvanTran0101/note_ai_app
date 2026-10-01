/// Persistent protection metadata. It contains no proof of unlock authority.
final class NoteProtection {
  const NoteProtection.unprotected() : enabled = false, revision = 0;

  factory NoteProtection({required bool enabled, required int revision}) {
    if (revision < 0 || (enabled && revision == 0)) {
      throw ArgumentError('Invalid note protection metadata.');
    }
    return NoteProtection._(enabled, revision);
  }

  const NoteProtection._(this.enabled, this.revision);

  final bool enabled;
  final int revision;

  void requireSuccessor(NoteProtection next) {
    if (next.revision <= revision) {
      throw StateError('Protection transitions require a newer revision.');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is NoteProtection &&
      enabled == other.enabled &&
      revision == other.revision;

  @override
  int get hashCode => Object.hash(enabled, revision);

  @override
  String toString() => 'NoteProtection(enabled: $enabled, revision: $revision)';
}

enum NoteOperation {
  read,
  edit,
  delete,
  manage,
  summary,
  export,
  attachmentRead,
  attachmentWrite,
}

final class NoteContentUnavailable implements Exception {
  const NoteContentUnavailable();

  @override
  String toString() => 'NoteContentUnavailable';
}
