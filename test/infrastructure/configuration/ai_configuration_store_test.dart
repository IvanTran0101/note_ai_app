import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/infrastructure/configuration/ai_configuration_store.dart';
import 'package:note_ai_app/infrastructure/configuration/ai_configuration_store_io.dart'
    as native;
import 'package:note_ai_app/infrastructure/configuration/ai_configuration_store_stub.dart'
    as stub;

AiReadinessSnapshot _snapshot({
  String modelId = 'gemma-3-1b-it',
  String modelVersion = '1b-q4-k-m',
  String modelSha256 =
      'aa55aa55aa55aa55aa55aa55aa55aa55aa55aa55aa55aa55aa55aa55aa55aa55',
  String? localPath,
  String platform = 'ios',
  String osVersion = '18.0',
  bool isPhysicalDevice = true,
  List<String>? supportedAbis,
  ModelReadinessStatus status = ModelReadinessStatus.ready,
  String? lastError,
  RuntimeReadinessStatus runtimeStatus = RuntimeReadinessStatus.unknown,
  String? runtimeError,
  DateTime? updatedAt,
}) {
  return AiReadinessSnapshot(
    modelId: modelId,
    modelVersion: modelVersion,
    modelSha256: modelSha256,
    localPath: localPath,
    platform: platform,
    osVersion: osVersion,
    isPhysicalDevice: isPhysicalDevice,
    supportedAbis: supportedAbis ?? const <String>['arm64'],
    status: status,
    lastError: lastError,
    runtimeStatus: runtimeStatus,
    runtimeError: runtimeError,
    updatedAt: updatedAt ?? DateTime.utc(2026, 9, 3, 8, 30),
  );
}

typedef _Fixture = ({
  Directory directory,
  native.FileAiConfigurationStore store,
});

Future<Directory> _supportDirectory() async {
  final Directory directory = await Directory.systemTemp.createTemp(
    'ai_configuration_store_test_',
  );
  addTearDown(() async {
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });
  return directory;
}

/// A native store over a fresh temporary directory, deleted when the test ends.
Future<_Fixture> _newFixture() async {
  final Directory directory = await _supportDirectory();
  final native.FileAiConfigurationStore store = native.FileAiConfigurationStore(
    applicationSupportPathResolver: () async => directory.path,
  );
  return (directory: directory, store: store);
}

File _storeFile(Directory directory) =>
    File('${directory.path}${Platform.pathSeparator}ai_configuration.json');

Future<List<FileSystemEntity>> _temporaryResidue(Directory directory) =>
    directory
        .list()
        .where(
          (FileSystemEntity entity) => entity.path.contains(
            '${Platform.pathSeparator}ai_configuration.json.tmp-',
          ),
        )
        .toList();

Matcher _formatError(String fragment) => throwsA(
  isA<FormatException>().having(
    (FormatException error) => error.message,
    'message',
    contains(fragment),
  ),
);

Matcher _storeError(String fragment) => throwsA(
  isA<AiConfigurationStoreException>().having(
    (AiConfigurationStoreException error) => error.message,
    'message',
    contains(fragment),
  ),
);

void _expectFormatError(Map<String, Object?> json, String fragment) {
  expect(() => AiReadinessSnapshot.fromJson(json), _formatError(fragment));
}

Map<String, Object?> _jsonWith(void Function(Map<String, Object?>) mutate) {
  final Map<String, Object?> json = _snapshot().toJson();
  mutate(json);
  return json;
}

