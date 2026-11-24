import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/dev/m06_local_connection.dart';
import 'package:note_ai_app/application/notes/sharing_gateway.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/sync/sync_coordinator_service.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/domain/notes/note.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/domain/notes/note_role.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';
import 'package:note_ai_app/infrastructure/notes/http_share_gateway.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';
import 'package:note_ai_app/infrastructure/security/http_note_security_gateway.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store.dart';
import 'package:note_ai_app/infrastructure/sync/http_remote_note_data_source.dart';

import '../infrastructure/documents/m09_storage_fixtures.dart' as fixture;
import 'security_fixtures.dart' show MemoryCiphertextStore, securityPassword;
import 'm09_real_http_web.dart' if (dart.library.io) 'm09_real_http_io.dart';

/// Opt-in actual local service; the full default regression never needs a server.
/// Native/browser use actual encrypted file/IndexedDB with isolated QA backing.
void registerM09LocalTransportScenarios({bool realPlatform = false}) {
  test(
    'actual local HTTP rich sync/share/revoke/protected read roundtrip',
    () async {
      final nonce = DateTime.now().microsecondsSinceEpoch.toString();
      final id = 'm09-http-$nonce',
          owner = devActors['owner']!,
          actor = devActors['recipient']!;
      final client = realLoopbackClient();
      addTearDown(client.close);
      Future<String?> ownerToken({required bool forceRefresh}) async =>
          devToken(owner, 'access');
      final ownerRemote = HttpRemoteNoteDataSource(
        baseUri: devLogicalApi,
        tokenProvider: ownerToken,
        client: client,
        expectedAccountUserId: owner,
        labelsEnabled: true,
        documentsEnabled: true,
      );
      final readerRemote = HttpRemoteNoteDataSource(
        baseUri: devLogicalApi,
        tokenProvider: ({required forceRefresh}) async =>
            devToken(actor, 'access'),
        client: client,
        expectedAccountUserId: actor,
        labelsEnabled: true,
        documentsEnabled: true,
      );
      final platform = realPlatform
          ? createLocalSyncStore(accountUserId: 'm09-http-local-$nonce')
                as EncryptedSyncStore
          : null;
      addTearDown(() => platform?.dispose());
      final backing = platform?.backing ?? MemoryCiphertextStore();
      final store = EncryptedSyncStore(owner, backing);
      addTearDown(store.dispose);
      var sequence = 0;
      final repository = NoteRepository(
        currentAccountUserId: () => owner,
        localSyncStoreFactory: ({required accountUserId}) => store,
        generateMutationId: () => 'm09-$nonce-${++sequence}',
        now: () => fixture.at,
      );
      final document = fixture.doc();
      await repository.save(
        Note.reconstitute(
          id: id,
          ownerId: owner,
          title: 'Synthetic M09 HTTP',
          content: document.plainText,
          document: document,
          createdAt: fixture.at,
          updatedAt: fixture.at,
          pinnedAt: fixture.at,
        ),
      );
      final coordinator = SyncCoordinatorService(
        accountUserId: owner,
        localStore: store,
        remote: ownerRemote,
        labelsEnabled: true,
        delay: (_) async {},
      );
      addTearDown(coordinator.dispose);
      await coordinator.syncNow();
      var saved = (await store.read()).notes.singleWhere((n) => n.id == id);
      expect(saved.document, document);
      expect(saved.serverRevision, 1);
      expect((await store.read()).outbox, isEmpty);
      final encoded = await backing.readEncoded();
      expect(encoded, isNot(contains('private rich')));
      expect(encoded, isNot(contains('fontSize')));
      final reopened = EncryptedSyncStore(owner, backing);
      addTearDown(reopened.dispose);
      expect(
        (await reopened.read()).notes.singleWhere((n) => n.id == id).document,
        document,
      );

      final formatted = fixture.doc(bold: true);
      await repository.save(
        Note.reconstitute(
          id: id,
          ownerId: owner,
          title: saved.title,
          content: formatted.plainText,
          document: formatted,
          createdAt: saved.createdAt,
          updatedAt: saved.updatedAt.add(const Duration(seconds: 1)),
          contentRevision: saved.serverRevision,
          pinnedAt: saved.pinnedAt,
        ),
      );
      await coordinator.syncNow();
      saved = (await store.read()).notes.singleWhere((n) => n.id == id);
      expect(saved.document, formatted);
      expect(saved.serverRevision, 2);
      expect(saved.pinnedAt, fixture.at);
      await expectLater(
        ownerRemote.push(
          SyncMutation(
            mutationId: 'old-client-$nonce',
            noteId: id,
            operation: SyncMutationOperation.update,
            baseRevision: 2,
            payload: const SyncNotePayload(
              title: 'Legacy',
              content: 'plain replacement',
            ),
          ),
        ),
        throwsA(
          isA<SyncFailure>().having(
            (e) => e.code,
            'code',
            SyncErrorCode.documentRequiresUpgrade,
          ),
        ),
      );
      await readerRemote.negotiateWireVersion();
      final sharing = HttpShareGateway(
        baseUri: devLogicalApi,
        actorId: owner,
        tokenProvider: ownerToken,
        isCurrent: () => true,
        grantHeader: (_) async => null,
        client: client,
      );
      addTearDown(sharing.close);
      final identity = NoteIdentity(owner, id);
      final grant = await sharing.apply(
        identity,
        ShareCommand(
          requestId: 'share-$nonce',
          action: 'create',
          expectedAccessRevision: 0,
          email: devEmails['recipient'],
          role: NoteRole.editor,
        ),
      );
      var recipientPage = await _pullAll(readerRemote);
      final shared = recipientPage.snapshots.singleWhere((n) => n.id == id);
      expect(shared.document, formatted);
      expect(shared.ownerId, owner);
      final update = await readerRemote.push(
        SyncMutation(
          mutationId: 'recipient-$nonce',
          noteId: id,
          ownerId: owner,
          accessRevision: grant.accessRevision,
          operation: SyncMutationOperation.update,
          baseRevision: 2,
          payload: SyncNotePayload(
            title: 'Shared format',
            content: document.plainText,
            document: document,
            includesDocument: true,
          ),
        ),
      );
      expect(update.note!.document, document);
      expect(update.note!.revision, 3);
      await sharing.apply(
        identity,
        ShareCommand(
          requestId: 'revoke-$nonce',
          action: 'revoke',
          expectedAccessRevision: grant.accessRevision,
          recipientId: actor,
        ),
      );
      recipientPage = await _pullAll(
        readerRemote,
        cursor: recipientPage.nextCursor,
      );
      final revoked = recipientPage.snapshots.where((n) => n.id == id).last;
      expect(revoked.document, null);
      expect(revoked.contentAvailable, false);
      expect(revoked.content, isEmpty);
      expect(revoked.accessRemoved, true);
      await expectLater(
        readerRemote.push(
          SyncMutation(
            mutationId: 'revoked-write-$nonce',
            noteId: id,
            ownerId: owner,
            accessRevision: grant.accessRevision,
            operation: SyncMutationOperation.update,
            baseRevision: 3,
            payload: SyncNotePayload(
              title: 'Denied',
              content: document.plainText,
              document: document,
              includesDocument: true,
            ),
          ),
        ),
        throwsA(
          isA<SyncFailure>().having(
            (e) => e.code,
            'code',
            SyncErrorCode.forbidden,
          ),
        ),
      );

      final security = HttpNoteSecurityGateway(
        baseUri: devLogicalApi,
        accountId: owner,
        tokenProvider: ownerToken,
        isCurrentSession: () => true,
        documentsEnabled: true,
        client: client,
      );
      addTearDown(security.close);
      await security.enable(id, securityPassword, 3);
      final metadata = (await _pullAll(ownerRemote)).snapshots
          .where((n) => n.id == id)
          .last;
      expect(metadata.document, null);
      expect(metadata.content, isEmpty);
      await expectLater(
        ownerRemote.push(
          SyncMutation(
            mutationId: 'locked-write-$nonce',
            noteId: id,
            operation: SyncMutationOperation.update,
            baseRevision: 3,
            payload: SyncNotePayload(
              title: 'Denied',
              content: formatted.plainText,
              document: formatted,
              includesDocument: true,
            ),
          ),
        ),
        throwsA(
          isA<SyncFailure>().having(
            (e) => e.code,
            'code',
            SyncErrorCode.forbidden,
          ),
        ),
      );
      await expectLater(
        security.content(id),
        throwsA(isA<NoteSecurityFailure>()),
      );
      await security.unlock(id, securityPassword, {
        NoteOperation.read,
        NoteOperation.manage,
      });
      final authorized = await security.content(id);
      expect(authorized.document, document);
      expect(authorized.content, document.plainText);
      security.invalidate(id);
      await expectLater(
        security.content(id),
        throwsA(isA<NoteSecurityFailure>()),
      );
      // Retire only this synthetic QA note, preserving all other fixture data.
      await security.unlock(id, securityPassword, {
        NoteOperation.read,
        NoteOperation.manage,
      });
      await security.disable(
        id,
        securityPassword,
        authorized.protection.revision,
      );
      final deleted = await ownerRemote.push(
        SyncMutation(
          mutationId: 'cleanup-$nonce',
          noteId: id,
          operation: SyncMutationOperation.delete,
          baseRevision: 3,
        ),
      );
      expect(deleted.note!.isDeleted, true);
    },
    skip: !const bool.fromEnvironment('M09_LOCAL_HTTP'),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<SyncChangesPage> _pullAll(
  HttpRemoteNoteDataSource remote, {
  String? cursor,
}) async {
  final snapshots = <SyncNoteSnapshot>[];
  for (var pages = 0; pages < 100; pages++) {
    final page = await remote.pull(cursor: cursor, limit: 100);
    snapshots.addAll(page.snapshots);
    cursor = page.nextCursor;
    if (!page.hasMore) {
      return SyncChangesPage(
        snapshots: snapshots,
        nextCursor: cursor,
        wireVersion: page.wireVersion,
      );
    }
  }
  throw StateError('Synthetic local feed did not complete.');
}
