/// Persistence representation of a [Note].
///
/// This DTO is deliberately independent from a database driver and from
/// Flutter. It defines the serialized shape used by infrastructure while the
/// domain aggregate remains unaware of persistence concerns.
final class NoteRecord {
  const NoteRecord({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Creates a record from a strict JSON-compatible map.
  ///
  /// All six fields are required. Identity and text fields must be strings,
  /// timestamp fields must be valid ISO-8601 strings, and unknown fields are
  /// rejected so schema drift cannot be silently persisted.
  factory NoteRecord.fromJson(Map<String, Object?> json) {
    _rejectUnknownFields(json);

    return NoteRecord(
      id: _readString(json, 'id'),
      ownerId: _readString(json, 'ownerId'),
      title: _readString(json, 'title'),
      content: _readString(json, 'content'),
      createdAt: _readTimestamp(json, 'createdAt'),
      updatedAt: _readTimestamp(json, 'updatedAt'),
    );
  }

  final String id;
  final String ownerId;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Converts this record to a JSON-compatible map.
  ///
  /// [DateTime.toIso8601String] is used for both persisted timestamps.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'ownerId': ownerId,
      'title': title,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static const Set<String> _fieldNames = <String>{
    'id',
    'ownerId',
    'title',
    'content',
    'createdAt',
    'updatedAt',
  };

  static void _rejectUnknownFields(Map<String, Object?> json) {
    final List<String> unknownFields = json.keys
        .where((String key) => !_fieldNames.contains(key))
        .toList(growable: false);
    if (unknownFields.isNotEmpty) {
      throw FormatException(
        'Unknown NoteRecord field(s): ${unknownFields.join(', ')}.',
      );
    }
  }

  static String _readString(Map<String, Object?> json, String fieldName) {
    if (!json.containsKey(fieldName)) {
      throw FormatException('Missing required NoteRecord field "$fieldName".');
    }

    final Object? value = json[fieldName];
    if (value is! String) {
      throw FormatException('NoteRecord field "$fieldName" must be a string.');
    }

    return value;
  }

  static DateTime _readTimestamp(Map<String, Object?> json, String fieldName) {
    final String rawValue = _readString(json, fieldName);
    if (rawValue.isEmpty) {
      throw FormatException(
        'NoteRecord field "$fieldName" must be a valid ISO-8601 timestamp.',
      );
    }

    final DateTime? timestamp = DateTime.tryParse(rawValue);
    if (timestamp == null) {
      throw FormatException(
        'NoteRecord field "$fieldName" must be a valid ISO-8601 timestamp.',
      );
    }

    return timestamp;
  }
}
