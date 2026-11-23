import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

import '../../application/attachments/attachment_media.dart';
import '../../application/attachments/attachment_policy.dart';
import '../../application/notes/note_access.dart';

AttachmentMediaBridge createAttachmentMediaBridge() => _NativeMediaBridge();

final class _NativeMediaBridge implements AttachmentMediaBridge {
  @override
  Future<AttachmentMediaHandle> open(AttachmentMediaRequest request) async {
    await request.authorize();
    if (request.exportFile) return _export(request);
    if (!{'video/mp4', 'application/pdf'}.contains(request.mimeType)) {
      throw const FormatException('Unsupported streaming media.');
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final cap = base64UrlEncode(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    ).replaceAll('=', '');
    final handle = _NativeMediaHandle(
      server,
      Uri.parse('http://127.0.0.1:${server.port}/$cap'),
    );
    server.listen((http) => unawaited(_serve(http, request, handle, cap)));
    try {
      await request.authorize();
      return handle;
    } on Object {
      await handle.close();
      rethrow;
    }
  }

  Future<void> _serve(
    HttpRequest http,
    AttachmentMediaRequest request,
    _NativeMediaHandle handle,
    String cap,
  ) async {
    var sent = false;
    try {
      if (handle.closed ||
          http.uri.path != '/$cap' ||
          !{'GET', 'HEAD'}.contains(http.method)) {
        http.response.statusCode = HttpStatus.forbidden;
        return;
      }
      await request.authorize();
      late (int, int) range;
      try {
        range = _range(
          http.headers.value(HttpHeaders.rangeHeader),
          request.sizeBytes,
        );
      } on FormatException {
        http.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        http.response.headers.set(
          'content-range',
          'bytes */${request.sizeBytes}',
        );
        return;
      }
      final (start, end) = range;
      final response = http.response;
      response.statusCode = http.headers.value(HttpHeaders.rangeHeader) == null
          ? 200
          : 206;
      response.headers.set(HttpHeaders.contentTypeHeader, request.mimeType);
      response.headers.set('accept-ranges', 'bytes');
      response.headers.set('cache-control', 'no-store');
      response.headers.set('x-content-type-options', 'nosniff');
      response.contentLength = end - start;
      if (response.statusCode == 206) {
        response.headers.set(
          'content-range',
          'bytes $start-${end - 1}/${request.sizeBytes}',
        );
      }
      if (http.method == 'HEAD') return;
      for (var offset = start; offset < end;) {
        final stop = min(end, offset + AttachmentPolicy.chunkBytes);
        await for (final bytes in request.read(offset, stop)) {
          try {
            if (handle.closed) throw StateError('Media closed');
            sent = true;
            response.add(bytes);
            await response.flush();
          } finally {
            bytes.fillRange(0, bytes.length, 0);
          }
        }
        offset = stop;
      }
    } on Object {
      if (!sent) {
        http.response.statusCode = HttpStatus.forbidden;
        http.response.contentLength = 0;
        http.response.headers.removeAll('content-range');
      } else {
        unawaited(
          http.response
              .detachSocket()
              .then((socket) => socket.destroy())
              .catchError((Object _) {}),
        );
      }
    } finally {
      await http.response.close().catchError((Object _) {});
    }
  }

  (int, int) _range(String? header, int size) {
    if (header == null) return (0, size);
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header);
    if (match == null || match[1]!.isEmpty && match[2]!.isEmpty) {
      throw const FormatException('Invalid media range.');
    }
    final start = match[1]!.isEmpty
        ? max(0, size - int.parse(match[2]!))
        : int.parse(match[1]!);
    final end = match[1]!.isEmpty || match[2]!.isEmpty
        ? size
        : min(size, int.parse(match[2]!) + 1);
    if (start < 0 || start >= end || end > size) {
      throw const FormatException('Invalid media range.');
    }
    return (start, end);
  }

  Future<AttachmentMediaHandle> _export(AttachmentMediaRequest request) async {
    if (!Platform.isAndroid) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
    }
    const channel = MethodChannel('noteflow/attachment_export');
    final id = await channel.invokeMethod<String>('begin', {
      'fileName': request.fileName,
      'mimeType': request.mimeType,
      'sizeBytes': request.sizeBytes,
    });
    if (id == null) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
    }
    try {
      await for (final bytes in request.read(0, request.sizeBytes)) {
        final packet = Uint8List.fromList(bytes);
        try {
          await request.authorize();
          await channel.invokeMethod<void>('write', {
            'id': id,
            'bytes': packet,
          });
        } finally {
          packet.fillRange(0, packet.length, 0);
          bytes.fillRange(0, bytes.length, 0);
        }
      }
      await request.authorize();
      await channel.invokeMethod<void>('finish', {'id': id});
      return _ExportedHandle();
    } on Object {
      await channel
          .invokeMethod<void>('cancel', {'id': id})
          .catchError((Object _) {});
      rethrow;
    }
  }
}

final class _NativeMediaHandle implements AttachmentMediaHandle {
  _NativeMediaHandle(this.server, this.uri);
  final HttpServer server;
  @override
  final Uri uri;
  bool closed = false;
  @override
  bool get exported => false;
  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await server.close(force: true);
  }
}

final class _ExportedHandle implements AttachmentMediaHandle {
  @override
  Uri? get uri => null;
  @override
  bool get exported => true;
  @override
  Future<void> close() async {}
}
