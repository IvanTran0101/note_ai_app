import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../application/attachments/attachment_media.dart';
import '../../application/attachments/attachment_policy.dart';
import '../../application/notes/note_access.dart';

AttachmentMediaBridge createAttachmentMediaBridge() => _WebMediaBridge();

/// Child worker scope controls only the media iframe. The main app's worker,
/// IndexedDB and offline cache are not replaced. Private bytes never persist here.
final class _WebMediaBridge implements AttachmentMediaBridge {
  _WebMediaBridge() {
    // Warm only public viewer assets while online. Private bytes/capabilities
    // remain transient and every later open still requires fresh authority.
    unawaited(_worker().then<void>((_) {}, onError: (Object _) {}));
  }
  final _sessions = <String, AttachmentMediaRequest>{};
  Future<web.ServiceWorker>? _opening;
  late final JSFunction _listener = ((web.MessageEvent event) {
    if (event.origin != web.window.location.origin || event.ports.length != 1) {
      return;
    }
    final raw = event.data.dartify();
    if (raw is! Map || raw['kind'] != 'noteflow-media-read') return;
    final request = _sessions[raw['cap']];
    if (request == null) return;
    unawaited(_reply(event.ports[0], request, raw['start'], raw['end']));
  }).toJS;
  bool _listening = false;

  Future<web.ServiceWorker> _worker() async {
    final opening = _opening ??= _register();
    try {
      return await opening;
    } finally {
      // Share only concurrent registration work. An activated worker can be
      // replaced later, so constructor warmup must not pin it for this session.
      if (identical(_opening, opening)) _opening = null;
    }
  }

