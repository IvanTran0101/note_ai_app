/// [IUserProfileRepository] implementation for `dart:io` platforms.
///
/// Persists one schemaVersion=1 JSON envelope in the application-support
/// directory, resolved with `path_provider`'s [getApplicationSupportDirectory]
/// by default:
///
/// ```json
/// {
///   "schemaVersion": 1,
///   "profiles": {
///     "user-1": {"displayName": "Ada", "avatarReference": null}
///   }
/// }
/// ```
///
/// Profiles are keyed by `userId`, so saving the same `userId` replaces that
/// entry and never duplicates it. Only the NoteFlow-owned fields `userId`
/// (the key), `displayName`, and `avatarReference` are stored; no credential
/// material is read or written by this boundary.
///
/// Writes are atomic: the payload is written to a same-directory temporary
/// file, flushed and closed, then renamed over the target. On failure only the
/// temporary file this write issued is cleaned up. All operations are
/// serialized per repository instance, so a read observes every preceding
/// write and concurrent read-modify-write saves cannot drop each other's
/// entries. Reads never repair persisted data: malformed or unsupported files
/// raise [UserProfileRepositoryException] unchanged.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/users/user_profile.dart';
import '../../domain/users/user_profile_repository.dart';

/// Creates the native file-backed user-profile repository over the default
/// `<app support>/user_profiles.json` location.
///
/// The signature matches the Web stub factory so the conditional facade can
/// swap them by platform. Tests inject a temporary file through
/// [FileUserProfileRepository.file]. This factory is intentionally not wired
/// into `main.dart`.
IUserProfileRepository createUserProfileRepository() {
  return FileUserProfileRepository();
}

/// JSON-file [IUserProfileRepository] for native platforms.
///
/// One instance owns one file. Concurrent use of two instances over the same
/// path is not serialized against each other.
final class FileUserProfileRepository implements IUserProfileRepository {
  /// [file] overrides the default `<app support>/user_profiles.json` location.
  /// When it is omitted the path is resolved lazily per operation, so no
  /// plugin channel is touched at construction time.
  FileUserProfileRepository({this.file});

  /// The JSON file this repository owns, or null to resolve the default
  /// application-support location per operation.
  final File? file;

  static const int _schemaVersion = 1;
  static const String _fileName = 'user_profiles.json';
  static const Set<String> _envelopeFields = <String>{
    'schemaVersion',
    'profiles',
  };
  static const Set<String> _profileFields = <String>{
    'displayName',
    'avatarReference',
  };

  static int _temporaryFileSequence = 0;

  /// The tail is always a successful release future; operation failures are
  /// returned only to the caller of that operation and do not poison the
  /// queue for later reads or writes.
  Future<void> _operationTail = Future<void>.value();

  @override
  Future<UserProfile?> findByUserId(String userId) {
    return _enqueue<UserProfile?>(() async {
      final Map<String, UserProfile> profiles = await _readProfiles(
        await _profileFile(),
      );
      return profiles[userId];
    });
  }

  @override
  Future<void> save(UserProfile profile) {
    return _enqueue<void>(() async {
      final File target = await _profileFile();
      // One read-modify-write inside one queued operation: saving one profile
      // must not drop profiles stored for other users.
      final Map<String, UserProfile> profiles = Map<String, UserProfile>.of(
        await _readProfiles(target),
      );
      profiles[profile.userId] = profile;
      await _writeProfiles(target, profiles);
    });
  }

  Future<File> _profileFile() async {
    final File? injected = file;
    if (injected != null) {
      return injected;
    }

    final String supportPath;
    try {
      supportPath = (await getApplicationSupportDirectory()).path.trim();
    } on Object catch (error) {
      throw UserProfileRepositoryException(
        'failed to resolve the application support directory',
        cause: error,
      );
    }
    if (supportPath.isEmpty) {
      throw const UserProfileRepositoryException(
        'the application support directory path is empty',
      );
    }
    return File(
      '${Directory(supportPath).path}${Platform.pathSeparator}$_fileName',
    );
  }

  Future<Map<String, UserProfile>> _readProfiles(File target) async {
    final bool exists;
    try {
      exists = await target.exists();
    } on Object catch (error) {
      throw UserProfileRepositoryException(
        'failed to read ${target.path}',
        cause: error,
      );
    }
    if (!exists) {
      return <String, UserProfile>{};
    }

    final String encoded;
    try {
      encoded = await target.readAsString();
    } on Object catch (error) {
      throw UserProfileRepositoryException(
        'failed to read ${target.path}',
        cause: error,
      );
    }

    return _decodeProfiles(encoded, target.path);
  }

