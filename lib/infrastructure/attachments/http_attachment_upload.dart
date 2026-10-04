import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import '../../application/attachments/attachment_binding.dart';
import '../../application/attachments/attachment_policy.dart';
import '../../application/attachments/attachment_transfer.dart';
import '../../application/attachments/local_attachment_draft.dart';
import '../../application/notes/note_access.dart';
import '../../domain/notes/attachment.dart';
import '../../domain/notes/note_protection.dart';
import '../security/note_jwt_subject.dart';
import '../sync/http_remote_note_data_source.dart';
import 'attachment_codec.dart';
import 'attachment_http_request.dart';

/// Bounded upload with durable server ACK/recovery. No plaintext/URL in outbox.
final class HttpAttachmentUpload {
  HttpAttachmentUpload({
    required this.baseUri,
    required this.tokenProvider,
    required this.grantHeader,
    required this.requireAccess,
    this.allowLocalDev = false,
    this.onProgress,
    http.Client? client,
  }) : _client = client ?? http.Client() {
    if (baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        !(baseUri.scheme == 'https' && baseUri.host.isNotEmpty ||
            _local(baseUri))) {
      throw ArgumentError('An HTTPS attachment API is required.');
    }
  }
  final Uri baseUri;
  final SyncAccessTokenProvider tokenProvider;
  final String? Function(AttachmentBinding, NoteOperation) grantHeader;
  final void Function(AttachmentBinding, NoteOperation) requireAccess;
  final bool allowLocalDev;
  final void Function(AttachmentProgress)? onProgress;
  final http.Client _client;
  final _aborts = <String, Completer<void>>{};
  bool _local(Uri u) =>
      allowLocalDev &&
      u.scheme == 'http' &&
      u.host == '127.0.0.1' &&
      u.port == 8796;
  Uri _endpoint(
    AttachmentBinding b,
    String id,
    String action,
  ) => baseUri.replace(
    path:
        '${baseUri.path.replaceFirst(RegExp(r'/$'), '')}/notes/${Uri.encodeComponent(b.note.noteId)}/attachments/$id/$action',
    queryParameters: {'ownerId': b.note.ownerId},
  );
  Future<Map<String, dynamic>> _call(
    AttachmentBinding b,
    String id,
    String action, [
    Map<String, Object?>? body,
  ]) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      requireAccess(b, NoteOperation.attachmentWrite);
      final token = await tokenProvider(forceRefresh: attempt == 1)
          .timeout(const Duration(seconds: 30));
      requireAccess(b, NoteOperation.attachmentWrite);
      if (token == null || noteJwtSubject(token) != b.actorId) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
      }
      final grant = grantHeader(b, NoteOperation.attachmentWrite);
      if (b.protection.enabled && grant == null) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.locked);
      }
      final result = await attachmentHttpRequest<Map<String, dynamic>?>(
        client: _client,
        method: body == null ? 'GET' : 'POST',
        uri: _endpoint(b, id, action),
        requireAccess: () => requireAccess(b, NoteOperation.attachmentWrite),
        cancel: action == 'cancel' ? null : _aborts[id]?.future,
        configure: (request) {
          request.headers.addAll({
            'authorization': 'Bearer $token',
            'content-type': 'application/json',
            'x-note-unlock-grant': ?grant,
          });
          if (body != null) request.body = jsonEncode(body);
        },
        consume: (response) async {
          if (response.statusCode == 401 && attempt == 0) {
            await response.stream.listen((_) {}).cancel();
            return null;
          }
          final bytes = BytesBuilder();
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 30),
          )) {
            requireAccess(b, NoteOperation.attachmentWrite);
            if (bytes.length + chunk.length > 16384) {
              throw const FormatException('Attachment response is too large.');
            }
            bytes.add(chunk);
          }
          requireAccess(b, NoteOperation.attachmentWrite);
          if (response.statusCode != 200) {
            throw NoteSecurityFailure(
              response.statusCode == 403 || response.statusCode == 423
                  ? NoteSecurityFailureCode.denied
                  : NoteSecurityFailureCode.network,
            );
          }
          return Map<String, dynamic>.from(
            jsonDecode(utf8.decode(bytes.takeBytes())) as Map,
          );
        },
      );
      if (result != null) return result;
    }
    throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
  }

  Future<Attachment> upload(
    AttachmentBinding b,
    LocalAttachmentDraft draft,
    Stream<List<int>> Function() openRead,
  ) async {
    final id = draft.cacheId;
    if (_aborts.containsKey(id)) {
      throw StateError('Attachment transfer is already running.');
    }
    final abort = Completer<void>();
    _aborts[id] = abort;
    void progress(String phase, int completed) => onProgress?.call(
      AttachmentProgress(id, phase, completed, draft.sizeBytes),
    );
    try {
      var status = await _call(b, id, 'begin', {
        'id': id,
        'fileName': draft.fileName,
        'mimeType': draft.mimeType,
        'sizeBytes': draft.sizeBytes,
        'sha256': draft.sha256,
      });
      if (status['phase'] == 'cancelled' || status['phase'] == 'unlinked') {
        throw StateError('Attachment attempt was cancelled.');
      }
      if (status['attachment'] == null) {
        if (status['phase'] == 'uploading') {
          final completed = status['completedChunks'];
          if (completed is! int ||
              completed < 0 ||
              completed > draft.chunkCount ||
              status['chunkCount'] != draft.chunkCount) {
            throw const FormatException('Invalid upload progress.');
          }
          var index = 0;
          await for (final raw in openRead()) {
            final bytes = Uint8List.fromList(raw);
            try {
              requireAccess(b, NoteOperation.attachmentWrite);
              final expected =
                  (draft.sizeBytes - index * AttachmentPolicy.chunkBytes).clamp(
                    0,
                    AttachmentPolicy.chunkBytes,
                  );
              if (bytes.length != expected) {
                throw const FormatException('Invalid encrypted upload chunk.');
              }
              if (index >= completed) {
                final checksum = crypto.sha256.convert(bytes).toString();
                final target = await _call(b, id, 'chunk-url', {
                  'index': index,
                  'sha256': checksum,
                });
                await _put(
                  b,
                  Uri.parse(target['url'] as String),
                  Map<String, String>.from(target['headers'] as Map),
                  bytes,
                  abort.future,
                );
                await _call(b, id, 'chunk-ack', {
                  'index': index,
                  'sha256': checksum,
                });
              }
              progress(
                'Uploading',
                ((index + 1) * AttachmentPolicy.chunkBytes).clamp(
                  0,
                  draft.sizeBytes,
                ),
              );
              index++;
            } finally {
              bytes.fillRange(0, bytes.length, 0);
              raw.fillRange(0, raw.length, 0);
            }
          }
          if (index != draft.chunkCount) {
            throw const FormatException('Incomplete encrypted upload.');
          }
        }
        progress('Verifying', draft.sizeBytes);
        status = await _call(b, id, 'verify', const {});
      }
      final attachment = AttachmentCodec.decodeList([
        status['attachment'],
      ], noteId: b.note.noteId).single;
      progress('Awaiting note sync', draft.sizeBytes);
      return attachment;
    } on Object {
      progress('Retry needed', 0);
      rethrow;
    } finally {
      _aborts.remove(id);
      if (!abort.isCompleted) abort.complete();
    }
  }

  Future<void> _put(
    AttachmentBinding b,
    Uri url,
    Map<String, String> headers,
    Uint8List bytes,
    Future<void> cancel,
  ) async {
    final s3 =
        url.scheme == 'https' &&
        RegExp(r'^[a-z0-9.-]+\.s3(?:\.[a-z0-9-]+)?\.amazonaws\.com$')
            .hasMatch(url.host);
    if (url.userInfo.isNotEmpty ||
        url.hasFragment ||
        !(s3 || _local(url) && url.path == '/dev/attachment-put') ||
        headers.keys.any(
          (k) => !{
            'content-type',
            'x-amz-checksum-sha256',
            'x-amz-server-side-encryption',
          }.contains(k.toLowerCase()),
        )) {
      throw const FormatException('Invalid staging upload destination.');
    }
    requireAccess(b, NoteOperation.attachmentWrite);
    await attachmentHttpRequest<void>(
      client: _client,
      method: 'PUT',
      uri: url,
      cancel: cancel,
      requireAccess: () => requireAccess(b, NoteOperation.attachmentWrite),
      configure: (request) {
        request.bodyBytes = bytes;
        request.headers.addAll(headers);
      }, // Never forwards JWT or M05 grants to S3.
      consume: (response) async {
        await response.stream.listen((_) {}).cancel();
        requireAccess(b, NoteOperation.attachmentWrite);
        if (response.statusCode != 200) {
          throw const NoteSecurityFailure(NoteSecurityFailureCode.network);
        }
      },
    );
  }

  Future<void> cancel(AttachmentBinding b, String id) async {
    final abort = _aborts[id];
    if (abort != null && !abort.isCompleted) abort.complete();
    await _call(b, id, 'cancel', const {});
  }

  Future<bool> linked(AttachmentBinding b, String id) async =>
      (await _call(b, id, 'status'))['phase'] == 'linked';
}
