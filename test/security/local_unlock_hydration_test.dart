import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/notes/note_security_gateway.dart';
import 'package:note_ai_app/application/notes/note_security_service.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';

import 'security_fixtures.dart';
import 'security_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final mode in ['online', 'offline', 'wrong password']) {
    test(
      '$mode unlock with a cached key and a newer metadata-only revision',
      () async {
        const account = 'unlock-hydration';
        final protection = NoteProtection(enabled: true, revision: 1);
        final session = CurrentUserSession()
          ..setIdentity(
            AuthIdentity(
              userId: account,
              email: 'qa@example.invalid',
              isEmailVerified: true,
            ),
          );
        final store = EncryptedSyncStore(account, MemoryCiphertextStore());
        final gateway = _HydrationGateway(protection);
        final service = NoteSecurityService(
          accountId: account,
          currentUser: session,
          session: session,
          store: store,
          vault: store,
          gateway: gateway,
          localFirst: true,
          now: () => fixtureTime,
        );
        addTearDown(() {
          service.dispose();
          store.dispose();
        });
        await store.replace(securityState(account));
        await store.seal('alpha', securityPassword, protection);
        service.lock('alpha');
        await store.update(
          (state) => LocalSyncState(
            accountUserId: account,
            cursor: state.cursor,
            notes: [
              LocalNoteState(
                id: 'alpha',
                ownerId: account,
                title: '',
                content: '',
                createdAt: fixtureTime,
                updatedAt: fixtureTime,
                serverRevision: 8,
                protection: protection,
                contentAvailable: false,
              ),
              state.notes.last,
            ],
          ),
        );
        if (mode == 'online') {
          await service.unlock('alpha', securityPassword);
          final state = await store.read();
          final fresh = state.notes.singleWhere((n) => n.id == 'alpha');
          expect(fresh.contentAvailable, true);
          expect(fresh.content, 'fresh authorized revision');
          expect(fresh.serverRevision, 8);
          expect(fresh.labelIds, ['authorized-label']);
          expect(
            state.notes.singleWhere((n) => n.id == 'beta').content,
            'sibling content',
          );
          expect(state.cursor!.value, 'synthetic-cursor');
          expect(gateway.unlockCalls, 1);
          expect(gateway.contentCalls, 1);
        } else {
          await expectLater(
            service.unlock(
              'alpha',
              mode == 'wrong password' ? 'wrong password' : securityPassword,
              offline: mode == 'offline',
            ),
            throwsA(
              isA<NoteSecurityFailure>().having(
                (f) => f.code,
                'code',
                mode == 'offline'
                    ? NoteSecurityFailureCode.staleRevision
                    : NoteSecurityFailureCode.invalidPassword,
              ),
            ),
          );
          expect((await store.read()).notes.first.contentAvailable, false);
          expect(gateway.unlockCalls, 0);
          expect(gateway.contentCalls, 0);
        }
      },
    );
  }
}

final class _HydrationGateway implements INoteSecurityGateway {
  _HydrationGateway(NoteProtection protection) {
    delegate.protection = protection;
    delegate.password = securityPassword;
  }
  final delegate = SyntheticSecurityGateway();
  int unlockCalls = 0, contentCalls = 0;
  @override
  Future<NoteProtection> metadata(String id) => delegate.metadata(id);
  @override
  Future<NoteUnlockLease> unlock(
    String id,
    String password,
    Set<NoteOperation> operations,
  ) {
    unlockCalls++;
    return delegate.unlock(id, password, operations);
  }

  @override
  Future<SyncNoteSnapshot> content(String id) async {
    contentCalls++;
    if (!hasAuthority(id, delegate.protection, NoteOperation.read)) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.locked);
    }
    return SyncNoteSnapshot(
      id: id,
      title: privateTitle,
      content: 'fresh authorized revision',
      createdAt: fixtureTime,
      serverUpdatedAt: fixtureTime,
      revision: 8,
      protection: delegate.protection,
      labelIds: ['authorized-label'],
      includesLabels: true,
      includesAttachments: true,
    );
  }

  @override
  bool hasAuthority(String id, NoteProtection p, NoteOperation operation) =>
      delegate.hasAuthority(id, p, operation);
  @override
  void invalidate(String? id) => delegate.invalidate(id);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected gateway action');
}
