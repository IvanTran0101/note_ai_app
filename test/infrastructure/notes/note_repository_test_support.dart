import 'dart:async';

import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/local_sync_store.dart';
import 'package:note_ai_app/application/sync/note_sync_status.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/domain/notes/note.dart';

/// Test clock with an explicit, inspectable UTC instant.
final class TestClock {
  TestClock([DateTime? start])
    : _value = start ?? DateTime.utc(2026, 9, 25, 10, 0, 0);

  DateTime _value;

  /// The current instant, used for assertions.
  DateTime get value => _value;

  /// The injected `now` function.
  DateTime now() => _value;

  void advance(Duration duration) {
    _value = _value.add(duration);
  }
}

/// Deterministic mutation-id generator.
final class TestMutationIds {
  int _next = 0;

  /// The injected `generateMutationId` function.
  String next() => 'mutation-${++_next}';
}

/// Builds a domain Note with stable defaults.
Note testNote({
  required String id,
  String ownerId = 'user-1',
  String title = 'Title',
  String content = 'Content',
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final DateTime created = createdAt ?? DateTime.utc(2026, 9, 25, 9);
  return Note.reconstitute(
    id: id,
    ownerId: ownerId,
    title: title,
    content: content,
    createdAt: created,
    updatedAt: updatedAt ?? created,
  );
}

/// Builds a stored local note with stable defaults.
LocalNoteState testLocalNote({
  required String id,
  String ownerId = 'user-1',
  String title = 'Title',
  String content = 'Content',
  DateTime? createdAt,
  DateTime? updatedAt,
  int serverRevision = 0,
  DateTime? deletedAt,
  NoteSyncStatus status = NoteSyncStatus.synced,
}) {
  final DateTime created = createdAt ?? DateTime.utc(2026, 9, 25, 9);
  return LocalNoteState(
    id: id,
    ownerId: ownerId,
    title: title,
    content: content,
    createdAt: created,
    updatedAt: updatedAt ?? created,
    serverRevision: serverRevision,
    deletedAt: deletedAt,
    status: status,
  );
}

/// Builds an outbox entry with stable defaults.
PendingMutation testMutation({
  required String mutationId,
  required String noteId,
  required SyncMutationOperation operation,
  required int baseRevision,
  SyncNotePayload? payload,
  DateTime? createdAt,
  int retryCount = 0,
  SyncErrorCode? lastError,
  bool blocked = false,
}) {
  return PendingMutation(
    mutationId: mutationId,
    noteId: noteId,
    operation: operation,
    baseRevision: baseRevision,
    payload: payload,
    createdAt: createdAt ?? DateTime.utc(2026, 9, 25, 9),
    retryCount: retryCount,
    lastError: lastError,
    blocked: blocked,
  );
}

/// In-memory [ILocalSyncStore] fake that pins the repository's persistence
/// behavior.
///
/// It is account-bound exactly like a production adapter, can fail a replace,
/// can gate reads and replaces so tests can observe queue ordering, and tracks
/// concurrent access so tests can prove serialization.
final class FakeLocalSyncStore implements ILocalSyncStore {
  FakeLocalSyncStore({required this.accountUserId, LocalSyncState? initial})
    : _state = initial ?? LocalSyncState(accountUserId: accountUserId);

  final String accountUserId;

  LocalSyncState _state;

  /// Artificial latency applied inside both [read] and [replace].
  Duration delay = Duration.zero;

  /// When set, [replace] throws it before touching the stored state.
  Object? failure;

  /// When set, [read] waits for it.
  Completer<void>? readGate;

  /// When set, [replace] completes [replaceStarted] and waits for it.
  Completer<void>? replaceGate;

  /// Completed when a gated [replace] starts.
  final Completer<void> replaceStarted = Completer<void>();

  int readCount = 0;
  int replaceCount = 0;
  int _activeOperations = 0;
  int maximumActiveOperations = 0;

  /// The persisted state, for direct assertions.
  LocalSyncState get state => _state;

  @override
  Future<LocalSyncState> read() async {
    readCount++;
    await _runOperation(() async {
      final Completer<void>? gate = readGate;
      if (gate != null) {
        await gate.future;
      }
    });
    return _state;
  }

  @override
  Future<void> replace(LocalSyncState state) async {
    replaceCount++;
    await _runOperation(() async {
      final Completer<void>? gate = replaceGate;
      if (gate != null) {
        if (!replaceStarted.isCompleted) {
          replaceStarted.complete();
        }
        await gate.future;
      }
    });
    if (state.accountUserId != accountUserId) {
      throw StateError('refusing to store another account state');
    }
    final Object? error = failure;
    if (error != null) {
      throw error;
    }
    _state = state;
  }

  Future<void> _runOperation(Future<void> Function() body) async {
    _activeOperations++;
    if (_activeOperations > maximumActiveOperations) {
      maximumActiveOperations = _activeOperations;
    }
    try {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      await body();
    } finally {
      _activeOperations--;
    }
  }
}

/// Creates and caches one [FakeLocalSyncStore] per account, counting factory
/// invocations so tests can prove the repository caches stores.
final class FakeLocalSyncStoreFactory {
  FakeLocalSyncStoreFactory({Map<String, LocalSyncState>? initialStates})
    : initialStates = initialStates ?? <String, LocalSyncState>{};

  final Map<String, LocalSyncState> initialStates;
  final Map<String, FakeLocalSyncStore> stores = <String, FakeLocalSyncStore>{};

  int createCount = 0;

  /// The injected `localSyncStoreFactory` function.
  ILocalSyncStore create({required String accountUserId}) {
    createCount++;
    return stores.putIfAbsent(
      accountUserId,
      () => FakeLocalSyncStore(
        accountUserId: accountUserId,
        initial: initialStates[accountUserId],
      ),
    );
  }

  /// The store created for [accountUserId]; fails when none was created.
  FakeLocalSyncStore store(String accountUserId) {
    final FakeLocalSyncStore? store = stores[accountUserId];
    if (store == null) {
      throw StateError('no store was created for $accountUserId');
    }
    return store;
  }
}
