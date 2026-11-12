import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_conflict.dart';
import 'package:note_ai_app/application/sync/sync_cursor.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/security/encoded_account_store.dart';

const securityPassword = 'synthetic-note-password';
const privateTitle = 'M05 synthetic private title';
const privateBody = 'M05 synthetic private body 🧪';
final fixtureTime = DateTime.utc(2026, 10, 2);

LocalNoteState securityNote(
  String account, {
  String id = 'alpha',
  NoteProtection protection = const NoteProtection.unprotected(),
  String content = privateBody,
}) => LocalNoteState(
  id: id,
  ownerId: account,
  title: privateTitle,
  content: content,
  createdAt: fixtureTime,
  updatedAt: fixtureTime,
  serverRevision: 7,
  protection: protection,
);

LocalSyncState securityState(String account, {bool pending = false}) {
  final note = securityNote(account);
  final mutation = PendingMutation(
    mutationId: 'stable-mutation-id',
    noteId: 'alpha',
    operation: SyncMutationOperation.update,
    baseRevision: 7,
    payload: const SyncNotePayload(title: privateTitle, content: privateBody),
    createdAt: fixtureTime,
    retryCount: 3,
    lastError: SyncErrorCode.timeout,
  );
  return LocalSyncState(
    accountUserId: account,
    notes: [
      note,
      securityNote(account, id: 'beta', content: 'sibling content'),
    ],
    outbox: pending ? [mutation] : [],
    cursor: const SyncCursor('synthetic-cursor'),
    conflicts: pending
        ? [
            SyncConflict(
              noteId: 'alpha',
              local: note,
              pending: mutation,
              remote: SyncNoteSnapshot(
                id: 'alpha',
                title: 'private remote title',
                content: 'private remote content',
                createdAt: fixtureTime,
                serverUpdatedAt: fixtureTime,
                revision: 8,
              ),
              detectedAt: fixtureTime,
            ),
          ]
        : [],
  );
}

final class MemoryCiphertextStore implements EncodedAccountStore {
  String? encoded;
  int failCommits = 0;
  final List<String> commits = [];
  @override
  Future<String?> readEncoded() async => encoded;
  @override
  Future<bool> compareAndSet(String? expected, String encrypted) async {
    if (failCommits > 0) {
      failCommits--;
      return false;
    }
    if (encoded != expected) return false;
    encoded = encrypted;
    commits.add(encrypted);
    return true;
  }

  @override
  Future<void> cleanLegacyStaging(
    String accountId,
    Future<String> Function(String) sealLegacy,
  ) async {}
}
