import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'database_context_contract.dart';
import 'note_record.dart';

/// Native JSON-file implementation of [DatabaseContext].
///
/// The file is private to the application and uses a versioned envelope:
///
/// ```json
/// {"schemaVersion": 1, "notes": []}
/// ```
///
/// Every operation is placed on one FIFO queue. This makes a read observe all
/// preceding writes and keeps repository read-modify-write operations safe
/// when they share this context instance.
final class FileDatabaseContext implements DatabaseContext {
  FileDatabaseContext({
    ApplicationSupportPathResolver? applicationSupportPathResolver,
  }) : _applicationSupportPathResolver =
           applicationSupportPathResolver ?? _defaultApplicationSupportPath;

  static const int _schemaVersion = 1;
  static const String _fileName = 'notes.json';
  static int _temporaryFileSequence = 0;

  final ApplicationSupportPathResolver _applicationSupportPathResolver;

  /// The tail is always a successful release future; operation failures are
  /// returned only to the caller of that operation and do not poison the
  /// queue for later reads or writes.
  Future<void> _operationTail = Future<void>.value();

  static Future<String> _defaultApplicationSupportPath() async {
    final Directory directory = await getApplicationSupportDirectory();
    return directory.path;
  }

  @override
  Future<List<NoteRecord>> readNotes() {
    return _enqueue<List<NoteRecord>>(() async {
      final File file = await _notesFile();
      if (!await file.exists()) {
        return <NoteRecord>[];
      }

      final String encoded;
      try {
        encoded = await file.readAsString();
      } on Object catch (error) {
        throw DatabaseContextException(
          'failed to read ${file.path}',
          cause: error,
        );
      }

      return _decodeRecords(encoded, file.path);
    });
  }

  @override
  Future<void> writeNotes(Iterable<NoteRecord> notes) {
    return _enqueue<void>(() async {
      final File target = await _notesFile();
      final List<NoteRecord> snapshot;
      try {
        // Materialize before any filesystem mutation. This both preserves the
        // caller's order and prevents a lazy iterable from changing midway
        // through serialization.
        snapshot = List<NoteRecord>.of(notes, growable: false);
      } on Object catch (error) {
        throw DatabaseContextException(
          'failed to materialize note records',
          cause: error,
        );
      }

      final String encoded;
      try {
        encoded = jsonEncode(<String, Object?>{
          'schemaVersion': _schemaVersion,
          'notes': snapshot.map((NoteRecord note) => note.toJson()).toList(),
        });
      } on Object catch (error) {
        throw DatabaseContextException(
          'failed to encode note records',
          cause: error,
        );
      }

      try {
        await target.parent.create(recursive: true);
      } on Object catch (error) {
        throw DatabaseContextException(
          'failed to create the notes directory',
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
        throw DatabaseContextException(
          'failed to atomically write ${target.path}',
          cause: error,
        );
      }
    });
  }

  Future<File> _notesFile() async {
    final String supportPath;
    try {
      supportPath = (await _applicationSupportPathResolver()).trim();
    } on Object catch (error) {
      throw DatabaseContextException(
        'failed to resolve the application support directory',
        cause: error,
      );
    }
    if (supportPath.isEmpty) {
      throw const DatabaseContextException(
        'the application support directory path is empty',
      );
    }
    return File(
      '${Directory(supportPath).path}${Platform.pathSeparator}$_fileName',
    );
  }

  List<NoteRecord> _decodeRecords(String encoded, String path) {
    final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on Object catch (error) {
      throw DatabaseContextException('malformed JSON in $path', cause: error);
    }

    final Map<String, Object?> envelope = _objectMap(
      decoded,
      'the JSON root must be an object',
    );
    final Object? schemaVersion = envelope['schemaVersion'];
    if (schemaVersion is! int || schemaVersion != _schemaVersion) {
      throw DatabaseContextException(
        'unsupported schemaVersion in $path: $schemaVersion',
      );
    }

    final Object? encodedNotes = envelope['notes'];
    if (encodedNotes is! List<Object?>) {
      throw DatabaseContextException(
        'the notes field in $path must be an array',
      );
    }

    final List<NoteRecord> records = <NoteRecord>[];
    for (var index = 0; index < encodedNotes.length; index++) {
      final Map<String, Object?> noteJson = _objectMap(
        encodedNotes[index],
        'notes[$index] in $path must be an object',
      );
      try {
        records.add(NoteRecord.fromJson(noteJson));
      } on Object catch (error) {
        throw DatabaseContextException(
          'invalid note record at notes[$index] in $path',
          cause: error,
        );
      }
    }
    return List<NoteRecord>.unmodifiable(records);
  }

  static Map<String, Object?> _objectMap(Object? value, String message) {
    if (value is! Map) {
      throw DatabaseContextException(message);
    }

    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      final Object? key = entry.key;
      if (key is! String) {
        throw DatabaseContextException('$message (all keys must be strings)');
      }
      result[key] = entry.value;
    }
    return result;
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
