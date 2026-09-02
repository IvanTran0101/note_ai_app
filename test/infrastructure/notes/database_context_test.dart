import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note.dart';
import 'package:note_ai_app/infrastructure/notes/database_context.dart';
import 'package:note_ai_app/infrastructure/notes/database_context_io.dart'
    as native;
import 'package:note_ai_app/infrastructure/notes/database_context_stub.dart'
    as stub;
import 'package:note_ai_app/infrastructure/notes/note_mapper.dart';
import 'package:note_ai_app/infrastructure/notes/note_record.dart';

Note _note({
  required String id,
  String ownerId = 'owner-1',
  String title = 'Title',
  String content = 'Content',
  int minute = 0,
}) {
  final DateTime now = DateTime.utc(2026, 9, 2, 10, minute);
  return Note.create(
    id: id,
    ownerId: ownerId,
    title: title,
    content: content,
    now: now,
  );
}

NoteRecord _record({
  required String id,
  String ownerId = 'owner-1',
  String title = 'Title',
  String content = 'Content',
  int minute = 0,
}) {
  return NoteMapper.toRecord(
    _note(
      id: id,
      ownerId: ownerId,
      title: title,
      content: content,
      minute: minute,
    ),
  );
}

File _notesFile(Directory supportDirectory) {
  return File('${supportDirectory.path}${Platform.pathSeparator}notes.json');
}

void main() {
  late Directory supportDirectory;
  late native.FileDatabaseContext context;

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'database_context_test_',
    );
    context = native.FileDatabaseContext(
      applicationSupportPathResolver: () async => supportDirectory.path,
    );
  });

  tearDown(() async {
    if (supportDirectory.existsSync()) {
      await supportDirectory.delete(recursive: true);
    }
  });

  group('FileDatabaseContext reads', () {
    test('returns an empty collection when notes.json is missing', () async {
      expect(await context.readNotes(), isEmpty);
      expect(_notesFile(supportDirectory).existsSync(), isFalse);
    });

    test('round-trips records and preserves their input order', () async {
      final List<NoteRecord> records = <NoteRecord>[
        _record(id: 'note-2', minute: 2),
        _record(id: 'note-1', minute: 1),
      ];

      await context.writeNotes(records);
      final List<NoteRecord> restored = await context.readNotes();

      expect(restored.map((NoteRecord record) => record.id), [
        'note-2',
        'note-1',
      ]);
      expect(restored[0].toJson(), records[0].toJson());
      expect(restored[1].toJson(), records[1].toJson());
    });

    test('rejects malformed JSON without replacing the file', () async {
      final File file = _notesFile(supportDirectory);
      await file.writeAsString('{not-json');

      await expectLater(
        context.readNotes(),
        throwsA(
          isA<DatabaseContextException>().having(
            (DatabaseContextException error) => error.message,
            'message',
            contains('malformed JSON'),
          ),
        ),
      );
      expect(await file.readAsString(), '{not-json');
    });

    test('rejects an unsupported schema version', () async {
      await _notesFile(supportDirectory).writeAsString(
        jsonEncode(<String, Object?>{'schemaVersion': 2, 'notes': <Object?>[]}),
      );

      await expectLater(
        context.readNotes(),
        throwsA(
          isA<DatabaseContextException>().having(
            (DatabaseContextException error) => error.message,
            'message',
            contains('unsupported schemaVersion'),
          ),
        ),
      );
    });

    test('rejects a wrong envelope shape', () async {
      await _notesFile(supportDirectory).writeAsString(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'notes': <String, Object?>{'id': 'not-an-array'},
        }),
      );

      await expectLater(
        context.readNotes(),
        throwsA(
          isA<DatabaseContextException>().having(
            (DatabaseContextException error) => error.message,
            'message',
            contains('must be an array'),
          ),
        ),
      );
    });

    test('rejects an invalid record instead of silently dropping it', () async {
      await _notesFile(supportDirectory).writeAsString(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'notes': <Object?>[
            <String, Object?>{'id': 'incomplete'},
          ],
        }),
      );

      await expectLater(
        context.readNotes(),
        throwsA(
          isA<DatabaseContextException>().having(
            (DatabaseContextException error) => error.message,
            'message',
            contains('invalid note record'),
          ),
        ),
      );
    });
  });

  group('FileDatabaseContext writes', () {
    test(
      'writes a valid final envelope and leaves no temporary file',
      () async {
        await context.writeNotes(<NoteRecord>[_record(id: 'note-1')]);

        final File file = _notesFile(supportDirectory);
        expect(file.existsSync(), isTrue);
        final Object? decoded = jsonDecode(await file.readAsString());
        expect(decoded, <String, Object?>{
          'schemaVersion': 1,
          'notes': <Object?>[_record(id: 'note-1').toJson()],
        });

        final List<FileSystemEntity> temporaryFiles = await supportDirectory
            .list()
            .where(
              (FileSystemEntity entity) =>
                  entity.path.startsWith('${file.path}.tmp-'),
            )
            .toList();
        expect(temporaryFiles, isEmpty);
      },
    );

    test(
      'cleans only its temporary file when the atomic rename fails',
      () async {
        // A directory at the final path makes rename fail after the temporary
        // file has been created, which exercises the failure cleanup branch.
        await Directory(_notesFile(supportDirectory).path).create();

        await expectLater(
          context.writeNotes(<NoteRecord>[_record(id: 'note-1')]),
          throwsA(isA<DatabaseContextException>()),
        );

        final List<FileSystemEntity> temporaryFiles = await supportDirectory
            .list()
            .where(
              (FileSystemEntity entity) => entity.path.contains(
                '${Platform.pathSeparator}notes.json.tmp-',
              ),
            )
            .toList();
        expect(temporaryFiles, isEmpty);
        expect(
          _notesFile(supportDirectory).statSync().type,
          FileSystemEntityType.directory,
        );
      },
    );

    test('serializes concurrent writes and a following read', () async {
      final List<Future<void>> writes = <Future<void>>[];
      for (var index = 0; index < 6; index++) {
        writes.add(
          context.writeNotes(<NoteRecord>[_record(id: 'note-$index')]),
        );
      }

      final Future<List<NoteRecord>> read = context.readNotes();
      await Future.wait(writes);
      final List<NoteRecord> records = await read;

      expect(records, hasLength(1));
      expect(records.single.id, 'note-5');
    });
  });

  group('platform facade', () {
    test('exports the native context on an IO test host', () {
      expect(
        FileDatabaseContext(
          applicationSupportPathResolver: () async => supportDirectory.path,
        ),
        isA<native.FileDatabaseContext>(),
      );
      expect(const Object(), isNot(isA<stub.FileDatabaseContext>()));
    });

    test('Web stub remains safe and does not import dart:io', () {
      final stub.FileDatabaseContext unavailable = stub.FileDatabaseContext(
        applicationSupportPathResolver: () async => 'unused',
      );

      expect(() => unavailable.readNotes(), throwsUnsupportedError);
      expect(
        () => unavailable.writeNotes(const <NoteRecord>[]),
        throwsUnsupportedError,
      );
    });
  });
}
