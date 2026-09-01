/// Web implementation of the model downloader API.
library;

import 'model_provisioning_contract.dart';
import 'model_selection.dart';

/// Web-compatible response shape matching the native downloader API.
final class ModelDownloadResponse {
  /// Creates a response value for API compatibility and tests.
  const ModelDownloadResponse({
    required this.statusCode,
    required this.uri,
    required this.body,
    this.contentLength,
  });

  /// HTTP status code.
  final int statusCode;

  /// Final response URI.
  final Uri uri;

  /// Declared response length, when available.
  final int? contentLength;

  /// Response body stream.
  final Stream<List<int>> body;
}

/// Web-compatible response loader type matching the native API.
typedef ModelDownloadResponseLoader = Future<ModelDownloadResponse> Function(
  Uri uri,
);

/// Typed failure raised when local model downloads are unavailable on Web.
final class ModelDownloadException implements Exception {
  /// Creates a download failure.
  const ModelDownloadException(this.message);

  /// Explanation suitable for logs or application error mapping.
  final String message;

  @override
  String toString() => 'ModelDownloadException: $message';
}

/// Web stub; local GGUF provisioning is not supported by this runtime.
final class HttpModelDownloader implements IModelDownloader {
  /// Creates the Web stub.
  HttpModelDownloader({
    ModelDownloadResponseLoader? responseLoader,
    int maxRedirects = 5,
  });

  /// Matches the native test seam.
  @override
  Future<void> download({
    required ModelDescriptor model,
    required ModelStagingFile target,
  }) async {
    throw UnsupportedError(
      'Local model downloads are not available on Web; '
      'use a remote inference path.',
    );
  }

  /// Matches the native lifecycle API.
  void close() {}
}

/// Creates the Web downloader stub.
IModelDownloader createModelDownloader({
  ModelDownloadResponseLoader? responseLoader,
  int maxRedirects = 5,
}) {
  return HttpModelDownloader(
    responseLoader: responseLoader,
    maxRedirects: maxRedirects,
  );
}
