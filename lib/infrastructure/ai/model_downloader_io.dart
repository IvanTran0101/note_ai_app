/// `dart:io` implementation of the model downloader.
///
/// The default transport is [HttpClient]. The optional response loader is a
/// small test seam so unit tests can exercise HTTPS, redirects, and streaming
/// guards with tiny local fixtures instead of contacting a real model host.
library;

import 'dart:io';

import 'model_provisioning_contract.dart';
import 'model_selection.dart';

export 'model_provisioning_contract.dart' show ModelDownloadException;

/// A response abstraction used by [HttpModelDownloader] and its test seam.
final class ModelDownloadResponse {
  /// Creates a streamed response.
  const ModelDownloadResponse({
    required this.statusCode,
    required this.uri,
    required this.body,
    this.contentLength,
  });

  /// HTTP status code returned by the source.
  final int statusCode;

  /// Final response URI after any redirects.
  final Uri uri;

  /// Declared response length, or null when the server uses chunked/unknown
  /// length transfer.
  final int? contentLength;

  /// Response bytes delivered incrementally.
  final Stream<List<int>> body;
}

/// Test-only transport seam for producing a [ModelDownloadResponse].
typedef ModelDownloadResponseLoader = Future<ModelDownloadResponse> Function(
  Uri uri,
);

/// Streams one selected model artifact into the storage-provided staging path.
final class HttpModelDownloader implements IModelDownloader {
  /// Creates an HTTPS model downloader.
  ///
  /// [responseLoader] is intended for unit tests. When omitted, the
  /// implementation creates a native [HttpClient], follows redirects, and
  /// requires the final response URI to remain HTTPS.
  HttpModelDownloader({
    this.responseLoader,
    this.maxRedirects = 5,
    this.requestTimeout = const Duration(minutes: 15),
  }) {
    if (maxRedirects < 0) {
      throw ArgumentError.value(
        maxRedirects,
        'maxRedirects',
        'must not be negative',
      );
    }
    if (requestTimeout.compareTo(Duration.zero) <= 0) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'must be greater than zero',
      );
    }
  }

  /// Optional injected response loader used by tests.
  final ModelDownloadResponseLoader? responseLoader;

  /// Maximum number of redirects accepted by the native HTTP client.
  final int maxRedirects;

  /// Maximum time allowed for connection/headers and for an idle response
  /// body read. The default is intentionally long enough for a large GGUF
  /// artifact on a mobile network.
  final Duration requestTimeout;

  HttpClient? _client;

  /// Releases the native HTTP client, if it has been created.
  void close() {
    _client?.close(force: true);
    _client = null;
  }

  @override
  Future<void> download({
    required ModelDescriptor model,
    required ModelStagingFile target,
    ModelDownloadProgress? onProgress,
  }) async {
    if (target.model != model) {
      throw const ModelDownloadException(
        'staging target does not belong to the selected model',
      );
    }

    final String targetPath = target.path.trim();
    if (targetPath.isEmpty) {
      throw const ModelDownloadException('staging target path is empty');
    }
    if (model.fileSizeBytes <= 0) {
      throw const ModelDownloadException(
        'model descriptor fileSizeBytes must be positive',
      );
    }

    final Uri sourceUri = _parseHttpsUri(model.downloadUrl);
    final ModelDownloadResponse response;
    try {
      response = await _fetch(sourceUri);
    } on ModelDownloadException {
      rethrow;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        ModelDownloadException('failed to fetch ${model.downloadUrl}: $error'),
        stackTrace,
      );
    }

    final String responseScheme = response.uri.scheme.toLowerCase();
    if (responseScheme != 'https') {
      throw ModelDownloadException(
        'redirected model response must remain HTTPS, got ${response.uri}',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ModelDownloadException(
        'model download returned HTTP ${response.statusCode} for '
        '${response.uri}',
      );
    }

    final int? declaredLength = response.contentLength;
    if (declaredLength != null && declaredLength > model.fileSizeBytes) {
      throw ModelDownloadException(
        'model response is larger than the descriptor: declared '
        '$declaredLength bytes, expected at most ${model.fileSizeBytes}',
      );
    }

    IOSink? sink;
    var receivedBytes = 0;
    try {
      sink = File(targetPath).openWrite(mode: FileMode.write);
      await for (final List<int> chunk in response.body.timeout(
        requestTimeout,
      )) {
        receivedBytes += chunk.length;
        if (receivedBytes > model.fileSizeBytes) {
          throw ModelDownloadException(
            'model response exceeded the descriptor size while streaming: '
            '$receivedBytes bytes, expected at most ${model.fileSizeBytes}',
          );
        }
        sink.add(chunk);
        // Progress is advisory: report only bytes that passed the descriptor
        // bound and were handed to the sink.
        onProgress?.call(receivedBytes);
      }
      await sink.flush();
    } on ModelDownloadException {
      rethrow;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        ModelDownloadException(
          'failed while writing model staging file "$targetPath": $error',
        ),
        stackTrace,
      );
    } finally {
      await sink?.close();
    }
  }

  Future<ModelDownloadResponse> _fetch(Uri sourceUri) async {
    final ModelDownloadResponseLoader? loader = responseLoader;
    if (loader != null) {
      return loader(sourceUri).timeout(requestTimeout);
    }

    final HttpClient client = _client ??= HttpClient();
    final HttpClientRequest request = await client
        .getUrl(sourceUri)
        .timeout(requestTimeout);
    request.followRedirects = true;
    request.maxRedirects = maxRedirects;
    final HttpClientResponse response = await request.close().timeout(
      requestTimeout,
    );
    final List<RedirectInfo> redirects = response.redirects;
    return ModelDownloadResponse(
      statusCode: response.statusCode,
      uri: redirects.isEmpty ? request.uri : redirects.last.location,
      contentLength: response.contentLength < 0 ? null : response.contentLength,
      body: response,
    );
  }

  static Uri _parseHttpsUri(String rawUrl) {
    final Uri uri;
    try {
      uri = Uri.parse(rawUrl.trim());
    } on FormatException catch (error) {
      throw ModelDownloadException('invalid model download URL: $error');
    }
    if (uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty) {
      throw ModelDownloadException(
        'model download URL must be an absolute HTTPS URL: $rawUrl',
      );
    }
    return uri;
  }
}

/// Creates the native model downloader used by the composition root.
IModelDownloader createModelDownloader({
  ModelDownloadResponseLoader? responseLoader,
  int maxRedirects = 5,
  Duration requestTimeout = const Duration(minutes: 15),
}) {
  return HttpModelDownloader(
    responseLoader: responseLoader,
    maxRedirects: maxRedirects,
    requestTimeout: requestTimeout,
  );
}
