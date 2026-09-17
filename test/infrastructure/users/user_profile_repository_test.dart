import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/users/user_profile.dart';
import 'package:note_ai_app/infrastructure/users/user_profile_repository.dart';
import 'package:note_ai_app/infrastructure/users/user_profile_repository_io.dart'
    as native;
import 'package:note_ai_app/infrastructure/users/user_profile_repository_stub.dart'
    as stub;

UserProfile _profile({
  String userId = 'user-1',
  String displayName = 'Ada Lovelace',
  String? avatarReference,
}) {
  return UserProfile.create(
    userId: userId,
    displayName: displayName,
    avatarReference: avatarReference,
  );
}

Matcher _isProfile({
  String userId = 'user-1',
  String displayName = 'Ada Lovelace',
  String? avatarReference,
}) {
  return isA<UserProfile>()
      .having((UserProfile profile) => profile.userId, 'userId', userId)
      .having(
        (UserProfile profile) => profile.displayName,
        'displayName',
        displayName,
      )
      .having(
        (UserProfile profile) => profile.avatarReference,
        'avatarReference',
        avatarReference,
      );
}

Matcher _repositoryError(String fragment) => throwsA(
  isA<native.UserProfileRepositoryException>().having(
    (native.UserProfileRepositoryException error) => error.message,
    'message',
    contains(fragment),
  ),
);

typedef _Fixture = ({
  Directory directory,
  File file,
  native.FileUserProfileRepository repository,
});

/// A native repository over a fresh temporary directory, deleted at test end.
Future<_Fixture> _newFixture() async {
  final Directory directory = await Directory.systemTemp.createTemp(
    'user_profile_repository_test_',
  );
  addTearDown(() async {
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });
  final File file = File(
    '${directory.path}${Platform.pathSeparator}user_profiles.json',
  );
  return (
    directory: directory,
    file: file,
    repository: native.FileUserProfileRepository(file: file),
  );
}

Future<List<FileSystemEntity>> _temporaryResidue(Directory directory) =>
    directory
        .list()
        .where(
          (FileSystemEntity entity) => entity.path.contains(
            '${Platform.pathSeparator}user_profiles.json.tmp-',
          ),
        )
        .toList();

/// Writes [content] as the stored file and returns those exact bytes.
Future<String> _writeStoredFile(File file, String content) async {
  await file.writeAsString(content);
  return content;
}

String _envelope(Map<String, Object?> profiles) =>
    jsonEncode(<String, Object?>{'schemaVersion': 1, 'profiles': profiles});

