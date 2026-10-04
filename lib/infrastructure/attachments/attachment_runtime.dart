import 'dart:math';

import '../../application/attachments/attachment_application.dart';
import '../../domain/notes/note_repository.dart';
import '../../application/notes/note_access.dart';
import '../security/encrypted_sync_store.dart';
import '../security/note_security_runtime.dart';
import 'attachment_security_adapter.dart';
import 'attachment_chunk_cipher.dart';
import 'attachment_store.dart';
import 'encrypted_attachment_cache.dart';

/// Account-scoped binary cache; uses the canonical Note writer and M05 key.
/// Cloud upload is deliberately unavailable until verified association exists.
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
      return AttachmentApplicationService(
        notes: notes,
        drafts: cache,
        captureBinding: authority.capture,
        requireAccess: authority.requireAccess,
        upload: (_, _, _) async => throw const NoteSecurityFailure(
          NoteSecurityFailureCode.unavailable,
        ),
        now: () => DateTime.now().toUtc(),
        requestSync: requestSync,
      );
    });
  }
}
