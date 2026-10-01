/// Frozen M2.0 local sync state schema vocabulary.
///
/// Native JSON documents and Web IndexedDB records use this one envelope, so
/// every field name and the schema version live here rather than in the codecs
/// that read them. The version is 2: version 1 was the notes-only document.
library;

/// Field names and the schema version of the frozen M2 local sync document.
abstract final class LocalSyncSchema {
  /// The only schema version this codec reads or writes.
  static const int version = 3;

  // Envelope fields.
  static const String schemaVersion = 'schemaVersion';
  static const String accountUserId = 'accountUserId';
  static const String notes = 'notes';
  static const String outbox = 'outbox';
  static const String cursor = 'cursor';
  static const String conflicts = 'conflicts';

  // Local note fields.
  static const String id = 'id';
  static const String ownerId = 'ownerId';
  static const String title = 'title';
  static const String content = 'content';
  static const String createdAt = 'createdAt';
  static const String updatedAt = 'updatedAt';
  static const String serverRevision = 'serverRevision';
  static const String deletedAt = 'deletedAt';
  static const String status = 'status';
  static const String protected = 'protected';
  static const String protectionRevision = 'protectionRevision';
  static const String contentAvailable = 'contentAvailable';

  // Pending mutation fields.
  static const String mutationId = 'mutationId';
  static const String noteId = 'noteId';
  static const String operation = 'operation';
  static const String baseRevision = 'baseRevision';
  static const String payload = 'payload';
  static const String retryCount = 'retryCount';
  static const String lastError = 'lastError';
  static const String blocked = 'blocked';

  // Remote note snapshot fields.
  static const String serverUpdatedAt = 'serverUpdatedAt';
  static const String revision = 'revision';

  // Conflict fields.
  static const String remote = 'remote';
  static const String local = 'local';
  static const String pending = 'pending';
  static const String detectedAt = 'detectedAt';

  /// Exactly the fields the envelope carries.
  static const Set<String> envelopeFields = <String>{
    schemaVersion,
    accountUserId,
    notes,
    outbox,
    cursor,
    conflicts,
  };

  /// Exactly the fields one local note record carries.
  static const Set<String> noteFields = <String>{
    protected,
    protectionRevision,
    contentAvailable,
    id,
    ownerId,
    title,
    content,
    createdAt,
    updatedAt,
    serverRevision,
    deletedAt,
    status,
  };

  /// Exactly the fields one mutation payload carries.
  static const Set<String> payloadFields = <String>{title, content};

  /// Exactly the fields one pending mutation record carries.
  static const Set<String> mutationFields = <String>{
    mutationId,
    noteId,
    operation,
    baseRevision,
    payload,
    createdAt,
    retryCount,
    lastError,
    blocked,
  };

  /// Exactly the fields one remote note snapshot record carries.
  static const Set<String> snapshotFields = <String>{
    protected,
    protectionRevision,
    contentAvailable,
    id,
    title,
    content,
    createdAt,
    serverUpdatedAt,
    revision,
    deletedAt,
  };

  /// Exactly the fields one conflict record carries.
  static const Set<String> conflictFields = <String>{
    noteId,
    remote,
    local,
    pending,
    detectedAt,
  };
}
