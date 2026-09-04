/// Platform-neutral contract for the persisted AI model-readiness store.
///
/// [AiConfiguration] (`ai_configuration.dart`) is runtime policy that lives
/// for the process lifetime. This library models the opposite concern: the
/// durable readiness state of the on-device model that survives restarts.
///
/// The library stays free of `dart:io`, `package:path_provider`, and the
/// `local_llm_bridge` package so it compiles on the Web; native persistence
/// lives behind a conditional import in `ai_configuration_store.dart`, and on
/// the Web the stub's methods throw [UnsupportedError] — Web never fakes
/// persisted model readiness.
///
/// A stored [AiReadinessSnapshot] is advisory bookkeeping only: the model
/// manager still selects the current descriptor, locates the file, and
/// verifies integrity before serving it.
library;

/// Resolves the application-private support directory as an absolute path
/// string. A plain function so the contract stays free of `dart:io` and
/// platform plugins, and tests inject a temporary directory without a channel.
typedef ApplicationSupportPathResolver = Future<String> Function();

/// Lifecycle status of the on-device model recorded by [AiReadinessSnapshot].
enum ModelReadinessStatus {
  /// The model artifact is being downloaded and verified on this device.
  preparing,

  /// The model artifact is downloaded, verified, and usable on this device.
  ready,

  /// The last provisioning attempt failed; [AiReadinessSnapshot.lastError]
  /// carries the failure detail when one was recorded.
  failed,
}

/// Immutable persisted snapshot of the readiness of one on-device model.
///
/// Every field is required except [localPath] and [lastError], which are
/// nullable. The value is immutable: strings are trimmed, [supportedAbis] is
/// stored as an unmodifiable, order-sensitive copy, and value equality covers
/// all fields.
final class AiReadinessSnapshot {
  /// Creates a validated snapshot. Strings are trimmed; required strings and
  /// [supportedAbis] must be non-blank, and a blank [localPath]/[lastError]
  /// normalizes to null.
  factory AiReadinessSnapshot({
    required String modelId,
    required String modelVersion,
    required String modelSha256,
    String? localPath,
    required String platform,
    required String osVersion,
    required bool isPhysicalDevice,
    required List<String> supportedAbis,
    required ModelReadinessStatus status,
    String? lastError,
    required DateTime updatedAt,
  }) {
    return AiReadinessSnapshot._(
      modelId: _requireNonBlank(modelId, 'modelId'),
      modelVersion: _requireNonBlank(modelVersion, 'modelVersion'),
      modelSha256: _requireNonBlank(modelSha256, 'modelSha256'),
      localPath: _normalizeNullableString(localPath),
      platform: _requireNonBlank(platform, 'platform'),
      osVersion: _requireNonBlank(osVersion, 'osVersion'),
      isPhysicalDevice: isPhysicalDevice,
      supportedAbis: _copySupportedAbis(supportedAbis),
      status: status,
      lastError: _normalizeNullableString(lastError),
      updatedAt: updatedAt,
    );
  }

  /// Creates a snapshot from a strict JSON-compatible map. Unknown fields are
  /// rejected; optional fields may be absent or null; malformed data raises
  /// [FormatException].
  factory AiReadinessSnapshot.fromJson(Map<String, Object?> json) {
    _rejectUnknownFields(json);
    return AiReadinessSnapshot._(
      modelId: _readNonBlankString(json, 'modelId'),
      modelVersion: _readNonBlankString(json, 'modelVersion'),
      modelSha256: _readNonBlankString(json, 'modelSha256'),
      localPath: _readNullableString(json, 'localPath'),
      platform: _readNonBlankString(json, 'platform'),
      osVersion: _readNonBlankString(json, 'osVersion'),
      isPhysicalDevice: _readRequiredBool(json, 'isPhysicalDevice'),
      supportedAbis: _readSupportedAbis(json),
      status: _readStatus(json),
      lastError: _readNullableString(json, 'lastError'),
      updatedAt: _readTimestamp(json, 'updatedAt'),
    );
  }

