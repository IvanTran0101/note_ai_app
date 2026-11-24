import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/notes/note_security_service.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/application/sync/sync_state_reconciliation.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';
import 'package:note_ai_app/infrastructure/security/unavailable_note_security_gateway.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_state_codec.dart';

import 'platform_probe.dart';
import 'security_fixtures.dart';

NoteSecurityService localService(String account, EncryptedSyncStore store) {
  final session = CurrentUserSession()
    ..setIdentity(
      AuthIdentity(
        userId: account,
        email: 'synthetic@example.invalid',
        isEmailVerified: true,
      ),
    );
  return NoteSecurityService(
    accountId: account,
    currentUser: session,
    session: session,
    store: store,
    vault: store,
    localFirst: true,
    gateway: const UnavailableNoteSecurityGateway(),
  );
}

LocalSyncState unsynced(String account) => LocalSyncState(
  accountUserId: account,
  notes: [
    LocalNoteState(
      id: 'alpha',
      ownerId: account,
      title: privateTitle,
      content: privateBody,
      createdAt: fixtureTime,
      updatedAt: fixtureTime,
    ),
    securityNote(account, id: 'beta', content: 'sibling content'),
  ],
  outbox: [
    PendingMutation(
      mutationId: 'local-create',
      noteId: 'alpha',
      operation: SyncMutationOperation.create,
      baseRevision: 0,
      payload: const SyncNotePayload(title: privateTitle, content: privateBody),
      createdAt: fixtureTime,
    ),
  ],
);

