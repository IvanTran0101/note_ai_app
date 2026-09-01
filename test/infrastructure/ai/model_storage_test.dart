// Unit tests for IModelStorage/LocalModelStorage — no real GGUF model, no
// path_provider plugin channel, and no local LLM runtime. The directory
// resolver is injected; model existence is simulated with real temp files.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/infrastructure/ai/model_selection.dart';
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
}
