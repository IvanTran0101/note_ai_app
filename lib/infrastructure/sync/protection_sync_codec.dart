import 'dart:convert';

import '../../application/sync/protection_sync_change.dart';
import '../../domain/notes/note_protection.dart';
import 'local_sync_codec_reader.dart';

abstract final class ProtectionSyncCodec {
  static Map<String, Object?> encode(ProtectionSyncChange c) {
    _validateVerifier(c.verifier);
    return {
      'before': {'enabled': c.before.enabled, 'revision': c.before.revision},
      'after': {'enabled': c.after.enabled, 'revision': c.after.revision},
      'verifier': c.verifier,
    };
  }

  static void _validateVerifier(String? value) {
    if (value == null) return;
    if (!RegExp(r'^pbkdf2-sha256-v1\$[A-Za-z0-9+/]{22}==\$[A-Za-z0-9+/]{43}=$')
        .hasMatch(value)) {
      throw const FormatException('Invalid password representation.');
    }
    final parts = value.split(r'$');
    for (final part in parts.skip(1)) {
      if (base64Encode(base64Decode(part)) != part) {
        throw const FormatException('Invalid password representation.');
      }
    }
  }

  static ProtectionSyncChange decode(Object? value) {
    final r = SyncCodecObject.from(
      value,
      path: 'protectionChange',
      allowedFields: {'before', 'after', 'verifier'},
    );
    NoteProtection protection(String field) {
      final p = r.requireNullableObject(field, {'enabled', 'revision'});
      if (p == null) r.fail(field, 'is required.');
      return NoteProtection(
        enabled: p.requireBool('enabled'),
        revision: p.requireNonNegativeInt('revision'),
      );
    }

    final verifier = r.rawValue('verifier') == null
        ? null
        : r.requireString('verifier');
    try {
      _validateVerifier(verifier);
    } on FormatException {
      r.fail('verifier', 'must be a supported salted representation.');
    }
    return buildCodecModel(
      () => ProtectionSyncChange(
        before: protection('before'),
        after: protection('after'),
        verifier: verifier,
      ),
      path: r.path,
    );
  }
}