  Future<web.ServiceWorker> _register() async {
    if (!web.window.isSecureContext) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
    }
    final base = Uri.parse(web.document.baseURI);
    final registration = await web.window.navigator.serviceWorker
        .register(
          base.resolve('attachment_worker.js').toString().toJS,
          web.RegistrationOptions(
            scope: base.resolve('attachment_media/').toString(),
          ),
        )
        .toDart;
    if (registration.installing == null && registration.waiting == null) {
      try {
        // register() can return the previous active worker before its update
        // check discovers a replacement. Finish that check before choosing it.
        await registration.update().toDart;
      } on Object {
        // Offline local reads can still use the installed, activated viewer.
        if (registration.active?.state != 'activated') rethrow;
      }
    }
    final worker =
        registration.installing ?? registration.waiting ?? registration.active;
    if (worker == null) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
    }
    await _awaitActivation(worker);
    return worker;
  }

  Future<void> _awaitActivation(web.ServiceWorker worker) async {
    final ready = Completer<void>();
    void checkState() {
      if (ready.isCompleted) return;
      if (worker.state == 'activated') ready.complete();
      if (worker.state == 'redundant') {
        ready.completeError(const _MediaWorkerReplaced());
      }
    }

    final listener = ((web.Event _) => checkState()).toJS;
    worker.addEventListener('statechange', listener);
    try {
      checkState();
      await ready.future.timeout(const Duration(seconds: 30));
    } finally {
      worker.removeEventListener('statechange', listener);
    }
  }

  @override
  Future<AttachmentMediaHandle> open(AttachmentMediaRequest request) async {
    await request.authorize();
    if (!request.exportFile &&
        !{'video/mp4', 'application/pdf'}.contains(request.mimeType)) {
      throw const FormatException('Unsupported streaming media.');
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      await request.authorize();
      try {
        return await _openAttempt(request);
      } on _MediaWorkerReplaced {
        if (attempt == 1) {
          throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
        }
      }
    }
    throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
  }

  Future<AttachmentMediaHandle> _openAttempt(
    AttachmentMediaRequest request,
  ) async {
    final worker = await _worker();
    if (!_listening) {
      web.window.navigator.serviceWorker.addEventListener('message', _listener);
      _listening = true;
    }
    final random = Random.secure();
    final cap = base64UrlEncode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    _sessions[cap] = request;
    final channel = web.MessageChannel();
    final handle = _WebMediaHandle(_mediaUri(request, cap), () async {
      _closeSession(worker, cap);
    });
    try {
      await _registerSession(worker, request, cap, channel);
      if (worker.state != 'activated') throw const _MediaWorkerReplaced();
      await request.authorize();
      if (worker.state != 'activated') throw const _MediaWorkerReplaced();
      return handle;
    } on Object {
      await handle.close();
      rethrow;
    } finally {
      channel.port1.close();
      channel.port2.close();
    }
  }

  Future<void> _registerSession(
    web.ServiceWorker worker,
    AttachmentMediaRequest request,
    String cap,
    web.MessageChannel channel,
  ) async {
    final registered = Completer<void>();
    final acknowledged = ((web.MessageEvent event) {
      final data = event.data.dartify();
      if (data is Map &&
          data['registered'] == true &&
          !registered.isCompleted) {
        registered.complete();
      }
    }).toJS;
    channel.port1.addEventListener('message', acknowledged);
    channel.port1.start();
    if (worker.state != 'activated') throw const _MediaWorkerReplaced();
    try {
      worker.postMessage(
        {
          'kind': 'noteflow-media-register',
          'cap': cap,
          'size': request.sizeBytes,
          'mime': request.mimeType,
          'fileName': request.fileName,
          'exportFile': request.exportFile,
        }.jsify(),
        [channel.port2].toJS,
      );
      await registered.future.timeout(const Duration(seconds: 10));
    } on Object {
      if (worker.state != 'activated') throw const _MediaWorkerReplaced();
      rethrow;
    }
  }

  Uri _mediaUri(AttachmentMediaRequest request, String cap) =>
      Uri.parse(web.document.baseURI)
          .resolve('attachment_media/host.html')
          .replace(
            fragment: cap,
            queryParameters: request.exportFile
                ? {'export': '1'}
                : request.mimeType == 'application/pdf'
                ? {'pdf': '1'}
                : null,
          );

  void _closeSession(web.ServiceWorker worker, String cap) {
    _sessions.remove(cap);
    // Remove local authority even if a replaced worker rejects the close post.
    try {
      worker.postMessage({'kind': 'noteflow-media-close', 'cap': cap}.jsify());
    } on Object {
      // The abandoned worker's private state is transient.
    }
    if (_sessions.isEmpty && _listening) {
      web.window.navigator.serviceWorker.removeEventListener(
        'message',
        _listener,
      );
      _listening = false;
    }
  }

  Future<void> _reply(
    web.MessagePort port,
    AttachmentMediaRequest request,
    Object? start,
    Object? end,
  ) async {
    Uint8List? buffer;
    try {
      if (start is! int ||
          end is! int ||
          start < 0 ||
          end < start ||
          end > request.sizeBytes ||
          end - start > AttachmentPolicy.chunkBytes) {
        throw const FormatException('Invalid media range.');
      }
      await request.authorize();
      buffer = Uint8List(end - start);
      var offset = 0;
      if (end > start) {
        await for (final bytes in request.read(start, end)) {
          try {
            if (offset + bytes.length > buffer.length) {
              throw const FormatException('Invalid range response.');
            }
            buffer.setRange(offset, offset + bytes.length, bytes);
            offset += bytes.length;
          } finally {
            bytes.fillRange(0, bytes.length, 0);
          }
        }
      }
      await request.authorize();
      if (offset != buffer.length) {
        throw const FormatException('Incomplete range response.');
      }
      port.postMessage({'bytes': buffer}.jsify());
    } on Object {
      port.postMessage({'error': true}.jsify());
    } finally {
      buffer?.fillRange(0, buffer.length, 0);
      port.close();
    }
  }
}

final class _MediaWorkerReplaced implements Exception {
  const _MediaWorkerReplaced();
}

final class _WebMediaHandle implements AttachmentMediaHandle {
  _WebMediaHandle(this.uri, this._close);
  @override
  final Uri uri;
  final Future<void> Function() _close;
  bool _closed = false;
  @override
  bool get exported => false;
  @override
  Future<void> close() async {
    if (!_closed) {
      _closed = true;
      await _close();
    }
  }
}
