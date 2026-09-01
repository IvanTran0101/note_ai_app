import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/infrastructure/ai/model_downloader.dart' as facade;
import 'package:note_ai_app/infrastructure/ai/model_downloader_io.dart';
import 'package:note_ai_app/infrastructure/ai/model_downloader_stub.dart'
    as stub;
import 'package:note_ai_app/infrastructure/ai/model_provisioning_contract.dart';
import 'package:note_ai_app/infrastructure/ai/model_selection.dart';

const String _zeroDigest =
    '0000000000000000000000000000000000000000000000000000000000000000';

ModelDescriptor _model({String url = 'https://example.test/model.gguf'}) {
  return ModelDescriptor(
    id: 'test-model',
    version: 'test',
    fileName: 'model.gguf',
    downloadUrl: url,
    sha256: _zeroDigest,
    fileSizeBytes: 4,
    estimatedPeakMemoryBytes: null,
    requiredFreeStorageBytes: null,
    supportedPlatforms: const <String>['ios'],
    supportedAbis: const <String>['arm64'],
    minOsVersion: '0',
    contextSize: 128,
    maxOutputTokens: 16,
    quantization: 'Q4_K_M',
    selectionPriority: 1,
  );
}

ModelStagingFile _target(ModelDescriptor model, String path) {
  return ModelStagingFile(model: model, path: path);
}

ModelDownloadResponse _response({
  int statusCode = 200,
  int? contentLength = 4,
  Uri? uri,
  Iterable<List<int>> chunks = const <List<int>>[
    <int>[1, 2],
    <int>[3, 4],
  ],
}) {
  return ModelDownloadResponse(
    statusCode: statusCode,
    uri: uri ?? Uri.parse('https://example.test/model.gguf'),
    contentLength: contentLength,
    body: Stream<List<int>>.fromIterable(chunks),
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('model_downloader_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('HttpModelDownloader', () {
    test('streams a tiny fixture into the storage staging path', () async {
      final ModelDescriptor model = _model();
      final File targetFile = File('${tempDir.path}/model.gguf.part');
      Uri? requestedUri;
      final HttpModelDownloader downloader = HttpModelDownloader(
        responseLoader: (Uri uri) async {
          requestedUri = uri;
          return _response();
        },
      );

      await downloader.download(
        model: model,
        target: _target(model, targetFile.path),
      );

      expect(requestedUri, Uri.parse(model.downloadUrl));
      expect(await targetFile.readAsBytes(), <int>[1, 2, 3, 4]);
      downloader.close();
    });

    test('accepts an HTTPS redirect response', () async {
      final ModelDescriptor model = _model();
      final File targetFile = File('${tempDir.path}/redirected.part');
      final HttpModelDownloader downloader = HttpModelDownloader(
        responseLoader: (_) async =>
            _response(uri: Uri.parse('https://cdn.example.test/model.gguf')),
      );

      await downloader.download(
        model: model,
        target: _target(model, targetFile.path),
      );

      expect(await targetFile.readAsBytes(), <int>[1, 2, 3, 4]);
      downloader.close();
    });

    test('rejects a non-HTTPS source before requesting it', () async {
      final ModelDescriptor model = _model(url: 'http://example.test/model');
      var called = false;
      final HttpModelDownloader downloader = HttpModelDownloader(
        responseLoader: (_) async {
          called = true;
          return _response();
        },
      );

      await expectLater(
        downloader.download(
          model: model,
          target: _target(model, '${tempDir.path}/model.part'),
        ),
        throwsA(
          isA<ModelDownloadException>().having(
            (ModelDownloadException error) => error.message,
            'message',
            contains('HTTPS'),
          ),
        ),
      );
      expect(called, isFalse);
      downloader.close();
    });

    test('rejects non-success HTTP status', () async {
      final ModelDescriptor model = _model();
      final File targetFile = File('${tempDir.path}/not-found.part');
      final HttpModelDownloader downloader = HttpModelDownloader(
        responseLoader: (_) async => _response(statusCode: 404),
      );

      await expectLater(
        downloader.download(
          model: model,
          target: _target(model, targetFile.path),
        ),
        throwsA(
          isA<ModelDownloadException>().having(
            (ModelDownloadException error) => error.message,
            'message',
            contains('HTTP 404'),
          ),
        ),
      );
      expect(targetFile.existsSync(), isFalse);
      downloader.close();
    });

    test('rejects a declared response larger than the descriptor', () async {
      final ModelDescriptor model = _model();
      final File targetFile = File('${tempDir.path}/oversize.part');
      final HttpModelDownloader downloader = HttpModelDownloader(
        responseLoader: (_) async => _response(contentLength: 5),
      );

      await expectLater(
        downloader.download(
          model: model,
          target: _target(model, targetFile.path),
        ),
        throwsA(
          isA<ModelDownloadException>().having(
            (ModelDownloadException error) => error.message,
            'message',
            contains('larger'),
          ),
        ),
      );
      expect(targetFile.existsSync(), isFalse);
      downloader.close();
    });

    test(
      'rejects an unknown-length response once it exceeds the size',
      () async {
        final ModelDescriptor model = _model();
        final File targetFile = File('${tempDir.path}/stream-oversize.part');
        final HttpModelDownloader downloader = HttpModelDownloader(
          responseLoader: (_) async => _response(
            contentLength: null,
            chunks: const <List<int>>[
              <int>[1, 2, 3],
              <int>[4, 5],
            ],
          ),
        );

        await expectLater(
          downloader.download(
            model: model,
            target: _target(model, targetFile.path),
          ),
          throwsA(isA<ModelDownloadException>()),
        );
        downloader.close();
      },
    );

    test('rejects a redirect that downgrades to HTTP', () async {
      final ModelDescriptor model = _model();
      final HttpModelDownloader downloader = HttpModelDownloader(
        responseLoader: (_) async =>
            _response(uri: Uri.parse('http://example.test/model.gguf')),
      );

      await expectLater(
        downloader.download(
          model: model,
          target: _target(model, '${tempDir.path}/downgrade.part'),
        ),
        throwsA(isA<ModelDownloadException>()),
      );
      downloader.close();
    });
  });

  group('facade and Web API surface', () {
    test('native facade exposes the concrete factory', () {
      final IModelDownloader downloader = facade.createModelDownloader();
      expect(downloader, isA<HttpModelDownloader>());
      (downloader as HttpModelDownloader).close();
    });

    test('Web stub rejects local downloading', () async {
      final stub.HttpModelDownloader downloader = stub.HttpModelDownloader();
      final ModelDescriptor model = _model();

      await expectLater(
        downloader.download(
          model: model,
          target: _target(model, '${tempDir.path}/web.part'),
        ),
        throwsUnsupportedError,
      );
      downloader.close();
    });
  });
}
