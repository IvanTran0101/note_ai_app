import 'dart:math';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../application/attachments/attachment_transfer.dart';

import '../../application/attachments/attachment_application.dart';
import '../../domain/notes/note_repository.dart';
import '../../application/notes/note_access.dart';
import '../security/encrypted_sync_store.dart';
import '../security/note_security_runtime.dart';
import 'attachment_security_adapter.dart';
import 'attachment_chunk_cipher.dart';
import 'attachment_store.dart';
import 'encrypted_attachment_cache.dart';
import 'http_attachment_upload.dart';
import 'http_attachment_reader.dart';

/// Account-scoped binary cache; uses the canonical Note writer and M05 key.
/// Verified transport is composed only when the Note security API is configured.
final class AttachmentRuntime {
  AttachmentRuntime({
    required this.security,
    required this.notes,
    required this.storeForAccount,
    required this.requestSync,
    AttachmentBlobStore Function({required String actorId})? blobStoreFactory,
  }) : blobStoreFactory = blobStoreFactory ?? createAttachmentBlobStore;
  final NoteSecurityRuntime security;
  final INoteRepository notes;
  final EncryptedSyncStore Function(String) storeForAccount;
  final void Function(String) requestSync;
  final AttachmentBlobStore Function({required String actorId})
  blobStoreFactory;
  final _services = <String, AttachmentApplicationService>{};
  late final authority = AttachmentSecurityAdapter(
    security: security,
    storeForAccount: storeForAccount,
  );

  AttachmentApplicationService forCurrentAccount() {
    final actor = security.session.requiredUserId;
    security.requireSession(actor);
    return _services.putIfAbsent(actor, () {
      final cipher = AttachmentChunkCipher(
        requireAccess: authority.requireAccess,
        resolveKey: (binding) => storeForAccount(actor).attachmentKey(binding),
        resolveLegacyKey: (binding) =>
            storeForAccount(actor).attachmentLegacyKey(binding),
      );
      final cache = EncryptedAttachmentCache(
        actorId: actor,
        store: blobStoreFactory(actorId: actor),
        cipher: cipher,
        generateId: () {
          final random = Random.secure();
          return List.generate(
            32,
            (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
          ).join();
        },
      );
      final progress = StreamController<AttachmentProgress>.broadcast(
        sync: true,
      );
      storeForAccount(actor)
          .beforeAttachmentProtectionChange = (reference) async {
        try {
          final binding = await authority.capture(reference);
          await cache.upgradeLegacyPackets(binding);
        } on NoteSecurityFailure catch (e) {
          // A password reset cannot recover retired private keys. Keep those
          // ciphertexts blocked; normal unlocked administration must migrate.
          if (e.code != NoteSecurityFailureCode.locked &&
              e.code != NoteSecurityFailureCode.staleRevision) {
            rethrow;
          }
        }
      };
      final uri = security.baseUri;
      final local =
          kDebugMode &&
          uri?.scheme == 'http' &&
          uri?.host == '127.0.0.1' &&
          uri?.port == 8796;
      final uploader = uri == null
          ? null
          : HttpAttachmentUpload(
              baseUri: uri,
              tokenProvider: security.tokenProvider,
              grantHeader: security.attachmentGrant,
              requireAccess: authority.requireAccess,
              client: security.client,
              allowLocalDev: local,
              onProgress: progress.add,
            );
      final reader = uri == null
          ? null
          : HttpAttachmentReader(
              baseUri: uri,
              tokenProvider: security.tokenProvider,
              grantHeader: security.attachmentGrant,
              requireAccess: authority.requireAccess,
              client: security.client,
              allowLocalDev: local,
            );
      return AttachmentApplicationService(
        notes: notes,
        drafts: cache,
        captureBinding: authority.capture,
        requireAccess: authority.requireAccess,
        upload:
            uploader?.upload ??
            (_, _, _) async => throw const NoteSecurityFailure(
              NoteSecurityFailureCode.unavailable,
            ),
        now: () => DateTime.now().toUtc(),
        requestSync: requestSync,
        remoteRead: reader?.read,
        remoteCancel: uploader?.cancel,
        isAssociated: uploader?.linked,
        progress: progress.stream,
      );
    });
  }
}
