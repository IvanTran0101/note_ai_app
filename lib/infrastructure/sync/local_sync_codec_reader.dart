/// Strict field reading for the M2 local sync state codec.
///
/// A stored document is written only by the M2 codecs, so its shape is known
/// exactly: every declared field must be present, a nullable field is stored as
/// an explicit null, and an unknown field is an error rather than something to
/// ignore. This is deliberately stricter than the M1.3 wire mapper, which
/// tolerates additive fields in server payloads -- a local document that does
/// not match the frozen schema is corrupt, and dropping part of it silently
/// would lose local note state.
///
/// Messages name the field and the rule that failed, never the stored value, so
/// no note content or cursor value can reach a log through a decode failure.
library;

import 'local_sync_codec_exception.dart';

/// One object of the local sync document under strict schema validation.
final class SyncCodecObject {
  SyncCodecObject._(this._values, this.path);

  /// Validates [data] as an object carrying exactly the [allowedFields].
  ///
  /// [path] locates the object in the document (`notes[2]`) and is used only to
  /// build failure paths.
  factory SyncCodecObject.from(
    Object? data, {
    required String path,
    required Set<String> allowedFields,
    Set<String> optionalFields = const <String>{},
  }) {
    if (data is! Map) {
      throw LocalSyncCodecException('must be an object.', path: path);
    }
    final Map<String, Object?> values = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in data.entries) {
      final Object? key = entry.key;
      if (key is! String) {
        throw LocalSyncCodecException(
          'must use string field names.',
          path: path,
        );
      }
      values[key] = entry.value;
    }
    for (final String key in values.keys) {
      if (!allowedFields.contains(key)) {
        throw LocalSyncCodecException(
          'must not contain a field outside the M2 local sync schema.',
          path: path,
        );
      }
    }
    for (final String field in allowedFields) {
      if (!optionalFields.contains(field) && !values.containsKey(field)) {
        throw LocalSyncCodecException(
          'must contain the field "$field".',
          path: path,
        );
      }
    }
    return SyncCodecObject._(values, path);
  }

  final Map<String, Object?> _values;

  /// Where this object sits in the document, for example `notes[2]`.
  final String path;

  /// The path of [field] inside the document, for example `notes[2].title`.
  String fieldPath(String field) => path.isEmpty ? field : '$path.$field';

  /// Reports a failure at [field] of this object with a value-free [message].
  Never fail(String field, String message) {
    throw LocalSyncCodecException(message, path: fieldPath(field));
  }

  /// Returns the raw value of [field], whose presence is already guaranteed.
  ///
  /// Used for a scalar with dedicated mapping rules, such as the opaque cursor,
  /// where the dedicated codec owns type validation.
  Object? rawValue(String field) => _values[field];

  /// Whether [field] was present in the input object.
  bool contains(String field) => _values.containsKey(field);

  /// Reads a required string field.
  String requireString(String field) {
    final Object? value = _values[field];
    if (value is! String) {
      fail(field, 'must be a string.');
    }
    return value;
  }

  /// Reads a required string field that is not blank.
  String requireNonBlankString(String field) {
    final String value = requireString(field);
    if (value.trim().isEmpty) {
      fail(field, 'must not be blank.');
    }
    return value;
  }

  /// Reads an optional string field stored explicitly as null when absent.
  String? requireNullableString(String field) {
    final Object? value = _values[field];
    if (value == null) return null;
    if (value is! String) {
      fail(field, 'must be a string or null.');
    }
    return value;
  }

  /// Reads a required integer field.
  int requireInt(String field) {
    final Object? value = _values[field];
    if (value is! int) {
      fail(field, 'must be an integer.');
    }
    return value;
  }

  /// Reads a required integer field that is zero or greater.
  int requireNonNegativeInt(String field) {
    final int value = requireInt(field);
    if (value < 0) {
      fail(field, 'must not be negative.');
    }
    return value;
  }

  /// Reads a required integer field that is greater than zero.
  int requirePositiveInt(String field) {
    final int value = requireInt(field);
    if (value <= 0) {
      fail(field, 'must be positive.');
    }
    return value;
  }

  /// Reads a required boolean field.
  bool requireBool(String field) {
    final Object? value = _values[field];
    if (value is! bool) {
      fail(field, 'must be a boolean.');
    }
    return value;
  }

  /// Reads a required ISO-8601 timestamp field.
  DateTime requireTimestamp(String field) {
    final Object? value = _values[field];
    if (value is! String) {
      fail(field, 'must be an ISO-8601 timestamp string.');
    }
    final DateTime? timestamp = value.isEmpty ? null : DateTime.tryParse(value);
    if (timestamp == null) {
      fail(field, 'must be a valid ISO-8601 timestamp.');
    }
    return timestamp;
  }

  /// Reads an optional ISO-8601 timestamp field, stored as an explicit null.
  DateTime? requireNullableTimestamp(String field) {
    if (_values[field] == null) {
      return null;
    }
    return requireTimestamp(field);
  }

  /// Reads a required enum field by exact [allowedValues] name.
  T requireEnum<T extends Enum>(String field, List<T> allowedValues) {
    final Object? value = _values[field];
    if (value is! String) {
      fail(field, 'must be a string naming a ${T.toString()} value.');
    }
    for (final T candidate in allowedValues) {
      if (candidate.name == value) {
        return candidate;
      }
    }
    fail(field, 'must name a declared ${T.toString()} value.');
  }

  /// Reads an optional enum field, stored as an explicit null.
  T? requireNullableEnum<T extends Enum>(String field, List<T> allowedValues) {
    if (_values[field] == null) {
      return null;
    }
    return requireEnum(field, allowedValues);
  }

  /// Reads a required nested object with exactly [allowedFields].
  SyncCodecObject requireObject(
    String field,
    Set<String> allowedFields, {
    Set<String> optionalFields = const <String>{},
  }) {
    return SyncCodecObject.from(
      _values[field],
      path: fieldPath(field),
      allowedFields: allowedFields,
      optionalFields: optionalFields,
    );
  }

  /// Reads an optional nested object, stored as an explicit null.
  SyncCodecObject? requireNullableObject(
    String field,
    Set<String> allowedFields, {
    Set<String> optionalFields = const <String>{},
  }) {
    if (_values[field] == null) {
      return null;
    }
    return requireObject(field, allowedFields, optionalFields: optionalFields);
  }

  /// Reads a required array field, rejecting a non-array value.
  List<Object?> _requireList(String field) {
    final Object? value = _values[field];
    if (value is! List) {
      fail(field, 'must be an array.');
    }
    return List<Object?>.of(value);
  }

  /// Reads a required array of objects, each with exactly [allowedFields].
  List<SyncCodecObject> requireObjectList(
    String field,
    Set<String> allowedFields,
  ) {
    final String basePath = fieldPath(field);
    final List<Object?> entries = _requireList(field);
    return <SyncCodecObject>[
      for (int index = 0; index < entries.length; index++)
        SyncCodecObject.from(
          entries[index],
          path: '$basePath[$index]',
          allowedFields: allowedFields,
        ),
    ];
  }
}

/// Builds a validated model from decoded fields.
///
/// A model constructor rejects an invariant the codec did not check itself;
/// [ArgumentError] is translated into a typed failure so a caller sees one
/// exception type, and the model's own message is dropped rather than nested.
T buildCodecModel<T>(T Function() build, {required String path}) {
  try {
    return build();
  } on ArgumentError {
    throw LocalSyncCodecException(
      'does not satisfy the model invariants.',
      path: path,
    );
  }
}
