import 'dart:convert';

abstract final class AttachmentStoreCodec {
  static Map<String, Object?> index(String input) {
    if (input.length > 1024 * 1024) {
      throw const FormatException('Binary cache index is too large.');
    }
    try {
      final result = Map<String, Object?>.from(jsonDecode(input) as Map);
      for (final entry in result.entries) {
        final record = Map<String, Object?>.from(entry.value as Map);
        if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.key) ||
            record.length != 4 ||
            record['scope'] is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(record['scope'] as String) ||
            record['sizeBytes'] is! int ||
            (record['sizeBytes'] as int) <= 0 ||
            (record['sizeBytes'] as int) > 50 * 1024 * 1024 ||
            record['chunkCount'] is! int ||
            (record['chunkCount'] as int) < 0 ||
            (record['chunkCount'] as int) > 200 ||
            !{
              'staging',
              'queued',
              'linked',
              'cancelling',
              'remoteCancelling',
              'remote',
            }.contains(record['phase'])) {
          throw const FormatException();
        }
      }
      return result;
    } on Object {
      throw const FormatException('Invalid encrypted cache index.');
    }
  }

  static Map<String, Object?> packet(String input) {
    if (input.length > 512 * 1024) {
      throw const FormatException('Encrypted chunk is too large.');
    }
    try {
      final value = Map<String, Object?>.from(jsonDecode(input) as Map);
      if (value.length != 3 ||
          value['nonce'] is! String ||
          value['ciphertext'] is! String ||
          value['mac'] is! String) {
        throw const FormatException();
      }
      return value;
    } on Object {
      throw const FormatException('Invalid encrypted cache packet.');
    }
  }
}