void main() {
  group('AiReadinessSnapshot value semantics', () {
    test('is immutable, trims strings, and keeps a copy-safe ABI list', () {
      final List<String> abis = <String>[' arm64 '];
      final AiReadinessSnapshot snapshot = _snapshot(
        modelId: ' gemma ',
        localPath: '   ',
        supportedAbis: abis,
      );

      abis.add('x86_64');

      expect(snapshot.modelId, 'gemma');
      expect(snapshot.localPath, isNull);
      expect(snapshot.supportedAbis, const <String>['arm64']);
      expect(
        () => snapshot.supportedAbis.add('riscv64'),
        throwsUnsupportedError,
      );
    });

    test('has value equality across identical and differing fields', () {
      final AiReadinessSnapshot snapshot = _snapshot();

      expect(_snapshot(), snapshot);
      expect(_snapshot().hashCode, snapshot.hashCode);

      final List<AiReadinessSnapshot> variants = <AiReadinessSnapshot>[
        _snapshot(modelId: 'other-model'),
        _snapshot(modelVersion: 'other-version'),
        _snapshot(modelSha256: 'bb' * 32),
        _snapshot(localPath: '/elsewhere.gguf'),
        _snapshot(platform: 'android'),
        _snapshot(osVersion: '15.0'),
        _snapshot(isPhysicalDevice: false),
        _snapshot(status: ModelReadinessStatus.preparing),
        _snapshot(lastError: 'boom'),
        _snapshot(runtimeStatus: RuntimeReadinessStatus.loading),
        _snapshot(
          runtimeStatus: RuntimeReadinessStatus.failed,
          runtimeError: 'runtime unavailable',
        ),
        _snapshot(updatedAt: DateTime.utc(2025, 1, 1)),
      ];
      for (final AiReadinessSnapshot variant in variants) {
        expect(snapshot, isNot(variant));
      }

      final AiReadinessSnapshot twoAbis = _snapshot(
        supportedAbis: const <String>['arm64', 'x86_64'],
      );
      expect(
        twoAbis,
        isNot(_snapshot(supportedAbis: const <String>['x86_64', 'arm64'])),
      );
      expect(twoAbis, isNot(_snapshot(supportedAbis: const <String>['arm64'])));
    });

    test('round-trips through JSON including optional fields and nulls', () {
      final AiReadinessSnapshot snapshot = _snapshot(
        localPath: '/support/models/gemma.gguf',
        isPhysicalDevice: false,
        supportedAbis: const <String>['arm64', 'x86_64'],
        lastError: 'checksum mismatch',
      );

      final Map<String, Object?> json = snapshot.toJson();
      expect(json['updatedAt'], '2026-09-03T08:30:00.000Z');
      expect(json['status'], 'ready');
      expect(json['runtimeStatus'], 'unknown');
      expect(json['supportedAbis'], const <String>['arm64', 'x86_64']);

      final AiReadinessSnapshot restored = AiReadinessSnapshot.fromJson(json);
      expect(restored, snapshot);
      expect(restored.toJson(), json);

      final AiReadinessSnapshot sparseRestored = AiReadinessSnapshot.fromJson(
        _snapshot().toJson()..remove('localPath'),
      );
      expect(sparseRestored.localPath, isNull);
      expect(sparseRestored.lastError, isNull);
      expect(sparseRestored.runtimeStatus, RuntimeReadinessStatus.unknown);
      expect(sparseRestored.runtimeError, isNull);
      expect(sparseRestored, _snapshot());
    });

    test('round-trips runtime readiness and can update it independently', () {
      final AiReadinessSnapshot snapshot = _snapshot(
        runtimeStatus: RuntimeReadinessStatus.failed,
        runtimeError: 'The local runtime could not start.',
      );

      final AiReadinessSnapshot restored = AiReadinessSnapshot.fromJson(
        snapshot.toJson(),
      );
      expect(restored.runtimeStatus, RuntimeReadinessStatus.failed);
      expect(restored.runtimeError, 'The local runtime could not start.');

      final AiReadinessSnapshot ready = snapshot.withRuntimeStatus(
        RuntimeReadinessStatus.ready,
      );
      expect(ready.modelId, snapshot.modelId);
      expect(ready.status, snapshot.status);
      expect(ready.runtimeStatus, RuntimeReadinessStatus.ready);
      expect(ready.runtimeError, isNull);
    });
  });

  group('AiReadinessSnapshot JSON and field validation', () {
    test('rejects malformed JSON maps with a FormatException', () {
      final List<(String, Map<String, Object?>)>
      cases = <(String, Map<String, Object?>)>[
        ('Unknown', _jsonWith((json) => json['surprise'] = 1)),
        ('modelVersion', _jsonWith((json) => json.remove('modelVersion'))),
        (
          'isPhysicalDevice',
          _jsonWith((json) => json['isPhysicalDevice'] = 'yes'),
        ),
        ('modelId', _jsonWith((json) => json['modelId'] = '   ')),
        ('status', _jsonWith((json) => json['status'] = 'downloading')),
        ('localPath', _jsonWith((json) => json['localPath'] = 42)),
        ('lastError', _jsonWith((json) => json['lastError'] = true)),
        (
          'runtimeStatus',
          _jsonWith((json) => json['runtimeStatus'] = 'starting'),
        ),
        ('runtimeError', _jsonWith((json) => json['runtimeError'] = false)),
        ('updatedAt', _jsonWith((json) => json['updatedAt'] = 'not-a-date')),
        (
          'supportedAbis',
          _jsonWith((json) => json['supportedAbis'] = <String>[]),
        ),
        ('supportedAbis', _jsonWith((json) => json['supportedAbis'] = 'arm64')),
        (
          'supportedAbis',
          _jsonWith((json) => json['supportedAbis'] = <Object?>['arm64', 3]),
        ),
      ];

      for (final (String fragment, Map<String, Object?> json) in cases) {
        _expectFormatError(json, fragment);
      }
    });

    test('constructor rejects blank identities and empty ABI lists', () {
      expect(() => _snapshot(modelId: ' '), throwsArgumentError);
      expect(() => _snapshot(modelSha256: ''), throwsArgumentError);
      expect(
        () => _snapshot(supportedAbis: const <String>[]),
        throwsArgumentError,
      );
      expect(
        () => _snapshot(supportedAbis: const <String>['arm64', '  ']),
        throwsArgumentError,
      );
    });

    test('accepts a cancelled artifact status', () {
      expect(
        _snapshot(status: ModelReadinessStatus.cancelled).status,
        ModelReadinessStatus.cancelled,
      );
    });

    test('old records without runtime fields default to unknown', () {
      final Map<String, Object?> json = _snapshot().toJson()
        ..remove('runtimeStatus')
        ..remove('runtimeError');

      final AiReadinessSnapshot restored = AiReadinessSnapshot.fromJson(json);

      expect(restored.runtimeStatus, RuntimeReadinessStatus.unknown);
      expect(restored.runtimeError, isNull);
    });
  });

  group('native FileAiConfigurationStore', () {
    test('reads null when the file is missing and creates nothing', () async {
      final _Fixture fixture = await _newFixture();
      expect(await fixture.store.read(), isNull);
      expect(_storeFile(fixture.directory).existsSync(), isFalse);
    });

    test('round-trips a saved snapshot under the versioned envelope', () async {
      final _Fixture fixture = await _newFixture();
      final AiReadinessSnapshot snapshot = _snapshot(
        localPath: '/support/models/gemma.gguf',
        supportedAbis: const <String>['arm64', 'x86_64'],
        status: ModelReadinessStatus.preparing,
      );

      await fixture.store.save(snapshot);

      expect(await fixture.store.read(), snapshot);
      expect(
        jsonDecode(await _storeFile(fixture.directory).readAsString()),
        <String, Object?>{'schemaVersion': 1, 'snapshot': snapshot.toJson()},
      );
    });

    test('a later save replaces the previous snapshot', () async {
      final _Fixture fixture = await _newFixture();
      await fixture.store.save(_snapshot(modelId: 'first-model'));
      await fixture.store.save(_snapshot(modelId: 'second-model'));

      expect((await fixture.store.read())?.modelId, 'second-model');
    });

    test('clear removes state and is a no-op when nothing is stored', () async {
      final _Fixture fixture = await _newFixture();
      await fixture.store.save(_snapshot());
      await fixture.store.clear();
      expect(_storeFile(fixture.directory).existsSync(), isFalse);
      expect(await fixture.store.read(), isNull);
      await fixture.store.clear();
      expect(_storeFile(fixture.directory).existsSync(), isFalse);
    });

    test(
      'rejects malformed JSON and invalid envelopes without repair',
      () async {
        final _Fixture fixture = await _newFixture();
        final File file = _storeFile(fixture.directory);

        await file.writeAsString('{not-json');
        await expectLater(fixture.store.read(), _storeError('malformed JSON'));
        expect(await file.readAsString(), '{not-json');

        await file.writeAsString('[1, 2, 3]');
        await expectLater(
          fixture.store.read(),
          _storeError('must be an object'),
        );

        await file.writeAsString(
          jsonEncode(<String, Object?>{
            'schemaVersion': 2,
            'snapshot': _snapshot().toJson(),
          }),
        );
        await expectLater(
          fixture.store.read(),
          _storeError('unsupported schemaVersion'),
        );

        await file.writeAsString(
          jsonEncode(<String, Object?>{
            'schemaVersion': 1,
            'snapshot': 'not-an-object',
          }),
        );
        await expectLater(fixture.store.read(), _storeError('snapshot field'));
      },
    );

    test(
      'rejects an invalid snapshot field without replacing the file',
      () async {
        final _Fixture fixture = await _newFixture();
        final File file = _storeFile(fixture.directory);
        final Map<String, Object?> envelope = <String, Object?>{
          'schemaVersion': 1,
          'snapshot': _snapshot().toJson()..['status'] = 'downloading',
        };
        await file.writeAsString(jsonEncode(envelope));

        await expectLater(
          fixture.store.read(),
          _storeError('invalid model readiness snapshot'),
        );
        expect(await file.readAsString(), jsonEncode(envelope));
      },
    );

    test('writes an envelope and leaves no temporary file residue', () async {
      final _Fixture fixture = await _newFixture();
      final AiReadinessSnapshot snapshot = _snapshot(isPhysicalDevice: false);
      await fixture.store.save(snapshot);

      final File file = _storeFile(fixture.directory);
      expect(file.existsSync(), isTrue);
      expect(jsonDecode(await file.readAsString()), <String, Object?>{
        'schemaVersion': 1,
        'snapshot': snapshot.toJson(),
      });
      expect(await _temporaryResidue(fixture.directory), isEmpty);
    });

    test(
      'cleans only its temporary file when the atomic rename fails',
      () async {
        final _Fixture fixture = await _newFixture();
        // A directory at the final path makes rename fail after the temporary
        // file has been created, exercising the failure cleanup branch.
        await Directory(_storeFile(fixture.directory).path).create();

        await expectLater(
          fixture.store.save(_snapshot()),
          throwsA(isA<AiConfigurationStoreException>()),
        );
        expect(await _temporaryResidue(fixture.directory), isEmpty);
        expect(
          _storeFile(fixture.directory).statSync().type,
          FileSystemEntityType.directory,
        );
      },
    );

    test('serializes concurrent saves and a following read', () async {
      final _Fixture fixture = await _newFixture();
      final List<Future<void>> saves = <Future<void>>[];
      for (var index = 0; index < 6; index++) {
        saves.add(fixture.store.save(_snapshot(modelId: 'snapshot-$index')));
      }

      final Future<AiReadinessSnapshot?> read = fixture.store.read();
      await Future.wait(saves);
      expect((await read)?.modelId, 'snapshot-5');
    });
  });

  group('platform facade', () {
    test('exposes the native store on an IO test host', () async {
      final Directory directory = await _supportDirectory();
      final AiConfigurationStore store = createAiConfigurationStore(
        applicationSupportPathResolver: () async => directory.path,
      );

      expect(store, isA<native.FileAiConfigurationStore>());
      expect(store, isNot(isA<stub.FileAiConfigurationStore>()));

      await store.save(_snapshot());
      expect(await store.read(), _snapshot());
    });

    test('Web stub keeps constructor parity and throws UnsupportedError', () {
      final stub.FileAiConfigurationStore store = stub.FileAiConfigurationStore(
        applicationSupportPathResolver: () async => 'unused',
      );

      expect(() => store.read(), throwsUnsupportedError);
      expect(() => store.save(_snapshot()), throwsUnsupportedError);
      expect(() => store.clear(), throwsUnsupportedError);
    });
  });
}
