/// Realtime is an invalidation hint. Only cursor sync may write local notes.
final class RevisionSignal {
  const RevisionSignal({
    required this.eventId,
    required this.ownerId,
    required this.noteId,
    this.revision,
    this.protectionRevision,
    this.accessRevision,
  });
  final String eventId;
  final String ownerId;
  final String noteId;
  final int? revision;
  final int? protectionRevision;
  final int? accessRevision;
}

final class RevisionNotice {
  const RevisionNotice.connected() : signal = null;
  const RevisionNotice.changed(this.signal);
  final RevisionSignal? signal;
}

abstract interface class IRevisionSource {
  Stream<RevisionNotice> get notices;
  void start();
  void reconnect();
  Future<void> dispose();
}
