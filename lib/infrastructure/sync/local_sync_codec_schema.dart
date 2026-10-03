/// Field names and version for the local account sync document.
library;

abstract final class LocalSyncSchema {
  /// The only schema version this codec reads or writes.
  static const int version = 4;

  static const String schemaVersion = 'schemaVersion';
  static const String accountUserId = 'accountUserId';
  static const String notes = 'notes';
  static const String outbox = 'outbox';
  static const String cursor = 'cursor';
  static const String conflicts = 'conflicts';
  static const String userPreferences = 'userPreferences';

  static const String id = 'id';
  static const String ownerId = 'ownerId';
  static const String title = 'title';
  static const String content = 'content';
  static const String createdAt = 'createdAt';
  static const String updatedAt = 'updatedAt';
  static const String pinnedAt = 'pinnedAt';
  static const String serverRevision = 'serverRevision';
  static const String deletedAt = 'deletedAt';
  static const String status = 'status';
  static const String protected = 'protected';
  static const String protectionRevision = 'protectionRevision';
  static const String contentAvailable = 'contentAvailable';
  static const String share = 'share';
  static const String accessRevision = 'accessRevision';
  static const Set<String> noteOptionalFields = {share};
  static const Set<String> mutationOptionalFields = {
    ownerId,
    accessRevision,
    'protectionChange',
  };
  static const Set<String> snapshotOptionalFields = {ownerId, share};

  static const String mutationId = 'mutationId';
  static const String noteId = 'noteId';
  static const String operation = 'operation';
  static const String baseRevision = 'baseRevision';
  static const String payload = 'payload';
  static const String retryCount = 'retryCount';
  static const String lastError = 'lastError';
  static const String blocked = 'blocked';

  static const String serverUpdatedAt = 'serverUpdatedAt';
  static const String revision = 'revision';
  static const String remote = 'remote';
  static const String local = 'local';
  static const String pending = 'pending';
  static const String detectedAt = 'detectedAt';

  static const String userId = 'userId';
  static const String theme = 'theme';
  static const String noteFontSize = 'noteFontSize';
  static const String noteColorKey = 'noteColorKey';
  static const String noteLayout = 'noteLayout';

  static const Set<String> envelopeFields = <String>{
    schemaVersion,
    accountUserId,
    notes,
    outbox,
    cursor,
    conflicts,
    userPreferences,
  };
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
    pinnedAt,
    serverRevision,
    deletedAt,
    status,
  };
  static const Set<String> payloadFields = <String>{title, content, pinnedAt};
  static const Set<String> payloadFieldsV2 = <String>{title, content};
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
  static const Set<String> mutationFieldsV2 = mutationFields;
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
    pinnedAt,
    deletedAt,
  };
  static const Set<String> conflictFields = <String>{
    noteId,
    remote,
    local,
    pending,
    detectedAt,
  };
  static const Set<String> conflictFieldsV2 = conflictFields;
  static const Set<String> userPreferencesFields = <String>{
    userId,
    theme,
    noteFontSize,
    noteColorKey,
    noteLayout,
  };

  static const Set<String> envelopeFieldsV2 = <String>{
    schemaVersion,
    accountUserId,
    notes,
    outbox,
    cursor,
    conflicts,
  };
  static const Set<String> noteFieldsV2 = <String>{
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
  static const Set<String> snapshotFieldsV2 = <String>{
    id,
    title,
    content,
    createdAt,
    serverUpdatedAt,
    revision,
    deletedAt,
  };
}
