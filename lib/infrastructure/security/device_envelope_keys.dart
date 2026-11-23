import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../application/notes/note_access.dart';
import 'note_crypto.dart';

/// Unique key IDs make simultaneous first writes safe across tabs/processes.
/// Existing ciphertext never causes a missing platform key to be regenerated.
final class DeviceEnvelopeKeys {
  DeviceEnvelopeKeys(this.namespace, this.crypto);
  final String namespace;
  final NoteCrypto crypto;
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false, migrateWithBackup: false),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  Future<({String id, SecretKey key})> create() async {
    try {
      final id = base64UrlEncode(crypto.randomBytes(24)).replaceAll('=', '');
      final bytes = crypto.randomBytes(32);
      try {
        await _storage.write(
          key: 'm05.$namespace.$id',
          value: base64Encode(bytes),
        );
        return (
          id: id,
          key: SecretKeyData(List<int>.of(bytes), overwriteWhenDestroyed: true),
        );
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    } on Object {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.storage);
    }
  }

  Future<SecretKey> read(String id) async {
    try {
      if (!RegExp(r'^[A-Za-z0-9_-]{32}$').hasMatch(id)) {
        throw const FormatException();
      }
      final value = await _storage.read(key: 'm05.$namespace.$id');
      if (value == null) throw const FormatException();
      final bytes = base64Decode(value);
      try {
        if (bytes.length != 32) throw const FormatException();
        return SecretKeyData(List<int>.of(bytes), overwriteWhenDestroyed: true);
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    } on Object {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.storage);
    }
  }
}
