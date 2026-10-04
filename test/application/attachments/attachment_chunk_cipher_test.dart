import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/attachments/attachment_binding.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/attachments/attachment_chunk_cipher.dart';
import 'package:note_ai_app/infrastructure/security/note_crypto.dart';

AttachmentBinding binding({
  String actor = 'owner',
  String note = 'note',
  int epoch = 1,
}) => AttachmentBinding(
  actorId: actor,
  note: NoteIdentity('owner', note),
  protection: NoteProtection(enabled: true, revision: epoch),
  accessRevision: 1,
  sessionGeneration: 1,
  contentRevision: 2,
);

void main() {
  test(
    'M05 AES-GCM ciphertext is bound to actor, canonical note, epoch and chunk',
    () async {
      final key = await NoteCrypto().newKey();
      addTearDown(key.destroy);
      final cipher = AttachmentChunkCipher(
        requireAccess: (_, _) {},
        resolveKey: (_) async => key,
      );
      final packet = await cipher.seal(binding(), 'a' * 64, 0, [10, 20, 30]);
      expect(packet.keys.toSet(), {'nonce', 'ciphertext', 'mac'});
      expect(await cipher.open(binding(), 'a' * 64, 0, packet), [10, 20, 30]);
      for (final other in [
        binding(actor: 'recipient'),
        binding(note: 'other'),
        binding(epoch: 2),
      ]) {
        await expectLater(
          cipher.open(other, 'a' * 64, 0, packet),
          throwsA(isA<Exception>()),
        );
      }
      await expectLater(
        cipher.open(binding(), 'a' * 64, 1, packet),
        throwsA(isA<Exception>()),
      );
    },
  );
  test('explicit attachment scope required; key/session changes mid-await fail closed', () async {
    final key = await NoteCrypto().newKey();
    addTearDown(key.destroy);
    var permitted = true;
    final requested = <NoteOperation>[];
    final cipher = AttachmentChunkCipher(
      requireAccess: (_, operation) {
        requested.add(operation);
        if (!permitted) throw StateError('locked');
      },
      resolveKey: (_) async {
        permitted = false;
        return key;
      },
    );
    await expectLater(
      cipher.seal(binding(), 'b' * 64, 0, [1]),
      throwsStateError,
    );
    expect(requested, [
      NoteOperation.attachmentWrite,
      NoteOperation.attachmentWrite,
    ]);
    await expectLater(
      cipher.open(binding(), 'b' * 64, 0, {}, operation: NoteOperation.read),
      throwsArgumentError,
    );
  });
  test(
    'nonce is fresh even for identical data; source buffers are not mutated',
    () async {
      final key = await NoteCrypto().newKey();
      addTearDown(key.destroy);
      final cipher = AttachmentChunkCipher(
        requireAccess: (_, _) {},
        resolveKey: (_) async => key,
      );
      final bytes = [1, 2, 3];
      final first = await cipher.seal(binding(), 'c' * 64, 0, bytes);
      final second = await cipher.seal(binding(), 'c' * 64, 0, bytes);
      expect(first['nonce'], isNot(second['nonce']));
      expect(bytes, [1, 2, 3]);
    },
  );
}
