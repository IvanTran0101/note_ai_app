import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import '../../application/attachments/attachment_binding.dart';
import '../../application/attachments/attachment_policy.dart';
import '../../application/notes/note_access.dart';
import '../../domain/notes/attachment.dart';
import '../../domain/notes/note_protection.dart';
import '../security/note_jwt_subject.dart';
import 'attachment_http_request.dart';
import '../sync/http_remote_note_data_source.dart';

/// Authenticated REST content route, never a public/presigned GET. Every
/// bounded Range request obtains a fresh JWT/grant and the backend must intersect
/// them with its current ACL, note manifest and object/protection/access epochs.
/// The caller supplies M05/M06's live guard; this adapter cannot grant access.
final class HttpAttachmentReader {
  HttpAttachmentReader({
    required this.baseUri,
    required this.tokenProvider,
    required this.grantHeader,
    required this.requireAccess,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
    bool allowLocalDev = false,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null {
    if (!(baseUri.scheme == 'https' ||
            allowLocalDev &&
                baseUri.scheme == 'http' &&
                baseUri.host == '127.0.0.1' &&
                baseUri.port == 8796) ||
        baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        timeout <= Duration.zero) {
      throw ArgumentError(
        'An HTTPS attachment API and positive timeout are required.',
      );
    }
  }

  final Uri baseUri;
  final SyncAccessTokenProvider tokenProvider;
  // Reuse HttpNoteSecurityGateway.grantHeader with attachmentRead, not read.
  final String? Function(AttachmentBinding binding, NoteOperation operation)
  grantHeader;
  final void Function(AttachmentBinding binding, NoteOperation operation)
  requireAccess;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;
  bool _closed = false;

  void _require(AttachmentBinding binding, Attachment attachment) {
    if (_closed) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
    }
    if (attachment.noteId != binding.note.noteId) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
    }
    requireAccess(binding, NoteOperation.attachmentRead);
  }

  Uri _endpoint(AttachmentBinding binding, Attachment attachment) {
    final prefix = baseUri.path.endsWith('/')
        ? baseUri.path
        : '${baseUri.path}/';
    return baseUri.replace(
      path:
          '${prefix}notes/${Uri.encodeComponent(binding.note.noteId)}'
          '/attachments/${Uri.encodeComponent(attachment.id)}/content',
      queryParameters: {
        'ownerId': binding.note.ownerId,
        'objectVersion': attachment.objectVersion,
      },
    );
  }

  /// End is exclusive, matching the encrypted cache's local Range reader.
  /// Each yielded buffer belongs to the caller and should be erased on close.
  /// A full read also verifies SHA-256 before completion; a preview must wait
  /// for completion before displaying the collected bytes.
  Stream<Uint8List> read(
    AttachmentBinding binding,
    Attachment attachment, {
    int start = 0,
    int? end,
  }) async* {
    final stop = end ?? attachment.sizeBytes;
    if (start < 0 ||
        stop < start ||
        stop > attachment.sizeBytes ||
        attachment.sizeBytes > 50 * AttachmentPolicy.mib) {
      throw ArgumentError('Invalid attachment byte range.');
    }
    _require(binding, attachment);
    AttachmentPolicy.validate(
      fileName: attachment.fileName,
      mimeType: attachment.mimeType,
      sizeBytes: attachment.sizeBytes,
      existing: const [],
    );
    final digest = _DigestSink();
    final hasher = crypto.sha256.startChunkedConversion(digest);
    try {
      for (var offset = start; offset < stop;) {
        final next = (offset + AttachmentPolicy.chunkBytes < stop)
            ? offset + AttachmentPolicy.chunkBytes
            : stop;
        final bytes = await _range(binding, attachment, offset, next);
        try {
          _require(binding, attachment);
          hasher.add(bytes);
          yield bytes;
        } catch (_) {
          bytes.fillRange(0, bytes.length, 0);
          rethrow;
        }
        offset = next;
      }
      _require(binding, attachment);
      hasher.close();
      if (start == 0 &&
          stop == attachment.sizeBytes &&
          digest.value.toString() != attachment.sha256) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.storage);
      }
    } on NoteSecurityFailure {
      rethrow;
    } on TimeoutException {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.network);
    } on Object {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
    }
  }

  Future<Uint8List> _range(
    AttachmentBinding binding,
    Attachment attachment,
    int start,
    int end,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      _require(binding, attachment);
      final token = await tokenProvider(forceRefresh: attempt == 1)
          .timeout(timeout);
      _require(binding, attachment);
      if (token == null || noteJwtSubject(token) != binding.actorId) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
      }
      final grant = grantHeader(binding, NoteOperation.attachmentRead);
      if (binding.protection.enabled &&
          (grant == null || !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(grant))) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.locked);
      }
      final result = await attachmentHttpRequest<Uint8List?>(
        client: _client,
        method: 'GET',
        uri: _endpoint(binding, attachment),
        timeout: timeout,
        requireAccess: () => _require(binding, attachment),
        discard: (bytes) => bytes?.fillRange(0, bytes.length, 0),
        configure: (request) => request.headers.addAll({
          'Authorization': 'Bearer $token',
          'Range': 'bytes=$start-${end - 1}',
          'Accept': attachment.mimeType,
          'X-Note-Unlock-Grant': ?grant,
        }),
        consume: (response) async {
          if (response.statusCode == 401 && attempt == 0) {
            await response.stream.listen((_) {}).cancel();
            return null;
          }
          if (response.statusCode != 206 ||
              response.headers['content-range'] !=
                  'bytes $start-${end - 1}/${attachment.sizeBytes}' ||
              response.headers['content-type']?.split(';').first.trim() !=
                  attachment.mimeType ||
              response.contentLength != null &&
                  response.contentLength != end - start) {
            await response.stream.listen((_) {}).cancel();
            throw NoteSecurityFailure(
              response.statusCode == 401 || response.statusCode == 403
                  ? NoteSecurityFailureCode.denied
                  : NoteSecurityFailureCode.unavailable,
            );
          }
          final bytes = Uint8List(end - start);
          var written = 0;
          try {
            await for (final chunk in response.stream.timeout(timeout)) {
              _require(binding, attachment);
              if (written + chunk.length > bytes.length) {
                throw const NoteSecurityFailure(
                  NoteSecurityFailureCode.unavailable,
                );
              }
              bytes.setRange(written, written + chunk.length, chunk);
              written += chunk.length;
            }
            _require(binding, attachment);
            if (written != bytes.length) {
              throw const NoteSecurityFailure(
                NoteSecurityFailureCode.unavailable,
              );
            }
            return bytes;
          } on Object {
            bytes.fillRange(0, bytes.length, 0);
            rethrow;
          }
        },
      );
      if (result != null) return result;
    }
    throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
  }

  void close() {
    _closed = true;
    if (_ownsClient) _client.close();
  }
}

final class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest data) => value = data;
  @override
  void close() {}
}