  Map<String, UserProfile> _decodeProfiles(String encoded, String path) {
    final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on Object catch (error) {
      throw UserProfileRepositoryException(
        'malformed JSON in $path',
        cause: error,
      );
    }

    final Map<String, Object?> envelope = _objectMap(
      decoded,
      'the JSON root in $path must be an object',
    );
    // The version is checked before the remaining fields: an envelope from a
    // future schema may legitimately carry fields this version cannot read.
    final Object? schemaVersion = envelope['schemaVersion'];
    if (schemaVersion is! int || schemaVersion != _schemaVersion) {
      throw UserProfileRepositoryException(
        'unsupported schemaVersion in $path: $schemaVersion',
      );
    }

    _rejectUnknownFields(
      envelope,
      _envelopeFields,
      'the JSON envelope in $path',
    );

    final Map<String, Object?> encodedProfiles = _objectMap(
      envelope['profiles'],
      'the profiles field in $path must be an object keyed by userId',
    );

    final Map<String, UserProfile> profiles = <String, UserProfile>{};
    for (final MapEntry<String, Object?> entry in encodedProfiles.entries) {
      final String userId = entry.key.trim();
      if (userId.isEmpty) {
        throw UserProfileRepositoryException(
          'every profile key in $path must be a non-blank userId',
        );
      }
      if (profiles.containsKey(userId)) {
        throw UserProfileRepositoryException(
          'duplicate userId "$userId" in $path',
        );
      }

      final Map<String, Object?> profileJson = _objectMap(
        entry.value,
        'the profile for userId "$userId" in $path must be an object',
      );
      _rejectUnknownFields(
        profileJson,
        _profileFields,
        'the profile for userId "$userId" in $path',
      );

      final Object? displayName = profileJson['displayName'];
      final Object? avatarReference = profileJson['avatarReference'];
      if (displayName is! String || avatarReference is! String?) {
        throw UserProfileRepositoryException(
          'the profile for userId "$userId" in $path must store a string '
          'displayName and a string-or-null avatarReference',
        );
      }

      try {
        profiles[userId] = UserProfile.reconstitute(
          userId: userId,
          displayName: displayName,
          avatarReference: avatarReference,
        );
      } on Object catch (error) {
        throw UserProfileRepositoryException(
          'invalid profile for userId "$userId" in $path',
          cause: error,
        );
      }
    }
    return profiles;
  }

  Future<void> _writeProfiles(
    File target,
    Map<String, UserProfile> profiles,
  ) async {
    final String encoded;
    try {
      // Sorted keys make the payload byte-stable for a given state.
      final List<String> userIds = profiles.keys.toList(growable: false)
        ..sort();
      encoded = jsonEncode(<String, Object?>{
        'schemaVersion': _schemaVersion,
        'profiles': <String, Object?>{
          for (final String userId in userIds)
            userId: <String, Object?>{
              'displayName': profiles[userId]!.displayName,
              'avatarReference': profiles[userId]!.avatarReference,
            },
        },
      });
    } on Object catch (error) {
      throw UserProfileRepositoryException(
        'failed to encode the stored user profiles',
        cause: error,
      );
    }

    try {
      await target.parent.create(recursive: true);
    } on Object catch (error) {
      throw UserProfileRepositoryException(
        'failed to create the user profile directory',
        cause: error,
      );
    }

    final File temporary = File(_temporaryPathFor(target));
    bool temporaryIssued = false;
    try {
      await temporary.create(exclusive: true);
      temporaryIssued = true;

      final RandomAccessFile handle = await temporary.open(
        mode: FileMode.writeOnly,
      );
      try {
        await handle.writeString(encoded);
        await handle.flush();
      } finally {
        await handle.close();
      }

      // The temporary file is in the same directory, so this is one
      // filesystem rename rather than a copy followed by a delete. On the
      // supported native filesystems it atomically replaces the old file.
      await temporary.rename(target.path);
    } on Object catch (error) {
      if (temporaryIssued) {
        await _cleanIssuedTemporaryFile(temporary);
      }
      throw UserProfileRepositoryException(
        'failed to atomically write ${target.path}',
        cause: error,
      );
    }
  }

  static Map<String, Object?> _objectMap(Object? value, String message) {
    if (value is! Map) {
      throw UserProfileRepositoryException(message);
    }

    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      final Object? key = entry.key;
      if (key is! String) {
        throw UserProfileRepositoryException(
          '$message (all keys must be strings)',
        );
      }
      result[key] = entry.value;
    }
    return result;
  }

  static void _rejectUnknownFields(
    Map<String, Object?> json,
    Set<String> knownFields,
    String description,
  ) {
    final List<String> unknownFields = json.keys
        .where((String key) => !knownFields.contains(key))
        .toList(growable: false);
    if (unknownFields.isNotEmpty) {
      throw UserProfileRepositoryException(
        '$description contains unsupported field(s): '
        '${unknownFields.join(', ')}',
      );
    }
  }

  static String _temporaryPathFor(File target) {
    final int sequence = ++_temporaryFileSequence;
    final int timestamp = DateTime.now().microsecondsSinceEpoch;
    return '${target.path}.tmp-$pid-$timestamp-$sequence';
  }

  static Future<void> _cleanIssuedTemporaryFile(File temporary) async {
    try {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    } on Object {
      // Cleanup must never replace the original persistence failure and it
      // must not search for or delete any path other than this issued file.
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final Future<void> previous = _operationTail;
    final Completer<void> release = Completer<void>();
    _operationTail = release.future;
    return previous.then((_) async {
      try {
        return await operation();
      } finally {
        release.complete();
      }
    });
  }
}

/// A typed failure raised by the JSON-file user-profile repository.
final class UserProfileRepositoryException implements Exception {
  /// Creates a repository failure with an optional underlying cause.
  const UserProfileRepositoryException(this.message, {this.cause});

  /// Human-readable failure explanation.
  final String message;

  /// Original storage/encoding failure, when one exists.
  final Object? cause;

  @override
  String toString() {
    final Object? original = cause;
    if (original == null) {
      return 'UserProfileRepositoryException: $message';
    }
    return 'UserProfileRepositoryException: $message (cause: $original)';
  }
}
