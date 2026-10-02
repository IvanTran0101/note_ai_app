import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../../application/notes/note_access.dart';

/// Vetted primitives; fresh nonces and AAD bind every ciphertext to its owner.
final class NoteCrypto {
  final AesGcm _cipher = AesGcm.with256bits();
  final Pbkdf2 _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 600000,
    bits: 256,
  );
  final Random _random = Random.secure();
  List<int> randomBytes(int count) =>
      List<int>.generate(count, (_) => _random.nextInt(256));
  Future<SecretKey> newKey() async =>
      SecretKeyData(randomBytes(32), overwriteWhenDestroyed: true);

  Future<SecretKey> passwordKey(String password, List<int> salt) async {
    final bytes = utf8.encode(password);
    if (password.length < 8 || bytes.length > 512 || salt.length != 16) {
      bytes.fillRange(0, bytes.length, 0);
      throw const NoteSecurityFailure(NoteSecurityFailureCode.invalidInput);
    }
    final input = SecretKeyData(
      List<int>.of(bytes),
      overwriteWhenDestroyed: true,
    );
    try {
      return await _kdf.deriveKey(secretKey: input, nonce: salt);
    } finally {
      input.destroy();
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  /// Separate salt from the wrapping KEK: publishing this hash cannot unwrap keys.
  Future<String> passwordVerifier(String password) async {
    final salt = randomBytes(16);
    final key = await passwordKey(password, salt);
    final bytes = List<int>.of(await key.extractBytes());
    try {
      return 'pbkdf2-sha256-v1\$${base64Encode(salt)}\$${base64Encode(bytes)}';
    } finally {
      key.destroy();
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<Map<String, Object?>> encrypt(
    List<int> data,
    SecretKey key,
    String aad,
  ) async {
    final box = await _cipher.encrypt(
      data,
      secretKey: key,
      nonce: randomBytes(12),
      aad: utf8.encode(aad),
    );
    return {
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
  }

  Future<List<int>> decrypt(Object? packet, SecretKey key, String aad) async {
    try {
      final p = Map<String, Object?>.from(packet as Map);
      if (p.length != 3) throw const FormatException();
      final nonce = base64Decode(p['nonce'] as String);
      final mac = base64Decode(p['mac'] as String);
      if (nonce.length != 12 || mac.length != 16) throw const FormatException();
      return await _cipher.decrypt(
        SecretBox(
          base64Decode(p['ciphertext'] as String),
          nonce: nonce,
          mac: Mac(mac),
        ),
        secretKey: key,
        aad: utf8.encode(aad),
      );
    } on Object {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.storage);
    }
  }

  Future<Map<String, Object?>> encryptJson(
    Object data,
    SecretKey key,
    String aad,
  ) async {
    final bytes = utf8.encode(jsonEncode(data));
    try {
      return await encrypt(bytes, key, aad);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<Map<String, Object?>> decryptJson(
    Object? data,
    SecretKey key,
    String aad,
  ) async {
    final bytes = await decrypt(data, key, aad);
    try {
      return Map<String, Object?>.from(jsonDecode(utf8.decode(bytes)) as Map);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }
}