void main() {
  group('native FileUserProfileRepository', () {
    test('reads null for a missing file and creates nothing', () async {
      final _Fixture fixture = await _newFixture();

      expect(await fixture.repository.findByUserId('user-1'), isNull);
      expect(fixture.file.existsSync(), isFalse);
    });

    test('round-trips a saved profile under the versioned envelope', () async {
      final _Fixture fixture = await _newFixture();
      final UserProfile profile = _profile(
        userId: 'user-1',
        displayName: 'Ada Lovelace',
        avatarReference: 'avatars/ada.png',
      );

      expect(fixture.repository.file, fixture.file);
      await fixture.repository.save(profile);

      expect(
        await fixture.repository.findByUserId('user-1'),
        _isProfile(
          userId: 'user-1',
          displayName: 'Ada Lovelace',
          avatarReference: 'avatars/ada.png',
        ),
      );
      expect(jsonDecode(await fixture.file.readAsString()), <String, Object?>{
        'schemaVersion': 1,
        'profiles': <String, Object?>{
          'user-1': <String, Object?>{
            'displayName': 'Ada Lovelace',
            'avatarReference': 'avatars/ada.png',
          },
        },
      });
    });

    test('round-trips a null avatar reference', () async {
      final _Fixture fixture = await _newFixture();

      await fixture.repository.save(_profile(avatarReference: 'avatars/1.png'));
      await fixture.repository.save(_profile(avatarReference: null));

      expect(await fixture.repository.findByUserId('user-1'), _isProfile());
      expect(jsonDecode(await fixture.file.readAsString()), <String, Object?>{
        'schemaVersion': 1,
        'profiles': <String, Object?>{
          'user-1': <String, Object?>{
            'displayName': 'Ada Lovelace',
            'avatarReference': null,
          },
        },
      });
    });

    test('replaces the profile stored for the same userId', () async {
      final _Fixture fixture = await _newFixture();

      await fixture.repository.save(_profile(displayName: 'Ada Lovelace'));
      await fixture.repository.save(
        _profile(displayName: 'Ada Byron', avatarReference: 'avatars/2.png'),
      );

      expect(
        await fixture.repository.findByUserId('user-1'),
        _isProfile(displayName: 'Ada Byron', avatarReference: 'avatars/2.png'),
      );
      final Map<String, Object?> stored =
          jsonDecode(await fixture.file.readAsString()) as Map<String, Object?>;
      expect(stored['profiles'], hasLength(1));
    });

    test('keeps profiles for different users isolated', () async {
      final _Fixture fixture = await _newFixture();

      await fixture.repository.save(
        _profile(userId: 'user-1', displayName: 'Ada'),
      );
      await fixture.repository.save(
        _profile(userId: 'user-2', displayName: 'Grace'),
      );
      await fixture.repository.save(
        _profile(userId: 'user-2', displayName: 'Grace Hopper'),
      );

      expect(
        await fixture.repository.findByUserId('user-1'),
        _isProfile(displayName: 'Ada'),
      );
      expect(
        await fixture.repository.findByUserId('user-2'),
        _isProfile(userId: 'user-2', displayName: 'Grace Hopper'),
      );
      expect(await fixture.repository.findByUserId('user-3'), isNull);
    });

    test('creates missing parent directories for the stored file', () async {
      final _Fixture fixture = await _newFixture();
      final File nested = File(
        <String>[
          fixture.directory.path,
          'nested',
          'deeper',
          'user_profiles.json',
        ].join(Platform.pathSeparator),
      );
      final native.FileUserProfileRepository repository =
          native.FileUserProfileRepository(file: nested);

      await repository.save(_profile());

      expect(nested.existsSync(), isTrue);
      expect(await repository.findByUserId('user-1'), _isProfile());
    });

    test('rejects malformed JSON without repairing the file', () async {
      final _Fixture fixture = await _newFixture();

      for (final (String content, String fragment) in <(String, String)>[
        ('', 'malformed JSON'),
        ('{not-json', 'malformed JSON'),
        ('[1, 2, 3]', 'must be an object'),
      ]) {
        final String stored = await _writeStoredFile(fixture.file, content);

        await expectLater(
          fixture.repository.findByUserId('user-1'),
          _repositoryError(fragment),
        );
        expect(await fixture.file.readAsString(), stored);
      }
    });

    test(
      'rejects an unsupported envelope without repairing the file',
      () async {
        final _Fixture fixture = await _newFixture();

        final List<(String, String)> cases = <(String, String)>[
          (
            jsonEncode(<String, Object?>{
              'schemaVersion': 2,
              'profiles': <String, Object?>{},
            }),
            'unsupported schemaVersion',
          ),
          (
            jsonEncode(<String, Object?>{
              'schemaVersion': '1',
              'profiles': <String, Object?>{},
            }),
            'unsupported schemaVersion',
          ),
          (
            jsonEncode(<String, Object?>{'profiles': <String, Object?>{}}),
            'unsupported schemaVersion',
          ),
          (
            jsonEncode(<String, Object?>{
              'schemaVersion': 1,
              'profiles': 'nope',
            }),
            'profiles field',
          ),
          (jsonEncode(<String, Object?>{'schemaVersion': 1}), 'profiles field'),
          (
            jsonEncode(<String, Object?>{
              'schemaVersion': 1,
              'profiles': <String, Object?>{},
              'notes': <Object?>[],
            }),
            'unsupported field',
          ),
        ];

        for (final (String content, String fragment) in cases) {
          final String stored = await _writeStoredFile(fixture.file, content);

          await expectLater(
            fixture.repository.findByUserId('user-1'),
            _repositoryError(fragment),
          );
          expect(await fixture.file.readAsString(), stored);
        }
      },
    );

    test(
      'rejects an invalid profile entry without repairing the file',
      () async {
        final _Fixture fixture = await _newFixture();

        final List<(String, String)> cases = <(String, String)>[
          (
            _envelope(<String, Object?>{'user-1': 'not-an-object'}),
            'must be an object',
          ),
          (
            _envelope(<String, Object?>{'user-1': <String, Object?>{}}),
            'displayName',
          ),
          (
            _envelope(<String, Object?>{
              'user-1': <String, Object?>{'displayName': '   '},
            }),
            'invalid profile',
          ),
          (
            _envelope(<String, Object?>{
              'user-1': <String, Object?>{'displayName': 7},
            }),
            'displayName',
          ),
          (
            _envelope(<String, Object?>{
              'user-1': <String, Object?>{
                'displayName': 'Ada',
                'avatarReference': 9,
              },
            }),
            'avatarReference',
          ),
          (
            _envelope(<String, Object?>{
              'user-1': <String, Object?>{
                'displayName': 'Ada',
                'userId': 'user-1',
              },
            }),
            'unsupported field',
          ),
          (
            _envelope(<String, Object?>{
              '   ': <String, Object?>{'displayName': 'Ada'},
            }),
            'non-blank userId',
          ),
          (
            _envelope(<String, Object?>{
              'user-1': <String, Object?>{'displayName': 'Ada'},
              ' user-1 ': <String, Object?>{'displayName': 'Grace'},
            }),
            'duplicate userId',
          ),
        ];

        for (final (String content, String fragment) in cases) {
          final String stored = await _writeStoredFile(fixture.file, content);

          await expectLater(
            fixture.repository.findByUserId('user-1'),
            _repositoryError(fragment),
          );
          expect(await fixture.file.readAsString(), stored);
        }
      },
    );

    test(
      'refuses to save over corrupt JSON and leaves the bytes intact',
      () async {
        final _Fixture fixture = await _newFixture();
        const String corrupt = '{not-json';
        await fixture.file.writeAsString(corrupt);

        await expectLater(
          fixture.repository.save(_profile()),
          _repositoryError('malformed JSON'),
        );
        expect(await fixture.file.readAsString(), corrupt);
        expect(await _temporaryResidue(fixture.directory), isEmpty);
      },
    );

    test('writes atomically and leaves no temporary file residue', () async {
      final _Fixture fixture = await _newFixture();

      await fixture.repository.save(_profile());

      expect(fixture.file.existsSync(), isTrue);
      expect(await _temporaryResidue(fixture.directory), isEmpty);
      // Only the profile file remains: the write replaced, never appended to,
      // a same-directory temporary file.
      expect(
        (await fixture.directory.list().toList()).map(
          (FileSystemEntity entity) => entity.path,
        ),
        <String>[fixture.file.path],
      );
    });

    test(
      'cleans only its temporary file when the atomic rename fails',
      () async {
        final _Fixture fixture = await _newFixture();
        // A directory at the final path makes rename fail after the temporary
        // file has been created, exercising the failure cleanup branch.
        await Directory(fixture.file.path).create();

        await expectLater(
          fixture.repository.save(_profile()),
          _repositoryError('failed to atomically write'),
        );

        expect(await _temporaryResidue(fixture.directory), isEmpty);
        expect(fixture.file.statSync().type, FileSystemEntityType.directory);
      },
    );

    test('serializes concurrent saves so no user entry is dropped', () async {
      final _Fixture fixture = await _newFixture();
      final List<Future<void>> saves = <Future<void>>[
        for (var index = 0; index < 6; index++)
          fixture.repository.save(
            _profile(userId: 'user-$index', displayName: 'User $index'),
          ),
      ];
      final Future<UserProfile?> observed = fixture.repository.findByUserId(
        'user-5',
      );

      await Future.wait(saves);

      expect(
        await observed,
        _isProfile(userId: 'user-5', displayName: 'User 5'),
      );
      for (var index = 0; index < 6; index++) {
        expect(
          await fixture.repository.findByUserId('user-$index'),
          _isProfile(userId: 'user-$index', displayName: 'User $index'),
        );
      }
    });

    test('serializes concurrent replacements of one userId', () async {
      final _Fixture fixture = await _newFixture();
      final List<Future<void>> saves = <Future<void>>[
        for (var index = 0; index < 6; index++)
          fixture.repository.save(_profile(displayName: 'Revision $index')),
      ];

      await Future.wait(saves);

      expect(
        await fixture.repository.findByUserId('user-1'),
        _isProfile(displayName: 'Revision 5'),
      );
    });
  });

  group('platform facade', () {
    test('exposes the native repository on an IO test host', () {
      final IUserProfileRepository repository = createUserProfileRepository();

      expect(repository, isA<native.FileUserProfileRepository>());
      expect(repository, isNot(isA<stub.FileUserProfileRepository>()));
    });

    test('Web stub keeps class/factory parity and rejects every call', () {
      final stub.FileUserProfileRepository repository =
          stub.FileUserProfileRepository();

      expect(repository, isA<IUserProfileRepository>());
      expect(() => repository.findByUserId('user-1'), throwsUnsupportedError);
      expect(() => repository.save(_profile()), throwsUnsupportedError);

      final IUserProfileRepository fromFactory = stub
          .createUserProfileRepository();
      expect(fromFactory, isA<stub.FileUserProfileRepository>());
      expect(() => fromFactory.findByUserId('user-1'), throwsUnsupportedError);
      expect(() => fromFactory.save(_profile()), throwsUnsupportedError);
    });
  });
}
