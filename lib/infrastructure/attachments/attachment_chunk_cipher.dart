import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../application/attachments/attachment_binding.dart';
import '../../application/attachments/attachment_policy.dart';
import '../../domain/notes/note_protection.dart';
import '../security/note_crypto.dart';

/// Reuses M05 primitives and its key authority. There is deliberately no
/// device-key fallback for a protected note. SecretKey remains Infrastructure.
final class AttachmentChunkCipher {
  AttachmentChunkCipher({
    required this.requireAccess,
    required this.resolveKey,
    NoteCrypto? crypto,
  }) : _crypto = crypto ?? NoteCrypto();
  final void Function(AttachmentBinding binding, NoteOperation operation)
  requireAccess;
  final Future<SecretKey> Function(AttachmentBinding binding) resolveKey;
  final NoteCrypto _crypto;

  String _aad(AttachmentBinding binding, String cacheId, int chunk) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(cacheId) || chunk < -1) {
      throw ArgumentError('Invalid binary cache identity.');
    }
    return jsonEncode([
      'NoteFlow/M03/chunk/v1',
      binding.actorId,
      binding.note.ownerId,
      binding.note.noteId,
      binding.protection.enabled,
      binding.protection.revision,
      binding.accessRevision,
      cacheId,
      chunk,
    ]);
  }

  Future<Map<String, Object?>> seal(
    AttachmentBinding binding,
    String cacheId,
    int chunk,
    List<int> plaintext,
  ) async {
    if (plaintext.isEmpty || plaintext.length > AttachmentPolicy.chunkBytes) {
      throw ArgumentError('Invalid attachment chunk size.');
    }
    requireAccess(binding, NoteOperation.attachmentWrite);
    final key = await resolveKey(binding);
    requireAccess(binding, NoteOperation.attachmentWrite);
    final packet = await _crypto.encrypt(
      plaintext,
      key,
      _aad(binding, cacheId, chunk),
    );
    requireAccess(binding, NoteOperation.attachmentWrite);
    return packet;
  }

  Future<Uint8List> open(
    AttachmentBinding binding,
    String cacheId,
    int chunk,
    Object packet, {
    NoteOperation operation = NoteOperation.attachmentRead,
  }) async {
    if (operation != NoteOperation.attachmentRead &&
        operation != NoteOperation.attachmentWrite) {
      throw ArgumentError(
        'A binary reader requires its explicit operation scope.',
      );
    }
    requireAccess(binding, operation);
    final key = await resolveKey(binding);
    requireAccess(binding, operation);
    final plaintext = await _crypto.decrypt(
      packet,
      key,
      _aad(binding, cacheId, chunk),
    );
    try {
      requireAccess(binding, operation);
      if (plaintext.isEmpty || plaintext.length > AttachmentPolicy.chunkBytes) {
        throw const FormatException('Invalid attachment chunk.');
      }
      return Uint8List.fromList(plaintext);
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }
}
