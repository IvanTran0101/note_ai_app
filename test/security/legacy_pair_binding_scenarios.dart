import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';
import 'package:note_ai_app/infrastructure/security/note_bundle_projection.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_state_codec.dart';

import 'security_fixtures.dart';

/// Fixtures use the old bare-id AAD, including a legacy reserved-prefix id.
void registerLegacyPairBindingScenarios() {
  for (final quarantined in [false, true]) {
    test(
      'old v3 reserved-id ciphertext survives pair migration, quarantine=$quarantined',
      () async {
        final actor =
            'm06-legacy-$quarantined-${DateTime.now().microsecondsSinceEpoch}';
        const id = 'nf-note:legacy-owned-id';
        final p = NoteProtection(enabled: true, revision: 1);
        final note = securityNote(
          actor,
          id: id,
          protection: quarantined ? const NoteProtection.unprotected() : p,
        );
        final state = LocalSyncState(accountUserId: actor, notes: [note]);
        final backing = MemoryCiphertextStore();
        final setup = EncryptedSyncStore(actor, backing);
        final crypto = setup.codec.crypto;
        final device = await setup.codec.deviceKeys.create();
        final data = LocalSyncStateCodec.encode(state);
        final reference = note.referenceFor(actor);
        final bundle = NoteBundleProjection.bundle(data, reference);
        NoteBundleProjection.redact(data, reference);
        final accountAad = 'NoteFlow/M05/v3/${setup.codec.namespace.hash}';
        final protected = <String, Object?>{};
        final quarantine = <String, Object?>{};
        if (quarantined) {
          quarantine[id] = await crypto.encryptJson(
            bundle,
            device.key,
            '$accountAad/quarantine/${jsonEncode(id)}',
          );
        } else {
          final key = await crypto.newKey();
          final salt = crypto.randomBytes(16);
          final kek = await crypto.passwordKey(securityPassword, salt);
          final bytes = List<int>.of(await key.extractBytes());
          try {
            final aad = '$accountAad/note/${jsonEncode(id)}/1';
            protected[id] = {
              'epoch': 1,
              'salt': base64Encode(salt),
              'wrapped': await crypto.encrypt(bytes, kek, '$aad/key'),
              'box': await crypto.encryptJson(bundle, key, aad),
              'pendingIds': <String>[],
            };
          } finally {
            bytes.fillRange(0, bytes.length, 0);
            key.destroy();
            kek.destroy();
          }
        }
        try {
          backing.encoded = jsonEncode({
            'schemaVersion': 3,
            'algorithm': 'AES-256-GCM',
            'keyId': device.id,
            'packet': await crypto.encryptJson(
              {
                'state': data,
                'protected': protected,
                'quarantine': quarantine,
                'retained': <String, Object?>{},
              },
              device.key,
              accountAad,
            ),
          });
        } finally {
          device.key.destroy();
          setup.dispose();
        }
        final store = EncryptedSyncStore(actor, backing);
        addTearDown(store.dispose);
        expect((await store.read()).notes.single.contentAvailable, false);
        await store.unlock(
          reference,
          securityPassword,
          p,
          verifiedOnline: quarantined,
        );
        expect((await store.read()).notes.single.id, id);
        expect((await store.read()).notes.single.content, privateBody);
        store.dispose();
        final reopened = EncryptedSyncStore(actor, backing);
        addTearDown(reopened.dispose);
        await reopened.unlock(reference, securityPassword, p);
        expect((await reopened.read()).notes.single.content, privateBody);
        expect(backing.encoded, isNot(contains(privateBody)));
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}