  AiReadinessSnapshot._({
    required this.modelId,
    required this.modelVersion,
    required this.modelSha256,
    required this.localPath,
    required this.platform,
    required this.osVersion,
    required this.isPhysicalDevice,
    required this.supportedAbis,
    required this.status,
    required this.lastError,
    required this.updatedAt,
  });

  /// Catalog identifier of the model this record describes.
  final String modelId;

  /// Version of the model artifact this record describes.
  final String modelVersion;

  /// SHA-256 of the verified artifact, hex-encoded.
  final String modelSha256;

  /// Advisory model-file path recorded at provisioning time, or null. Never
  /// trusted by the model manager, which re-selects and re-verifies on demand.
  final String? localPath;

  /// Runtime platform of the device that produced this record (e.g. `ios`).
  final String platform;

  /// Operating system version of that device (e.g. `18.0`).
  final String osVersion;

  /// True when this record came from physical hardware, not a simulator.
  final bool isPhysicalDevice;

  /// Native ABIs of that device in preference order, unmodifiable. Together
  /// with [platform], [osVersion], and [isPhysicalDevice] this forms the
  /// capability fingerprint deciding whether the record is valid for the
  /// current device. Volatile memory/storage thresholds are intentionally
  /// absent because midterm threshold policy is skipped.
  final List<String> supportedAbis;

  /// Current readiness status of the model on the recorded device.
  final ModelReadinessStatus status;

  /// Failure detail from the last provisioning attempt, when recorded.
  final String? lastError;

  /// When this record was last updated (ISO-8601 on the wire).
  final DateTime updatedAt;

  /// Converts this snapshot to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'modelId': modelId,
      'modelVersion': modelVersion,
      'modelSha256': modelSha256,
      'localPath': localPath,
      'platform': platform,
      'osVersion': osVersion,
      'isPhysicalDevice': isPhysicalDevice,
      'supportedAbis': supportedAbis,
      'status': status.name,
      'lastError': lastError,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static const Set<String> _fieldNames = <String>{
    'modelId',
    'modelVersion',
    'modelSha256',
    'localPath',
    'platform',
    'osVersion',
    'isPhysicalDevice',
    'supportedAbis',
    'status',
    'lastError',
    'updatedAt',
  };

  static void _rejectUnknownFields(Map<String, Object?> json) {
    final List<String> unknownFields = json.keys
        .where((String key) => !_fieldNames.contains(key))
        .toList(growable: false);
    if (unknownFields.isNotEmpty) {
      throw FormatException(
        'Unknown AiReadinessSnapshot field(s): ${unknownFields.join(', ')}.',
      );
    }
  }