void registerLocalFirstScenarios({
  Future<String> Function()? supportPathResolver,
  Future<String> Function(String)? readRecord,
}) {
  test('local-first new unsynced note enables offline, survives real storage reopen, rotates and disables offline', () async {
    final account = 'm05-local-${DateTime.now().microsecondsSinceEpoch}';
    final store = createLocalSyncStore(
      accountUserId: account,
      applicationSupportPathResolver: supportPathResolver,
    ) as EncryptedSyncStore;
    await store.replace(unsynced(account));
    final service = localService(account, store);
    await service.enable('alpha', securityPassword, securityPassword);
    final first = await store.read();
    expect(first.notes.first.protection.enabled, true);
    expect(first.outbox.single.mutationId, 'local-create');
    expect(first.outbox.single.baseRevision, 0);
    expect(first.outbox.single.protectionChange!.before.revision, 0);
    expect(
      first.outbox.single.protectionChange!.verifier,
      startsWith('pbkdf2-sha256-v1\$'),
    );
    expect(
      LocalSyncStateCodec.decode(LocalSyncStateCodec.encode(first)),
      first,
    );
    service.dispose();
    store.dispose();
    final raw = await (readRecord ?? readPlatformRecord)(account);
    for (final secret in [
      privateTitle,
      privateBody,
      securityPassword,
      'pbkdf2-sha256-v1',
    ]) {
      expect(raw, isNot(contains(secret)));
    }
    final reopened = createLocalSyncStore(
      accountUserId: account,
      applicationSupportPathResolver: supportPathResolver,
    ) as EncryptedSyncStore;
    final next = localService(account, reopened);
    addTearDown(() {
      next.dispose();
      reopened.dispose();
    });
    expect((await reopened.read()).notes.first.contentAvailable, false);
    await expectLater(
      next.unlock('alpha', 'incorrect-password', offline: true),
      throwsA(
        isA<NoteSecurityFailure>().having(
          (e) => e.code,
          'code',
          NoteSecurityFailureCode.invalidPassword,
        ),
      ),
    );
    await next.unlock('alpha', securityPassword, offline: true);
    expect((await reopened.read()).notes.first.content, privateBody);
    await next.changePassword(
      'alpha',
      securityPassword,
      'replacement-password',
      'replacement-password',
    );
    next.lock('alpha');
    await expectLater(
      next.unlock('alpha', securityPassword, offline: true),
      throwsA(isA<NoteSecurityFailure>()),
    );
    await next.unlock('alpha', 'replacement-password', offline: true);
    await expectLater(
      next.disable('alpha', securityPassword),
      throwsA(isA<NoteSecurityFailure>()),
    );
    await next.disable('alpha', 'replacement-password');
    final end = await reopened.read();
    expect(
      end.notes.first.protection,
      NoteProtection(enabled: false, revision: 3),
    );
    expect(end.notes.first.content, privateBody);
    expect(end.notes.last.content, 'sibling content');
    expect(end.outbox.single.mutationId, 'local-create');
    expect(end.outbox.single.protectionChange!.before.revision, 0);
    expect(end.outbox.single.protectionChange!.after.revision, 3);
    expect(end.outbox.single.protectionChange!.verifier, null);
  }, timeout: const Timeout(Duration(minutes: 8)));

  test('local-first independent passwords, wrong-current refusal and remote old metadata preserve pending keys', () async {
    final account = 'm05-independent-${DateTime.now().microsecondsSinceEpoch}';
    final store = EncryptedSyncStore(account, MemoryCiphertextStore());
    final service = localService(account, store);
    addTearDown(() {
      service.dispose();
      store.dispose();
    });
    await store.replace(unsynced(account));
    await service.enable('alpha', securityPassword, securityPassword);
    await service.enable('beta', 'sibling-password', 'sibling-password');
    await expectLater(
      service.changePassword(
        'alpha',
        'wrong-password',
        'replacement-password',
        'replacement-password',
      ),
      throwsA(isA<NoteSecurityFailure>()),
    );
    final before = await store.read();
    expect(before.notes.first.protection.revision, 1);
    await service.observeSnapshot(
      SyncNoteSnapshot(
        id: 'alpha',
        title: 'old',
        content: 'old',
        createdAt: fixtureTime,
        serverUpdatedAt: fixtureTime,
        revision: 1,
      ),
    );
    expect((await store.read()).notes.first.protection.revision, 1);
    service.lock(null);
    await service.unlock('alpha', securityPassword, offline: true);
    expect((await store.read()).notes.last.contentAvailable, false);
    await expectLater(
      service.unlock('beta', securityPassword, offline: true),
      throwsA(isA<NoteSecurityFailure>()),
    );
    await service.unlock('beta', 'sibling-password', offline: true);
    expect((await store.read()).notes.last.content, 'sibling content');
    final repo = NoteRepository(
      currentAccountUserId: () => account,
      localSyncStoreFactory: ({required accountUserId}) => store,
      generateMutationId: () => 'edit-after-protection',
      now: () => fixtureTime,
      accessGuard: service,
    );
    final edited = (await repo.findById('alpha'))!;
    edited.replaceContent('$privateBody edited offline', fixtureTime);
    await repo.save(edited);
    final editedState = await store.read();
    final alpha = editedState.outbox.firstWhere((m) => m.noteId == 'alpha');
    expect(alpha.mutationId, 'local-create');
    expect(alpha.protectionChange!.after.revision, 1);
    expect(alpha.payload!.content, '$privateBody edited offline');
    await repo.deleteById('alpha');
    expect(
      (await store.read()).outbox.where((m) => m.noteId == 'alpha'),
      isEmpty,
    );
    expect((await store.read()).notes.where((n) => n.id == 'alpha'), isEmpty);
    expect((await store.read()).notes.single.content, 'sibling content');
    expect(
      service.gateway.hasAuthority(
        'alpha',
        before.notes.first.protection,
        NoteOperation.manage,
      ),
      false,
    );
  }, timeout: const Timeout(Duration(minutes: 8)));

  test('compound ACK and historical pull preserve a later local password epoch and payload', () async {
    final account = 'm05-ack-${DateTime.now().microsecondsSinceEpoch}';
    final store = EncryptedSyncStore(account, MemoryCiphertextStore());
    addTearDown(store.dispose);
    await store.replace(unsynced(account));
    await store.enableLocal('alpha', securityPassword);
    final first = (await store.read()).outbox.single;
    await store.update(
      (s) => LocalSyncState(
        accountUserId: account,
        notes: s.notes,
        outbox: [
          PendingMutation(
            mutationId: first.mutationId,
            noteId: first.noteId,
            operation: first.operation,
            baseRevision: first.baseRevision,
            payload: first.payload,
            protectionChange: first.protectionChange,
            createdAt: first.createdAt,
            retryCount: 1,
          ),
        ],
      ),
    );
    await store.changeLocal('alpha', securityPassword, 'replacement-password');
    final reconcile = SyncStateReconciliation(
      accountUserId: account,
      localStore: store,
      clock: () => fixtureTime,
    );
    await reconcile.acknowledge(
      first,
      SyncNoteSnapshot(
        id: 'alpha',
        title: '',
        content: '',
        createdAt: fixtureTime,
        serverUpdatedAt: fixtureTime,
        revision: 1,
        protection: first.protectionChange!.after,
        contentAvailable: false,
      ),
    );
    final state = await store.read();
    expect(state.notes.first.protection.revision, 2);
    expect(state.notes.first.content, privateBody);
    expect(state.outbox.single.protectionChange!.before.revision, 1);
    expect(state.outbox.single.baseRevision, 1);
  }, timeout: const Timeout(Duration(minutes: 8)));
}
