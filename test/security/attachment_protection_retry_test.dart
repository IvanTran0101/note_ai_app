import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:note_ai_app/application/notes/note_security_service.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';

import 'local_first_scenarios.dart';
import 'security_fixtures.dart';
import 'security_harness.dart';

PendingMutation rejected(PendingMutation entry) => PendingMutation(
  mutationId: entry.mutationId,
  noteId: entry.noteId,
  ownerId: entry.ownerId,
  operation: entry.operation,
  baseRevision: entry.baseRevision,
  payload: SyncNotePayload(
    title: entry.payload!.title,
    content: entry.payload!.content,
    pinnedAt: entry.payload!.pinnedAt,
    includesPinnedAt: entry.payload!.includesPinnedAt,
    includesAttachments: true,
    attachmentManifest: entry.payload!.attachmentManifest,
    includesLabels: entry.payload!.includesLabels,
    labelMembership: entry.payload!.labelMembership,
  ),
  protectionChange: entry.protectionChange,
  createdAt: entry.createdAt,
  retryCount: 2,
  lastError: SyncErrorCode.invalidMutation,
  blocked: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'first online owner unlock explicitly requests attachment export scope',
    () async {
      final harness = SecurityHarness('owner');
      addTearDown(harness.dispose);
      await harness.initialize();
      harness.gateway
        ..password = securityPassword
        ..protection = NoteProtection(enabled: true, revision: 1);
      await harness.security.unlock('alpha', securityPassword);
      expect(harness.gateway.lease!.operations, contains(NoteOperation.export));
      expect(
        harness.gateway.lease!.operations,
        contains(NoteOperation.attachmentRead),
      );
      expect(
        harness.security.allows(
          ownerId: 'owner',
          noteId: 'alpha',
          protection: harness.gateway.protection,
          operation: NoteOperation.export,
        ),
        true,
      );
    },
  );

  test('explicit protection retry preserves frozen attachment mutation and does not unblock ordinary invalid writes', () async {
    final store = EncryptedSyncStore('owner', MemoryCiphertextStore());
    final service = localService('owner', store);
    addTearDown(() {
      service.dispose();
      store.dispose();
    });
    await store.replace(securityState('owner'));
    await service.enable('alpha', securityPassword, securityPassword);
    final initial = await store.read();
    final target = rejected(initial.outbox.single);
    expect(target.payload!.includesAttachments, true);
    final ordinary = PendingMutation(
      mutationId: 'unrelated-invalid',
      noteId: 'beta',
      operation: SyncMutationOperation.update,
      baseRevision: 7,
      payload: const SyncNotePayload(title: 'beta', content: 'keep'),
      createdAt: fixtureTime,
      retryCount: 1,
      lastError: SyncErrorCode.invalidMutation,
      blocked: true,
    );
    await store.update(
      (state) => LocalSyncState(
        accountUserId: state.accountUserId,
        notes: state.notes,
        outbox: [target, ordinary],
        cursor: state.cursor,
        labels: state.labels,
        userPreferences: state.userPreferences,
        syncWireVersion: state.syncWireVersion,
        conflicts: state.conflicts,
      ),
    );
    await service.authorizePendingSync('alpha', securityPassword);
    final result = await store.read();
    final retry = result.outbox.first;
    expect(retry.blocked, false);
    expect(retry.lastError, null);
    expect(retry.mutation, target.mutation);
    expect(retry.retryCount, 2);
    expect(retry.createdAt, target.createdAt);
    expect(result.outbox.last, ordinary);
    expect(result.notes, initial.notes);
    expect(result.cursor, initial.cursor);
  });

  test('ordinary unlock does not automatically retry an invalid protection mutation', () async {
    final store = EncryptedSyncStore('owner', MemoryCiphertextStore());
    final service = localService('owner', store);
    addTearDown(() {
      service.dispose();
      store.dispose();
    });
    await store.replace(securityState('owner'));
    await service.enable('alpha', securityPassword, securityPassword);
    final initial = await store.read();
    final target = rejected(initial.outbox.single);
    await store.update(
      (state) => LocalSyncState(
        accountUserId: state.accountUserId,
        notes: state.notes,
        outbox: [target],
        cursor: state.cursor,
      ),
    );
    service.lock('alpha');
    await service.unlock('alpha', securityPassword, offline: true);
    expect((await store.read()).outbox.single, target);
  });
}