  static String _requireNonBlank(String raw, String fieldName) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(raw, fieldName, 'must not be blank');
    }
    return trimmed;
  }

  static String? _normalizeNullableString(String? raw) {
    final String? trimmed = raw?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static List<String> _copySupportedAbis(List<String> supportedAbis) {
    if (supportedAbis.isEmpty) {
      throw ArgumentError.value(
        supportedAbis,
        'supportedAbis',
        'must not be empty',
      );
    }
    return List<String>.unmodifiable(<String>[
      for (final String abi in supportedAbis) _requireNonBlank(abi, 'abi'),
    ]);
  }

  static String _readNonBlankString(Map<String, Object?> json, String field) {
    final Object? value = json[field];
    if (value is! String) {
      throw FormatException(
        'AiReadinessSnapshot field "$field" must be a string.',
      );
    }
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw FormatException(
        'AiReadinessSnapshot field "$field" must not be blank.',
      );
    }
    return trimmed;
  }

  static String? _readNullableString(Map<String, Object?> json, String field) {
    final Object? value = json[field];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw FormatException(
        'AiReadinessSnapshot field "$field" must be a string or null.',
      );
    }
    return _normalizeNullableString(value);
  }

  static bool _readRequiredBool(Map<String, Object?> json, String field) {
    final Object? value = json[field];
    if (value is! bool) {
      throw FormatException(
        'AiReadinessSnapshot field "$field" must be a boolean.',
      );
    }
    return value;
  }

  static List<String> _readSupportedAbis(Map<String, Object?> json) {
    final Object? value = json['supportedAbis'];
    if (value is! List) {
      throw const FormatException(
        'AiReadinessSnapshot field "supportedAbis" must be an array of '
        'non-blank ABI strings.',
      );
    }
    if (value.isEmpty) {
      throw const FormatException(
        'AiReadinessSnapshot field "supportedAbis" must not be empty.',
      );
    }
    final List<String> normalized = <String>[];
    for (var index = 0; index < value.length; index++) {
      final Object? abi = value[index];
      if (abi is! String || abi.trim().isEmpty) {
        throw FormatException(
          'AiReadinessSnapshot field "supportedAbis" must contain only '
          'non-blank strings (index $index).',
        );
      }
      normalized.add(abi.trim());
    }
    return List<String>.unmodifiable(normalized);
  }

  static ModelReadinessStatus _readStatus(Map<String, Object?> json) {
    final Object? value = json['status'];
    if (value is! String) {
      throw const FormatException(
        'AiReadinessSnapshot field "status" must be a string.',
      );
    }
    final ModelReadinessStatus? status = ModelReadinessStatus.values
        .asNameMap()[value];
    if (status == null) {
      throw FormatException(
        'AiReadinessSnapshot field "status" must be one of '
        '${ModelReadinessStatus.values.map((s) => s.name).join(', ')}.',
      );
    }
    return status;
  }

  static DateTime _readTimestamp(Map<String, Object?> json, String field) {
    final Object? value = json[field];
    if (value is! String) {
      throw FormatException(
        'AiReadinessSnapshot field "$field" must be a string.',
      );
    }
    final DateTime? timestamp = DateTime.tryParse(value);
    if (timestamp == null) {
      throw FormatException(
        'AiReadinessSnapshot field "$field" must be a valid ISO-8601 '
        'timestamp.',
      );
    }
    return timestamp;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is AiReadinessSnapshot &&
        other.modelId == modelId &&
        other.modelVersion == modelVersion &&
        other.modelSha256 == modelSha256 &&
        other.localPath == localPath &&
        other.platform == platform &&
        other.osVersion == osVersion &&
        other.isPhysicalDevice == isPhysicalDevice &&
        _sameAbis(other.supportedAbis, supportedAbis) &&
        other.status == status &&
        other.lastError == lastError &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    modelId,
    modelVersion,
    modelSha256,
    localPath,
    platform,
    osVersion,
    isPhysicalDevice,
    Object.hashAll(supportedAbis),
    status,
    lastError,
    updatedAt,
  );

  static bool _sameAbis(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) {
        return false;
      }
    }
    return true;
  }
}

/// Persists and loads the model-readiness snapshot for one application.
///
/// Implementations never validate the model file; they only persist the
/// bookkeeping snapshot. A missing state file reads as null. Corrupt or
/// unsupported persisted data raises [AiConfigurationStoreException] and is
/// never silently replaced on read.
abstract interface class AiConfigurationStore {
  /// Loads the stored readiness snapshot, or null when none is stored.
  Future<AiReadinessSnapshot?> read();

  /// Atomically replaces the stored readiness snapshot.
  Future<void> save(AiReadinessSnapshot snapshot);

  /// Removes any stored readiness snapshot. Missing state is a no-op.
  Future<void> clear();
}

/// A typed failure raised by the persisted AI configuration store.
final class AiConfigurationStoreException implements Exception {
  /// Creates a store failure with an optional underlying cause.
  const AiConfigurationStoreException(this.message, {this.cause});

  /// Human-readable failure explanation.
  final String message;

  /// Original storage/encoding failure, when one exists.
  final Object? cause;

  @override
  String toString() {
    final Object? original = cause;
    if (original == null) {
      return 'AiConfigurationStoreException: $message';
    }
    return 'AiConfigurationStoreException: $message (cause: $original)';
  }
}
