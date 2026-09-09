// Unit tests for IModelStorage/LocalModelStorage — no real GGUF model, no
// path_provider plugin channel, and no local LLM runtime. The directory
// resolver is injected; model existence is simulated with real temp files.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/infrastructure/ai/model_selection.dart';
import 'package:note_ai_app/infrastructure/ai/model_provisioning_contract.dart';
import 'package:note_ai_app/infrastructure/ai/model_storage.dart' as facade;
import 'package:note_ai_app/infrastructure/ai/model_storage_contract.dart';
import 'package:note_ai_app/infrastructure/ai/model_storage_io.dart';
import 'package:note_ai_app/infrastructure/ai/model_storage_stub.dart' as stub;

/// Builds a valid descriptor; storage only ever reads [ModelDescriptor.fileName].
ModelDescriptor _descriptor({String fileName = 'custom.gguf'}) {
  return ModelDescriptor(
    id: 'test-model',
    version: '1.0.0',
    fileName: fileName,
    downloadUrl: 'https://example.invalid/test.gguf',
    sha256: '0000000000000000000000000000000000000000000000000000000000000000',
    fileSizeBytes: 1 << 20,
    estimatedPeakMemoryBytes: 1 << 30,
    requiredFreeStorageBytes: 1 << 20,
    supportedPlatforms: const ['android', 'ios'],
    supportedAbis: const ['arm64'],
    minOsVersion: '14.0',
    contextSize: 2048,
    maxOutputTokens: 256,
    quantization: 'Q4_K_M',
    selectionPriority: 0,
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('model_storage_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('LocalModelStorage default app-support layout', () {
    test('returns the models path when the model exists', () async {
      final Directory modelsDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}$kModelDirectoryName',
      )..createSync(recursive: true);
      final File modelFile = File(
        '${modelsDir.path}${Platform.pathSeparator}$kModelFileName',
      )..writeAsStringSync('fake gguf');

      final IModelStorage storage = LocalModelStorage(
        appSupportDirectoryPath: () async => tempDir.path,
      );

      final String path = await storage.resolveModelPath();

      expect(path, modelFile.absolute.path);
      expect(File(path).existsSync(), isTrue);
    });

    test('throws ModelNotFoundException when the model is missing', () async {
      final IModelStorage storage = LocalModelStorage(
        appSupportDirectoryPath: () async => tempDir.path,
      );

      await expectLater(
        storage.resolveModelPath(),
        throwsA(isA<ModelNotFoundException>()),
      );
    });

    test(
      'wraps directory resolver failures in ModelStorageException',
      () async {
        final IModelStorage storage = LocalModelStorage(
          appSupportDirectoryPath: () async =>
              throw StateError('no support dir'),
        );

        await expectLater(
          storage.resolveModelPath(),
          throwsA(
            isA<ModelStorageException>().having(
              (Object e) => (e as ModelStorageException).message,
              'message',
              contains('application support directory'),
            ),
          ),
        );
      },
    );
  });

  group('LocalModelStorage override path', () {
    test('returns the override path when it exists', () async {
      final File override = File(
        '${tempDir.path}${Platform.pathSeparator}custom.gguf',
      )..writeAsStringSync('fake gguf');

      final IModelStorage storage = LocalModelStorage(
        overrideModelPath: override.path,
      );

      expect(await storage.resolveModelPath(), override.absolute.path);
    });

    test('override wins and the directory resolver is never called', () async {
      final File override = File(
        '${tempDir.path}${Platform.pathSeparator}custom.gguf',
      )..writeAsStringSync('fake gguf');

      final IModelStorage storage = LocalModelStorage(
        overrideModelPath: override.path,
        appSupportDirectoryPath: () async =>
            fail('directory resolver must not be called with an override'),
      );

      expect(await storage.resolveModelPath(), override.absolute.path);
    });

    test(
      'throws ModelNotFoundException when the override path is missing',
      () async {
        final String missing =
            '${tempDir.path}${Platform.pathSeparator}missing.gguf';

        final IModelStorage storage = LocalModelStorage(
          overrideModelPath: missing,
        );

        await expectLater(
          storage.resolveModelPath(),
          throwsA(isA<ModelNotFoundException>()),
        );
      },
    );

    test(
      'treats a blank override as absent and uses app-support layout',
      () async {
        final Directory modelsDir = Directory(
          '${tempDir.path}${Platform.pathSeparator}$kModelDirectoryName',
        )..createSync(recursive: true);
        final File modelFile = File(
          '${modelsDir.path}${Platform.pathSeparator}$kModelFileName',
        )..writeAsStringSync('fake gguf');

        final IModelStorage storage = LocalModelStorage(
          overrideModelPath: '   ',
          appSupportDirectoryPath: () async => tempDir.path,
        );

        expect(await storage.resolveModelPath(), modelFile.absolute.path);
      },
    );
  });

  group('createModelStorage factory', () {
    test('returns a LocalModelStorage', () {
      expect(createModelStorage(), isA<LocalModelStorage>());
    });
  });

  group('model_storage.dart facade', () {
    test('createModelStorage resolves to the io implementation, not the Web '
        'stub, under flutter test', () {
      // The analyzer evaluates `dart.library.io` conservatively; at runtime
      // on an io host the conditional export must pick the real storage.
      expect(
        facade.createModelStorage(),
        isNot(isA<stub.UnavailableModelStorage>()),
      );
    });
  });

  group('Web stub (model_storage_stub.dart)', () {
    test('resolveModelPath throws UnsupportedError and never fakes a path', () {
      const stub.UnavailableModelStorage storage =
          stub.UnavailableModelStorage();

      expect(() => storage.resolveModelPath(), throwsUnsupportedError);
    });

    test('findModel throws UnsupportedError and never fakes a path', () {
      const stub.UnavailableModelStorage storage =
          stub.UnavailableModelStorage();

      expect(() => storage.findModel(_descriptor()), throwsUnsupportedError);
    });

    test('all staging actions throw UnsupportedError', () {
      const stub.UnavailableModelStorage storage =
          stub.UnavailableModelStorage();
      final ModelStagingFile staging = ModelStagingFile(
        model: _descriptor(),
        path: '/unavailable/custom.gguf.part',
      );

      expect(
        () => storage.createStagingFile(_descriptor()),
        throwsUnsupportedError,
      );
      expect(() => storage.commitStagingFile(staging), throwsUnsupportedError);
      expect(() => storage.discardStagingFile(staging), throwsUnsupportedError);
      expect(() => storage.cleanupStagingFiles(), throwsUnsupportedError);
      expect(() => storage.discardModel(_descriptor()), throwsUnsupportedError);
    });
  });

  group('LocalModelStorage findModel (model-aware)', () {
    test('returns the absolute path when the descriptor file exists', () async {
      final Directory modelsDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}$kModelDirectoryName',
      )..createSync(recursive: true);
      final File modelFile = File(
        '${modelsDir.path}${Platform.pathSeparator}custom.gguf',
      )..writeAsStringSync('fake gguf');

      final IModelStorage storage = LocalModelStorage(
        appSupportDirectoryPath: () async => tempDir.path,
      );

      final String? path = await storage.findModel(
        _descriptor(fileName: 'custom.gguf'),
      );

      expect(path, modelFile.absolute.path);
      expect(File(path!).existsSync(), isTrue);
    });

    test('returns null when the descriptor file is missing', () async {
      final IModelStorage storage = LocalModelStorage(
        appSupportDirectoryPath: () async => tempDir.path,
      );

      expect(
        await storage.findModel(_descriptor(fileName: 'missing.gguf')),
        isNull,
      );
    });

    test(
      'locates descriptor.fileName, independent of the legacy Gemma file',
      () async {
        final Directory modelsDir = Directory(
          '${tempDir.path}${Platform.pathSeparator}$kModelDirectoryName',
        )..createSync(recursive: true);
        File('${modelsDir.path}${Platform.pathSeparator}other.gguf')
            .writeAsStringSync('fake gguf');

        final IModelStorage storage = LocalModelStorage(
          appSupportDirectoryPath: () async => tempDir.path,
        );

        // The descriptor's file is found even though the legacy Gemma file is
        // absent (resolveModelPath still throws for it).
        expect(
          await storage.findModel(_descriptor(fileName: 'other.gguf')),
          isNotNull,
        );
        await expectLater(
          storage.resolveModelPath(),
          throwsA(isA<ModelNotFoundException>()),
        );

        // A descriptor pointing at a file that is not on disk resolves to null,
        // even though the legacy Gemma file exists.
        File('${modelsDir.path}${Platform.pathSeparator}$kModelFileName')
            .writeAsStringSync('fake gguf');
        expect(
          await storage.findModel(_descriptor(fileName: 'absent.gguf')),
          isNull,
        );
      },
    );

    test('override wins and the directory resolver is never called', () async {
      final File override = File(
        '${tempDir.path}${Platform.pathSeparator}custom.gguf',
      )..writeAsStringSync('fake gguf');

      final IModelStorage storage = LocalModelStorage(
        overrideModelPath: override.path,
        appSupportDirectoryPath: () async =>
            fail('directory resolver must not be called with an override'),
      );

      expect(
        await storage.findModel(_descriptor(fileName: 'ignored.gguf')),
        override.absolute.path,
      );
    });

    test('returns null for a missing file under an override', () async {
      final IModelStorage storage = LocalModelStorage(
        overrideModelPath:
            '${tempDir.path}${Platform.pathSeparator}missing.gguf',
      );

      expect(await storage.findModel(_descriptor()), isNull);
    });

    test(
      'wraps directory resolver failures in ModelStorageException',
      () async {
        final IModelStorage storage = LocalModelStorage(
          appSupportDirectoryPath: () async =>
              throw StateError('no support dir'),
        );

        await expectLater(
          storage.findModel(_descriptor()),
          throwsA(
            isA<ModelStorageException>().having(
              (Object e) => (e as ModelStorageException).message,
              'message',
              contains('application support directory'),
            ),
          ),
        );
      },
    );

    test('rejects a fileName that is not a bare file name', () async {
      final IModelStorage storage = LocalModelStorage(
        appSupportDirectoryPath: () async => tempDir.path,
      );

      await expectLater(
        storage.findModel(_descriptor(fileName: '../escape.gguf')),
        throwsA(isA<ModelStorageException>()),
      );
      await expectLater(
        storage.findModel(_descriptor(fileName: 'a/b.gguf')),
        throwsA(isA<ModelStorageException>()),
      );
      await expectLater(
        storage.findModel(_descriptor(fileName: '  ')),
        throwsA(isA<ModelStorageException>()),
      );
    });
  });

  group('LocalModelStorage staging', () {
    test('creates a unique app-private .part file for the model', () async {
      final LocalModelStorage storage = LocalModelStorage(
        appSupportDirectoryPath: () async => tempDir.path,
      );

      final ModelStagingFile staging = await storage.createStagingFile(
        _descriptor(fileName: 'staged.gguf'),
      );

      expect(staging.model.fileName, 'staged.gguf');
      expect(staging.path, File(staging.path).absolute.path);
      expect(staging.path, endsWith('.part'));
      expect(
        File(staging.path).parent.absolute.path,
        Directory(
          '${tempDir.path}${Platform.pathSeparator}$kModelDirectoryName',
        ).absolute.path,
      );
      expect(File(staging.path).existsSync(), isTrue);
      expect(File(staging.path).lengthSync(), 0);
    });

    test('commits a staging file atomically to the final model path', () async {
      final LocalModelStorage storage = LocalModelStorage(
        appSupportDirectoryPath: () async => tempDir.path,
      );
      final ModelStagingFile staging = await storage.createStagingFile(
        _descriptor(fileName: 'staged.gguf'),
      );
      await File(staging.path).writeAsString('fake gguf bytes');

      final String finalPath = await storage.commitStagingFile(staging);

      final File finalFile = File(finalPath);
      expect(finalPath, endsWith('staged.gguf'));
      expect(finalFile.existsSync(), isTrue);
      expect(finalFile.readAsStringSync(), 'fake gguf bytes');
      expect(File(staging.path).existsSync(), isFalse);
    });

    test(
      'discards an issued staging file without publishing a model',
      () async {
        final LocalModelStorage storage = LocalModelStorage(
          appSupportDirectoryPath: () async => tempDir.path,
        );
        final ModelStagingFile staging = await storage.createStagingFile(
          _descriptor(fileName: 'discarded.gguf'),
        );
        await File(staging.path).writeAsString('partial bytes');

        await storage.discardStagingFile(staging);

        expect(File(staging.path).existsSync(), isFalse);
        expect(
          await storage.findModel(_descriptor(fileName: 'discarded.gguf')),
          isNull,
        );
      },
    );

    test('rejects commit when the staging file is missing', () async {
      final LocalModelStorage storage = LocalModelStorage(
        appSupportDirectoryPath: () async => tempDir.path,
      );
      final ModelStagingFile staging = await storage.createStagingFile(
        _descriptor(fileName: 'missing.gguf'),
      );
      await File(staging.path).delete();

      await expectLater(
        storage.commitStagingFile(staging),
        throwsA(isA<ModelNotFoundException>()),
      );
    });

    test('refuses to overwrite an existing final model', () async {
      final LocalModelStorage storage = LocalModelStorage(
        appSupportDirectoryPath: () async => tempDir.path,
      );
      final ModelDescriptor model = _descriptor(fileName: 'existing.gguf');
      final ModelStagingFile staging = await storage.createStagingFile(model);
      await File(staging.path).writeAsString('new bytes');
      final File finalFile = File(
        '${tempDir.path}${Platform.pathSeparator}$kModelDirectoryName'
        '${Platform.pathSeparator}${model.fileName}',
      )..writeAsStringSync('keep existing bytes');

      await expectLater(
        storage.commitStagingFile(staging),
        throwsA(isA<ModelStorageException>()),
      );
      expect(finalFile.readAsStringSync(), 'keep existing bytes');
      expect(File(staging.path).readAsStringSync(), 'new bytes');
    });

    test('refuses a staging path outside the app-private directory', () async {
      final LocalModelStorage storage = LocalModelStorage(
        appSupportDirectoryPath: () async => tempDir.path,
      );
      final ModelDescriptor model = _descriptor(fileName: 'foreign.gguf');
      final File foreign = File(
        '${tempDir.path}${Platform.pathSeparator}foreign.gguf.part',
      )..writeAsStringSync('foreign bytes');
      final ModelStagingFile staging = ModelStagingFile(
        model: model,
        path: foreign.path,
      );

      await expectLater(
        storage.commitStagingFile(staging),
        throwsA(isA<ModelStorageException>()),
      );
      await expectLater(
        storage.discardStagingFile(staging),
        throwsA(isA<ModelStorageException>()),
      );
      expect(foreign.existsSync(), isTrue);
    });

    test(
      'rejects staging when an explicit model override is configured',
      () async {
        final File override = File(
          '${tempDir.path}${Platform.pathSeparator}override.gguf',
        )..writeAsStringSync('override bytes');
        final LocalModelStorage storage = LocalModelStorage(
          overrideModelPath: override.path,
          appSupportDirectoryPath: () async => tempDir.path,
        );

        await expectLater(
          storage.createStagingFile(_descriptor()),
          throwsA(isA<ModelStorageException>()),
        );
      },
    );

    test('cleans only stale recognized staging files', () async {
      final Directory modelsDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}$kModelDirectoryName',
      )..createSync(recursive: true);
      final File stale = File(
        '${modelsDir.path}${Platform.pathSeparator}model.gguf.1-2.part',
      )..writeAsStringSync('stale');
      stale.setLastModifiedSync(
        DateTime.now().subtract(const Duration(days: 2)),
      );
      final File fresh = File(
        '${modelsDir.path}${Platform.pathSeparator}model.gguf.3-4.part',
      )..writeAsStringSync('fresh');
      final File unrecognized = File(
        '${modelsDir.path}${Platform.pathSeparator}keep.part',
      )..writeAsStringSync('keep');

      final LocalModelStorage storage = LocalModelStorage(
        appSupportDirectoryPath: () async => tempDir.path,
      );

      expect(
        await storage.cleanupStagingFiles(olderThan: const Duration(hours: 24)),
        1,
      );
      expect(stale.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
      expect(unrecognized.existsSync(), isTrue);
    });

    test('rejects a negative stale-file age', () {
      final LocalModelStorage storage = LocalModelStorage(
        appSupportDirectoryPath: () async => tempDir.path,
      );

      expect(
        () =>
            storage.cleanupStagingFiles(olderThan: const Duration(seconds: -1)),
        throwsArgumentError,
      );
    });

    test(
      'discardModel removes only the exact app-private model artifact',
      () async {
        final Directory modelsDir = Directory(
          '${tempDir.path}${Platform.pathSeparator}$kModelDirectoryName',
        )..createSync(recursive: true);
        final ModelDescriptor model = _descriptor(fileName: 'invalid.gguf');
        final File invalid = File(
          '${modelsDir.path}${Platform.pathSeparator}${model.fileName}',
        )..writeAsStringSync('invalid');
        final File other = File(
          '${modelsDir.path}${Platform.pathSeparator}other.gguf',
        )..writeAsStringSync('keep');
        final LocalModelStorage storage = LocalModelStorage(
          appSupportDirectoryPath: () async => tempDir.path,
        );

        await storage.discardModel(model);

        expect(invalid.existsSync(), isFalse);
        expect(other.existsSync(), isTrue);
      },
    );

    test('discardModel never deletes an explicit override', () async {
      final File override = File(
        '${tempDir.path}${Platform.pathSeparator}override.gguf',
      )..writeAsStringSync('keep');
      final LocalModelStorage storage = LocalModelStorage(
        overrideModelPath: override.path,
        appSupportDirectoryPath: () async => tempDir.path,
      );

      await storage.discardModel(_descriptor(fileName: 'override.gguf'));

      expect(override.existsSync(), isTrue);
      expect(override.readAsStringSync(), 'keep');
    });
  });
}
